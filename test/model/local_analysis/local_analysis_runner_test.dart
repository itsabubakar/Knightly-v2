import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_context.dart';
import 'package:lichess_mobile/src/model/engine/position_evaluator.dart';
import 'package:lichess_mobile/src/model/engine/work.dart';
import 'package:lichess_mobile/src/model/local_analysis/local_analysis_runner.dart';

import '../../test_container.dart';
import '../engine/fake_engine.dart';

/// 1. e4 e5
final _moves = [SanMove('e4', Move.parse('e2e4')!), SanMove('e5', Move.parse('e7e5')!)];

const _gameId = GameId('abcdefgh');

LocalAnalysisRunner _runner(Ref ref) => LocalAnalysisRunner(
  ref: ref,
  gameId: _gameId,
  variant: Variant.standard,
  initial: Chess.initial,
  moves: _moves,
);

final _runnerProvider = Provider<LocalAnalysisRunner>(_runner);

/// The analysis board's evaluator: the user's own evaluations.
const _boardContext = EvaluationContext(
  id: StringId('board'),
  variant: Variant.standard,
  initialPosition: Chess.initial,
);

EvalWork _boardWork(Duration searchTime) => EvalWork(
  id: _boardContext.id,
  variant: Variant.standard,
  threads: 1,
  searchTime: searchTime,
  multiPv: 1,
  threatMode: false,
  initialPosition: Chess.initial,
  steps: const IListConst([]),
);

int _goCount() => fakeEngine.commands.where((command) => command.startsWith('go')).length;

void main() {
  setUp(() => fakeEngine = FakeEngine());

  test('the analysis evaluates every position', () async {
    final container = await makeContainer();
    final evals = await container.read(_runnerProvider).run(kQuickAnalysisTime, onProgress: (_) {});
    expect(evals, hasLength(3));
    expect(evals!.every((eval) => eval != null), isTrue);
  });

  test("the user's evaluations mark the engine busy, a background one doesn't", () async {
    final container = await makeContainer();
    final foreground = container.read(foregroundEvaluationsProvider);
    container.listen(positionEvaluatorProvider(_boardContext), (_, _) {});
    final board = container.read(positionEvaluatorProvider(_boardContext).notifier);

    board.evaluate(_boardWork(const Duration(seconds: 4)));
    expect(foreground.isBusy, isTrue);
    board.stop();
    expect(foreground.isBusy, isFalse);

    const background = EvaluationContext(
      id: StringId('knightly-analysis-abcdefgh'),
      variant: Variant.standard,
      initialPosition: Chess.initial,
      isBackground: true,
    );
    container.listen(positionEvaluatorProvider(background), (_, _) {});
    container
        .read(positionEvaluatorProvider(background).notifier)
        .evaluate(_boardWork(const Duration(seconds: 4)));
    expect(foreground.isBusy, isFalse);
  });

  test("the analysis waits while the user's engine is evaluating", () async {
    final container = await makeContainer();
    container.listen(positionEvaluatorProvider(_boardContext), (_, _) {});
    final board = container.read(positionEvaluatorProvider(_boardContext).notifier);
    board.evaluate(_boardWork(const Duration(seconds: 30)));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final goesBefore = _goCount();

    var done = false;
    final run = container
        .read(_runnerProvider)
        .run(kQuickAnalysisTime, onProgress: (_) {})
        .whenComplete(() => done = true);

    // The engine stays the user's.
    await Future<void>.delayed(kAnalysisPauseCheck * 3);
    expect(done, isFalse);
    expect(_goCount(), goesBefore);

    // The user leaves: the analysis goes on.
    board.stop();
    final evals = await run;
    expect(evals, hasLength(3));
    expect(_goCount(), greaterThanOrEqualTo(goesBefore + 3));
  });

  test("a position the engine is done with early, or the user's engine interrupts, isn't waited "
      'on', () async {
    final container = await makeContainer();
    container.listen(positionEvaluatorProvider(_boardContext), (_, _) {});
    final board = container.read(positionEvaluatorProvider(_boardContext).notifier);

    final runner = container.read(_runnerProvider);
    final run = runner.run(const Duration(seconds: 2), onProgress: (_) {});
    // The first position is being evaluated: the user's engine takes over.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    board.evaluate(_boardWork(const Duration(milliseconds: 100)));
    board.stop();

    // The fake engine searches for less than asked: no waiting for the timeout.
    final evals = await run.timeout(const Duration(seconds: 10));
    expect(evals, hasLength(3));
    expect(evals!.every((eval) => eval != null), isTrue);
  });

  test('a cancelled analysis stops while waiting', () async {
    final container = await makeContainer();
    container.listen(positionEvaluatorProvider(_boardContext), (_, _) {});
    container
        .read(positionEvaluatorProvider(_boardContext).notifier)
        .evaluate(_boardWork(const Duration(seconds: 30)));
    final runner = container.read(_runnerProvider);
    final run = runner.run(kQuickAnalysisTime, onProgress: (_) {});
    await Future<void>.delayed(kAnalysisPauseCheck);
    runner.cancel();
    expect(await run, isNull);
  });
}
