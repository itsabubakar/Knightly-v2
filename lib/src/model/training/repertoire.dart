import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/explorer/opening_explorer.dart';
import 'package:lichess_mobile/src/model/explorer/opening_explorer_preferences.dart';
import 'package:lichess_mobile/src/model/explorer/opening_explorer_repository.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _logger = Logger('Repertoire');

/// How deep the opponent's replies are filled in on their own: 20 half moves, move 10.
const kRepertoireAutoDepth = 20;

/// How many of the opponent's most played replies are filled in.
const kRepertoireReplies = 3;

/// A position of a repertoire, whatever the move order that led to it: the pieces, the side to
/// move, the castling rights and the en passant square (no move counters).
String repertoirePositionKey(Position position) => position.fen.split(' ').take(4).join(' ');

/// An opening repertoire: the user's move in each of their positions, the opponent's replies in
/// the others.
typedef Repertoire = ({int id, String name, Side side, DateTime createdAt});

/// A move of a repertoire, from a position.
typedef RepertoireMove = ({String uci, String san});

/// A repertoire and its moves, by position (see [repertoirePositionKey]).
typedef RepertoireTree = ({Repertoire repertoire, IMap<String, IList<RepertoireMove>> moves});

extension RepertoireTreeExtension on RepertoireTree {
  /// The moves of the repertoire in [position].
  IList<RepertoireMove> movesAt(Position position) =>
      moves[repertoirePositionKey(position)] ?? const IListConst([]);

  /// Whether it's the user's move in [position].
  bool isMine(Position position) => position.turn == repertoire.side;

  /// The user's positions reached by the repertoire where their move is still to choose, the
  /// shallowest first, with the moves that lead to them (UCI): the "to do" of the builder.
  List<List<String>> positionsToFill({int maxPlies = kRepertoireAutoDepth}) {
    final result = <List<String>>[];
    final seen = <String>{};
    final queue = Queue<(Position, List<String>)>()..add((Chess.initial, const []));
    while (queue.isNotEmpty) {
      final (position, path) = queue.removeFirst();
      if (!seen.add(repertoirePositionKey(position)) || path.length >= maxPlies) continue;
      final moves = movesAt(position);
      if (isMine(position) && moves.isEmpty) {
        // The start position needs no move to be "to do" for Black: White moves first.
        if (path.isNotEmpty || repertoire.side == Side.white) result.add(path);
        continue;
      }
      for (final move in moves) {
        final parsed = Move.parse(move.uci);
        if (parsed == null || !position.isLegal(parsed)) continue;
        queue.add((position.play(parsed), [...path, move.uci]));
      }
    }
    return result;
  }

  /// The number of the user's moves: one card each.
  int get myMoveCount {
    var count = 0;
    for (final MapEntry(:key, :value) in moves.entries) {
      final turn = key.split(' ')[1] == 'w' ? Side.white : Side.black;
      if (turn == repertoire.side) count += value.length;
    }
    return count;
  }
}

/// The card of the user's move in the position [positionKey] of the repertoire [repertoireId].
String openingCardId(int repertoireId, String positionKey) => 'opening:$repertoireId:$positionKey';

Repertoire _repertoireFromRow(Map<String, Object?> row) => (
  id: row['id']! as int,
  name: row['name']! as String,
  side: Side.values.byName(row['side']! as String),
  createdAt: DateTime.fromMillisecondsSinceEpoch(row['createdAt']! as int),
);

/// The user's repertoires, with their number of moves and of cards due.
typedef RepertoireSummary = ({Repertoire repertoire, int cards, int due});

final repertoiresProvider = FutureProvider.autoDispose<IList<RepertoireSummary>>((Ref ref) async {
  final authUser = ref.watch(authControllerProvider);
  if (authUser == null) return const IListConst([]);
  final db = await ref.watch(knightlyDatabaseProvider.future);
  final rows = await db.query(
    'repertoire',
    where: 'userId = ?',
    whereArgs: [authUser.user.id.value],
    orderBy: 'createdAt',
  );
  return [
    for (final row in rows)
      await () async {
        final repertoire = _repertoireFromRow(row);
        final counts = await countTrainingCards(
          db,
          authUser.user.id,
          sourceId: repertoire.id.toString(),
        );
        return (repertoire: repertoire, cards: counts.total, due: counts.due + counts.fresh);
      }(),
  ].toIList();
}, name: 'RepertoiresProvider');

