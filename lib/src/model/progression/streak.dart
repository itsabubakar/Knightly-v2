import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The XP for a day of streak: 5, plus 1 per 7 days of streak, at most 15.
int streakDayXp(int streakLength) => math.min(5 + streakLength ~/ 7, 15);

/// A local calendar date, without time, as `yyyy-MM-dd`.
@immutable
class const Day(final int year, final int month, final int day) implements Comparable<Day> {
  factory of(DateTime date) {
    final local = date.toLocal();
    return Day(local.year, local.month, local.day);
  }

  factory parse(String key) {
    final [year, month, day] = key.split('-').map(int.parse).toList();
    return Day(year, month, day);
  }

  DateTime get dateTime => DateTime(year, month, day);

  /// The day after this one (DateTime handles the month and year ends, and the DST changes).
  Day get next => Day.of(DateTime(year, month, day + 1));

  Day get previous => Day.of(DateTime(year, month, day - 1));

  String get key => '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(Day other) => key.compareTo(other.key);

  bool operator <(Day other) => compareTo(other) < 0;

  bool operator <=(Day other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) => other is Day && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

/// What a day is in the streak.
enum StreakDayStatus() {
  /// At least one game was finished.
  played,

  /// Missed, but covered by a streak freeze.
  frozen,

  /// Missed: the streak was broken.
  missed,

  /// Today, without a game yet: the streak is waiting for one.
  pending,

  /// Before the streak counting started.
  notCounted,
}

/// The streak computed by [computeStreak].
@immutable
class const StreakResult({
  /// The days played in a row (the frozen days keep the streak but don't count), up to today.
  required final int current,

  /// The longest streak.
  required final int longest,

  /// Whether a game was finished today.
  required final bool playedToday,

  /// The streak freezes left.
  required final int freezesLeft,

  /// The missed days newly covered by a freeze.
  required final List<Day> newlyFrozenDays,

  /// The length of the streak on each played day, for its XP.
  required final Map<Day, int> streakLengthByPlayedDay,

  /// The status of each counted day, from the start to today.
  required final Map<Day, StreakDayStatus> statusByDay,
});

/// Computes the streak from [start] to [today], from the [playedDays].
///
/// A missed day after [processedUntil] (the last day already settled) uses a freeze, if the streak
/// is going and [freezes] are left; the days up to [processedUntil] keep their settled outcome: the
/// [frozenDays] were covered, the other missed days broke the streak. So a freeze earned later never
/// covers an old missed day, and a freeze is never used twice for a day.
StreakResult computeStreak({
  required Set<Day> playedDays,
  required Set<Day> frozenDays,
  required Day start,
  required Day today,
  required Day? processedUntil,
  required int freezes,
}) {
  var freezesLeft = freezes;
  final newlyFrozen = <Day>[];
  final lengths = <Day, int>{};
  final statuses = <Day, StreakDayStatus>{};
  var run = 0;
  var longest = 0;
  for (var day = start; day <= today; day = day.next) {
    if (playedDays.contains(day)) {
      run++;
      longest = math.max(longest, run);
      lengths[day] = run;
      statuses[day] = .played;
    } else if (frozenDays.contains(day)) {
      statuses[day] = .frozen;
    } else if (day == today) {
      statuses[day] = .pending;
    } else if (run > 0 && freezesLeft > 0 && (processedUntil == null || processedUntil < day)) {
      freezesLeft--;
      newlyFrozen.add(day);
      statuses[day] = .frozen;
    } else {
      run = 0;
      statuses[day] = .missed;
    }
  }
  return StreakResult(
    current: run,
    longest: longest,
    playedToday: playedDays.contains(today),
    freezesLeft: freezesLeft,
    newlyFrozenDays: newlyFrozen,
    streakLengthByPlayedDay: lengths,
    statusByDay: statuses,
  );
}
