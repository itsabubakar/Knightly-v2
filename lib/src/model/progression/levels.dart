import 'package:flutter/foundation.dart';

/// The XP needed to go from level 1 to 2; each next level needs [kXpPerLevelIncrease] more.
const kXpForLevel2 = 100;

/// How much more XP each level needs than the previous one.
const kXpPerLevelIncrease = 25;

/// The total XP at which [level] starts (level 1 starts at 0).
///
/// Level 2 starts at 100, level 3 at 225, ..., level 8 at 1,225 and level 9 at 1,500.
int xpAtLevelStart(int level) {
  final steps = level - 1;
  return steps * kXpForLevel2 + kXpPerLevelIncrease * steps * (steps - 1) ~/ 2;
}

/// A player's level, computed from their total XP.
@immutable
class const PlayerLevel({required final int totalXp}) {
  /// The level number, from 1.
  int get number {
    var level = 1;
    while (xpAtLevelStart(level + 1) <= totalXp) {
      level++;
    }
    return level;
  }

  /// The total XP at which this level started.
  int get startXp => xpAtLevelStart(number);

  /// The total XP at which the next level starts.
  int get nextLevelXp => xpAtLevelStart(number + 1);

  /// The XP still needed to reach the next level.
  int get xpToNextLevel => nextLevelXp - totalXp;

  /// How far through this level, from 0 to 1.
  double get progress => (totalXp - startXp) / (nextLevelXp - startXp);

  String get title => levelTitle(number);

  String get roman => romanNumeral(number);

  @override
  bool operator ==(Object other) => other is PlayerLevel && other.totalXp == totalXp;

  @override
  int get hashCode => totalXp.hashCode;
}

/// The title of [level].
String levelTitle(int level) => switch (level) {
  <= 2 => 'The Newcomer',
  <= 4 => 'The Learner',
  <= 6 => 'The Apprentice',
  <= 9 => 'The Practitioner',
  <= 12 => 'The Tactician',
  <= 15 => 'The Strategist',
  <= 19 => 'The Expert',
  <= 24 => 'The Master',
  _ => 'The Grandmaster',
};

/// [number] in Roman numerals (e.g. 8 is VIII).
String romanNumeral(int number) {
  const numerals = [
    (1000, 'M'),
    (900, 'CM'),
    (500, 'D'),
    (400, 'CD'),
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  final buffer = StringBuffer();
  var rest = number;
  for (final (value, numeral) in numerals) {
    while (rest >= value) {
      buffer.write(numeral);
      rest -= value;
    }
  }
  return buffer.toString();
}
