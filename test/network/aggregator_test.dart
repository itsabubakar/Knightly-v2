import 'package:fake_async/fake_async.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/account/ongoing_game.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/aggregator.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../test_container.dart';
import '../test_helpers.dart';
import 'fake_http_client_factory.dart';
import 'http_test.dart';

void main() {
  setUp(() {
    FakeClient.reset();
  });

  Future<Aggregator> fakeClientAggregator() async {
    final container = await makeContainer(
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
          return FakeHttpClientFactory(() => FakeClient());
        }),
      },
    );
    return await container.read(aggregatorProvider);
  }

  Future<Aggregator> mockClientAggregator(MockClient client) async {
    final container = await lichessClientContainer(client);
    return await container.read(aggregatorProvider);
  }

  final String aggrInterval = '${kAggregationInterval.inMilliseconds}ms';

  group('Aggregator', () {
    test(
      'if only one request is made within $aggrInterval, it will make an atomic request',
      () async {
        final aggregator = await fakeClientAggregator();
        final uri = Uri(path: '/api/test');

        final response = await aggregator.readJson(uri, atomicMapper: (data) => data);

        final requests = FakeClient.verifyRequests();
        expect(requests.length, 1);
        expect(requests.first.url.path, uri.path);
        expect(response, isNotNull);
      },
    );

    test(
      'non supported uris will not aggregate and make atomic request after $aggrInterval',
      () async {
        final aggregator = await fakeClientAggregator();

        final uri1 = Uri(path: '/api/test1');
        final uri2 = Uri(path: '/api/test2');

        fakeAsync((async) {
          aggregator.readJson(uri1, atomicMapper: (data) => data);
          aggregator.readJson(uri2, atomicMapper: (data) => data);

          async.elapse(kAggregationInterval);

          // Check that the requests were made separately
          final requests = FakeClient.verifyRequests();
          expect(requests.length, 2);
        });
      },
    );

    test('supported uris will not aggregate if group has less than half of target group', () async {
      int requestsCount = 0;

      final mockClient = MockClient((request) {
        requestsCount++;
        if (request.url.path == '/api/account') {
          return mockResponse(accountResponse, 200);
        }
        if (request.url.path == '/api/account/playing') {
          return mockResponse(ongoingGameResponse, 200);
        }
        return mockResponse('', 404);
      });

      final aggregator = await mockClientAggregator(mockClient);

      final accountUri = Uri(path: '/api/account', queryParameters: {'playban': '1'});
      final ongoingGamesUri = Uri(path: '/api/account/playing');

      final [account, ongoingGames] = await Future.wait([
        aggregator.readJson(
          accountUri,
          atomicMapper: User.fromServerJson,
          aggregatedMapper: (json) => User.fromServerJson(json as Map<String, dynamic>),
        ),
        aggregator.readJson(
          ongoingGamesUri,
          atomicMapper: ongoingGamesFromServerJson,
          aggregatedMapper: (json) {
            if (json is! List<dynamic>) {
              throw Exception('Could not read json object as {nowPlaying: []}');
            }
            return json
                .map((e) => OngoingGame.fromServerJson(e as Map<String, dynamic>))
                .where((e) => e.variant.isPlaySupported)
                .toIList();
          },
        ),
      ]);

      expect(requestsCount, 2);
      expect(account, isA<User>());
      expect(ongoingGames, isA<IList<OngoingGame>>());
    });

    test('never aggregates into the official app endpoints', () async {
      final requestedPaths = <String>[];

      final mockClient = MockClient((request) {
        requestedPaths.add(request.url.path);
        if (request.url.path == '/api/account') {
          return mockResponse(accountResponse, 200);
        }
        return mockResponse('{}', 200);
      });

      final aggregator = await mockClientAggregator(mockClient);

      await Future.wait([
        aggregator.readJson(Uri(path: '/api/account'), atomicMapper: User.fromServerJson),
        aggregator.readJson(Uri(path: '/api/challenge'), atomicMapper: (json) => json),
        aggregator.readJson(Uri(path: '/tournament/featured'), atomicMapper: (json) => json),
        aggregator.readJson(Uri(path: '/api/tv/channels'), atomicMapper: (json) => json),
      ]);

      // `/api/mobile/home` and `/api/mobile/watch` accept only the official app's tokens.
      expect(requestedPaths, isNot(contains(startsWith('/api/mobile/'))));
      expect(requestedPaths.length, 4);
    });
  });
}

const accountResponse = '''
{
  "id": "testUser",
    "username": "testUser",
    "createdAt": 1290415680000,
    "seenAt": 1290415680000,
    "title": "GM",
    "patron": true,
    "patronColor": 1,
    "perfs": {
      "blitz": {
        "games": 2340,
        "rating": 1681,
        "rd": 30,
        "prog": 10
      },
      "rapid": {
        "games": 2340,
        "rating": 1677,
        "rd": 30,
        "prog": 10
      },
      "classical": {
        "games": 2340,
        "rating": 1618,
        "rd": 30,
        "prog": 10
      }
    },
    "profile": {
      "country": "France",
      "location": "Lille",
      "bio": "test bio",
      "firstName": "John",
      "lastName": "Doe",
      "fideRating": 1800,
      "links": "http://test.com"
    }
}
''';

const ongoingGameResponse = '''
{
  "nowPlaying": [
    {
      "gameId": "rCRw1AuO",
      "fullId": "rCRw1AuOvonq",
      "color": "black",
      "fen": "r1bqkbnr/pppp2pp/2n1pp2/8/8/3PP3/PPPB1PPP/RN1QKBNR w KQkq - 2 4",
      "hasMoved": true,
      "isMyTurn": false,
      "lastMove": "b8c6",
      "opponent": {
        "id": "philippe",
        "rating": 1790,
        "username": "Philippe"
      },
      "perf": "correspondence",
      "rated": false,
      "secondsLeft": 1209600,
      "source": "friend",
      "speed": "correspondence",
      "variant": {
        "key": "standard",
        "name": "Standard"
      }
    }
  ]
}
''';