/// Creates a repertoire; returns its id.
Future<int> createRepertoire(
  Database db,
  UserId userId, {
  required String name,
  required Side side,
}) => db.insert('repertoire', {
  'userId': userId.value,
  'name': name.trim(),
  'side': side.name,
  'createdAt': DateTime.now().millisecondsSinceEpoch,
});

/// Deletes the repertoire [id], its moves and its cards.
Future<void> deleteRepertoire(Database db, UserId userId, int id) => db.transaction((txn) async {
  await txn.delete('repertoire', where: 'id = ? AND userId = ?', whereArgs: [id, userId.value]);
  await txn.delete('repertoire_move', where: 'repertoireId = ?', whereArgs: [id]);
  await txn.delete(
    'training_card',
    where: 'userId = ? AND kind = ? AND sourceId = ?',
    whereArgs: [userId.value, TrainingKind.opening.name, id.toString()],
  );
});

/// A repertoire with its moves, edited in the builder.
final repertoireTreeProvider = AsyncNotifierProvider.autoDispose
    .family<RepertoireTreeNotifier, RepertoireTree, int>(
      RepertoireTreeNotifier.new,
      name: 'RepertoireTreeProvider',
    );

class RepertoireTreeNotifier(final int repertoireId) extends AsyncNotifier<RepertoireTree> {
  @override
  Future<RepertoireTree> build() async {
    final db = await ref.watch(knightlyDatabaseProvider.future);
    final rows = await db.query('repertoire', where: 'id = ?', whereArgs: [repertoireId]);
    if (rows.isEmpty) throw StateError('No repertoire $repertoireId');
    final moveRows = await db.query(
      'repertoire_move',
      where: 'repertoireId = ?',
      whereArgs: [repertoireId],
    );
    final moves = <String, List<RepertoireMove>>{};
    for (final row in moveRows) {
      (moves[row['fen']! as String] ??= []).add((
        uci: row['uci']! as String,
        san: row['san']! as String,
      ));
    }
    return (
      repertoire: _repertoireFromRow(rows.first),
      moves: {for (final e in moves.entries) e.key: e.value.lock}.lock,
    );
  }

  UserId? get _userId => ref.read(authControllerProvider)?.user.id;

