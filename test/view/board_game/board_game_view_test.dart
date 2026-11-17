import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/board_api/game_notes.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_screen.dart';
import 'package:lichess_mobile/src/view/board_game/board_game_view.dart';
import 'package:lichess_mobile/src/view/game/correspondence_clock_widget.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/view/settings/board_settings_screen.dart';
import 'package:lichess_mobile/src/view/user/user_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/material_diff.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
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

  Future<void> openGame(
    WidgetTester tester, {
    String moves = 'e2e4 e7e5',
    Map<String, dynamic>? gameFull,
    ShowRatings showRatings = ShowRatings.yes,
  }) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const GameScreen(source: ExistingGameSource(GameFullId('abcdefghwxyz'))),
      authUser: fakeAuthUser,
      overrides: {
        useBoardApiProvider: useBoardApiProvider.overrideWithValue(true),
        showRatingsPrefProvider: showRatingsPrefProvider.overrideWith((ref) => showRatings),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(api.client),
        ),
      },
    );
    await tester.pumpWidget(app);
    api.gameLines.add(gameFull ?? gameFullJson(moves: moves));
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

  testWidgets('shows the ratings', (tester) async {
    await openGame(tester);
    expect(find.textContaining('1550', findRichText: true), findsOneWidget);
    await closeGame(tester);
  });

  testWidgets('hides the ratings when the setting says so', (tester) async {
    await openGame(tester, showRatings: ShowRatings.no);
    expect(find.textContaining('opponent', findRichText: true), findsOneWidget);
    expect(find.textContaining('1550', findRichText: true), findsNothing);
    await closeGame(tester);
  });

  testWidgets('a correspondence game shows the time left to move', (tester) async {
    await openGame(
      tester,
      gameFull: gameFullJson(
        moves: 'e2e4 e7e5',
        daysPerTurn: 3,
        wtime: const Duration(days: 2, hours: 5).inMilliseconds,
        btime: const Duration(days: 3).inMilliseconds,
      ),
    );
    expect(find.byType(CorrespondenceClock), findsNWidgets(2));
    await closeGame(tester);
  });

  testWidgets('the board settings open from the game', (tester) async {
    await openGame(tester);
    await tester.tap(find.byTooltip('Board settings'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(BoardSettingsScreen), findsOneWidget);
    await closeGame(tester);
  });

  testWidgets("tapping a player's name opens their profile", (tester) async {
    await openGame(tester);
    await tester.tap(find.textContaining('opponent', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(UserScreen), findsOneWidget);
    await closeGame(tester);
  });

  testWidgets('a real-time game has no analysis board or notes while it goes on', (tester) async {
    await openGame(tester);
    expect(find.byTooltip('Analysis board'), findsNothing);
    expect(find.byTooltip('Notes'), findsNothing);
    await closeGame(tester);
  });

  testWidgets('a correspondence game has an analysis board without engine', (tester) async {
    await openGame(tester, gameFull: gameFullJson(moves: 'e2e4 e7e5', daysPerTurn: 3));
    await tester.tap(find.byTooltip('Analysis board'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AnalysisScreen), findsOneWidget);
    final screen = tester.widget<AnalysisScreen>(find.byType(AnalysisScreen));
    expect(screen.options, isA<Pgn>().having((o) => o.isComputerAnalysisAllowed, 'engine', false));
    await closeGame(tester);
  });

  testWidgets('the notes of a correspondence game are kept', (tester) async {
    await openGame(tester, gameFull: gameFullJson(moves: 'e2e4 e7e5', daysPerTurn: 3));
    await tester.tap(find.byTooltip('Notes'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'Push the f pawn');
    expect(readGameNote(const GameId('abcdefgh')), 'Push the f pawn');

    // Closed and opened again.
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Notes'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Push the f pawn'), findsOneWidget);
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

  testWidgets('shows the material difference', (tester) async {
    // White took a pawn.
    await openGame(tester, moves: 'e2e4 d7d5 e4d5');
    expect(find.byType(MaterialDifferenceDisplay), findsNWidgets(2));
    expect(find.text('+1'), findsOneWidget);
    await closeGame(tester);
  });

  testWidgets('rematch of a correspondence game sends a new challenge', (tester) async {
    api.postResponses['/api/challenge/opponent'] = {
      'id': 'H9fIRZUk',
      'url': 'https://lichess.org/game/H9fIRZUk',
      'status': 'created',
      'challenger': {'id': 'testuser', 'name': 'testuser', 'rating': 1500},
      'destUser': {'id': 'opponent', 'name': 'opponent', 'rating': 1550},
      'variant': {'key': 'standard', 'name': 'Standard', 'short': 'Std'},
      'rated': true,
      'speed': 'correspondence',
      'timeControl': {'type': 'correspondence', 'daysPerTurn': 3},
      'color': 'black',
      'direction': 'out',
    };
    await openGame(tester, gameFull: gameFullJson(moves: 'e2e4 e7e5', daysPerTurn: 3));
    api.gameLines.add(gameStateJson(moves: 'e2e4 e7e5', status: 'resign', winner: 'black'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // In the result dialog too.
    expect(
      find.descendant(of: find.byType(PlatformAlertDialog), matching: find.text('Rematch')),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(_button('Rematch'));
    // The challenge, then a second to hear if it's declined at once.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));
    final challenge = api.posts.singleWhere((p) => p.$1 == '/api/challenge/opponent');
    // Same settings, colors swapped.
    expect(challenge.$2, contains('days=3'));
    expect(challenge.$2, contains('color=black'));
    expect(find.text('Rematch sent to opponent.'), findsOneWidget);

    await closeGame(tester);
  });

  testWidgets('no rematch while the game is going on', (tester) async {
    await openGame(tester);
    expect(_button('Rematch'), findsNothing);
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
