import 'dart:math' as math;

import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:lichess_mobile/src/model/engine/practice_comment.dart';

/// The engine's verdict on a played move.
typedef MoveJudgement = ({
  MoveVerdict verdict,

  /// The best move in the position before, in SAN, when the played move wasn't it.
  String? bestSan,

  /// The shallowest of the two searches compared.
  int depth,
});

/// Judges the move at [path] of the analysis tree [root] from the evaluations of the positions
/// before and after it, like the practice mode does (see [MoveVerdict.fromShift]).
///
/// Null when either position has no evaluation yet: the engine (local or cloud) has to have looked
/// at both.
MoveJudgement? judgeMove(ViewNode root, UciPath path) {
  final branches = root.branchesOn(path).toList();
  if (branches.isEmpty) return null;
  final branch = branches.last;
  final ViewNode before = branches.length >= 2 ? branches[branches.length - 2] : root;
  final evalBefore = before.eval;
  final evalAfter = branch.eval;
  final playedMove = branch.sanMove;
  if (evalBefore == null || evalAfter == null) return null;

  final mover = before.position.turn;
  final winningChancesBefore = evalBefore.winningChances(mover);
  final winningChancesAfter = evalAfter.winningChances(mover);
  final best = evalBefore.bestMove;
  final isBest = best == null || normalizeUci(best.uci) == normalizeUci(playedMove.move.uci);
  final verdict = MoveVerdict.fromShift(
    winningChancesBefore - winningChancesAfter,
    hasBetterMove: !isBest,
    winningChancesBefore: winningChancesBefore,
    winningChancesAfter: winningChancesAfter,
  );
  return (
    verdict: verdict,
    bestSan: !isBest && before.position.isLegal(best) ? before.position.makeSan(best).$2 : null,
    depth: math.min(evalBefore.depth, evalAfter.depth),
  );
}

/// The verdict's name, as shown to the user.
String verdictLabel(MoveVerdict verdict) => switch (verdict) {
  .goodMove => 'Good move',
  .notBest => 'Not the best, still winning',
  .inaccuracy => 'Inaccuracy',
  .mistake => 'Mistake',
  .blunder => 'Blunder',
};
