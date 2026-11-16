import 'dart:convert';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/progression/achievements.dart';
import 'package:lichess_mobile/src/model/progression/levels.dart';
import 'package:lichess_mobile/src/model/progression/streak.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_repository.dart';
import 'package:lichess_mobile/src/model/review/game_tags.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _logger = Logger('Progression');

/// How far back each sync looks again, before the previous one, to catch the games that were still
/// being played: their XP is never counted twice.
const _kSyncOverlap = Duration(days: 1);

/// An achievement with how far the player is towards it.
typedef AchievementProgress = ({Achievement achievement, int current, DateTime? earnedAt});

/// Something to celebrate: a level reached or an achievement earned.
sealed class Celebration();

class LevelUp(final int level) implements Celebration;

class AchievementEarned(final Achievement achievement) implements Celebration;

/// The player's progression: level, XP, achievements and what earned them.
@immutable
class const ProgressionState({
  required final PlayerLevel level,

  /// The XP earned today.
  required final int xpToday,

  /// The games finished since the progression started.
  required final int gamesPlayed,

  /// The puzzles solved since the progression started.
  required final int puzzlesSolved,

  /// The time studied, in total.
  required final Duration studyTime,

  /// The study sessions.
  required final int studySessions,

  /// The streak freezes held, at most [kMaxStreakFreezes].
  required final int streakFreezes,

  /// The days played in a row, up to today (see [computeStreak]).
  required final int currentStreak,

  /// The longest streak since the progression started.
  required final int longestStreak,

  /// Whether a game was finished today, which keeps the streak going.
  required final bool playedToday,

  /// The last 7 days, oldest first, ending today.
  required final IList<({Day day, StreakDayStatus status})> lastWeek,

  /// All the achievements, in display order, with the player's progress.
  required final IList<AchievementProgress> achievements,

  /// What the player hasn't been shown yet: level-ups and achievements, oldest first.
  required final IList<Celebration> celebrations,

  /// When the progression started: when the user first signed in to Knightly with it.
  required final DateTime startedAt,
}) {
  int get totalXp => level.totalXp;
}

/// The progression of the signed in user, synced with their lichess activity; null when signed out.
///
/// XP counts only what happens after the user first signed in to Knightly (see
/// [ProgressionState.startedAt]).
final progressionProvider = AsyncNotifierProvider<ProgressionNotifier, ProgressionState?>(
  ProgressionNotifier.new,
  name: 'ProgressionProvider',
);

class ProgressionNotifier() extends AsyncNotifier<ProgressionState?> {
  @override
  Future<ProgressionState?> build() async {
    final authUser = ref.watch(authControllerProvider);
    if (authUser == null) return null;
    final db = await ref.watch(knightlyDatabaseProvider.future);
    final userId = authUser.user.id;
    final sync = await _readSyncState(db, userId);
    var synced = false;
    try {
      await _sync(db, userId, sync);
      synced = true;
    } catch (e, st) {
      // Offline or lichess unavailable: show what was already counted.
      _logger.warning('Could not sync the progression:', e, st);
    }
    // The missed days are settled (using a freeze or breaking the streak) only with an up to date
    // game history: offline, a day may look missed only because its games are not synced yet.
    if (synced) await _settleStreak(db, userId, sync.startedAt);
    await _awardRewards(db, userId, sync.startedAt);
    return await _readState(db, userId, sync.startedAt);
  }

  /// Syncs with the latest lichess activity.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Updates the XP, level and achievements after a change made in the app (e.g. a tagged move),
  /// without syncing with lichess.
  Future<void> recalculate() async {
    final current = state.value;
    final authUser = ref.read(authControllerProvider);
    if (current == null || authUser == null) return;
    final db = await ref.read(knightlyDatabaseProvider.future);
    final userId = authUser.user.id;
    await _awardRewards(db, userId, current.startedAt);
    if (!ref.mounted) return;
    state = AsyncData(await _readState(db, userId, current.startedAt));
  }

  /// Marks the [ProgressionState.celebrations] as shown.
  Future<void> markCelebrated() async {
    final current = state.value;
    final authUser = ref.read(authControllerProvider);
    if (current == null || authUser == null) return;
    final db = await ref.read(knightlyDatabaseProvider.future);
    final userId = authUser.user.id;
    await db.update('achievement', {'seen': 1}, where: 'userId = ?', whereArgs: [userId.value]);
    final rewards = await _readRewards(db, userId);
    await _writeRewards(db, userId, (
      freezes: rewards.freezes,
      rewardedLevel: rewards.rewardedLevel,
      celebratedLevel: current.level.number,
    ));
    if (!ref.mounted) return;
    state = AsyncData(await _readState(db, userId, current.startedAt));
  }