  /// Adds [move], played in the position reached by [path] (UCI moves from the start).
  ///
  /// The user's move replaces their other move in that position (one move to learn per position),
  /// and becomes a card; after it, the opponent's most played replies are added on their own, down
  /// to [kRepertoireAutoDepth] (see [addTopReplies]).
  Future<void> addMove(List<String> path, Move move, {bool fillReplies = true}) async {
    final tree = await future;
    final userId = _userId;
    if (userId == null) return;
    final position = _positionAfter(path);
    if (position == null || !position.isLegal(move)) return;
    final (after, san) = position.makeSan(move);
    final key = repertoirePositionKey(position);
    final mine = tree.isMine(position);
    final db = await ref.read(knightlyDatabaseProvider.future);
    await db.transaction((txn) async {
      if (mine) {
        await txn.delete(
          'repertoire_move',
          where: 'repertoireId = ? AND fen = ? AND uci != ?',
          whereArgs: [repertoireId, key, move.uci],
        );
        await saveTrainingCard(
          txn,
          userId: userId,
          id: openingCardId(repertoireId, key),
          kind: TrainingKind.opening,
          sourceId: repertoireId.toString(),
          fen: position.fen,
          answer: move.uci,
          path: path,
          orientation: tree.repertoire.side,
          title: tree.repertoire.name,
        );
      }
      await txn.insert('repertoire_move', {
        'repertoireId': repertoireId,
        'fen': key,
        'uci': move.uci,
        'san': san,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    if (mine) await _prune(db, userId);
    ref.invalidateSelf();
    await future;
    if (mine && fillReplies && path.length + 1 < kRepertoireAutoDepth) {
      await addTopReplies([...path, move.uci], after);
    }
  }

  /// Adds the opponent's [kRepertoireReplies] most played replies in [position] (reached by
  /// [path]), from lichess's games at the levels and speeds of the opening explorer settings.
  Future<void> addTopReplies(List<String> path, Position position) async {
    final tree = await future;
    if (tree.isMine(position) || position.isGameOver) return;
    final OpeningExplorerEntry entry;
    try {
      entry = await fetchRepertoireExplorer(ref, position);
    } catch (e, st) {
      _logger.warning('Could not read the replies of the explorer', e, st);
      return;
    }
    final replies = entry.moves
        .sortedBy<num>((m) => -(m.white + m.draws + m.black))
        .take(kRepertoireReplies);
    final db = await ref.read(knightlyDatabaseProvider.future);
    final key = repertoirePositionKey(position);
    final batch = db.batch();
    for (final reply in replies) {
      batch.insert('repertoire_move', {
        'repertoireId': repertoireId,
        'fen': key,
        'uci': reply.uci,
        'san': reply.san,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    ref.invalidateSelf();
    await future;
  }

  /// Removes the move [uci] in the position reached by [path], and what came after it (unless
  /// another line reaches it).
  Future<void> removeMove(List<String> path, String uci) async {
    final userId = _userId;
    final position = _positionAfter(path);
    if (userId == null || position == null) return;
    final db = await ref.read(knightlyDatabaseProvider.future);
    await db.delete(
      'repertoire_move',
      where: 'repertoireId = ? AND fen = ? AND uci = ?',
      whereArgs: [repertoireId, repertoirePositionKey(position), uci],
    );
    await _prune(db, userId);
    ref.invalidateSelf();
    await future;
  }

  Future<void> rename(String name) async {
    final db = await ref.read(knightlyDatabaseProvider.future);
    await db.update(
      'repertoire',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [repertoireId],
    );
    ref.invalidateSelf();
  }

  /// Removes the moves and cards no longer reached from the start position.
  Future<void> _prune(Database db, UserId userId) async {
    final rows = await db.query(
      'repertoire_move',
      where: 'repertoireId = ?',
      whereArgs: [repertoireId],
    );
    final byKey = <String, List<String>>{};
    for (final row in rows) {
      (byKey[row['fen']! as String] ??= []).add(row['uci']! as String);
    }
    final reached = <String>{};
    final queue = Queue<Position>()..add(Chess.initial);
    while (queue.isNotEmpty) {
      final position = queue.removeFirst();
      final key = repertoirePositionKey(position);
      if (!reached.add(key)) continue;
      for (final uci in byKey[key] ?? const <String>[]) {
        final move = Move.parse(uci);
        if (move != null && position.isLegal(move)) queue.add(position.play(move));
      }
    }
    final unreached = byKey.keys.where((key) => !reached.contains(key)).toList();
    final cards = await db.query(
      'training_card',
      columns: ['id'],
      where: 'userId = ? AND kind = ? AND sourceId = ?',
      whereArgs: [userId.value, TrainingKind.opening.name, repertoireId.toString()],
    );
    final prefix = openingCardId(repertoireId, '');
    final staleCards = [
      for (final card in cards)
        if (byKey[(card['id']! as String).substring(prefix.length)] == null ||
            !reached.contains((card['id']! as String).substring(prefix.length)))
          card['id']! as String,
    ];
    await db.transaction((txn) async {
      for (final key in unreached) {
        await txn.delete(
          'repertoire_move',
          where: 'repertoireId = ? AND fen = ?',
          whereArgs: [repertoireId, key],
        );
      }
      await deleteTrainingCards(txn, userId, staleCards);
    });
  }
}

/// The position after [path] (UCI moves from the start), null if one isn't legal.
Position? _positionAfter(List<String> path) {
  Position position = Chess.initial;
  for (final uci in path) {
    final move = Move.parse(uci);
    if (move == null || !position.isLegal(move)) return null;
    position = position.play(move);
  }
  return position;
}

/// The moves played in [position] in lichess's games, at the levels and speeds of the user's
/// opening explorer settings.
Future<OpeningExplorerEntry> fetchRepertoireExplorer(Ref ref, Position position) {
  final prefs = ref.read(openingExplorerPreferencesProvider).lichessDb;
  return ref
      .read(openingExplorerRepositoryProvider)
      .getLichessDatabase(
        position.fen,
        variant: Variant.standard,
        speeds: prefs.speeds,
        ratings: prefs.ratings,
      );
}

/// The explorer's moves in a position (its FEN), for the builder's suggestions.
final repertoireExplorerProvider = FutureProvider.autoDispose.family<OpeningExplorerEntry, String>(
  (Ref ref, String fen) =>
      fetchRepertoireExplorer(ref, Position.setupPosition(Rule.chess, Setup.parseFen(fen))),
  name: 'RepertoireExplorerProvider',
);
