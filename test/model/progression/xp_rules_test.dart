import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';

void main() {
  group('gameXp', () {
    test('depends on the speed only, without the length', () {
      expect(gameXp(Speed.rapid), 15);
      expect(gameXp(Speed.classical), 25);
      expect(gameXp(Speed.blitz), 5);
      expect(gameXp(Speed.bullet), 0);
    });

    test('grows with the length of the game, up to x1.5', () {
      // An early resignation gives nothing.
      expect(gameXp(Speed.rapid, moves: 9), 0);
      expect(gameXp(Speed.rapid, moves: 15), 8);
      expect(gameXp(Speed.rapid, moves: 30), 15);
      expect(gameXp(Speed.rapid, moves: 45), 19);
      expect(gameXp(Speed.rapid, moves: 60), 23);
      // No more after 60 moves.
      expect(gameXp(Speed.rapid, moves: 120), 23);
      expect(gameXp(Speed.correspondence, moves: 40), 29);
    });
  });

  test('fullMoves counts the moves of each side together', () {
    expect(fullMoves(0), 0);
    expect(fullMoves(1), 1);
    expect(fullMoves(2), 1);
    expect(fullMoves(89), 45);
  });
}
