import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/local_analysis/local_analysis_runner.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/service/server_analysis_service.dart';

import '../model/auth/fake_auth_storage.dart';
import '../network/fake_http_client_factory.dart';
import '../test_container.dart';
import '../test_helpers.dart';

const _gameId = GameId('abcdefgh');

/// 1. f3 e5 2. g4?? Qh4#, not analysed by lichess.
const _game = '''
{
  "id": "abcdefgh",
  "rated": false,
  "source": "lobby",
  "variant": "standard",
  "speed": "rapid",
  "perf": "rapid",
  "createdAt": 1706185945680,
  "lastMoveAt": 1706186170504,
  "status": "mate",
  "players": {
    "white": {"user": {"name": "testuser", "id": "testuser"}, "rating": 1500},
    "black": {"user": {"name": "opponent", "id": "opponent"}, "rating": 1500}
  },
  "winner": "black",
  "moves": "f3 e5 g4 Qh4#"
}
''';

void main() {
  test("requesting an analysis shows Knightly's saved one, without lichess", () async {
    final requests = <String>[];
    final client = MockClient((request) {
      requests.add(request.url.path);
      if (request.url.path == '/game/export/abcdefgh') return mockResponse(_game, 200);
      return mockResponse('', 404);
    });
    final container = await makeContainer(
      authUser: fakeAuthUser,
      overrides: {
        useBoardApiProvider: useBoardApiProvider.overrideWithValue(true),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => client),
        ),
      },
    );
    final db = await container.read(knightlyDatabaseProvider.future);
    await saveLocalAnalysis(db, _gameId, [
      (cp: 20, mate: null, pv: ['e2e4']),
      (cp: -50, mate: null, pv: ['e7e5']),
      (cp: -40, mate: null, pv: ['e2e4', 'd8h4']),
      (cp: null, mate: -1, pv: ['d8h4']),
      (cp: null, mate: -1, pv: []),
    ], deep: true);

    final service = container.read(serverAnalysisServiceProvider);
    await service.requestAnalysis(const ServerAnalysisSource.game(gameId: _gameId));

    final (source, event) = service.lastAnalysisEvent.value!;
    expect(source, const ServerAnalysisSource.game(gameId: _gameId));
    expect(event.isAnalysisComplete, isTrue);
    expect(event.analysis?.white.blunders, 1);
    // Already deep: nothing left to run.
    expect(service.currentAnalysis.value, isNull);
    // lichess was not asked to analyse.
    expect(requests, isNot(contains('/game/abcdefgh/request-analysis')));
  });
}
