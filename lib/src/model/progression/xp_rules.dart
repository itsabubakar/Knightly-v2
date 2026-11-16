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

/// The XP for a finished game of [speed], played anywhere (Knightly, the official app, the website).
///
/// Bullet and UltraBullet give no XP: Knightly is about slower, more thoughtful games.
int gameXp(Speed speed) => switch (speed) {
  Speed.rapid => 15,
  Speed.classical => 25,
  Speed.correspondence => 25,
  Speed.blitz => 5,
  Speed.bullet || Speed.ultraBullet => 0,
};

/// Whether a game with [status] was actually played to the end: aborted games and games never started
/// give no XP.
bool isPlayedGame(GameStatus status) =>
    status.value >= GameStatus.mate.value && status != GameStatus.noStart;
