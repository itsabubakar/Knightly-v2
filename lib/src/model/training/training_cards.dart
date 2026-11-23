import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// What a training card trains.
enum TrainingKind() {
  /// A position of an opening repertoire: the user plays their prepared move.
  opening,

  /// A mistake from one of the user's games: the user finds the move they missed.
  mistake,
}

/// How many cards never reviewed are shown each day, so that a big new repertoire comes in a little
/// at a time.
const kNewCardsPerDay = 15;

/// The XP for a card answered right (the first time it comes up in a session).
const kTrainingCardXp = 1;

/// When a card answered wrong comes back.
const kRelearnDelay = Duration(minutes: 10);

/// A position and the move to find in it, reviewed with spaced repetition: each right answer makes
/// the wait before the next review longer, a wrong one brings it back soon.
typedef TrainingCard = ({
  String id,
  TrainingKind kind,

  /// The repertoire (its id) or the game the card comes from.
  String sourceId,

  /// The position to play from.
  String fen,

  /// The move to find (UCI).
  String answer,

  /// The moves (UCI) from the start position to [fen], to show how the position came about.
  IList<String> path,
  Side orientation,

  /// What the card is, e.g. "Sicilian, as Black" or "vs opponent, move 23".
  String title,
  DateTime dueAt,
  double intervalDays,
  double ease,
  int reps,
  int lapses,

  /// When the card was first reviewed; null for a new card.
  DateTime? firstReviewedAt,
});

/// The review schedule of a card.
typedef ReviewSchedule = ({double intervalDays, double ease, int reps, int lapses, DateTime dueAt});

/// The schedule of a card after a review at [now]: answered right, the next review waits a day,
/// then three, then longer and longer (the interval times the ease, which grows a little with each
/// right answer); answered wrong, it comes back in [kRelearnDelay] and starts over, a little harder.
ReviewSchedule scheduleReview(
  ReviewSchedule current, {
  required bool correct,
  required DateTime now,
}) {
  if (!correct) {
    return (
      intervalDays: 0,
      ease: math.max(1.3, current.ease - 0.2),
      reps: 0,
      lapses: current.lapses + 1,
      dueAt: now.add(kRelearnDelay),
    );
  }
  final interval = switch (current.reps) {
    0 => 1.0,
    1 => 3.0,
    _ => math.max(current.intervalDays * current.ease, current.intervalDays + 1),
  };
  return (
    intervalDays: interval,
    ease: math.min(3.0, current.ease + 0.05),
    reps: current.reps + 1,
    lapses: current.lapses,
    dueAt: now.add(Duration(minutes: (interval * Duration.minutesPerDay).round())),
  );
}

/// The number a `SELECT COUNT(*)` query gave.
int _count(List<Map<String, Object?>> rows) => (rows.first.values.first! as num).toInt();

/// The start of the day of [time], in local time.
DateTime _startOfDay(DateTime time) => DateTime(time.year, time.month, time.day);

