import 'package:dartchess/dartchess.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The user's comments on the moves of a game, saved on the phone (lichess's game notes are only
/// for the official app).
///
/// A comment is kept with the moves that lead to it from the start, so a comment on a side line
/// brings its line back with it.

/// Callbacks of a move list whose moves can take the user's comments.
abstract class MoveCommentNotifier() {
  /// Whether the moves can take comments: only a game's do.
  bool get canCommentMoves;

  /// Sets the user's comment on the move at [path]; an empty one removes it.
  Future<void> setMoveComment(UciPath path, String text);
}

/// The user's comment on [branch]: its PGN comments' text.
String userMoveComment(ViewBranch branch) => [
  for (final comment in branch.comments ?? const <PgnComment>[])
    if (comment.text?.isNotEmpty == true) comment.text!,
].join(' ');

/// Sets [text] as the user's comment on [branch], keeping its other comments (clocks).
void setBranchComment(Branch branch, String text) {
  final kept = [
    for (final comment in branch.comments ?? const <PgnComment>[])
      if (comment.text == null || comment.text!.isEmpty) comment,
  ];
  final trimmed = text.trim();
  branch.comments = [...kept, if (trimmed.isNotEmpty) PgnComment(text: trimmed)];
  if (branch.comments!.isEmpty) branch.comments = null;
}

/// The moves (UCI) from [root] to the move at [path].
String movesTo(Root root, UciPath path) =>
    root.branchesOn(path).map((branch) => branch.sanMove.move.uci).join(' ');

/// Saves the user's comment on the move reached by [moves] in the game [gameId].
Future<void> saveMoveComment(Database db, StringId gameId, String moves, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return db.delete(
      'move_comment',
      where: 'gameId = ? AND moves = ?',
      whereArgs: [gameId.value, moves],
    );
  }
  return db.insert('move_comment', {
    'gameId': gameId.value,
    'moves': moves,
    'text': trimmed,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

/// Puts the comments saved for [gameId] on the moves of [root], adding the side lines they are on.
Future<void> applySavedMoveComments(Database db, StringId gameId, Root root) async {
  final rows = await db.query('move_comment', where: 'gameId = ?', whereArgs: [gameId.value]);
  for (final row in rows) {
    Node node = root;
    var found = true;
    for (final uci in (row['moves']! as String).split(' ')) {
      final existing = node.childById(UciCharPair.fromUci(uci));
      if (existing != null) {
        node = existing;
        continue;
      }
      final move = Move.parse(uci);
      if (move == null || !node.position.isLegal(move)) {
        found = false;
        break;
      }
      final (position, san) = node.position.makeSan(move);
      final branch = Branch(position: position, sanMove: SanMove(san, move), isUserAdded: true);
      node.addChild(branch);
      node = branch;
    }
    if (found && node is Branch) setBranchComment(node, row['text']! as String);
  }
}
