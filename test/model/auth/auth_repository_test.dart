import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/db/secure_storage.dart';
import 'package:lichess_mobile/src/model/auth/auth_repository.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';

const _accountResponse =
    '{"id":"test","username":"test","createdAt":1290415680000,"seenAt":1290415680000,"perfs":{}}';

/// Answers the token exchange with [token] and the account request with a test account, recording
/// the requests in [requests].
MockClient lichessClient({String token = 'test-token', List<http.Request>? requests}) =>
    MockClient((request) {
      requests?.add(request);
      switch (request.url.path) {
        case '/api/token':
          return mockResponse('{"token_type":"Bearer","access_token":"$token"}', 200);
        case '/api/account':
          return mockResponse(_accountResponse, 200);
        default:
          return mockResponse('', 404);
      }
    });

/// The authorization URLs opened in the browser by the containers of [makeAuthContainer].
final openedUrls = <Uri>[];

Future<ProviderContainer> makeAuthContainer({MockClient? client, OAuthBrowserLauncher? launcher}) {
  return makeContainer(
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
        return FakeHttpClientFactory(() => client ?? lichessClient());
      }),
      oauthBrowserLauncherProvider: oauthBrowserLauncherProvider.overrideWithValue(
        launcher ??
            (url) async {
              openedUrls.add(url);
              return true;
            },
      ),
    },
  );
}

/// Starts a sign in in [container] and returns the authorization URL opened in the browser.
Future<Uri> startSignIn(ProviderContainer container) async {
  await container.read(authRepositoryProvider).startSignIn();
  return openedUrls.last;
}

Uri callbackFor(Uri authorizationUrl, {String code = 'test-code'}) => Uri.parse(kOAuthRedirectUri)
    .replace(queryParameters: {'code': code, 'state': authorizationUrl.queryParameters['state']});

void main() {
  group('AuthRepository.startSignIn', () {
    test('opens the lichess authorization page with a PKCE challenge', () async {
      Uri? openedUrl;
      final container = await makeAuthContainer(
        launcher: (url) async {
          openedUrl = url;
          return true;
        },
      );

      await container.read(authRepositoryProvider).startSignIn();

      expect(openedUrl?.path, '/oauth');
      final params = openedUrl!.queryParameters;
      expect(params['response_type'], 'code');
      expect(params['client_id'], kLichessClientId);
      expect(params['redirect_uri'], '$kOAuthCustomUriSchemeName://login-callback');
      expect(params['scope'], contains('board:play'));
      expect(params['scope'], isNot(contains('web:mobile')));
      expect(params['code_challenge_method'], 'S256');

      final pending = jsonDecode(
        (await SecureStorage.instance.read(key: kPendingSignInStorageKey))!,
      ) as Map<String, dynamic>;
      expect(params['state'], pending['state']);
      final verifier = pending['codeVerifier'] as String;
      expect(
        params['code_challenge'],
        base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', ''),
      );
    });

    test('throws when the browser cannot be opened', () async {
      final container = await makeAuthContainer(launcher: (url) async => false);

      await expectLater(
        container.read(authRepositoryProvider).startSignIn(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('AuthRepository.completeSignIn', () {
    test('exchanges the code for a token and returns the authenticated user', () async {
      final requests = <http.Request>[];
      final container = await makeAuthContainer(client: lichessClient(requests: requests));
      final authorizationUrl = await startSignIn(container);

      final authUser = await container
          .read(authRepositoryProvider)
          .completeSignIn(callbackFor(authorizationUrl));

      expect(authUser.token, 'test-token');
      expect(authUser.user.name, 'test');

      expect(requests.firstWhere((r) => r.url.path == '/api/token').bodyFields, {
        'grant_type': 'authorization_code',
        'code': 'test-code',
        'code_verifier': isA<String>(),
        'redirect_uri': kOAuthRedirectUri,
        'client_id': kLichessClientId,
      });
      expect(
        requests.firstWhere((r) => r.url.path == '/api/account').headers['Authorization'],
        'Bearer test-token',
      );
      expect(await SecureStorage.instance.read(key: kPendingSignInStorageKey), isNull);
    });

    test('completes a sign in started before the app was killed', () async {
      final firstProcess = await makeAuthContainer();
      final authorizationUrl = await startSignIn(firstProcess);
      final pending = await SecureStorage.instance.read(key: kPendingSignInStorageKey);

      // A new process: new providers, and the secure storage is all that remains.
      final secondProcess = await makeAuthContainer();
      await SecureStorage.instance.write(key: kPendingSignInStorageKey, value: pending);

      final authUser = await secondProcess
          .read(authRepositoryProvider)
          .completeSignIn(callbackFor(authorizationUrl));

      expect(authUser.token, 'test-token');
    });

    test('throws when the state does not match', () async {
      final container = await makeAuthContainer();
      await startSignIn(container);

      await expectLater(
        container
            .read(authRepositoryProvider)
            .completeSignIn(
              Uri.parse(kOAuthRedirectUri).replace(queryParameters: {'code': 'c', 'state': 'x'}),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when no sign in was started', () async {
      final container = await makeAuthContainer();

      await expectLater(
        container
            .read(authRepositoryProvider)
            .completeSignIn(callbackFor(Uri(queryParameters: {'state': 's'}))),
        throwsA(isA<Exception>()),
      );
    });

    test('throws SignInCancelledException when the user denies the authorization', () async {
      final container = await makeAuthContainer();
      final authorizationUrl = await startSignIn(container);

      await expectLater(
        container
            .read(authRepositoryProvider)
            .completeSignIn(
              Uri.parse(kOAuthRedirectUri).replace(
                queryParameters: {
                  'error': 'access_denied',
                  'state': authorizationUrl.queryParameters['state'],
                },
              ),
            ),
        throwsA(isA<SignInCancelledException>()),
      );
    });
  });
}
