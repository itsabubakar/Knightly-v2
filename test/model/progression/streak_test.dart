import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/progression/streak.dart';

const _start = Day(2026, 11, 1);

StreakResult _streak(
  Set<int> playedDaysOfMonth, {
  int today = 10,
  int freezes = 0,
  Set<int> frozen = const {},
  int? processedUntil,
}) => computeStreak(
  playedDays: {for (final d in playedDaysOfMonth) Day(2026, 11, d)},
  frozenDays: {for (final d in frozen) Day(2026, 11, d)},
  start: _start,
  today: Day(2026, 11, today),
  processedUntil: processedUntil != null ? Day(2026, 11, processedUntil) : null,
  freezes: freezes,
);

void main() {
  test('counts the days played in a row', () {
    final streak = _streak({7, 8, 9, 10});
    expect(streak.current, 4);
    expect(streak.longest, 4);
    expect(streak.playedToday, isTrue);
  });

  test('a missed day breaks the streak', () {
    final streak = _streak({1, 2, 3, 5, 6}, today: 7);
    expect(streak.statusByDay[const Day(2026, 11, 4)], StreakDayStatus.missed);
    expect(streak.longest, 3);
    // Today is waiting for a game: the streak is not broken yet.
    expect(streak.current, 2);
    expect(streak.statusByDay[const Day(2026, 11, 7)], StreakDayStatus.pending);
  });

  test('a freeze covers a missed day, which keeps the streak but does not count', () {
    final streak = _streak({1, 2, 3, 5, 6}, today: 6, freezes: 2);
    expect(streak.current, 5);
    expect(streak.freezesLeft, 1);
    expect(streak.newlyFrozenDays, [const Day(2026, 11, 4)]);
    expect(streak.statusByDay[const Day(2026, 11, 4)], StreakDayStatus.frozen);
  });

  test('uses no freeze without a streak going', () {
    final streak = _streak({5, 6}, today: 6, freezes: 2);
    expect(streak.freezesLeft, 2);
    expect(streak.newlyFrozenDays, isEmpty);
    expect(streak.current, 2);
  });

  test('a day already settled as missed is not covered by a freeze earned later', () {
    final streak = _streak({1, 2, 3, 5}, today: 5, freezes: 3, processedUntil: 4);
    expect(streak.newlyFrozenDays, isEmpty);
    expect(streak.freezesLeft, 3);
    expect(streak.current, 1);
  });

  test('a day settled as frozen stays frozen', () {
    final streak = _streak({1, 2, 3, 5}, today: 5, frozen: {4}, processedUntil: 4);
    expect(streak.current, 4);
    expect(streak.freezesLeft, 0);
  });

  test('the streak day XP grows by 1 per week of streak, up to 15', () {
    expect(streakDayXp(1), 5);
    expect(streakDayXp(6), 5);
    expect(streakDayXp(7), 6);
    expect(streakDayXp(30), 9);
    expect(streakDayXp(100), 15);
  });

  test('days go across the month and year ends', () {
    expect(const Day(2026, 11, 30).next, const Day(2026, 12, 1));
    expect(const Day(2026, 12, 31).next, const Day(2027, 1, 1));
    expect(const Day(2026, 3, 1).previous, const Day(2026, 2, 28));
    expect(Day.parse('2026-11-05'), const Day(2026, 11, 5));
    expect(const Day(2026, 11, 5).key, '2026-11-05');
  });
}
