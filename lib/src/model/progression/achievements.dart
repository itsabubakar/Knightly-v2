/// The streak freezes a player can hold at once.
const kMaxStreakFreezes = 3;

/// What an achievement measures.
enum AchievementMetric() {
  gamesPlayed,
  rapidOrClassicalGames,
  classicalGames,
  correspondenceGames,
  rapidOrClassicalWins,
  longestWinStreak,
  puzzlesSolved,
  mostPuzzlesInADay,
  level,

  /// The longest streak.
  streakDays,

  /// The moves tagged with a mistake tag.
  mistakesTagged,

  /// The games with a lessons learned note.
  gamesReviewed,

  /// The hours studied, in total.
  studyHours;

  /// Whether the app measures it yet: the others are shown as coming soon.
  bool get isMeasured => true;
}

/// The groups of achievements, in display order.
enum AchievementCategory(final String label) {
  games('Games'),
  puzzles('Puzzles'),
  levels('Levels'),
  streak('Streak'),
  review('Review'),
  study('Study'),
}

/// An achievement: earned once, when its [metric] reaches its [target].
class const Achievement({
  required final String id,
  required final String name,
  required final String description,
  required final AchievementCategory category,
  required final AchievementMetric metric,
  required final int target,

  /// The XP it awards.
  final int xp = 0,

  /// Whether it awards a streak freeze.
  final bool awardsFreeze = false,
});

/// All the achievements, in display order.
const kAchievements = [
  Achievement(
    id: 'first_move',
    name: 'First Move',
    description: 'Finish your first game',
    category: .games,
    metric: .gamesPlayed,
    target: 1,
    xp: 10,
  ),
  Achievement(
    id: 'getting_serious',
    name: 'Getting Serious',
    description: 'Finish 10 Rapid or Classical games',
    category: .games,
    metric: .rapidOrClassicalGames,
    target: 10,
    xp: 25,
  ),
  Achievement(
    id: 'fifty_battles',
    name: 'Fifty Battles',
    description: 'Finish 50 games',
    category: .games,
    metric: .gamesPlayed,
    target: 50,
    xp: 50,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'centurion',
    name: 'Centurion',
    description: 'Finish 100 games',
    category: .games,
    metric: .gamesPlayed,
    target: 100,
    xp: 100,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'long_thinker',
    name: 'Long Thinker',
    description: 'Finish 10 Classical games',
    category: .games,
    metric: .classicalGames,
    target: 10,
    xp: 50,
  ),
  Achievement(
    id: 'pen_pal',
    name: 'Pen Pal',
    description: 'Finish 5 Correspondence games',
    category: .games,
    metric: .correspondenceGames,
    target: 5,
    xp: 40,
  ),
  Achievement(
    id: 'first_blood',
    name: 'First Blood',
    description: 'Win your first Rapid or Classical game',
    category: .games,
    metric: .rapidOrClassicalWins,
    target: 1,
    xp: 15,
  ),
  Achievement(
    id: 'on_a_roll',
    name: 'On a Roll',
    description: 'Win 5 games in a row',
    category: .games,
    metric: .longestWinStreak,
    target: 5,
    xp: 50,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'puzzle_rookie',
    name: 'Puzzle Rookie',
    description: 'Solve 25 puzzles',
    category: .puzzles,
    metric: .puzzlesSolved,
    target: 25,
    xp: 15,
  ),
  Achievement(
    id: 'tactician',
    name: 'Tactician',
    description: 'Solve 250 puzzles',
    category: .puzzles,
    metric: .puzzlesSolved,
    target: 250,
    xp: 75,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'puzzle_machine',
    name: 'Puzzle Machine',
    description: 'Solve 1,000 puzzles',
    category: .puzzles,
    metric: .puzzlesSolved,
    target: 1000,
    xp: 200,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'daily_dose',
    name: 'Daily Dose',
    description: 'Solve 20 puzzles in one day',
    category: .puzzles,
    metric: .mostPuzzlesInADay,
    target: 20,
    xp: 30,
  ),
  Achievement(
    id: 'apprentice',
    name: 'Apprentice',
    description: 'Reach level 5',
    category: .levels,
    metric: .level,
    target: 5,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'practitioner',
    name: 'Practitioner',
    description: 'Reach level 8',
    category: .levels,
    metric: .level,
    target: 8,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'tactician_title',
    name: 'Tactician Title',
    description: 'Reach level 10',
    category: .levels,
    metric: .level,
    target: 10,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'week_warrior',
    name: 'Week Warrior',
    description: 'Keep a 7-day streak',
    category: .streak,
    metric: .streakDays,
    target: 7,
    xp: 50,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'unbreakable',
    name: 'Unbreakable',
    description: 'Keep a 30-day streak',
    category: .streak,
    metric: .streakDays,
    target: 30,
    xp: 150,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'honest_mirror',
    name: 'Honest Mirror',
    description: 'Tag your first mistake',
    category: .review,
    metric: .mistakesTagged,
    target: 1,
    xp: 15,
  ),
  Achievement(
    id: 'student_of_the_game',
    name: 'Student of the Game',
    description: 'Review 10 games (lessons noted)',
    category: .review,
    metric: .gamesReviewed,
    target: 10,
    xp: 75,
    awardsFreeze: true,
  ),
  Achievement(
    id: 'deep_focus',
    name: 'Deep Focus',
    description: 'Study 10 hours in total',
    category: .study,
    metric: .studyHours,
    target: 10,
    xp: 100,
    awardsFreeze: true,
  ),
];
