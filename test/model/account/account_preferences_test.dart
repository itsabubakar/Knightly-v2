import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';
import '../auth/fake_auth_storage.dart';

/// Builds a valid `/api/account/preferences` server response, with the `zen` and `favFed` values
/// overridable so tests can assert parsing and refetching.
String prefsResponse({int zen = 0, String? favFed}) =>
    '''
{
  "prefs": {
    "autoQueen": 2,
    "autoThreefold": 2,
    "takeback": 3,
    "moretime": 3,
    "clockTenths": 1,
    "clockSound": true,
    "premove": true,
    "follow": true,
    "challenge": 4,
    "message": 3,
    "submitMove": 4,
    "confirmResign": 1,
    "zen": $zen,
    "pieceNotation": 0,
    "ratings": 1${favFed != null ? ',\n    "favFed": "$favFed"' : ''}
  },
  "language": "en-GB"
}
''';

void main() {
  group('AccountPrefState serialization', () {
    test('round-trips local preferences through JSON storage', () {
      final prefs = defaultAccountPreferences.copyWith(
        showRatings: ShowRatings.no,
        clockSound: const BooleanPref(false),
        favoriteFederation: const FederationId('FRA'),
      );

      // Encode the way local storage does, then inspect the primitive JSON.
      final json = jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>;

      // Enums serialize to their integer value, booleans to JSON booleans.
      expect(json['showRatings'], ShowRatings.no.value);
      expect(json['clockSound'], isFalse);

      final decoded = AccountPrefState.fromJson(json);

      expect(decoded.showRatings, ShowRatings.no);
      expect(decoded.clockSound.value, isFalse);
      expect(decoded.favoriteFederation, const FederationId('FRA'));
    });

    test('falls back to defaults on malformed json', () {
      expect(AccountPrefState.fromJson({'zen': 'not-an-int'}), defaultAccountPreferences);
    });
  });

  group('AccountPreferences when signed out', () {
    test('uses local defaults when nothing is stored', () async {
      final container = await makeContainer();

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs, defaultAccountPreferences);
    });

    test('loads persisted local preferences', () async {
      final binding = TestLichessBinding.ensureInitialized();
      final stored = defaultAccountPreferences.copyWith(
        showRatings: ShowRatings.no,
        pieceNotation: PieceNotation.letter,
        clockSound: const BooleanPref(false),
        submitMove: SubmitMove({SubmitMoveChoice.blitz, SubmitMoveChoice.rapid}),
      );
      await binding.setInitialSharedPreferencesValues({
        PrefCategory.account.storageKey: jsonEncode(stored.toJson()),
      });

      final container = await makeContainer();

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs.showRatings, ShowRatings.no);
      expect(prefs.pieceNotation, PieceNotation.letter);
      expect(prefs.clockSound.value, isFalse);
      expect(prefs.submitMove.choices, {SubmitMoveChoice.blitz, SubmitMoveChoice.rapid});
    });

    test('falls back to defaults when stored local preferences are corrupt', () async {
      final binding = TestLichessBinding.ensureInitialized();
      await binding.setInitialSharedPreferencesValues({
        PrefCategory.account.storageKey: 'not valid json {',
      });

      final container = await makeContainer();

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs, defaultAccountPreferences);
    });

    test('setting a preference updates the in-memory state without any network call', () async {
      final requests = <http.BaseRequest>[];
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() {
              return MockClient((request) async {
                requests.add(request);
                return http.Response('', 200);
              });
            });
          }),
        },
      );

      await container.read(accountPreferencesProvider.future);
      await container.read(accountPreferencesProvider.notifier).setShowRatings(ShowRatings.no);

      final prefs = await container.read(accountPreferencesProvider.future);
      expect(prefs.showRatings, ShowRatings.no);
      expect(requests, isEmpty);
    });

    test('setting a preference persists it to local storage', () async {
      final container = await makeContainer();

      await container.read(accountPreferencesProvider.future);
      await container.read(accountPreferencesProvider.notifier).setClockTenths(ClockTenths.always);

      final stored = testBinding.sharedPreferences.getString(PrefCategory.account.storageKey);
      expect(stored, isNotNull);

      final decoded = AccountPrefState.fromJson(jsonDecode(stored!) as Map<String, dynamic>);
      expect(decoded.clockTenths, ClockTenths.always);
    });

    test('local settings feed public preference providers', () async {
      final container = await makeContainer();

      await container.read(accountPreferencesProvider.notifier).setShowRatings(ShowRatings.no);
      await container
          .read(accountPreferencesProvider.notifier)
          .setPieceNotation(PieceNotation.letter);
      await container
          .read(accountPreferencesProvider.notifier)
          .setClockSound(const BooleanPref(false));
      await container.read(accountPreferencesProvider.notifier).setClockTenths(ClockTenths.always);

      expect(await container.read(showRatingsPrefProvider.future), ShowRatings.no);
      expect(await container.read(pieceNotationProvider.future), PieceNotation.letter);
      expect(await container.read(clockSoundProvider.future), isFalse);
      expect(await container.read(clockTenthsProvider.future), ClockTenths.always);
    });
  });

  group('AccountPreferences when signed in', () {
    test('fetches preferences from the server', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == '/api/account/preferences') {
          return mockResponse(prefsResponse(), 200);
        }
        return mockResponse('', 404);
      });

      final container = await makeContainer(
        authUser: fakeAuthUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs.autoQueen, AutoQueen.premove);
      expect(prefs.challenge, Challenge.registered);
      expect(prefs.showRatings, ShowRatings.yes);
      expect(prefs.favoriteFederation, isNull);
    });

    test('falls back to defaults when the server request fails', () async {
      final mockClient = MockClient((request) => mockResponse('', 500));

      final container = await makeContainer(
        authUser: fakeAuthUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs, defaultAccountPreferences);
    });

    test('setting a preference keeps it on the device, over the server value', () async {
      final posts = <http.Request>[];
      final mockClient = MockClient((request) {
        if (request.method == 'GET' && request.url.path == '/api/account/preferences') {
          // The server keeps its own value: Knightly can't write it.
          return mockResponse(prefsResponse(zen: 0), 200);
        }
        if (request.method == 'POST') posts.add(request);
        return mockResponse('', 404);
      });

      final container = await makeContainer(
        authUser: fakeAuthUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );

      final initial = await container.read(accountPreferencesProvider.future);
      expect(initial.zenMode, Zen.no);
      expect(initial.showRatings, ShowRatings.yes);

      await container.read(accountPreferencesProvider.notifier).setZen(Zen.yes);
      await container.read(accountPreferencesProvider.notifier).setShowRatings(ShowRatings.no);

      // Nothing is sent to lichess, which rejects preference writes from third-party apps.
      expect(posts, isEmpty);
      final updated = await container.read(accountPreferencesProvider.future);
      expect(updated.zenMode, Zen.yes);
      expect(updated.showRatings, ShowRatings.no);

      // The changes survive a refetch of the server preferences.
      container.invalidate(accountPreferencesProvider);
      final refetched = await container.read(accountPreferencesProvider.future);
      expect(refetched.zenMode, Zen.yes);
      expect(refetched.showRatings, ShowRatings.no);
      expect(await container.read(showRatingsPrefProvider.future), ShowRatings.no);
    });
  });
}
