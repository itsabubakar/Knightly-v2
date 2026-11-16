import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/db/secure_storage.dart';
import 'package:lichess_mobile/src/model/auth/auth_user.dart';
import 'package:lichess_mobile/src/model/auth/sign_in_failure_reporter.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

/// Host of the custom URI scheme callback. Must stay in sync with the intent-filter of
/// `MainActivity` in `android/app/src/main/AndroidManifest.xml`.
const kOAuthCustomSchemeCallbackHost = 'login-callback';

/// The custom URI scheme redirect for OAuth.
///
/// Custom schemes are more universally supported across Android browsers/OEMs than
/// HTTPS App Link redirects, so they are used on every platform and host.
const kOAuthRedirectUri = '$kOAuthCustomUriSchemeName://$kOAuthCustomSchemeCallbackHost';

/// The OAuth scopes Knightly asks for: the public API scopes of the features it supports.
///
/// Not `web:mobile`: lichess only accepts tokens with that scope from the official app, signed with
/// its private key.
const oauthScopes = [
  'board:play',
  'challenge:read',
  'challenge:write',
  'puzzle:read',
  'puzzle:write',
  'preference:read',
  'follow:read',
  'follow:write',
  'tournament:write',
  'msg:write',
  'study:read',
];

/// Storage key of the sign in started in the browser and not completed yet.
const kPendingSignInStorageKey = '$kLichessHost.pendingOAuthSignIn';

/// How long a sign in started in the browser can be completed.
const _kPendingSignInLifetime = Duration(minutes: 15);

/// Whether [uri] is the OAuth redirect lichess sends back to the app after a sign in.
bool isOAuthCallbackUri(Uri uri) =>
    uri.scheme == kOAuthCustomUriSchemeName && uri.host == kOAuthCustomSchemeCallbackHost;

/// Thrown when the user denies the authorization on lichess.
///
/// This is distinct from a genuine sign-in failure: the UI should silently
/// ignore it rather than surfacing an error.
class const SignInCancelledException() implements Exception {
  @override
  String toString() => 'Sign-in was cancelled.';
}

/// Opens the lichess authorization page in a browser; returns whether it could be opened.
typedef OAuthBrowserLauncher = Future<bool> Function(Uri url);

/// A provider for the [OAuthBrowserLauncher], overridable in tests.
final oauthBrowserLauncherProvider = Provider<OAuthBrowserLauncher>((Ref ref) {
  return (url) => launchUrl(url, mode: LaunchMode.inAppBrowserView);
}, name: 'OAuthBrowserLauncherProvider');

final authRepositoryProvider = Provider<AuthRepository>((Ref ref) {
  return AuthRepository(ref);
}, name: 'AuthRepositoryProvider');

/// Signs in with the OAuth 2.0 authorization code flow with PKCE.
///
/// The sign in happens in two steps, [startSignIn] and [completeSignIn], and its state is kept in
/// secure storage in between, not in memory: while the browser is open, Android may kill the app to
/// reclaim memory, and the app process receiving the redirect is then a new one.
class AuthRepository(final Ref _ref) {
  final Logger _log = Logger('AuthRepository');
  LichessClient get _client => _ref.read(lichessClientProvider);

  /// Starts the sign in: saves a new pending sign in and opens the lichess authorization page.
  ///
  /// Lichess then redirects to [kOAuthRedirectUri], which the app completes with [completeSignIn].
  Future<void> startSignIn() async {
    final codeVerifier = _randomString(64);
    final state = _randomString(32);
    await SecureStorage.instance.write(
      key: kPendingSignInStorageKey,
      value: jsonEncode({
        'codeVerifier': codeVerifier,
        'state': state,
        'startedAt': DateTime.now().toIso8601String(),
      }),
    );

    final url = lichessUri('/oauth', {
      'response_type': 'code',
      'client_id': kLichessClientId,
      'redirect_uri': kOAuthRedirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': _codeChallenge(codeVerifier),
      'scope': oauthScopes.join(' '),
      'state': state,
    });

    final opened = await _ref.read(oauthBrowserLauncherProvider)(url);
    if (!opened) {
      throw Exception('Could not open the browser to sign in.');
    }
  }

