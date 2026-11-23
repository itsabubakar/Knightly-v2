import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:lichess_mobile/src/view/training/training_home_card.dart';
import 'package:lichess_mobile/src/view/training/training_screen.dart';
import 'package:lichess_mobile/src/view/training/training_session_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../model/auth/fake_auth_storage.dart';
import '../../test_provider_scope.dart';

Future<void> _settleDb(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// One opening card, and two mistakes from a game against "opponent".
Future<void> _addCards(ProviderContainer container) async {
  final db = await container.read(knightlyDatabaseProvider.future);
  Future<void> add(String id, TrainingKind kind, String sourceId, String title) => saveTrainingCard(
    db,
    userId: fakeAuthUser.user.id,
    id: id,
    kind: kind,
    sourceId: sourceId,
    fen: Chess.initial.fen,
    answer: 'e2e4',
    path: const [],
    orientation: Side.white,
    title: title,
  );
  await add('opening:1:start', TrainingKind.opening, '1', 'My White');
  await add('mistake:abcdefgh:20', TrainingKind.mistake, 'abcdefgh', 'vs opponent, move 11');
  await add('mistake:abcdefgh:30', TrainingKind.mistake, 'abcdefgh', 'vs opponent, move 16');
}

void main() {
  Future<void> show(WidgetTester tester, Widget home) async {
    final app = await makeTestProviderScopeApp(
      tester,
      authUser: fakeAuthUser,
      home: Scaffold(body: home),
    );
    await tester.pumpWidget(app);
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    await tester.runAsync(() => _addCards(container));
    container.invalidate(trainingSummaryProvider);
    container.invalidate(mistakeGamesProvider);
    await _settleDb(tester);
  }

  testWidgets('the mistakes screen: only the mistakes (the openings set aside)', (tester) async {
    await show(tester, const TrainingScreen());
    expect(find.text('Mistakes from your games'), findsOneWidget);
    expect(find.textContaining('Openings'), findsNothing);
    expect(find.textContaining('Train openings'), findsNothing);
    expect(find.text('Train mistakes (2)'), findsOneWidget);
    expect(find.text('2 puzzles from 1 game · 2 to review'), findsOneWidget);
    // The game the puzzles come from, which opens its own training.
    expect(find.text('vs opponent'), findsOneWidget);

    await tester.tap(find.text('Train mistakes (2)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _settleDb(tester);
    final session = tester.widget<TrainingSessionScreen>(find.byType(TrainingSessionScreen));
    expect(session.kind, TrainingKind.mistake);
    expect(find.text('Your mistake'), findsOneWidget);
  });

  testWidgets("Home's card: the mistakes to review, not the openings", (tester) async {
    await show(tester, const TrainingHomeCard());
    expect(find.text('Openings'), findsNothing);
    expect(find.text('Your mistakes'), findsOneWidget);
    expect(find.text('2 to review'), findsOneWidget);
    expect(find.text('Train'), findsOneWidget);
    // The card's look through recent games waits a few seconds: let it go.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
