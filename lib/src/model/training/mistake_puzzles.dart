import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/game/game_filter.dart';
import 'package:lichess_mobile/src/model/game/game_repository.dart';
import 'package:lichess_mobile/src/model/local_analysis/local_analysis.dart';
import 'package:lichess_mobile/src/model/local_analysis/local_analysis_runner.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _logger = Logger('MistakePuzzles');

/// How much better (in winning chances, from -1 to 1) the best move must be than the second best
/// for a mistake to make a puzzle: one clear answer, as in lichess's puzzles.
const kClearBestGap = 0.2;

/// How long the engine checks each mistake for its best two moves.
const kMistakeCheckTime = Duration(seconds: 1);

/// How many games the background scan looks through at a time.
const kMistakeScanGamesPerRun = 3;

/// How far back the background scan looks for games.
const kMistakeScanPeriod = Duration(days: 30);

/// A move of the user's that the analysis judges a mistake or a blunder: the [ply] it was played
/// at (the number of moves before it) and the engine's move instead.
typedef MistakeCandidate = ({int ply, String bestUci, MoveJudgement judgement});

/// The user's mistakes and blunders in a game, from its analysis: the moves of [mySide] whose
/// evaluation dropped enough, where the engine preferred another move.
List<MistakeCandidate> findMistakeCandidates({
  required Position initial,
  required List<SanMove> moves,
  required GameEvals evals,
  required Side mySide,
}) {
  final result = <MistakeCandidate>[];
  var position = initial;
  for (var i = 0; i < moves.length && i + 1 < evals.length; i++) {
    final mover = position.turn;
    final before = evals[i];
    final after = evals[i + 1];
    final played = moves[i].move;
    position = position.playUnchecked(played);
    if (mover != mySide || before == null || after == null || before.pv.isEmpty) continue;
    final best = before.pv.first;
    if (best == played.uci) continue;
    final advice = adviseMove(mover: mover, before: before, after: after, bestSan: null);
    if (advice == null) continue;
    if (advice.judgement == MoveJudgement.mistake || advice.judgement == MoveJudgement.blunder) {
      result.add((ply: i, bestUci: best, judgement: advice.judgement));
    }
  }
  return result;
}

/// The one clear answer in a position, from the engine's best two [lines] there: the best move if
/// it's at least [kClearBestGap] better than the second best for the side to move ([turn]); null
/// when several moves are about as good, or the position has a single legal move.
String? clearBestMove(IList<PvData> lines, Side turn) {
  final withMoves = lines.where((line) => line.moves.isNotEmpty).toList();
  if (withMoves.length < 2) return null;
  final best = withMoves[0].winningChances(turn);
  final second = withMoves[1].winningChances(turn);
  return best - second >= kClearBestGap ? withMoves[0].moves.first : null;
}

/// Finds the user's mistakes in their games and makes them puzzles (training cards): from the
/// games analysed on the phone, and from their recent games, analysed quietly in the background.
final mistakePuzzleServiceProvider = Provider<MistakePuzzleService>(
  MistakePuzzleService.new,
  name: 'MistakePuzzleServiceProvider',
);

class MistakePuzzleService(final Ref ref) {
  bool _scanning = false;

  /// Whether the background scan ran in this session.
  bool _scannedThisSession = false;

  /// Looks through a few of the user's recent games (rapid and slower) for mistakes, once per
  /// session: the games not looked through yet, [kMistakeScanGamesPerRun] at a time.
  ///
  /// [now] looks again even if it already did in this session (the user asked for it). Returns
  /// the number of puzzles made.
  Future<int> scanRecentGames({bool now = false}) async {
    final authUser = ref.read(authControllerProvider);
    if (authUser == null || _scanning || (_scannedThisSession && !now)) return 0;
    _scanning = true;
    _scannedThisSession = true;
    try {
      final userId = authUser.user.id;
      final db = await ref.read(knightlyDatabaseProvider.future);
      final games = await ref
          .read(gameRepositoryProvider)
          .getUserGames(
            userId,
            max: 30,
            since: DateTime.now().subtract(kMistakeScanPeriod),
            filter: const GameFilterState(
              perfs: ISetConst({Perf.rapid, Perf.classical, Perf.correspondence}),
            ),
          );
      final since = DateTime.now().subtract(kMistakeScanPeriod);
      final scanned = {
        for (final row in await db.query(
          'mistake_scan',
          columns: ['gameId'],
          where: 'userId = ?',
          whereArgs: [userId.value],
        ))
          row['gameId']! as String,
      };
      final toScan = [
        for (final (:game, pov: _) in games)
          if (game.lastMoveAt.isAfter(since) && !scanned.contains(game.id.value)) game.id,
      ].take(kMistakeScanGamesPerRun);
      var found = 0;
      for (final id in toScan) {
        found += await scanGame(id);
      }
      return found;
    } catch (e, st) {
      _logger.warning('Could not look through the recent games', e, st);
      return 0;
    } finally {
      _scanning = false;
    }
  }

