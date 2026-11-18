import 'dart:math' as math;

import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';

/// The disciplines of Knightly's progression.
enum Discipline() {
  tactics,
  strategy,
  openings,
  endgames,
  analysis,
}

/// The XP for a solved puzzle (a tactics exercise).
const kPuzzleSolvedXp = 2;

/// The XP for a finished game of [speed], played anywhere (Knightly, the official app, the website):
/// the same for a win, a draw or a loss. With its number of [moves] (from [kGameLengthXpSince]),
/// longer games give more (see [gameLengthFactor]).
///
/// Bullet and UltraBullet give no XP: Knightly is about slower, more thoughtful games.
int gameXp(Speed speed, {int? moves}) {
  final base = switch (speed) {
    Speed.rapid => 15,
    Speed.classical => 25,
    Speed.correspondence => 25,
    Speed.blitz => 5,
    Speed.bullet || Speed.ultraBullet => 0,
  };
  return moves == null ? base : (base * gameLengthFactor(moves)).round();
}

/// Games finished from this day get the XP of their length (before, only of their speed).
final kGameLengthXpSince = DateTime.utc(2026, 11, 18);

/// How the length of a game of [moves] (full moves) scales its XP: nothing under 10 moves (an early
/// resignation), growing to the full XP at 30 moves, then up to ×1.5 at 60 moves and no more (a
/// lost game dragged out doesn't pay).
double gameLengthFactor(int moves) {
  if (moves < 10) return 0;
  if (moves <= 30) return moves / 30;
  return math.min(1.5, 1 + (moves - 30) / 60);
}

/// The number of full moves of a game of [plies] half moves.
int fullMoves(int plies) => (plies + 1) ~/ 2;

/// Whether a game with [status] was actually played to the end: aborted games and games never started
/// give no XP.
bool isPlayedGame(GameStatus status) =>
    status.value >= GameStatus.mate.value && status != GameStatus.noStart;