TrainingCard _cardFromRow(Map<String, Object?> row) {
  final path = row['path']! as String;
  return (
    id: row['id']! as String,
    kind: TrainingKind.values.byName(row['kind']! as String),
    sourceId: row['sourceId']! as String,
    fen: row['fen']! as String,
    answer: row['answer']! as String,
    path: path.isEmpty ? const IListConst([]) : path.split(' ').toIList(),
    orientation: Side.values.byName(row['orientation']! as String),
    title: row['title']! as String,
    dueAt: DateTime.fromMillisecondsSinceEpoch(row['dueAt']! as int),
    intervalDays: (row['intervalDays']! as num).toDouble(),
    ease: (row['ease']! as num).toDouble(),
    reps: row['reps']! as int,
    lapses: row['lapses']! as int,
    firstReviewedAt: row['firstReviewedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(row['firstReviewedAt']! as int)
        : null,
  );
}

/// Adds the card [id], or updates what it asks; its schedule is kept, unless the move to find
/// changed (it is then new again).
Future<void> saveTrainingCard(
  DatabaseExecutor db, {
  required UserId userId,
  required String id,
  required TrainingKind kind,
  required String sourceId,
  required String fen,
  required String answer,
  required Iterable<String> path,
  required Side orientation,
  required String title,
}) async {
  final existing = await db.query(
    'training_card',
    columns: ['answer'],
    where: 'id = ? AND userId = ?',
    whereArgs: [id, userId.value],
  );
  final now = DateTime.now().millisecondsSinceEpoch;
  final fields = {
    'kind': kind.name,
    'sourceId': sourceId,
    'fen': fen,
    'answer': answer,
    'path': path.join(' '),
    'orientation': orientation.name,
    'title': title,
  };
  if (existing.isEmpty || existing.first['answer'] != answer) {
    await db.insert('training_card', {
      'id': id,
      'userId': userId.value,
      ...fields,
      'createdAt': now,
      'dueAt': now,
      'intervalDays': 0.0,
      'ease': 2.5,
      'reps': 0,
      'lapses': 0,
      'firstReviewedAt': null,
      'lastReviewedAt': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  } else {
    await db.update(
      'training_card',
      fields,
      where: 'id = ? AND userId = ?',
      whereArgs: [id, userId.value],
    );
  }
}

/// Deletes the cards [ids].
Future<void> deleteTrainingCards(DatabaseExecutor db, UserId userId, Iterable<String> ids) async {
  final list = ids.toList();
  if (list.isEmpty) return;
  await db.delete(
    'training_card',
    where: 'userId = ? AND id IN (${List.filled(list.length, '?').join(',')})',
    whereArgs: [userId.value, ...list],
  );
}

/// What there is to review now: the cards due, and the new cards still allowed today.
typedef TrainingQueue = ({IList<TrainingCard> due, IList<TrainingCard> fresh});

/// The cards to review at [now], of [kind] (all kinds when null) and from [sourceId] (all when
/// null): the due ones first (the most overdue first), then the new ones allowed today.
Future<TrainingQueue> readTrainingQueue(
  Database db,
  UserId userId, {
  required DateTime now,
  TrainingKind? kind,
  String? sourceId,
}) async {
  final filters = [
    'userId = ?',
    if (kind != null) 'kind = ?',
    if (sourceId != null) 'sourceId = ?',
  ].join(' AND ');
  final args = [userId.value, ?kind?.name, ?sourceId];
  final due = await db.query(
    'training_card',
    where: '$filters AND firstReviewedAt IS NOT NULL AND dueAt <= ?',
    whereArgs: [...args, now.millisecondsSinceEpoch],
    orderBy: 'dueAt',
  );
  final introducedToday = _count(
    await db.rawQuery(
      'SELECT COUNT(*) FROM training_card WHERE userId = ? AND firstReviewedAt >= ?',
      [userId.value, _startOfDay(now).millisecondsSinceEpoch],
    ),
  );
  final allowed = math.max(0, kNewCardsPerDay - introducedToday);
  final fresh = allowed == 0
      ? const <Map<String, Object?>>[]
      : await db.query(
          'training_card',
          where: '$filters AND firstReviewedAt IS NULL',
          whereArgs: args,
          // A repertoire's lines in the order they were added, the shortest first.
          orderBy: 'createdAt, length(path)',
          limit: allowed,
        );
  return (due: due.map(_cardFromRow).toIList(), fresh: fresh.map(_cardFromRow).toIList());
}

/// The number of cards of [sourceId] (all when null), and how many of them are due now.
Future<({int total, int due, int fresh})> countTrainingCards(
  Database db,
  UserId userId, {
  String? sourceId,
}) async {
  final queue = await readTrainingQueue(db, userId, now: DateTime.now(), sourceId: sourceId);
  final total = _count(
    await db.rawQuery(
      'SELECT COUNT(*) FROM training_card WHERE userId = ?${sourceId != null ? ' AND sourceId = ?' : ''}',
      [userId.value, ?sourceId],
    ),
  );
  return (total: total, due: queue.due.length, fresh: queue.fresh.length);
}

/// What there is to train today, for the Home card: cards due and new, by kind.
typedef TrainingSummary = ({int openings, int mistakes, int openingCards, int mistakeCards});

final trainingSummaryProvider = FutureProvider.autoDispose<TrainingSummary?>((Ref ref) async {
  final authUser = ref.watch(authControllerProvider);
  if (authUser == null) return null;
  final db = await ref.watch(knightlyDatabaseProvider.future);
  final queue = await readTrainingQueue(db, authUser.user.id, now: DateTime.now());
  final cards = [...queue.due, ...queue.fresh];
  final totals = await db.rawQuery(
    'SELECT kind, COUNT(*) AS n FROM training_card WHERE userId = ? GROUP BY kind',
    [authUser.user.id.value],
  );
  int totalOf(TrainingKind kind) =>
      totals.firstWhere((row) => row['kind'] == kind.name, orElse: () => {'n': 0})['n']! as int;
  return (
    openings: cards.where((card) => card.kind == TrainingKind.opening).length,
    mistakes: cards.where((card) => card.kind == TrainingKind.mistake).length,
    openingCards: totalOf(TrainingKind.opening),
    mistakeCards: totalOf(TrainingKind.mistake),
  );
}, name: 'TrainingSummaryProvider');

/// Records the review of [card] at [now], [correct] or not, and gives its XP the first time it is
/// answered right in a day (Openings for an opening card, Tactics for a mistake). Returns the new
/// schedule.
final trainingReviewsProvider = Provider<TrainingReviews>(
  TrainingReviews.new,
  name: 'TrainingReviewsProvider',
);

/// Records the reviews of training cards.
class TrainingReviews(final Ref ref) {
  /// See [recordReview].
  Future<ReviewSchedule> record(TrainingCard card, {required bool correct, DateTime? now}) =>
      recordReview(ref, card, correct: correct, now: now);
}

Future<ReviewSchedule> recordReview(
  Ref ref,
  TrainingCard card, {
  required bool correct,
  DateTime? now,
}) async {
  final authUser = ref.read(authControllerProvider);
  final at = now ?? DateTime.now();
  final schedule = scheduleReview(
    (
      intervalDays: card.intervalDays,
      ease: card.ease,
      reps: card.reps,
      lapses: card.lapses,
      dueAt: card.dueAt,
    ),
    correct: correct,
    now: at,
  );
  if (authUser == null) return schedule;
  final userId = authUser.user.id;
  final db = await ref.read(knightlyDatabaseProvider.future);
  await db.transaction((txn) async {
    await txn.update(
      'training_card',
      {
        'dueAt': schedule.dueAt.millisecondsSinceEpoch,
        'intervalDays': schedule.intervalDays,
        'ease': schedule.ease,
        'reps': schedule.reps,
        'lapses': schedule.lapses,
        'firstReviewedAt': (card.firstReviewedAt ?? at).millisecondsSinceEpoch,
        'lastReviewedAt': at.millisecondsSinceEpoch,
      },
      where: 'id = ? AND userId = ?',
      whereArgs: [card.id, userId.value],
    );
    if (correct) {
      final day = _startOfDay(at);
      await txn.insert('xp_event', {
        'id': 'training:${card.id}:${day.year}-${day.month}-${day.day}',
        'userId': userId.value,
        'source': 'training',
        'xp': kTrainingCardXp,
        'discipline': card.kind == TrainingKind.opening
            ? Discipline.openings.name
            : Discipline.tactics.name,
        'createdAt': at.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  });
  await ref.read(progressionProvider.notifier).recalculate();
  return schedule;
}

/// The games the user's mistake puzzles come from, the latest first: the opponent ("vs …"), the
/// number of puzzles and how many are due.
typedef MistakeGame = ({String gameId, String title, int puzzles, int due});

final mistakeGamesProvider = FutureProvider.autoDispose<IList<MistakeGame>>((Ref ref) async {
  final authUser = ref.watch(authControllerProvider);
  if (authUser == null) return const IListConst([]);
  final db = await ref.watch(knightlyDatabaseProvider.future);
  final now = DateTime.now().millisecondsSinceEpoch;
  final rows = await db.rawQuery(
    '''
    SELECT sourceId, MIN(title) AS title, COUNT(*) AS puzzles,
      SUM(CASE WHEN firstReviewedAt IS NULL OR dueAt <= ? THEN 1 ELSE 0 END) AS due,
      MAX(createdAt) AS createdAt
    FROM training_card WHERE userId = ? AND kind = ?
    GROUP BY sourceId ORDER BY createdAt DESC
    ''',
    [now, authUser.user.id.value, TrainingKind.mistake.name],
  );
  return [
    for (final row in rows)
      (
        gameId: row['sourceId']! as String,
        // "vs opponent, move 12": the game's part.
        title: (row['title']! as String).split(',').first,
        puzzles: (row['puzzles']! as num).toInt(),
        due: (row['due']! as num?)?.toInt() ?? 0,
      ),
  ].toIList();
}, name: 'MistakeGamesProvider');
