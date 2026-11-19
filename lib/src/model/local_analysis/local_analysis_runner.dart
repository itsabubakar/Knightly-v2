import 'dart:async';
import 'dart:convert';

import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/engine/engine_budget.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_context.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/engine/position_evaluator.dart';
import 'package:lichess_mobile/src/model/engine/work.dart';
import 'package:lichess_mobile/src/model/local_analysis/local_analysis.dart';
import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _logger = Logger('LocalAnalysis');

/// How long the engine looks at each position in the quick pass: the judgements show in seconds.
const kQuickAnalysisTime = Duration(milliseconds: 150);

/// How long it looks in the deep pass, which then refines the analysis in the background.
const kDeepAnalysisTime = Duration(milliseconds: 1200);

/// How long the engine may take to start, before the first position.
const _kEngineStartTime = Duration(seconds: 20);

/// How often a paused analysis checks whether the engine is free again.
const kAnalysisPauseCheck = Duration(milliseconds: 500);

/// The engine's evaluation of each position of a game, the starting one first.
typedef GameEvals = List<PositionEval?>;

/// Evaluates every position of a game (the [initial] one, then after each of [moves]) with the
/// phone's engine.
///
/// It runs in the background: while the user's own evaluations (the analysis board's engine) are
/// running, it waits, and a position they interrupt is evaluated again (see
/// [ForegroundEvaluations]).
class LocalAnalysisRunner({
  required final Ref ref,
  required final GameId gameId,
  required final Variant variant,
  required final Position initial,
  required final List<SanMove> moves,
}) {
  bool _cancelled = false;

  /// Stops at the next position.
  void cancel() => _cancelled = true;

  bool get isCancelled => _cancelled;

  /// Evaluates each position for [searchTime], starting from [previous] (which a deep pass
  /// improves on), and calls [onProgress] after each one. Returns null when cancelled.
  Future<GameEvals?> run(
    Duration searchTime, {
    GameEvals? previous,
    required void Function(GameEvals evals) onProgress,
  }) async {
    final context = EvaluationContext(
      id: StringId('knightly-analysis-$gameId'),
      variant: variant,
      initialPosition: initial,
      isBackground: true,
    );
    final foreground = ref.read(foregroundEvaluationsProvider);
    // Keeps the evaluator while the analysis runs.
    final keepAlive = ref.listen(positionEvaluatorProvider(context), (_, _) {});
    try {
      final evals = previous != null
          ? List<PositionEval?>.of(previous)
          : List<PositionEval?>.filled(moves.length + 1, null);
      final threads = ref
          .read(engineBudgetProvider)
          .analysisThreads(ref.read(engineEvaluationPreferencesProvider).numEngineCores);
      var position = initial;
      final steps = <Step>[];
      var engineStarted = false;
      for (var i = 0; i <= moves.length; i++) {
        if (_cancelled) return null;
        if (i > 0) {
          position = position.playUnchecked(moves[i - 1].move);
          steps.add(Step(position: position, sanMove: moves[i - 1]));
        }
        final PositionEval? eval;
        if (position.isCheckmate) {
          // The side to move is mated.
          eval = (cp: null, mate: position.turn == Side.white ? -1 : 1, pv: const []);
        } else if (position.isGameOver) {
          eval = (cp: 0, mate: null, pv: const []);
        } else {
          final work = EvalWork(
            id: context.id,
            variant: variant,
            threads: threads,
            searchTime: searchTime,
            multiPv: 1,
            threatMode: false,
            initialPosition: initial,
            steps: steps.toIList(),
          );
          PositionEval? found;
          while (true) {
            // The engine is the user's while they use it.
            while (foreground.isBusy) {
              await Future<void>.delayed(kAnalysisPauseCheck);
              if (_cancelled) return null;
            }
            final (result, interrupted) = await _evaluate(
              context,
              work,
              foreground,
              timeout:
                  searchTime + (engineStarted ? const Duration(seconds: 3) : _kEngineStartTime),
            );
            if (_cancelled) return null;
            if (!interrupted) {
              found = result;
              break;
            }
          }
          eval = found;
          engineStarted = engineStarted || eval != null;
        }
        // A position the engine didn't answer about keeps what was known (the quick pass's, or the
        // previous position's), so the analysis stays whole.
        evals[i] = eval ?? evals[i] ?? (i > 0 ? evals[i - 1] : null);
        if (evals[i] == null && i == 0) throw StateError('The engine did not start.');
        onProgress(List.unmodifiable(evals));
      }
      ref.read(positionEvaluatorProvider(context).notifier).stop();
      return evals;
    } finally {
      keepAlive.close();
    }
  }

  /// The evaluation of [work], and whether the user's own evaluations interrupted it (it is then
  /// worth nothing: the engine went to them).
  ///
  /// It's over when the engine has searched for the time asked, or has stopped before (a position
  /// it has seen through, e.g. a mate).
  Future<(PositionEval?, bool)> _evaluate(
    EvaluationContext context,
    EvalWork work,
    ForegroundEvaluations foreground, {
    required Duration timeout,
  }) async {
    final done = Completer<void>();
    var interrupted = false;
    void onForeground() {
      if (!foreground.isBusy || done.isCompleted) return;
      interrupted = true;
      done.complete();
    }

    LocalEval? last;
    foreground.addListener(onForeground);
    var searched = false;
    var searchEnded = false;
    void endSoon() {
      // The engine's last words come throttled, after its search.
      Timer(kEngineEvalEmissionThrottleDelay * 2, () {
        if (!done.isCompleted) done.complete();
      });
    }

    final searching = ref.listen(positionEvaluatorProvider(context), (_, state) {
      if (state.isComputing) {
        searched = true;
      } else if (searched && !searchEnded) {
        searchEnded = true;
        if (last != null) endSoon();
      }
    });
    final evaluator = ref.read(positionEvaluatorProvider(context).notifier);
    final subscription = evaluator.evaluate(work).listen((result) {
      final isFirst = last == null;
      last = result.$2;
      if (isFirst && searchEnded) endSoon();
      if (result.$2.searchTime >= work.searchTime * 0.9 && !done.isCompleted) done.complete();
    });
    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      _logger.fine('No full evaluation at ply ${work.position.ply}, using what came');
    } finally {
      foreground.removeListener(onForeground);
      searching.close();
      await subscription.cancel();
    }
    final eval = last;
    if (interrupted || eval == null) return (null, interrupted);
    final pv = eval.pvs.firstOrNull;
    return (
      (cp: eval.mate == null ? eval.cp : null, mate: eval.mate, pv: pv?.moves.toList() ?? []),
      false,
    );
  }
}