  /// Whether the recent games are being looked through.
  bool get isScanning => _scanning;

  /// Makes puzzles of the user's mistakes in the game [gameId]: from Knightly's saved analysis of
  /// it, or from a quick one made now (and saved, for the analysis board). Each mistake is checked
  /// by the engine for one clear answer. Returns the number of puzzles made.
  Future<int> scanGame(GameId gameId, {GameEvals? evals}) async {
    final authUser = ref.read(authControllerProvider);
    if (authUser == null) return 0;
    final userId = authUser.user.id;
    final db = await ref.read(knightlyDatabaseProvider.future);
    try {
      final game = await ref.read(gameRepositoryProvider).getGame(gameId);
      final mySide = game.playerSideOf(userId);
      if (mySide == null || game.meta.variant != Variant.standard) {
        await _markScanned(db, userId, gameId, 0);
        return 0;
      }
      final initial = game.steps.first.position;
      final moves = [for (final step in game.steps.skip(1)) step.sanMove!];
      final runner = LocalAnalysisRunner(
        ref: ref,
        gameId: gameId,
        variant: game.meta.variant,
        initial: initial,
        moves: moves,
      );
      var gameEvals = evals ?? (await loadLocalAnalysis(db, gameId))?.evals;
      if (gameEvals == null || gameEvals.length != moves.length + 1) {
        gameEvals = await runner.run(kQuickAnalysisTime, onProgress: (_) {});
        if (gameEvals == null) return 0;
        await saveLocalAnalysis(db, gameId, gameEvals, deep: false);
      }
      final candidates = findMistakeCandidates(
        initial: initial,
        moves: moves,
        evals: gameEvals,
        mySide: mySide,
      );
      var found = 0;
      for (final candidate in candidates) {
        final lines = await runner.bestLines(candidate.ply, searchTime: kMistakeCheckTime);
        if (lines == null) continue;
        final answer = clearBestMove(lines, mySide);
        if (answer == null) continue;
        final best = lines.first;
        await _saveCard(
          db,
          userId,
          game,
          moves,
          initial,
          candidate.ply,
          answer,
          mySide,
          evals: (
            before: _cardEval(gameEvals[candidate.ply]),
            played: _cardEval(gameEvals[candidate.ply + 1]),
            best: (cp: best.mate == null ? best.cp : null, mate: best.mate),
          ),
        );
        found++;
      }
      await _markScanned(db, userId, gameId, found);
      ref.invalidate(trainingSummaryProvider);
      return found;
    } catch (e, st) {
      _logger.warning('Could not look for mistakes in $gameId', e, st);
      return 0;
    }
  }

  Future<void> _saveCard(
    Database db,
    UserId userId,
    ExportedGame game,
    List<SanMove> moves,
    Position initial,
    int ply,
    String answer,
    Side mySide, {
    required ({CardEval? before, CardEval? played, CardEval? best}) evals,
  }) async {
    var position = initial;
    for (var i = 0; i < ply; i++) {
      position = position.playUnchecked(moves[i].move);
    }
    final opponent = game.playerOf(mySide.opposite);
    final name = opponent.user?.name ?? opponent.name ?? 'Anonymous';
    await saveTrainingCard(
      db,
      userId: userId,
      id: 'mistake:${game.id}:$ply',
      kind: TrainingKind.mistake,
      sourceId: game.id.value,
      fen: position.fen,
      answer: answer,
      path: [for (final move in moves.take(ply)) move.move.uci],
      orientation: mySide,
      title: 'vs $name, move ${ply ~/ 2 + 1}',
      played: moves[ply].move.uci,
      beforeEval: evals.before,
      playedEval: evals.played,
      bestEval: evals.best,
    );
  }

  static CardEval? _cardEval(PositionEval? eval) =>
      eval == null ? null : (cp: eval.mate == null ? eval.cp : null, mate: eval.mate);

  Future<void> _markScanned(Database db, UserId userId, GameId gameId, int found) =>
      db.insert('mistake_scan', {
        'gameId': gameId.value,
        'userId': userId.value,
        'scannedAt': DateTime.now().millisecondsSinceEpoch,
        'found': found,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
}
