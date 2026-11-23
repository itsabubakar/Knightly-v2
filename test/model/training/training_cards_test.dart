import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';

import '../../test_container.dart';
import '../auth/fake_auth_storage.dart';

ReviewSchedule _fresh(DateTime now) =>
    (intervalDays: 0.0, ease: 2.5, reps: 0, lapses: 0, dueAt: now);

void main() {
  final now = DateTime(2026, 11, 23, 10);

  group('scheduleReview', () {
    test('right answers wait a day, three days, then longer and longer', () {
      final first = scheduleReview(_fresh(now), correct: true, now: now);
      expect(first.intervalDays, 1);
      expect(first.dueAt, now.add(const Duration(days: 1)));
      final second = scheduleReview(first, correct: true, now: first.dueAt);
      expect(second.intervalDays, 3);
      final third = scheduleReview(second, correct: true, now: second.dueAt);
      expect(third.intervalDays, greaterThan(7));
      expect(third.reps, 3);
    });

    test('a wrong answer brings the card back soon, and starts it over', () {
      final learnt = scheduleReview(
        scheduleReview(_fresh(now), correct: true, now: now),
        correct: true,
        now: now,
      );
      final missed = scheduleReview(learnt, correct: false, now: now);
      expect(missed.dueAt, now.add(kRelearnDelay));
      expect(missed.reps, 0);
      expect(missed.lapses, 1);
      expect(missed.ease, lessThan(learnt.ease));
      expect(scheduleReview(missed, correct: true, now: now).intervalDays, 1);
    });
  });

  group('cards', () {
    Future<ProviderContainer> newContainer() => makeContainer(authUser: fakeAuthUser);

    Future<void> addCard(
      ProviderContainer container,
      String id, {
      List<String> path = const [],
    }) async {
      final db = await container.read(knightlyDatabaseProvider.future);
      await saveTrainingCard(
        db,
        userId: fakeAuthUser.user.id,
        id: id,
        kind: TrainingKind.opening,
        sourceId: '1',
        fen: Chess.initial.fen,
        answer: 'e2e4',
        path: path,
        orientation: Side.white,
        title: 'Test',
      );
    }

    test('new cards come a few a day; a reviewed card is due when its time comes', () async {
      final container = await newContainer();
      for (var i = 0; i < kNewCardsPerDay + 5; i++) {
        await addCard(container, 'card$i');
      }
      final db = await container.read(knightlyDatabaseProvider.future);
      final userId = fakeAuthUser.user.id;
      var queue = await readTrainingQueue(db, userId, now: DateTime.now());
      expect(queue.fresh.length, kNewCardsPerDay);
      expect(queue.due, isEmpty);

      // Reviewed right: no longer new, due tomorrow.
      final card = queue.fresh.first;
      await container.read(trainingReviewsProvider).record(card, correct: true);
      queue = await readTrainingQueue(db, userId, now: DateTime.now());
      expect(queue.fresh.map((c) => c.id), isNot(contains(card.id)));
      // The day's allowance of new cards includes the one reviewed.
      expect(queue.fresh.length, kNewCardsPerDay - 1);
      expect(queue.due, isEmpty);
      final tomorrow = await readTrainingQueue(
        db,
        userId,
        now: DateTime.now().add(const Duration(days: 1, minutes: 1)),
      );
      expect(tomorrow.due.map((c) => c.id), [card.id]);
    });

    test('a right answer gives XP once a day, in its discipline', () async {
      final container = await newContainer();
      await addCard(container, 'card');
      final db = await container.read(knightlyDatabaseProvider.future);
      final card = (await readTrainingQueue(
        db,
        fakeAuthUser.user.id,
        now: DateTime.now(),
      )).fresh.single;
      await container.read(trainingReviewsProvider).record(card, correct: true);
      await container.read(trainingReviewsProvider).record(card, correct: true);
      await container.read(trainingReviewsProvider).record(card, correct: false);
      final events = await db.query('xp_event', where: "source = 'training'");
      expect(events, hasLength(1));
      expect(events.single['discipline'], 'openings');
      expect(events.single['xp'], kTrainingCardXp);
    });

    test('changing the move to find makes the card new again', () async {
      final container = await newContainer();
      await addCard(container, 'card');
      final db = await container.read(knightlyDatabaseProvider.future);
      final userId = fakeAuthUser.user.id;
      final card = (await readTrainingQueue(db, userId, now: DateTime.now())).fresh.single;
      await container.read(trainingReviewsProvider).record(card, correct: true);
      // The same move: the schedule stays.
      await addCard(container, 'card', path: ['e2e4']);
      var row = (await db.query('training_card')).single;
      expect(row['reps'], 1);
      expect(row['path'], 'e2e4');
      // Another move: new again.
      await saveTrainingCard(
        db,
        userId: userId,
        id: 'card',
        kind: TrainingKind.opening,
        sourceId: '1',
        fen: Chess.initial.fen,
        answer: 'd2d4',
        path: const [],
        orientation: Side.white,
        title: 'Test',
      );
      row = (await db.query('training_card')).single;
      expect(row['reps'], 0);
      expect(row['firstReviewedAt'], isNull);
    });
  });
}