  /// Completes the sign in from the [callback] redirect: exchanges its authorization code for an
  /// access token, and fetches the account it belongs to.
  ///
  /// Throws a [SignInCancelledException] if the user denied the authorization.
  Future<AuthUser> completeSignIn(Uri callback) async {
    try {
      final pending = await _readPendingSignIn();
      // A code can be exchanged only once, and only with its own verifier.
      await SecureStorage.instance.delete(key: kPendingSignInStorageKey);

      if (pending == null) {
        throw Exception('No sign in in progress.');
      }
      if (callback.queryParameters['state'] != pending.state) {
        throw Exception('The sign in response does not match the sign in request.');
      }
      switch (callback.queryParameters['error']) {
        case null:
          break;
        case 'access_denied':
          throw const SignInCancelledException();
        case final error:
          throw Exception(
            'Sign in failed: ${callback.queryParameters['error_description'] ?? error}',
          );
      }
      final code = callback.queryParameters['code'];
      if (code == null) {
        throw Exception('Authorization code not found.');
      }

      final token = await _ref
          .read(defaultClientProvider)
          .postReadJson(
            lichessUri('/api/token'),
            body: {
              'grant_type': 'authorization_code',
              'code': code,
              'code_verifier': pending.codeVerifier,
              'redirect_uri': kOAuthRedirectUri,
              'client_id': kLichessClientId,
            },
            mapper: (json) => json['access_token'] as String?,
          );
      if (token == null) {
        throw Exception('Access token not found.');
      }

      _log.fine('Got OAuth token response');

      return await _fetchAuthUser(token);
    } on SignInCancelledException {
      rethrow;
    } catch (e, st) {
      await reportSignInFailure(_ref, e, st);
      rethrow;
    }
  }

  Future<({String codeVerifier, String state})?> _readPendingSignIn() async {
    final string = await SecureStorage.instance.read(key: kPendingSignInStorageKey);
    if (string == null) return null;
    final json = jsonDecode(string) as Map<String, dynamic>;
    final startedAt = DateTime.parse(json['startedAt'] as String);
    if (DateTime.now().difference(startedAt) > _kPendingSignInLifetime) return null;
    return (codeVerifier: json['codeVerifier'] as String, state: json['state'] as String);
  }

  /// Fetches the account owning [token] and pairs it with the token.
  Future<AuthUser> _fetchAuthUser(String token) async {
    final user = await _client.readJson(
      Uri(path: '/api/account'),
      headers: {'Authorization': 'Bearer $token'},
      mapper: User.fromServerJson,
    );
    return AuthUser(token: token, user: user.lightUser);
  }

  /// Sign out the current user by revoking the auth token.
  Future<void> signOut() async {
    await _client.deleteRead(Uri(path: '/api/token'));
  }

  /// Check if the given authUser token is valid.
  Future<bool> checkToken(AuthUser authUser) async {
    final defaultClient = _ref.read(defaultClientProvider);
    final data = await defaultClient
        .postReadJson(lichessUri('/api/token/test'), mapper: (json) => json, body: authUser.token)
        .timeout(const Duration(seconds: 5));
    return data[authUser.token] != null;
  }
}

const _kUnreservedChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// A cryptographically secure random string of URL safe characters, as PKCE requires.
String _randomString(int length) {
  final random = Random.secure();
  return String.fromCharCodes(
    Iterable.generate(
      length,
      (_) => _kUnreservedChars.codeUnitAt(random.nextInt(_kUnreservedChars.length)),
    ),
  );
}

/// The S256 PKCE code challenge of [codeVerifier].
String _codeChallenge(String codeVerifier) =>
    base64UrlEncode(sha256.convert(ascii.encode(codeVerifier)).bytes).replaceAll('=', '');