  Future<void> _sync(Database db, UserId userId, _SyncState syncState) async {
    final since = syncState.lastSyncAt?.subtract(_kSyncOverlap) ?? syncState.startedAt;
    final syncedAt = DateTime.now();

    final games = await ref
        .read(lichessClientProvider)
        .readNdJsonList(
          Uri(
            path: '/api/games/user/$userId',
            queryParameters: {
              'since': since.millisecondsSinceEpoch.toString(),
              'max': '300',
              'moves': 'false',
            },
          ),
          headers: {'Accept': 'application/x-ndjson'},
          mapper: LightExportedGame.fromServerJson,
        );
    final puzzles = await ref.read(puzzleRepositoryProvider).puzzleActivity(300, since: since);

    final batch = db.batch();
    for (final game in games) {
      if (!isPlayedGame(game.status) || game.lastMoveAt.isBefore(syncState.startedAt)) continue;
      _addEvent(
        batch,
        id: 'game:${game.id}',
        userId: userId,
        source: 'game',
        xp: gameXp(game.speed),
        createdAt: game.lastMoveAt,
      );
      final pov = game.white.user?.id == userId ? Side.white : Side.black;
      batch.insert('game_record', {
        'id': game.id.value,
        'userId': userId.value,
        'speed': game.speed.name,
        'result': game.winner == null
            ? 'draw'
            : game.winner == pov
            ? 'win'
            : 'loss',
        'finishedAt': game.lastMoveAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final puzzle in puzzles) {
      if (!puzzle.win || puzzle.date.isBefore(syncState.startedAt)) continue;
      _addEvent(
        batch,
        id: 'puzzle:${puzzle.id}',
        userId: userId,
        source: 'puzzle',
        xp: kPuzzleSolvedXp,
        discipline: Discipline.tactics,
        createdAt: puzzle.date,
      );
    }
    batch.insert('kv', {
      'key': _syncStateKey(userId),
      'value': jsonEncode({
        'startedAt': syncState.startedAt.millisecondsSinceEpoch,
        'lastSyncAt': syncedAt.millisecondsSinceEpoch,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }
}

/// Awards the achievements newly reached, with their XP and freezes, and a freeze per level-up.
///
/// Repeats while an award reaches more: achievement XP can reach a level, which is an achievement.
Future<void> _awardRewards(Database db, UserId userId, DateTime startedAt) async {
  var rewards = await _readRewards(db, userId);
  for (var round = 0; round < 5; round++) {
    final metrics = await _readMetrics(db, userId, startedAt);
    final earned = await _earnedAchievements(db, userId);
    final reached = kAchievements.where(
      (a) =>
          a.metric.isMeasured && !earned.containsKey(a.id) && (metrics[a.metric] ?? 0) >= a.target,
    );

    var freezes = rewards.freezes;
    final batch = db.batch();
    final now = DateTime.now();
    for (final achievement in reached) {
      batch.insert('achievement', {
        'id': achievement.id,
        'userId': userId.value,
        'earnedAt': now.millisecondsSinceEpoch,
        'seen': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      if (achievement.xp > 0) {
        _addEvent(
          batch,
          id: 'achievement:${achievement.id}',
          userId: userId,
          source: 'achievement',
          xp: achievement.xp,
          createdAt: now,
        );
      }
      if (achievement.awardsFreeze) freezes++;
    }
    await batch.commit(noResult: true);

    final level = PlayerLevel(totalXp: await _totalXp(db, userId)).number;
    if (level > rewards.rewardedLevel) freezes += level - rewards.rewardedLevel;
    final updated = (
      freezes: math.min(freezes, kMaxStreakFreezes),
      rewardedLevel: math.max(level, rewards.rewardedLevel),
      celebratedLevel: rewards.celebratedLevel,
    );
    if (updated != rewards) await _writeRewards(db, userId, updated);
    rewards = updated;
    if (reached.isEmpty) return;
  }
}

void _addEvent(
  Batch batch, {
  required String id,
  required UserId userId,
  required String source,
  required int xp,
  Discipline? discipline,
  required DateTime createdAt,
}) {
  batch.insert('xp_event', {
    'id': id,
    'userId': userId.value,
    'source': source,
    'xp': xp,
    'discipline': discipline?.name,
    'createdAt': createdAt.millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

typedef _SyncState = ({DateTime startedAt, DateTime? lastSyncAt});

/// The freezes held, the level up to which the level-ups were rewarded, and up to which they were
/// celebrated.
typedef _Rewards = ({int freezes, int rewardedLevel, int celebratedLevel});

String _syncStateKey(UserId userId) => 'progression:$userId';

String _rewardsKey(UserId userId) => 'rewards:$userId';

/// The sync state of [userId]'s progression, which starts now if it hadn't yet.
Future<_SyncState> _readSyncState(Database db, UserId userId) async {
  final rows = await db.query('kv', where: 'key = ?', whereArgs: [_syncStateKey(userId)]);
  if (rows.isNotEmpty) {
    final json = jsonDecode(rows.first['value']! as String) as Map<String, dynamic>;
    final lastSyncAt = json['lastSyncAt'] as int?;
    return (
      startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
      lastSyncAt: lastSyncAt != null ? DateTime.fromMillisecondsSinceEpoch(lastSyncAt) : null,
    );
  }
  final startedAt = DateTime.now();
  await db.insert('kv', {
    'key': _syncStateKey(userId),
    'value': jsonEncode({'startedAt': startedAt.millisecondsSinceEpoch}),
  });
  return (startedAt: startedAt, lastSyncAt: null);
}

Future<_Rewards> _readRewards(Database db, UserId userId) async {
  final rows = await db.query('kv', where: 'key = ?', whereArgs: [_rewardsKey(userId)]);
  if (rows.isEmpty) return (freezes: 0, rewardedLevel: 1, celebratedLevel: 1);
  final json = jsonDecode(rows.first['value']! as String) as Map<String, dynamic>;
  return (
    freezes: json['freezes'] as int,
    rewardedLevel: json['rewardedLevel'] as int,
    celebratedLevel: json['celebratedLevel'] as int,
  );
}

Future<void> _writeRewards(Database db, UserId userId, _Rewards rewards) => db.insert('kv', {
  'key': _rewardsKey(userId),
  'value': jsonEncode({
    'freezes': rewards.freezes,
    'rewardedLevel': rewards.rewardedLevel,
    'celebratedLevel': rewards.celebratedLevel,
  }),
}, conflictAlgorithm: ConflictAlgorithm.replace);

Future<int> _totalXp(Database db, UserId userId) async {
  final rows = await db.rawQuery(
    'SELECT COALESCE(SUM(xp), 0) AS total FROM xp_event WHERE userId = ?',
    [userId.value],
  );
  return rows.first['total']! as int;
}

/// The earned achievements: their earning date and whether they were celebrated, by id.
Future<Map<String, ({DateTime earnedAt, bool seen})>> _earnedAchievements(
  Database db,
  UserId userId,
) async {
  final rows = await db.query('achievement', where: 'userId = ?', whereArgs: [userId.value]);
  return {
    for (final row in rows)
      row['id']! as String: (
        earnedAt: DateTime.fromMillisecondsSinceEpoch(row['earnedAt']! as int),
        seen: row['seen'] == 1,
      ),
  };
}

/// The measured [AchievementMetric]s of [userId].
Future<Map<AchievementMetric, int>> _readMetrics(
  Database db,
  UserId userId,
  DateTime startedAt,
) async {
  final rapidOrClassical = "speed IN ('${Speed.rapid.name}', '${Speed.classical.name}')";
  final games = (await db.rawQuery(
    '''
    SELECT
      COUNT(*) AS games,
      SUM(CASE WHEN $rapidOrClassical THEN 1 ELSE 0 END) AS rapidOrClassical,
      SUM(CASE WHEN speed = '${Speed.classical.name}' THEN 1 ELSE 0 END) AS classical,
      SUM(CASE WHEN speed = '${Speed.correspondence.name}' THEN 1 ELSE 0 END) AS correspondence,
      SUM(CASE WHEN $rapidOrClassical AND result = 'win' THEN 1 ELSE 0 END) AS rapidOrClassicalWins
    FROM game_record WHERE userId = ?
    ''',
    [userId.value],
  )).first;

  final results = await db.query(
    'game_record',
    columns: ['result'],
    where: 'userId = ?',
    whereArgs: [userId.value],
    orderBy: 'finishedAt',
  );
  var longestWinStreak = 0;
  var winStreak = 0;
  for (final row in results) {
    winStreak = row['result'] == 'win' ? winStreak + 1 : 0;
    longestWinStreak = math.max(longestWinStreak, winStreak);
  }

  final puzzles = (await db.rawQuery(
    '''
    SELECT COALESCE(MAX(perDay), 0) AS mostInADay FROM (
      SELECT COUNT(*) AS perDay FROM xp_event
      WHERE userId = ? AND source = 'puzzle'
      GROUP BY date(createdAt / 1000, 'unixepoch', 'localtime')
    )
    ''',
    [userId.value],
  )).first;
  final solved = (await db.rawQuery(
    "SELECT COUNT(*) AS solved FROM xp_event WHERE userId = ? AND source = 'puzzle'",
    [userId.value],
  )).first;

  return {
    AchievementMetric.gamesPlayed: (games['games'] as int?) ?? 0,
    AchievementMetric.rapidOrClassicalGames: (games['rapidOrClassical'] as int?) ?? 0,
    AchievementMetric.classicalGames: (games['classical'] as int?) ?? 0,
    AchievementMetric.correspondenceGames: (games['correspondence'] as int?) ?? 0,
    AchievementMetric.rapidOrClassicalWins: (games['rapidOrClassicalWins'] as int?) ?? 0,
    AchievementMetric.longestWinStreak: longestWinStreak,
    AchievementMetric.puzzlesSolved: (solved['solved'] as int?) ?? 0,
    AchievementMetric.mostPuzzlesInADay: (puzzles['mostInADay'] as int?) ?? 0,
    AchievementMetric.level: PlayerLevel(totalXp: await _totalXp(db, userId)).number,
    AchievementMetric.streakDays: (await _currentStreak(db, userId, startedAt)).longest,
    AchievementMetric.mistakesTagged: await _count(
      db,
      'SELECT COUNT(*) AS n FROM move_tag WHERE userId = ? AND tag IN (${_mistakeTagIds()})',
      userId,
    ),
    AchievementMetric.gamesReviewed: await _count(
      db,
      "SELECT COUNT(*) AS n FROM game_review WHERE userId = ? AND note != ''",
      userId,
    ),
    AchievementMetric.studyHours: (await _studyTotals(db, userId)).seconds ~/ 3600,
  };
}

/// The study sessions of [userId] and their total time, in seconds.
Future<({int sessions, int seconds})> _studyTotals(Database db, UserId userId) async {
  final row = (await db.rawQuery(
    'SELECT COUNT(*) AS n, COALESCE(SUM(durationSeconds), 0) AS seconds '
    'FROM study_session WHERE userId = ?',
    [userId.value],
  )).first;
  return (sessions: row['n']! as int, seconds: row['seconds']! as int);
}

Future<int> _count(Database db, String sql, UserId userId) async =>
    (await db.rawQuery(sql, [userId.value])).first['n']! as int;

/// The ids of the mistake tags (the starter ones, even if removed from the list since, and the
/// user's own) as an SQL list.
String _mistakeTagIds() => {
  for (final tag in [...kStarterTags, ...readStoredTagList()])
    if (tag.kind == TagKind.mistake) "'${tag.id.replaceAll("'", "''")}'",
}.join(', ');

Future<ProgressionState> _readState(Database db, UserId userId, DateTime startedAt) async {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  final row = (await db.rawQuery(
    '''
    SELECT
      COALESCE(SUM(xp), 0) AS totalXp,
      COALESCE(SUM(CASE WHEN createdAt >= ? THEN xp ELSE 0 END), 0) AS xpToday
    FROM xp_event WHERE userId = ?
    ''',
    [startOfToday, userId.value],
  )).first;
  final level = PlayerLevel(totalXp: row['totalXp']! as int);
  final metrics = await _readMetrics(db, userId, startedAt);
  final earned = await _earnedAchievements(db, userId);
  final rewards = await _readRewards(db, userId);
  final streak = await _currentStreak(db, userId, startedAt);
  final study = await _studyTotals(db, userId);
  final today = Day.of(now);
  var weekStart = today;
  for (var i = 0; i < 6; i++) {
    weekStart = weekStart.previous;
  }

  final unseen = kAchievements.where((a) => earned[a.id]?.seen == false).toList()
    ..sort((a, b) => earned[a.id]!.earnedAt.compareTo(earned[b.id]!.earnedAt));

  return ProgressionState(
    level: level,
    xpToday: row['xpToday']! as int,
    gamesPlayed: metrics[AchievementMetric.gamesPlayed]!,
    puzzlesSolved: metrics[AchievementMetric.puzzlesSolved]!,
    studyTime: Duration(seconds: study.seconds),
    studySessions: study.sessions,
    streakFreezes: rewards.freezes,
    currentStreak: streak.current,
    longestStreak: streak.longest,
    playedToday: streak.playedToday,
    lastWeek: [
      for (var day = weekStart; day <= today; day = day.next)
        (day: day, status: streak.statusByDay[day] ?? StreakDayStatus.notCounted),
    ].toIList(),
    achievements: [
      for (final achievement in kAchievements)
        (
          achievement: achievement,
          current: metrics[achievement.metric] ?? 0,
          earnedAt: earned[achievement.id]?.earnedAt,
        ),
    ].toIList(),
    celebrations: [
      if (level.number > rewards.celebratedLevel) LevelUp(level.number),
      for (final achievement in unseen) AchievementEarned(achievement),
    ].toIList(),
    startedAt: startedAt,
  );
}

String _streakKey(UserId userId) => 'streak:$userId';

/// The settled streak days: up to which day the missed days were settled, and the frozen ones.
Future<({Day? processedUntil, Set<Day> frozenDays})> _readStreakState(
  Database db,
  UserId userId,
) async {
  final rows = await db.query('kv', where: 'key = ?', whereArgs: [_streakKey(userId)]);
  if (rows.isEmpty) return (processedUntil: null, frozenDays: <Day>{});
  final json = jsonDecode(rows.first['value']! as String) as Map<String, dynamic>;
  final processedUntil = json['processedUntil'] as String?;
  return (
    processedUntil: processedUntil != null ? Day.parse(processedUntil) : null,
    frozenDays: {for (final day in json['frozen'] as List<dynamic>) Day.parse(day as String)},
  );
}

Future<Set<Day>> _playedDays(Database db, UserId userId, DateTime startedAt) async {
  final rows = await db.query(
    'game_record',
    columns: ['finishedAt'],
    where: 'userId = ? AND finishedAt >= ?',
    whereArgs: [userId.value, startedAt.millisecondsSinceEpoch],
  );
  return {
    for (final row in rows) Day.of(DateTime.fromMillisecondsSinceEpoch(row['finishedAt']! as int)),
  };
}

/// The streak as it stands, without settling new missed days.
Future<StreakResult> _currentStreak(Database db, UserId userId, DateTime startedAt) async {
  final state = await _readStreakState(db, userId);
  final today = Day.of(DateTime.now());
  return computeStreak(
    playedDays: await _playedDays(db, userId, startedAt),
    frozenDays: state.frozenDays,
    start: Day.of(startedAt),
    today: today,
    // Everything before today counts as settled: no freeze is used here.
    processedUntil: today.previous,
    freezes: 0,
  );
}

/// Settles the missed days up to yesterday, using the freezes, and awards the streak XP.
Future<void> _settleStreak(Database db, UserId userId, DateTime startedAt) async {
  final state = await _readStreakState(db, userId);
  final rewards = await _readRewards(db, userId);
  final today = Day.of(DateTime.now());
  final streak = computeStreak(
    playedDays: await _playedDays(db, userId, startedAt),
    frozenDays: state.frozenDays,
    start: Day.of(startedAt),
    today: today,
    processedUntil: state.processedUntil,
    freezes: rewards.freezes,
  );

  final batch = db.batch();
  for (final MapEntry(key: day, value: length) in streak.streakLengthByPlayedDay.entries) {
    _addEvent(
      batch,
      id: 'streak:${day.key}',
      userId: userId,
      source: 'streak',
      xp: streakDayXp(length),
      createdAt: day.dateTime,
    );
  }
  batch.insert('kv', {
    'key': _streakKey(userId),
    'value': jsonEncode({
      'processedUntil': today.previous.key,
      'frozen': [
        for (final day in {...state.frozenDays, ...streak.newlyFrozenDays}) day.key,
      ],
    }),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await batch.commit(noResult: true);

  if (streak.freezesLeft != rewards.freezes) {
    await _writeRewards(db, userId, (
      freezes: streak.freezesLeft,
      rewardedLevel: rewards.rewardedLevel,
      celebratedLevel: rewards.celebratedLevel,
    ));
  }
}
