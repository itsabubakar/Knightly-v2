import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/board_api/board_events.dart';
import 'package:lichess_mobile/src/model/board_api/board_game_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/view/board_game/board_game_view.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../auth/fake_auth_storage.dart';
import 'fake_board_api.dart';

const _id = GameId('abcdefgh');

/// Lets the fake streams deliver their lines.
Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeBoardApi api;

  setUp(() => api = FakeBoardApi());
  tearDown(() => api.close());

  Future<ProviderContainer> makeBoardContainer() async {
    final container = await makeContainer(
      authUser: fakeAuthUser,
      overrides: {
        useBoardApiProvider: useBoardApiProvider.overrideWithValue(true),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(api.client),
        ),
      },
    );
    container.listen(boardGameControllerProvider(_id), (_, _) {});
    return container;
  }

  Future<BoardGameState> load(ProviderContainer container, Map<String, dynamic> full) {
    api.gameLines.add(full);
    return container.read(boardGameControllerProvider(_id).future);
  }

  group('BoardGameController', () {
    test('loads the game from its gameFull line', () async {
      final container = await makeBoardContainer();
      final game = await load(container, gameFullJson(moves: 'e2e4 e7e5'));

      expect(game.mySide, Side.white);
      expect(game.sans.toList(), ['e4', 'e5']);
      expect(game.isMyTurn, isTrue);
      expect(game.clocksRunning, isTrue);
      expect(game.black.title, 'FM');
      expect(game.clock?.increment, const Duration(seconds: 5));
    });

    test('a move shows at once, is sent to lichess, then confirmed', () async {
      final container = await makeBoardContainer();
      await load(container, gameFullJson(moves: 'e2e4 e7e5'));

      final played = container
          .read(boardGameControllerProvider(_id).notifier)
          .userMove(Move.parse('g1f3')!);
      final optimistic = container.read(boardGameControllerProvider(_id)).value!;
      expect(optimistic.sans.last, 'Nf3');
      expect(optimistic.pendingMove, 'g1f3');
      expect(optimistic.isMyTurn, isFalse);
      await played;
      expect(api.posts.map((p) => p.$1), contains('/api/board/game/abcdefgh/move/g1f3'));

      api.gameLines.add(gameStateJson(moves: 'e2e4 e7e5 g1f3'));
      await _flush();
      final confirmed = container.read(boardGameControllerProvider(_id)).value!;
      expect(confirmed.pendingMove, isNull);
      expect(confirmed.moves.length, 3);
    });

    test('castling is sent as the king two squares move', () async {
      final container = await makeBoardContainer();
      await load(container, gameFullJson(moves: 'e2e4 e7e5 g1f3 b8c6 f1c4 g8f6'));

      // The board gives castling as the king taking its rook.
      await container
          .read(boardGameControllerProvider(_id).notifier)
          .userMove(const NormalMove(from: Square.e1, to: Square.h1));
      expect(api.posts.map((p) => p.$1), contains('/api/board/game/abcdefgh/move/e1g1'));

      // And lichess's castling replays as castling.
      api.gameLines.add(gameStateJson(moves: 'e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 e1g1'));
      await _flush();
      expect(container.read(boardGameControllerProvider(_id)).value!.sans.last, 'O-O');
    });

    test('can only move on its turn', () async {
      final container = await makeBoardContainer();
      await load(container, gameFullJson(moves: 'e2e4'));

      await container.read(boardGameControllerProvider(_id).notifier).userMove(Move.parse('d2d4')!);
      expect(api.posts, isEmpty);
    });

    test('the opponent offers a draw, then the game ends', () async {
      final container = await makeBoardContainer();
      await load(container, gameFullJson(moves: 'e2e4 e7e5'));

      api.gameLines.add(gameStateJson(moves: 'e2e4 e7e5', bdraw: true));
      await _flush();
      expect(container.read(boardGameControllerProvider(_id)).value!.opponentOffersDraw, isTrue);

      api.gameLines.add(gameStateJson(moves: 'e2e4 e7e5', status: 'resign', winner: 'black'));
      await _flush();
      final over = container.read(boardGameControllerProvider(_id)).value!;
      expect(over.isOver, isTrue);
      expect(over.clocksRunning, isFalse);
      expect(boardGameResult(over), '0-1 · White resigned');
    });

    test('the clock of the side to move counts down', () async {
      final container = await makeBoardContainer();
      final game = await load(container, gameFullJson(moves: 'e2e4 e7e5'));

      final later = game.clockAt.add(const Duration(seconds: 7));
      expect(game.timeLeft(Side.white, later), const Duration(minutes: 9, seconds: 53));
      expect(game.timeLeft(Side.black, later), const Duration(minutes: 10));
    });
  });

  group('BoardEvents', () {
    test('finds the start of a game, even announced before asking', () async {
      final container = await makeBoardContainer();
      final events = container.read(boardEventsProvider);
      await _flush();

      api.eventLines.add(gameStartJson());
      await _flush();
      final started = await events.gameStarted(_id);
      expect(started.fullId, const GameFullId('abcdefghwxyz'));
      expect(started.isRealTime, isTrue);
    });
  });
}
