import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';

/// Knightly's own computer analysis of a game, made on the phone: lichess's "Request a computer
/// analysis" is only for the official app.
///
/// It is written in the shape lichess's server analysis has (the analysis tree and the players'
/// summary), so the analysis board, its summary and "Learn from your mistakes" show it as they
/// show lichess's. The judgements, comments and accuracy follow lichess's rules (lila's `Advice`
/// and `AccuracyPercent`).

/// The engine's evaluation of a position: white's point of view, and the best line (UCI moves).
typedef PositionEval = ({int? cp, int? mate, List<String> pv});

/// How far a judged move fell, as lichess names it.
enum MoveJudgement(final int glyph, final String symbol, final String label) {
  inaccuracy(6, '?!', 'Inaccuracy'),
  mistake(2, '?', 'Mistake'),
  blunder(4, '??', 'Blunder'),
}

/// A judged move: its [judgement] and lichess's [comment], e.g. "Mistake. Nf3 was best.".
typedef MoveAdvice = ({MoveJudgement judgement, String comment});

/// Centipawns, capped as lichess does: a forced mate counts as ±1000.
int cappedCp(PositionEval eval) {
  if (eval.mate case final mate?) return mate > 0 ? 1000 : -1000;
  return (eval.cp ?? 0).clamp(-1000, 1000);
}

/// White's winning chances for [cp] centipawns, from -1 to 1 (lichess's formula).
double winningChances(int cp) => 2 / (1 + math.exp(-0.00368208 * cp.clamp(-1000, 1000))) - 1;

/// White's win percentage for [cp] centipawns.
double winPercent(int cp) => 50 + 50 * winningChances(cp);

/// lichess's advice on a move played by [mover], from the evaluations of the position [before] it
/// and [after] it; [bestSan] is the engine's move in the position before. Null for a good move.
MoveAdvice? adviseMove({
  required Side mover,
  required PositionEval before,
  required PositionEval after,
  required String? bestSan,
}) {
  final sign = mover == Side.white ? 1 : -1;
  final prevMate = before.mate != null ? before.mate! * sign : null;
  final nextMate = after.mate != null ? after.mate! * sign : null;
  final prevCp = before.cp != null ? before.cp! * sign : 0;
  final nextCp = after.cp != null ? after.cp! * sign : 0;
  final best = bestSan != null ? ' $bestSan was best.' : '';

  // A forced mate created against the mover, or let go of.
  final String? mateSequence;
  final MoveJudgement? mateJudgement;
  if (prevMate == null && nextMate != null && nextMate < 0) {
    mateSequence = 'Checkmate is now unavoidable';
    mateJudgement = prevCp < -999
        ? MoveJudgement.inaccuracy
        : prevCp < -700
        ? MoveJudgement.mistake
        : MoveJudgement.blunder;
  } else if (prevMate != null && prevMate > 0 && (nextMate == null || nextMate < 0)) {
    mateSequence = 'Lost forced checkmate sequence';
    mateJudgement = nextCp > 999
        ? MoveJudgement.inaccuracy
        : nextCp > 700
        ? MoveJudgement.mistake
        : MoveJudgement.blunder;
  } else {
    mateSequence = null;
    mateJudgement = null;
  }
  if (mateSequence != null && mateJudgement != null) {
    return (judgement: mateJudgement, comment: '$mateSequence.$best');
  }
  if (before.cp == null || after.cp == null) return null;

  final delta = (winningChances(before.cp!) - winningChances(after.cp!)) * sign;
  final judgement = delta >= 0.3
      ? MoveJudgement.blunder
      : delta >= 0.2
      ? MoveJudgement.mistake
      : delta >= 0.1
      ? MoveJudgement.inaccuracy
      : null;
  if (judgement == null) return null;
  return (judgement: judgement, comment: '${judgement.label}.$best');
}

