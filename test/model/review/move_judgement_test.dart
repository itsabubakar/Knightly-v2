import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:lichess_mobile/src/model/engine/practice_comment.dart';
import 'package:lichess_mobile/src/model/review/move_judgement.dart';

LocalEval _eval(Position position, {required int cp, required String bestMove, int depth = 18}) =>
    LocalEval(
      position: position,
      searchTime: const Duration(seconds: 4),
      cp: cp,
      depth: depth,
      nodes: 100000,
      millis: 4000,
      pvs: IList([
        PvData(moves: IList([bestMove]), cp: cp),
      ]),
      threatMode: false,
    );

/// The tree of 1. e4 e5, the path of Black's e5, and the position before it.
(Root, UciPath, Position) _game() {
  final root = Root.fromPgnMoves('e4 e5');
  final path = UciPath.fromNodeList(root.mainline.toList());
  return (root, path, root.mainline.first.position);
}

void main() {
  test('judges a move that throws the game away as a blunder, with the best move', () {
    final (root, path, before) = _game();
    // Equal before; after e5, White is winning by 5 pawns: Black's winning chances collapse.
    root.updateAt(path.penultimate, (node) => node.eval = _eval(before, cp: 30, bestMove: 'c7c5'));
    root.updateAt(path, (node) => node.eval = _eval(node.position, cp: 500, bestMove: 'g1f3'));

    final judgement = judgeMove(root.view, path)!;

    expect(judgement.verdict, MoveVerdict.blunder);
    expect(judgement.bestSan, 'c5');
    expect(judgement.depth, 18);
  });

  test('judges the best move as a good move', () {
    final (root, path, before) = _game();
    root.updateAt(path.penultimate, (node) => node.eval = _eval(before, cp: 30, bestMove: 'e7e5'));
    root.updateAt(path, (node) => node.eval = _eval(node.position, cp: 35, bestMove: 'g1f3'));

    final judgement = judgeMove(root.view, path)!;

    expect(judgement.verdict, MoveVerdict.goodMove);
    expect(judgement.bestSan, isNull);
  });

  test('cannot judge without both evaluations', () {
    final (root, path, before) = _game();
    expect(judgeMove(root.view, path), isNull);

    root.updateAt(path.penultimate, (node) => node.eval = _eval(before, cp: 30, bestMove: 'c7c5'));
    expect(judgeMove(root.view, path), isNull);
  });
}
