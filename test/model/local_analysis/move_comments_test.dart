import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:lichess_mobile/src/model/local_analysis/move_comments.dart';

import '../../test_container.dart';

Root gameTree() => Root.fromPgnGame(PgnGame.parsePgn('1. e4 { [%clk 0:10:00] } e5 2. Nf3 Nc6 *'));

void main() {
  const gameId = StringId('abcdefgh');

  test('a comment replaces the text, keeps the clock', () {
    final e4 = gameTree().mainline.first;
    setBranchComment(e4, 'Best by test');
    expect(userMoveComment(e4.view), 'Best by test');
    expect(e4.clock, const Duration(minutes: 10));

    setBranchComment(e4, '');
    expect(userMoveComment(e4.view), '');
    expect(e4.clock, const Duration(minutes: 10));
  });

  test('comments are saved and come back, with their side line', () async {
    final container = await makeContainer();
    final db = await container.read(knightlyDatabaseProvider.future);

    // On a game move.
    final root = gameTree();
    final nf3Path = UciPath.fromUciMoves(['e2e4', 'e7e5', 'g1f3']);
    await saveMoveComment(db, gameId, movesTo(root, nf3Path), 'Develops and attacks e5');
    // On a side line the user played: 2. f4.
    final e5 = root.mainline.elementAt(1);
    final f4 = Move.parse('f2f4')!;
    final (afterF4, san) = e5.position.makeSan(f4);
    e5.addChild(Branch(position: afterF4, sanMove: SanMove(san, f4)));
    final f4Path = UciPath.fromUciMoves(['e2e4', 'e7e5', 'f2f4']);
    await saveMoveComment(db, gameId, movesTo(root, f4Path), "The King's Gambit, too sharp");

    // The game opened again.
    final reopened = gameTree();
    await applySavedMoveComments(db, gameId, reopened);
    expect(userMoveComment(reopened.nodeAt(nf3Path).view as ViewBranch), 'Develops and attacks e5');
    final sideLine = reopened.nodeAt(f4Path);
    expect(sideLine, isA<Branch>());
    expect(userMoveComment(sideLine.view as ViewBranch), "The King's Gambit, too sharp");

    // Deleted.
    await saveMoveComment(db, gameId, movesTo(reopened, nf3Path), '');
    final again = gameTree();
    await applySavedMoveComments(db, gameId, again);
    expect(userMoveComment(again.nodeAt(nf3Path).view as ViewBranch), '');
  });
}
