import 'dart:convert';
import 'dart:math' as math;

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding/binding.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Storage key of the running study timer (backed up with Knightly's data).
const kStudyTimerStorageKey = 'knightly.studyTimer';

/// The longest a stopwatch session counts, so that a forgotten timer doesn't count all night.
const kMaxStopwatchDuration = Duration(hours: 3);

/// The shortest session that counts.
const kMinStudySession = Duration(minutes: 1);

/// How a session was timed.
enum StudyMode() {
  stopwatch,
  countdown,
  manual,
}

/// The XP of a study session: 1 per full minute.
int studyXp(Duration duration) => duration.inMinutes;

/// A finished study session.
typedef StudySession = ({
  int id,
  Discipline category,
  StudyMode mode,
  DateTime startedAt,
  Duration duration,

  /// The lichess study the session was about, if it was started from one.
  StudyRef? study,
});

/// A lichess study a session is about.
typedef StudyRef = ({StudyId id, String name});

/// The running study timer.
@immutable
class const StudyTimer({
  required final StudyMode mode,
  required final Discipline category,

  /// When the timer was started.
  required final DateTime startedAt,

  /// The countdown's length; null for a stopwatch.
  final Duration? planned,

  /// When the timer was paused, if it is.
  final DateTime? pausedAt,

  /// The time spent paused, before [pausedAt].
  final Duration pausedTotal = Duration.zero,

  /// The lichess study the session is about, if it was started from one.
  final StudyRef? study,
}) {
  factory fromJson(Map<String, dynamic> json) => StudyTimer(
    mode: StudyMode.values.byName(json['mode'] as String),
    category: Discipline.values.byName(json['category'] as String),
    startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
    planned: json['plannedSeconds'] != null
        ? Duration(seconds: json['plannedSeconds'] as int)
        : null,
    pausedAt: json['pausedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['pausedAt'] as int)
        : null,
    pausedTotal: Duration(seconds: json['pausedSeconds'] as int? ?? 0),
    study: json['studyId'] != null
        ? (id: StudyId(json['studyId'] as String), name: json['studyName'] as String? ?? '')
        : null,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'category': category.name,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'plannedSeconds': planned?.inSeconds,
    'pausedAt': pausedAt?.millisecondsSinceEpoch,
    'pausedSeconds': pausedTotal.inSeconds,
    'studyId': study?.id.value,
    'studyName': study?.name,
  };

  bool get isPaused => pausedAt != null;

  /// The time studied at [now], capped at the countdown's length or [kMaxStopwatchDuration].
  Duration elapsed(DateTime now) {
    final end = pausedAt ?? now;
    final studied = end.difference(startedAt) - pausedTotal;
    final cap = planned ?? kMaxStopwatchDuration;
    return Duration(seconds: math.max(0, math.min(studied.inSeconds, cap.inSeconds)));
  }

  /// The time left of a countdown at [now]; null for a stopwatch.
  Duration? remaining(DateTime now) => planned != null ? planned! - elapsed(now) : null;

  /// Whether the timer reached its end at [now]: the countdown's length, or the stopwatch's cap.
  bool isOver(DateTime now) => elapsed(now) >= (planned ?? kMaxStopwatchDuration);

  StudyTimer paused(DateTime now) => isPaused
      ? this
      : StudyTimer(
          mode: mode,
          category: category,
          startedAt: startedAt,
          planned: planned,
          pausedAt: now,
          pausedTotal: pausedTotal,
          study: study,
        );

  StudyTimer resumed(DateTime now) => !isPaused
      ? this
      : StudyTimer(
          mode: mode,
          category: category,
          startedAt: startedAt,
          planned: planned,
          pausedTotal: pausedTotal + now.difference(pausedAt!),
          study: study,
        );
}

/// The study sessions of the signed in user, newest first; empty when signed out.
final studySessionsProvider = AsyncNotifierProvider<StudySessions, IList<StudySession>>(
  StudySessions.new,
  name: 'StudySessionsProvider',
);

class StudySessions() extends AsyncNotifier<IList<StudySession>> {
  @override
  Future<IList<StudySession>> build() async {
    final authUser = ref.watch(authControllerProvider);
    if (authUser == null) return const IListConst([]);
    final db = await ref.watch(knightlyDatabaseProvider.future);
    final rows = await db.query(
      'study_session',
      where: 'userId = ?',
      whereArgs: [authUser.user.id.value],
      orderBy: 'startedAt DESC',
    );
    return [
      for (final row in rows)
        (
          id: row['id']! as int,
          category: Discipline.values.byName(row['category']! as String),
          mode: StudyMode.values.byName(row['mode']! as String),
          startedAt: DateTime.fromMillisecondsSinceEpoch(row['startedAt']! as int),
          duration: Duration(seconds: row['durationSeconds']! as int),
          study: row['studyId'] != null
              ? (id: StudyId(row['studyId']! as String), name: row['studyName'] as String? ?? '')
              : null,
        ),
    ].toIList();
  }

  /// Saves a session, with its XP; a session shorter than [kMinStudySession] doesn't count.
  Future<void> add({
    required Discipline category,
    required StudyMode mode,
    required DateTime startedAt,
    required Duration duration,
    StudyRef? study,
  }) async {
    final authUser = ref.read(authControllerProvider);
    if (authUser == null || duration < kMinStudySession) return;
    final userId = authUser.user.id.value;
    final progression = ref.read(progressionProvider.notifier);
    final db = await ref.read(knightlyDatabaseProvider.future);
    await db.transaction((txn) async {
      final id = await txn.insert('study_session', {
        'userId': userId,
        'category': category.name,
        'mode': mode.name,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'durationSeconds': duration.inSeconds,
        'studyId': study?.id.value,
        'studyName': study?.name,
      });
      await txn.insert('xp_event', {
        'id': 'study:$id',
        'userId': userId,
        'source': 'study',
        'xp': studyXp(duration),
        'discipline': category.name,
        'createdAt': startedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    ref.invalidateSelf();
    await progression.recalculate();
  }

  /// Deletes the session [id] and its XP.
  Future<void> delete(int id) async {
    final authUser = ref.read(authControllerProvider);
    if (authUser == null) return;
    final userId = authUser.user.id.value;
    final progression = ref.read(progressionProvider.notifier);
    final db = await ref.read(knightlyDatabaseProvider.future);
    await db.transaction((txn) async {
      await txn.delete('study_session', where: 'id = ? AND userId = ?', whereArgs: [id, userId]);
      await txn.delete(
        'xp_event',
        where: 'id = ? AND userId = ?',
        whereArgs: ['study:$id', userId],
      );
    });
    ref.invalidateSelf();
    await progression.recalculate();
  }
}

/// The running study timer, if any; it survives the app being closed.
final studyTimerProvider = NotifierProvider<StudyTimerNotifier, StudyTimer?>(
  StudyTimerNotifier.new,
  name: 'StudyTimerProvider',
);

class StudyTimerNotifier() extends Notifier<StudyTimer?> {
  @override
  StudyTimer? build() {
    final stored = LichessBinding.instance.sharedPreferences.getString(kStudyTimerStorageKey);
    if (stored == null) return null;
    try {
      return StudyTimer.fromJson(jsonDecode(stored) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[StudyTimer] Error reading the study timer: $e');
      return null;
    }
  }

  /// Starts a [mode] timer for [category]; a countdown lasts [planned]. [study] is the lichess
  /// study the session is about, if any.
  Future<void> start(StudyMode mode, Discipline category, {Duration? planned, StudyRef? study}) =>
      _save(
        StudyTimer(
          mode: mode,
          category: category,
          startedAt: DateTime.now(),
          planned: planned,
          study: study,
        ),
      );

  Future<void> pause() async {
    if (state case final timer?) await _save(timer.paused(DateTime.now()));
  }

  Future<void> resume() async {
    if (state case final timer?) await _save(timer.resumed(DateTime.now()));
  }

  /// Stops the timer and saves the session. Returns the time studied, or null without a timer.
  Future<Duration?> stop() async {
    final timer = state;
    if (timer == null) return null;
    final elapsed = timer.elapsed(DateTime.now());
    await _save(null);
    await ref
        .read(studySessionsProvider.notifier)
        .add(
          category: timer.category,
          mode: timer.mode,
          startedAt: timer.startedAt,
          duration: elapsed,
          study: timer.study,
        );
    return elapsed;
  }

  /// Stops the timer without saving the session.
  Future<void> discard() => _save(null);

  Future<void> _save(StudyTimer? timer) async {
    state = timer;
    final prefs = LichessBinding.instance.sharedPreferences;
    if (timer == null) {
      await prefs.remove(kStudyTimerStorageKey);
    } else {
      await prefs.setString(kStudyTimerStorageKey, jsonEncode(timer.toJson()));
    }
  }
}
