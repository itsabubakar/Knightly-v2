import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/game/game_socket_events.dart';
import 'package:lichess_mobile/src/model/local_analysis/local_analysis.dart';
import 'package:lichess_mobile/src/service/server_analysis_service.dart';

PositionEval cp(int value, [List<String> pv = const []]) => (cp: value, mate: null, pv: pv);
PositionEval mate(int value, [List<String> pv = const []]) => (cp: null, mate: value, pv: pv);

void main() {
  group('adviseMove', () {
    test('judges by the winning chances lost, as lichess does', () {
      // Equal, then a piece down: a blunder.
      final blunder = adviseMove(
        mover: Side.white,
        before: cp(20),
        after: cp(-300),
        bestSan: 'Nf3',
      );
      expect(blunder?.judgement, MoveJudgement.blunder);
      expect(blunder?.comment, 'Blunder. Nf3 was best.');

      expect(
        adviseMove(mover: Side.white, before: cp(0), after: cp(-130), bestSan: 'e4')?.judgement,
        MoveJudgement.mistake,
      );
      expect(
        adviseMove(mover: Side.white, before: cp(0), after: cp(-60), bestSan: 'e4')?.judgement,
        MoveJudgement.inaccuracy,
      );
      // A small loss is no mistake.
      expect(adviseMove(mover: Side.white, before: cp(30), after: cp(0), bestSan: 'e4'), isNull);
      // Black loses when white's eval goes up.
      expect(
        adviseMove(mover: Side.black, before: cp(0), after: cp(300), bestSan: 'e5')?.judgement,
        MoveJudgement.blunder,
      );
      // Already lost: another pawn makes little difference.
      expect(
        adviseMove(mover: Side.white, before: cp(-900), after: cp(-1000), bestSan: 'h3'),
        isNull,
      );
    });

    test('a forced mate created or let go of', () {
      final created = adviseMove(
        mover: Side.white,
        before: cp(10),
        after: mate(-3),
        bestSan: 'Kg1',
      );
      expect(created?.judgement, MoveJudgement.blunder);
      expect(created?.comment, 'Checkmate is now unavoidable. Kg1 was best.');

      final lost = adviseMove(mover: Side.white, before: mate(2), after: cp(150), bestSan: 'Qh7+');
      expect(lost?.judgement, MoveJudgement.blunder);
      expect(lost?.comment, 'Lost forced checkmate sequence. Qh7+ was best.');

      // Still winning by far: only an inaccuracy.
      expect(
        adviseMove(mover: Side.white, before: mate(2), after: cp(1200), bestSan: 'Qh7+')?.judgement,
        MoveJudgement.inaccuracy,
      );
    });
  });

  group('makeAnalysisJson', () {
    // 1. f3 e5 2. g4?? Qh4#
    final moves = ['f2f3', 'e7e5', 'g2g4', 'd8h4'].map((m) => Move.parse(m)!).toList();
    final evals = <PositionEval?>[
      cp(20, ['e2e4']),
      cp(-50, ['e7e5']),
      cp(-40, ['e2e4', 'd8h4']),
      mate(-1, ['d8h4']),
      mate(-1),
    ];

    test('reads as lichess server analysis: evals, judgements, best lines, summary', () {
      final event = ServerEvalEvent.fromJson(
        makeAnalysisJson(
          gameId: const GameId('abcdefgh'),
          initial: Chess.initial,
          moves: moves,
          evals: evals,
        ),
      );

      expect(event.isAnalysisComplete, isTrue);
      expect(event.evals.length, 4);
      // 2. g4 let black mate: "Checkmate is now unavoidable", with the better move as a line.
      final g4 = event.evals[2];
      expect(g4.judgment?.name, 'Blunder');
      expect(g4.judgment?.comment, 'Checkmate is now unavoidable. e4 was best.');
      expect(g4.variation, 'e4 Qh4+');
      // The mating move is not judged.
      expect(event.evals[3].judgment, isNull);

      expect(event.analysis?.white.blunders, 1);
      expect(event.analysis?.black.blunders, 0);
      expect(event.analysis!.white.accuracy, lessThan(event.analysis!.black.accuracy!));
    });

    test('is incomplete, without a summary, until every position is evaluated', () {
      final event = ServerEvalEvent.fromJson(
        makeAnalysisJson(
          gameId: const GameId('abcdefgh'),
          initial: Chess.initial,
          moves: moves,
          evals: [evals[0], evals[1], null, null, null],
        ),
      );
      expect(event.isAnalysisComplete, isFalse);
      expect(event.analysis, isNull);
    });

    test("replacing Knightly's analysis keeps the user's moves and comments", () {
      final root = Root.fromPgnGame(PgnGame.parsePgn('1. f3 e5 2. g4 Qh4# *'));
      // The user's own line and comment.
      final f3 = root.mainline.first;
      f3.comments = [const PgnComment(text: 'Weakens the king')];
      final userLine = Branch(
        position: Chess.initial.play(Move.parse('d2d4')!),
        sanMove: SanMove('d4', Move.parse('d2d4')!),
      );
      root.addChild(userLine);

      final json = makeAnalysisJson(
        gameId: const GameId('abcdefgh'),
        initial: Chess.initial,
        moves: moves,
        evals: evals,
      );
      ServerAnalysisService.mergeOngoingAnalysis(root, json['tree'] as Map<String, dynamic>);
      final g4 = root.mainline.elementAt(2);
      expect(g4.nags, [4]);
      // The best line next to the played move.
      expect(root.mainline.elementAt(1).children.length, 2);

      // A deeper pass says g4 was fine (it wasn't): the judgement and the line go.
      ServerAnalysisService.clearComputerAnalysis(root);
      final fine = makeAnalysisJson(
        gameId: const GameId('abcdefgh'),
        initial: Chess.initial,
        moves: moves,
        evals: [cp(20), cp(-50), cp(-40), cp(-60), mate(-1)],
      );
      ServerAnalysisService.mergeOngoingAnalysis(root, fine['tree'] as Map<String, dynamic>);
      expect(g4.nags, isNull);
      expect(root.mainline.elementAt(1).children.length, 1);
      // The user's line and comment are still there.
      expect(root.children.length, 2);
      expect(f3.comments?.single.text, 'Weakens the king');
    });
  });

  test('perfect play is 100% accurate', () {
    final summary = summarise(
      firstMover: Side.white,
      evals: [cp(20), cp(20), cp(20), cp(20), cp(20)],
      advice: [null, null, null, null],
    );
    expect(summary.white.accuracy, 100);
    expect(summary.black.accuracy, 100);
    expect(summary.white.acpl, 0);
  });
}
