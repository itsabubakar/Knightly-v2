import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/view/board_game/board_game_view.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../../model/auth/fake_auth_storage.dart';
import '../../model/board_api/fake_board_api.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// The bottom bar button labelled [label].
Finder _button(String label) =>
    find.byWidgetPredicate((widget) => widget is BottomBarButton && widget.label == label);

void main() {
  late FakeBoardApi api;

  setUp(() => api = FakeBoardApi());
  tearDown(() => api.close());

  Future<void> openGame(WidgetTester tester, {String moves = 'e2e4 e7e5'}) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const GameScreen(source: ExistingGameSource(GameFullId('abcdefghwxyz'))),
      authUser: fakeAuthUser,
      overrides: {
        useBoardApiProvider: useBoardApiProvider.overrideWithValue(true),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(api.client),
        ),
      },
    );
    await tester.pumpWidget(app);
    api.gameLines.add(gameFullJson(moves: moves));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Ends the screen's timers.
  Future<void> closeGame(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('a live game opens in the Board API view', (tester) async {
    await openGame(tester);

    expect(find.byType(BoardGameView), findsOneWidget);
    expect(find.text('10+5 · Rated'), findsOneWidget);
    expect(find.textContaining('opponent', findRichText: true), findsOneWidget);
    expect(find.textContaining('testuser', findRichText: true), findsOneWidget);
    // No abort once both sides have moved: resign instead.
    expect(_button('Resign'), findsOneWidget);

    await closeGame(tester);
  });

  testWidgets('accepting the opponent draw offer', (tester) async {
    await openGame(tester);

    api.gameLines.add(gameStateJson(moves: 'e2e4 e7e5', bdraw: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Your opponent offers a draw'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.posts.map((p) => p.$1), contains('/api/board/game/abcdefgh/draw/yes'));

    await closeGame(tester);
  });

  testWidgets('shows the result when the game ends', (tester) async {
    await openGame(tester);

    api.gameLines.add(gameStateJson(moves: 'f2f3 e7e5 g2g4 d8h4', status: 'mate', winner: 'black'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // In the result dialog and under the board.
    expect(find.text('0-1 · Checkmate'), findsNWidgets(2));

    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_button('Analysis board'), findsOneWidget);

    await closeGame(tester);
  });

  testWidgets('a move played on the board is sent to lichess', (tester) async {
    await openGame(tester);

    await playMove(tester, 'g1', 'f3');
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.posts.map((p) => p.$1), contains('/api/board/game/abcdefgh/move/g1f3'));

    await closeGame(tester);
  });

  testWidgets('a premove is played when the opponent moves', (tester) async {
    // Black to move: a move of the user is a premove.
    await openGame(tester, moves: 'e2e4');

    await playMove(tester, 'g1', 'f3');
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.posts, isEmpty);

    api.gameLines.add(gameStateJson(moves: 'e2e4 e7e5'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.posts.map((p) => p.$1), contains('/api/board/game/abcdefgh/move/g1f3'));

    await closeGame(tester);
  });
}