/// The accuracy of a move, from the win percentages (of the mover) [before] and [after] it.
double moveAccuracy(double before, double after) {
  if (after >= before) return 100;
  final raw = 103.1668100711649 * math.exp(-0.04354415386753951 * (before - after)) - 3.1669;
  return (raw + 1).clamp(0, 100);
}

/// A player's numbers for the summary: as lichess's analysis gives them.
typedef PlayerSummary = ({int inaccuracies, int mistakes, int blunders, int acpl, int accuracy});

/// The summaries of white and black, from the evaluations of every position of the game (the
/// first is the starting one) and the advice on each move.
({PlayerSummary white, PlayerSummary black}) summarise({
  required Side firstMover,
  required List<PositionEval> evals,
  required List<MoveAdvice?> advice,
}) {
  final cps = evals.map(cappedCp).toList();
  final wins = cps.map(winPercent).toList();
  final moves = cps.length - 1;

  // lichess weighs each move by how sharp the game was around it (the spread of the win
  // percentages over a window), then averages that weighted mean with the harmonic mean.
  final windowSize = (moves ~/ 10).clamp(2, 8);
  final windows = [
    for (var i = 0; i < windowSize - 2; i++) wins.take(windowSize).toList(),
    for (var i = 0; i + windowSize <= wins.length; i++) wins.sublist(i, i + windowSize),
  ];
  final weights = [for (final window in windows) _standardDeviation(window).clamp(0.5, 12.0)];

  PlayerSummary summary(Side side) {
    final accuracies = <double>[];
    final accuracyWeights = <double>[];
    var loss = 0;
    var count = 0;
    var inaccuracies = 0;
    var mistakes = 0;
    var blunders = 0;
    for (var i = 0; i < moves; i++) {
      final mover = i.isEven ? firstMover : firstMover.opposite;
      if (mover != side) continue;
      final before = side == Side.white ? wins[i] : 100 - wins[i];
      final after = side == Side.white ? wins[i + 1] : 100 - wins[i + 1];
      accuracies.add(moveAccuracy(before, after));
      accuracyWeights.add(i < weights.length ? weights[i] : weights.last);
      final sign = side == Side.white ? 1 : -1;
      loss += math.max(0, (cps[i] - cps[i + 1]) * sign);
      count++;
      switch (advice[i]?.judgement) {
        case MoveJudgement.inaccuracy:
          inaccuracies++;
        case MoveJudgement.mistake:
          mistakes++;
        case MoveJudgement.blunder:
          blunders++;
        case null:
          break;
      }
    }
    final accuracy = accuracies.isEmpty
        ? 100.0
        : (_weightedMean(accuracies, accuracyWeights) + _harmonicMean(accuracies)) / 2;
    return (
      inaccuracies: inaccuracies,
      mistakes: mistakes,
      blunders: blunders,
      acpl: count == 0 ? 0 : (loss / count).round(),
      accuracy: accuracy.round(),
    );
  }

  return (white: summary(Side.white), black: summary(Side.black));
}

double _standardDeviation(List<double> values) {
  final mean = values.reduce((a, b) => a + b) / values.length;
  final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b);
  return math.sqrt(variance / values.length);
}

double _weightedMean(List<double> values, List<double> weights) {
  var sum = 0.0;
  var total = 0.0;
  for (var i = 0; i < values.length; i++) {
    sum += values[i] * weights[i];
    total += weights[i];
  }
  return total == 0 ? 0 : sum / total;
}

double _harmonicMean(List<double> values) =>
    values.length / values.map((v) => 1 / math.max(v, 1)).reduce((a, b) => a + b);

/// The longest best line shown for a judged move.
const kAdviceLinePlies = 12;

