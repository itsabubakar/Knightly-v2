import 'package:dartchess/dartchess.dart' show Side;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:lichess_mobile/src/model/review/game_tags.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The XP for a tagged move.
const kMoveTaggedXp = 5;

/// The XP for a reviewed game: one with a lessons learned note.
const kGameReviewedXp = 20;

/// What identifies a reviewed game in the lists: its opponent, date and the user's side.
typedef ReviewedGameInfo = ({GameId gameId, String opponent, DateTime playedAt, Side orientation});

/// A tagged move.
typedef MoveTag = ({int ply, String san, String tagId});

/// The review of one of the user's games: its tagged moves and its lessons learned note.
@immutable
class const GameReviewState({required final IList<MoveTag> tags, required final String note}) {
  /// The tags of the move at [ply].
  ISet<String> tagsAt(int ply) =>
      tags.where((tag) => tag.ply == ply).map((tag) => tag.tagId).toISet();
}

/// The review of the signed in user's game; empty when signed out.
final gameReviewProvider = AsyncNotifierProvider.autoDispose
    .family<GameReviewNotifier, GameReviewState, GameId>(
      GameReviewNotifier.new,
      name: 'GameReviewProvider',
    );

class GameReviewNotifier(final GameId gameId) extends AsyncNotifier<GameReviewState> {
  @override
  Future<GameReviewState> build() async {
    final authUser = ref.watch(authControllerProvider);
    if (authUser == null) return const GameReviewState(tags: IListConst([]), note: '');
    final db = await ref.watch(knightlyDatabaseProvider.future);
    return await _read(db, authUser.user.id);
  }

  /// Puts [tagId] on the move at [ply], or removes it, with its XP.
  Future<void> toggleTag({
    required int ply,
    required String san,
    required String tagId,
    required ReviewedGameInfo info,
  }) async {
    final authUser = ref.read(authControllerProvider);
    if (authUser == null) return;
    final userId = authUser.user.id;
    // Read before the first await: the sheet may be closed, and this provider disposed, meanwhile.
    final progression = ref.read(progressionProvider.notifier);
    final discipline = ref.read(tagListProvider.notifier).byId(tagId)?.discipline;
    final db = await ref.read(knightlyDatabaseProvider.future);
    final eventId = 'tag:$gameId:$ply:$tagId';
    final isTagged = (await future).tagsAt(ply).contains(tagId);
    await db.transaction((txn) async {
      if (isTagged) {
        await txn.delete(
          'move_tag',
          where: 'gameId = ? AND userId = ? AND ply = ? AND tag = ?',
          whereArgs: [gameId.value, userId.value, ply, tagId],
        );
        await txn.delete(
          'xp_event',
          where: 'id = ? AND userId = ?',
          whereArgs: [eventId, userId.value],
        );
      } else {
        await _saveInfo(txn, userId, info);
        await txn.insert('move_tag', {
          'gameId': gameId.value,
          'userId': userId.value,
          'ply': ply,
          'san': san,
          'tag': tagId,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.insert('xp_event', {
          'id': eventId,
          'userId': userId.value,
          'source': 'tag',
          'xp': kMoveTaggedXp,
          'discipline': discipline?.name,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    await _afterChange(db, userId, progression);
  }

  /// Saves the lessons learned [note]: a game with a note is reviewed, which earns XP once.
  Future<void> saveNote(String note, ReviewedGameInfo info) async {
    final authUser = ref.read(authControllerProvider);
    if (authUser == null) return;
    final userId = authUser.user.id;
    final progression = ref.read(progressionProvider.notifier);
    final db = await ref.read(knightlyDatabaseProvider.future);
    final trimmed = note.trim();
    final eventId = 'review:$gameId';
    await db.transaction((txn) async {
      await _saveInfo(txn, userId, info);
      await txn.update(
        'game_review',
        {'note': trimmed, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
        where: 'gameId = ? AND userId = ?',
        whereArgs: [gameId.value, userId.value],
      );
      if (trimmed.isEmpty) {
        await txn.delete(
          'xp_event',
          where: 'id = ? AND userId = ?',
          whereArgs: [eventId, userId.value],
        );
      } else {
        await txn.insert('xp_event', {
          'id': eventId,
          'userId': userId.value,
          'source': 'review',
          'xp': kGameReviewedXp,
          'discipline': Discipline.analysis.name,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    await _afterChange(db, userId, progression);
  }

  Future<void> _saveInfo(Transaction txn, UserId userId, ReviewedGameInfo info) {
    return txn.insert('game_review', {
      'gameId': gameId.value,
      'userId': userId.value,
      'opponent': info.opponent,
      'playedAt': info.playedAt.millisecondsSinceEpoch,
      'orientation': info.orientation.name,
      'note': '',
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _afterChange(Database db, UserId userId, ProgressionNotifier progression) async {
    if (ref.mounted) ref.invalidate(reviewedGamesProvider);
    // The XP, level and the review achievements change.
    await progression.recalculate();
    if (!ref.mounted) return;
    state = AsyncData(await _read(db, userId));
  }

  Future<GameReviewState> _read(Database db, UserId userId) async {
    final tags = await db.query(
      'move_tag',
      where: 'gameId = ? AND userId = ?',
      whereArgs: [gameId.value, userId.value],
      orderBy: 'ply',
    );
    final review = await db.query(
      'game_review',
      columns: ['note'],
      where: 'gameId = ? AND userId = ?',
      whereArgs: [gameId.value, userId.value],
    );
    return GameReviewState(
      tags: [
        for (final row in tags)
          (ply: row['ply']! as int, san: row['san']! as String, tagId: row['tag']! as String),
      ].toIList(),
      note: review.isEmpty ? '' : review.first['note']! as String,
    );
  }
}

/// A game in the list of reviewed games.
typedef ReviewedGame = ({ReviewedGameInfo info, IList<MoveTag> tags, String note});

/// The games the signed in user tagged or reviewed, most recently played first.
final reviewedGamesProvider = FutureProvider.autoDispose<IList<ReviewedGame>>((Ref ref) async {
  final authUser = ref.watch(authControllerProvider);
  if (authUser == null) return const IListConst([]);
  final userId = authUser.user.id.value;
  final db = await ref.watch(knightlyDatabaseProvider.future);
  final games = await db.query(
    'game_review',
    where: 'userId = ?',
    whereArgs: [userId],
    orderBy: 'playedAt DESC',
  );
  final tags = await db.query('move_tag', where: 'userId = ?', whereArgs: [userId], orderBy: 'ply');
  return [
    for (final game in games)
      // A game whose tags were all removed and without a note is not reviewed anymore.
      if (game['note'] != '' || tags.any((tag) => tag['gameId'] == game['gameId']))
        (
          info: (
            gameId: GameId(game['gameId']! as String),
            opponent: game['opponent']! as String,
            playedAt: DateTime.fromMillisecondsSinceEpoch(game['playedAt']! as int),
            orientation: Side.values.byName(game['orientation']! as String),
          ),
          tags: [
            for (final tag in tags)
              if (tag['gameId'] == game['gameId'])
                (ply: tag['ply']! as int, san: tag['san']! as String, tagId: tag['tag']! as String),
          ].toIList(),
          note: game['note']! as String,
        ),
  ].toIList();
}, name: 'ReviewedGamesProvider');
