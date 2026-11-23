import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:lichess_mobile/src/view/training/training_session_screen.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:material_ui/material_ui.dart';

import '../../model/auth/fake_auth_storage.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// Lets the database work (real time) while the widgets are pumped.
Future<void> _settleDb(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets("a mistake: the game's move and its loss, the best move and its gain, the moves "
      'before it', (tester) async {
    // 1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6?? 4. Qxf7#: Black's mistake was Nf6, g6 was best.
    final app = await makeTestProviderScopeApp(
      tester,
      authUser: fakeAuthUser,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(TrainingSessionScreen.buildRoute()),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.pumpWidget(app);
    final container = ProviderScope.containerOf(tester.element(find.text('Open')));
    const path = ['e2e4', 'e7e5', 'd1h5', 'b8c6', 'f1c4'];
    await tester.runAsync(() async {
      final db = await container.read(knightlyDatabaseProvider.future);
      Position position = Chess.initial;
      for (final uci in path) {
        position = position.play(Move.parse(uci)!);
      }
      await saveTrainingCard(
        db,
        userId: fakeAuthUser.user.id,
        id: 'mistake:abcdefgh:5',
        kind: TrainingKind.mistake,
        sourceId: 'abcdefgh',
        fen: position.fen,
        answer: 'g7g6',
        path: path,
        orientation: Side.black,
        title: 'vs opponent, move 3',
        played: 'g8f6',
        beforeEval: (cp: 30, mate: null),
        playedEval: (cp: null, mate: 1),
        bestEval: (cp: 40, mate: null),
      );
    });
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _settleDb(tester);

    // From Black's side: -0.3 before, mated after Nf6.
    expect(find.textContaining('In your game: Nf6', findRichText: true), findsOneWidget);
    expect(find.textContaining('-0.3 → #-1', findRichText: true), findsOneWidget);
    expect(find.textContaining('Best:', findRichText: true), findsNothing);

    // The moves before it, and back.
    await tester.tap(find.bySemanticsLabel('Previous move').first);
    await tester.pump();
    expect(find.text('Going through the game: come back to the end to play.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Next move').first);
    await tester.pump();
    expect(find.text('Find the move you missed in your game.'), findsOneWidget);

    await playMove(tester, 'g7', 'g6', orientation: Side.black);
    await tester.pump();
    await _settleDb(tester);
    expect(find.text('Correct!'), findsOneWidget);
    expect(find.textContaining('Best: g6', findRichText: true), findsOneWidget);
    expect(find.textContaining('-0.4', findRichText: true), findsOneWidget);
  });

  /// Opens a session with one card: 1. e4, the user's move as White.
  Future<ProviderContainer> openSession(WidgetTester tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      authUser: fakeAuthUser,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(TrainingSessionScreen.buildRoute()),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.pumpWidget(app);
    final container = ProviderScope.containerOf(tester.element(find.text('Open')));
    await tester.runAsync(() async {
      final db = await container.read(knightlyDatabaseProvider.future);
      await saveTrainingCard(
        db,
        userId: fakeAuthUser.user.id,
        id: 'opening:1:start',
        kind: TrainingKind.opening,
        sourceId: '1',
        fen: Chess.initial.fen,
        answer: 'e2e4',
        path: const [],
        orientation: Side.white,
        title: 'My White',
      );
    });
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _settleDb(tester);
    return container;
  }

  testWidgets('the right move: correct, and the session is done', (tester) async {
    final container = await openSession(tester);
    expect(find.text('My White'), findsOneWidget);
    expect(find.text('Your move: what does your repertoire play?'), findsOneWidget);

    await playMove(tester, 'e2', 'e4');
    await tester.pump();
    expect(find.text('Correct!'), findsOneWidget);
    await _settleDb(tester);
    // It waits for Next.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Correct!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('training-next')));
    await tester.pump();
    expect(find.text('Session done'), findsOneWidget);
    expect(find.text('1 of 1 right the first time.'), findsOneWidget);

    await tester.runAsync(() async {
      final db = await container.read(knightlyDatabaseProvider.future);
      final row = (await db.query('training_card')).single;
      expect(row['reps'], 1);
    });
  });

  testWidgets('a wrong move shows the right one, which the user then plays', (tester) async {
    await openSession(tester);
    await playMove(tester, 'd2', 'd4');
    await tester.pump();
    expect(find.text('Not this one. Play the move shown.'), findsOneWidget);
    final shapes = tester.widget<GameLayout>(find.byType(GameLayout)).shapes;
    expect(shapes?.whereType<Arrow>().single.dest, Square.e4);
    await _settleDb(tester);

    // The right move: the card comes back at the end of the session.
    await playMove(tester, 'e2', 'e4');
    await tester.pump();
    await _settleDb(tester);
    expect(find.text("That's the move. It comes back later."), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('training-next')));
    await tester.pump();
    expect(find.text('My White'), findsOneWidget);
    expect(find.text('Your move: what does your repertoire play?'), findsOneWidget);

    // Right this time: done, but it counted as wrong.
    await playMove(tester, 'e2', 'e4');
    await tester.pump();
    await _settleDb(tester);
    await tester.tap(find.byKey(const ValueKey('training-next')));
    await tester.pump();
    expect(find.text('0 of 1 right the first time.'), findsOneWidget);
  });
}
