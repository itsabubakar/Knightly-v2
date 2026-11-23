import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/local_analysis/local_analysis.dart';
import 'package:lichess_mobile/src/model/training/mistake_puzzles.dart';

/// 1. f3 e5 2. g4?? Qh4#
List<SanMove> _moves() {
  Position position = Chess.initial;
  return [
    for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4'])
      () {
        final move = Move.parse(uci)!;
        final (next, san) = position.makeSan(move);
        position = next;
        return SanMove(san, move);
      }(),
  ];
}

final _evals = <PositionEval?>[
  (cp: 20, mate: null, pv: ['e2e4']),
  (cp: -50, mate: null, pv: ['e7e5']),
  (cp: -40, mate: null, pv: ['e2e4', 'd8h4']),
  (cp: null, mate: -1, pv: ['d8h4']),
  (cp: null, mate: -1, pv: []),
];

void main() {
  test("the user's blunder is found, with the engine's move", () {
    final candidates = findMistakeCandidates(
      initial: Chess.initial,
      moves: _moves(),
      evals: _evals,
      mySide: Side.white,
    );
    expect(candidates, hasLength(1));
    expect(candidates.single.ply, 2);
    expect(candidates.single.bestUci, 'e2e4');
    expect(candidates.single.judgement, MoveJudgement.blunder);
  });

  test("the opponent's moves are not the user's mistakes", () {
    expect(
      findMistakeCandidates(
        initial: Chess.initial,
        moves: _moves(),
        evals: _evals,
        mySide: Side.black,
      ),
      isEmpty,
    );
  });

  group('clearBestMove', () {
    PvData line(String uci, int cp) => PvData(moves: IList([uci]), cp: cp);

    test('a move much better than the next one is the answer', () {
      expect(clearBestMove(IList([line('e2e4', 400), line('d2d4', 30)]), Side.white), 'e2e4');
    });

    test('two moves about as good: no puzzle', () {
      expect(clearBestMove(IList([line('e2e4', 40), line('d2d4', 30)]), Side.white), isNull);
    });

    test("seen from Black's side", () {
      // Good for Black: White's evaluation low.
      expect(clearBestMove(IList([line('e7e5', -400), line('d7d5', -20)]), Side.black), 'e7e5');
    });

    test('a single legal move: no puzzle', () {
      expect(clearBestMove(IList([line('e2e4', 400)]), Side.white), isNull);
    });
  });
}