/// A saved analysis: the evaluations, and whether the deep pass finished.
typedef SavedAnalysis = ({GameEvals evals, bool deep});

/// The analysis of [gameId] saved on the phone, if any.
Future<SavedAnalysis?> loadLocalAnalysis(Database db, GameId gameId) async {
  final rows = await db.query('game_analysis', where: 'gameId = ?', whereArgs: [gameId.value]);
  if (rows.isEmpty) return null;
  try {
    final list = jsonDecode(rows.first['evals']! as String) as List<dynamic>;
    return (
      evals: [
        for (final item in list)
          if (item == null)
            null
          else
            (
              cp: (item as Map<String, dynamic>)['cp'] as int?,
              mate: item['mate'] as int?,
              pv: [for (final move in (item['pv'] as List<dynamic>? ?? const [])) move as String],
            ),
      ],
      deep: rows.first['deep'] == 1,
    );
  } catch (e, st) {
    _logger.warning('Could not read the saved analysis of $gameId', e, st);
    return null;
  }
}

/// Saves the analysis of [gameId] on the phone.
Future<void> saveLocalAnalysis(Database db, GameId gameId, GameEvals evals, {required bool deep}) =>
    db.insert('game_analysis', {
      'gameId': gameId.value,
      'evals': jsonEncode([
        for (final eval in evals)
          if (eval == null)
            null
          else
            {'cp': ?eval.cp, 'mate': ?eval.mate, 'pv': eval.pv.take(kAdviceLinePlies).toList()},
      ]),
      'deep': deep ? 1 : 0,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
