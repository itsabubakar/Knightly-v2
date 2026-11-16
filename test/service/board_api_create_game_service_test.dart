import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/board_api/board_events.dart';
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/game.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/service/board_api_create_game_service.dart';
import 'package:lichess_mobile/src/service/create_game_service.dart';

import '../model/auth/fake_auth_storage.dart';
import '../model/board_api/fake_board_api.dart';
import '../network/fake_http_client_factory.dart';
import '../test_container.dart';

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final _challengeJson = jsonDecode('''
{ "id": "H9fIRZUk", "url": "https://lichess.org/game/H9fIRZUk", "status": "created",
  "challenger": { "id": "testuser", "name": "testUser", "rating": 1500 },
  "destUser": { "id": "bobby", "name": "Bobby", "rating": 1635 },
  "variant": { "key": "standard", "name": "Standard", "short": "Std" }, "rated": true,
  "speed": "rapid", "timeControl": { "type": "clock", "limit": 600, "increment": 0, "show": "10+0" },
  "color": "random", "direction": "out" }
''') as Map<String, dynamic>;

void main() {
  late FakeBoardApi api;

  setUp(() => api = FakeBoardApi());
  tearDown(() => api.close());

  Future<(ProviderContainer, CreateGameService)> makeService() async {
    final container = await makeContainer(
      authUser: fakeAuthUser,
      overrides: {
        useBoardApiProvider: useBoardApiProvider.overrideWithValue(true),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(api.client),
        ),
      },
    );
    container.listen(createGameServiceProvider, (_, _) {});
    // The event stream connects first.
    container.read(boardEventsProvider);
    await _flush();
    return (container, container.read(createGameServiceProvider));
  }

  test('Knightly creates games through the Board API', () async {
    final (_, service) = await makeService();
    expect(service, isA<BoardApiCreateGameService>());
  });

  test('a seek is paired through the event stream', () async {
    final (_, service) = await makeService();

    final response = service.newLobbyGame(
      const GameSeek(clock: (Duration(minutes: 10), Duration.zero), rated: true),
    );
    await _flush();
    expect(api.posts.single.$1, '/api/board/seek');
    expect(api.posts.single.$2, contains('rated=true'));

    // A game of another source isn't the seek's.
    api.eventLines.add(gameStartJson(id: 'otherone', source: 'friend'));
    api.eventLines.add(gameStartJson(source: 'lobby'));
    expect(await response, const GameSeekCreated(fullId: GameFullId('abcdefghwxyz')));
  });

  test('a cancelled seek ends the search', () async {
    final (_, service) = await makeService();

    final response = service.newLobbyGame(
      const GameSeek(clock: (Duration(minutes: 15), Duration(seconds: 10)), rated: false),
    );
    await _flush();
    await service.cancelSeek();
    expect(await response, const GameSeekCancelled());
  });

  test('an accepted challenge opens its game', () async {
    final (_, service) = await makeService();
    api.postResponses['/api/challenge/bobby'] = _challengeJson;

    final challenge = await service.newOpenOrRealTimeChallenge(
      const ChallengeRequest(
        destUser: LightUser(id: UserId('bobby'), name: 'Bobby'),
        variant: Variant.standard,
        timeControl: ChallengeTimeControlType.clock,
        clock: (time: Duration(minutes: 10), increment: Duration.zero),
        rated: true,
        sideChoice: SideChoice.random,
      ),
    );
    expect(challenge.id, const ChallengeId('H9fIRZUk'));
    expect(api.posts.single.$2, contains('keepAliveStream=true'));

    final response = service.waitForChallengeResponse(challenge);
    api.eventLines.add(gameStartJson(id: 'H9fIRZUk', source: 'friend'));
    expect(await response, const ChallengeResponseAccepted(gameFullId: GameFullId('H9fIRZUkwxyz')));
  });

  test('a declined challenge says so', () async {
    final (_, service) = await makeService();
    api.postResponses['/api/challenge/bobby'] = _challengeJson;

    final challenge = await service.newOpenOrRealTimeChallenge(
      const ChallengeRequest(
        destUser: LightUser(id: UserId('bobby'), name: 'Bobby'),
        variant: Variant.standard,
        timeControl: ChallengeTimeControlType.clock,
        clock: (time: Duration(minutes: 10), increment: Duration.zero),
        rated: true,
        sideChoice: SideChoice.random,
      ),
    );
    final response = service.waitForChallengeResponse(challenge);
    api.eventLines.add({
      'type': 'challengeDeclined',
      'challenge': {..._challengeJson, 'status': 'declined', 'declineReasonKey': 'later'},
    });
    expect(
      await response,
      isA<ChallengeResponseDeclined>().having(
        (r) => r.declineReason,
        'declineReason',
        ChallengeDeclineReason.later,
      ),
    );
  });
}