/// The analysis of the game in the shape lichess's server sends it (`analysisProgress`): the tree
/// of the mainline with the evaluations, the judged moves with their comment and best line, and,
/// once every position is evaluated, the players' summaries.
///
/// [evals] holds the evaluation of each position (the starting one first), null where not
/// evaluated yet.
Map<String, dynamic> makeAnalysisJson({
  required GameId gameId,
  required Position initial,
  required List<Move> moves,
  required List<PositionEval?> evals,
}) {
  final positions = <Position>[initial];
  final sans = <String>[];
  for (final move in moves) {
    final (next, san) = positions.last.makeSan(move);
    positions.add(next);
    sans.add(san);
  }
  final complete = evals.every((eval) => eval != null);
  final advice = <MoveAdvice?>[];

  // From the last move back to the start, as each node holds its children.
  Map<String, dynamic>? next;
  for (var i = moves.length; i >= 0; i--) {
    final position = positions[i];
    final eval = evals[i];
    // The judgement of the move played from this position, and the line that was better.
    final played = i < moves.length ? next : null;
    Map<String, dynamic>? variation;
    if (played != null && i < moves.length) {
      final before = evals[i];
      final after = evals[i + 1];
      final bestUci = before?.pv.firstOrNull;
      final bestMove = bestUci != null ? Move.parse(bestUci) : null;
      final bestIsPlayed = bestMove != null && bestMove.uci == moves[i].uci;
      final bestSan = bestMove != null && !bestIsPlayed && position.isLegal(bestMove)
          ? position.makeSan(bestMove).$2
          : null;
      final moveAdvice = before != null && after != null && !positions[i + 1].isCheckmate
          ? adviseMove(mover: position.turn, before: before, after: after, bestSan: bestSan)
          : null;
      advice.insert(0, moveAdvice);
      if (moveAdvice != null) {
        played['glyphs'] = [
          {
            'id': moveAdvice.judgement.glyph,
            'symbol': moveAdvice.judgement.symbol,
            'name': moveAdvice.judgement.label,
          },
        ];
        played['comments'] = [
          {'text': moveAdvice.comment, 'by': 'lichess'},
        ];
        if (bestSan != null) variation = _line(position, before!.pv);
      }
    }
    next = {
      'ply': position.ply,
      'fen': position.fen,
      if (i > 0) 'uci': moves[i - 1].uci,
      if (i > 0) 'san': sans[i - 1],
      if (eval != null)
        'eval': {
          if (eval.mate != null) 'mate': eval.mate else 'cp': eval.cp ?? 0,
          'best': ?eval.pv.firstOrNull,
        },
      'children': [?played, ?variation],
    };
  }

  final summaries = complete
      ? summarise(firstMover: initial.turn, evals: evals.cast<PositionEval>(), advice: advice)
      : null;
  Map<String, dynamic> playerJson(PlayerSummary s) => {
    'inaccuracy': s.inaccuracies,
    'mistake': s.mistakes,
    'blunder': s.blunders,
    'acpl': s.acpl,
    'accuracy': s.accuracy,
  };
  return {
    // Knightly's, not lichess's: replaces the analysis it made before (see ServerAnalysisMixin).
    'tree': {...next!, 'knightly': true},
    if (summaries != null)
      'analysis': {
        'id': gameId.value,
        'white': playerJson(summaries.white),
        'black': playerJson(summaries.black),
      },
  };
}

/// The engine's best line from [position] as a chain of tree nodes.
Map<String, dynamic>? _line(Position position, List<String> pv) {
  final nodes = <Map<String, dynamic>>[];
  var current = position;
  for (final uci in pv.take(kAdviceLinePlies)) {
    final move = Move.parse(uci);
    if (move == null || !current.isLegal(move)) break;
    final (next, san) = current.makeSan(move);
    nodes.add({
      'ply': next.ply,
      'fen': next.fen,
      'uci': move.uci,
      'san': san,
      'children': <Object>[],
    });
    current = next;
  }
  if (nodes.isEmpty) return null;
  for (var i = nodes.length - 2; i >= 0; i--) {
    nodes[i]['children'] = [nodes[i + 1]];
  }
  return nodes.first;
}
