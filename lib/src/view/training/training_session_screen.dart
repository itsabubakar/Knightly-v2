import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/game/game_board_params.dart';
import 'package:lichess_mobile/src/model/training/repertoire.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/training/repertoire_screen.dart' show positionAfterPath;
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

/// The moves (SAN) of [path] (UCI) from the start position, with their numbers: "1. e4 c5 2. Nf3".
String pathSan(Iterable<String> path) {
  Position position = Chess.initial;
  final buffer = StringBuffer();
  for (final uci in path) {
    final move = Move.parse(uci);
    if (move == null || !position.isLegal(move)) break;
    final (next, san) = position.makeSan(move);
    if (position.turn == Side.white) {
      buffer.write('${position.fullmoves}. ');
    } else if (buffer.isEmpty) {
      buffer.write('${position.fullmoves}… ');
    }
    buffer.write('$san ');
    position = next;
  }
  return buffer.toString().trim();
}

/// A training session: the cards due and the new ones, one after the other. The user plays the
/// move; a wrong one shows the right move, which the user then plays, and the card comes back at
/// the end of the session.
class const TrainingSessionScreen({
  /// The kind of cards trained, all when null.
  final TrainingKind? kind,

  /// The repertoire (its id) or game the cards come from, all when null.
  final String? sourceId,
  final String title = 'Training',
  super.key,
}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute({
    TrainingKind? kind,
    String? sourceId,
    String title = 'Training',
  }) => buildScreenRoute(
    screen: TrainingSessionScreen(kind: kind, sourceId: sourceId, title: title),
  );

  @override
  ConsumerState<TrainingSessionScreen> createState() => _TrainingSessionScreenState();
}

/// How the current card went.
enum _Answer() {
  waiting,

  /// Found the first time: the card counts as right.
  correct,

  /// A wrong move: the right one is shown, to play.
  wrong,

  /// The right move played after a wrong one: the card comes back at the end of the session.
  corrected,
}

/// [eval] (White's) from [side]'s point of view: "+1.2", "-0.4", "#3".
String _evalText(CardEval eval, Side side) {
  final sign = side == Side.white ? 1 : -1;
  if (eval.mate case final mate?) return mate * sign > 0 ? '#${mate.abs()}' : '#-${mate.abs()}';
  final pawns = (eval.cp ?? 0) * sign / 100;
  return '${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(1)}';
}

/// How much [to] is better than [from] for [side], in pawns; null when a mate is involved.
double? _evalGain(CardEval from, CardEval to, Side side) {
  if (from.cp == null || to.cp == null) return null;
  return (to.cp! - from.cp!) * (side == Side.white ? 1 : -1) / 100;
}

/// The SAN of [uci] in [position], or the UCI if it isn't legal there.
String _san(Position position, String uci) {
  final move = Move.parse(uci);
  if (move == null || !position.isLegal(move)) return uci;
  return position.makeSan(move).$2;
}

class _TrainingSessionScreenState() extends ConsumerState<TrainingSessionScreen> {
  /// The cards left, the current one first; null while loading.
  List<TrainingCard>? _queue;

  /// The cards answered wrong in this session (reviewed again, without a second schedule change).
  final _failed = <String>{};
  int _reviewed = 0;
  int _right = 0;
  _Answer _answer = _Answer.waiting;

  /// The move the user played: the right one once found, or the wrong one.
  Move? _played;

  /// The move of the line shown while going through it (the number of moves from the start), null
  /// for the card's position.
  int? _viewPly;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final userId = ref.read(authControllerProvider)?.user.id;
    if (userId == null) {
      setState(() => _queue = []);
      return;
    }
    final db = await ref.read(knightlyDatabaseProvider.future);
    final queue = await readTrainingQueue(
      db,
      userId,
      now: DateTime.now(),
      kind: widget.kind,
      sourceId: widget.sourceId,
    );
    if (mounted) setState(() => _queue = [...queue.due, ...queue.fresh]);
  }

  TrainingCard? get _card => _queue?.firstOrNull;

  bool get _answered => _answer == _Answer.correct || _answer == _Answer.corrected;

  Future<void> _onMove(Move move) async {
    final card = _card;
    if (card == null) return;
    final correct = move.uci == card.answer || _sameCastling(card, move);
    final sound = ref.read(soundServiceProvider);
    if (_answer == _Answer.wrong) {
      // Correcting: only the right move goes on.
      if (!correct) return;
      unawaited(sound.play(Sound.move));
      setState(() {
        _answer = _Answer.corrected;
        _played = move;
      });
      return;
    }
    if (correct) {
      unawaited(sound.play(Sound.confirmation));
      setState(() {
        _answer = _Answer.correct;
        _played = move;
      });
      if (!_failed.contains(card.id)) {
        _reviewed++;
        _right++;
        await ref.read(trainingReviewsProvider).record(card, correct: true);
      }
    } else {
      unawaited(sound.play(Sound.error));
      setState(() {
        _answer = _Answer.wrong;
        _played = move;
      });
      if (_failed.add(card.id)) {
        _reviewed++;
        await ref.read(trainingReviewsProvider).record(card, correct: false);
      }
    }
  }

  /// Castling given as the king onto the rook, or two squares: the same move.
  bool _sameCastling(TrainingCard card, Move move) {
    final position = Chess.fromSetup(Setup.parseFen(card.fen));
    final answer = Move.parse(card.answer);
    if (answer is! NormalMove || move is! NormalMove || !position.isLegal(move)) return false;
    return position.normalizeMove(move) == position.normalizeMove(answer);
  }

  void _next({bool requeue = false}) {
    final queue = _queue;
    if (queue == null || queue.isEmpty) return;
    setState(() {
      final card = queue.removeAt(0);
      if (requeue) queue.add(card);
      _answer = _Answer.waiting;
      _played = null;
      _viewPly = null;
    });
    if (queue.isEmpty) {
      ref.invalidate(trainingSummaryProvider);
      ref.invalidate(repertoiresProvider);
    }
  }

  /// Goes [delta] moves back or forward through the line that led to the card's position.
  void _step(TrainingCard card, int delta) {
    final current = _viewPly ?? card.path.length;
    final ply = (current + delta).clamp(0, card.path.length);
    if (ply == current) return;
    setState(() => _viewPly = ply == card.path.length ? null : ply);
    // The sound of the move that led to the position shown.
    if (ply > 0) {
      final before = positionAfterPath(card.path.take(ply - 1).toList());
      final san = _san(before, card.path[ply - 1]);
      unawaited(
        ref.read(soundServiceProvider).play(san.contains('x') ? Sound.capture : Sound.move),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    final card = _card;
    final scheme = ColorScheme.of(context);
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text(
          queue == null || card == null ? widget.title : '${widget.title} · ${queue.length} left',
        ),
      ),
      extendBodyBehindAppBar: false,
      body: queue == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : card == null
          ? Center(
              child: Padding(
                padding: Styles.bodyPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 56, color: Flare.green),
                    const SizedBox(height: 12.0),
                    Text(
                      _reviewed == 0 ? 'Nothing to review right now' : 'Session done',
                      style: Styles.title,
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      _reviewed == 0
                          ? 'Come back later: cards come back when they are due.'
                          : '$_right of $_reviewed right the first time.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16.0),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: Builder(
                builder: (context) {
                  final position = Chess.fromSetup(Setup.parseFen(card.fen));
                  final lastMove = card.path.isNotEmpty ? Move.parse(card.path.last) : null;
                  final answer = Move.parse(card.answer);
                  final viewPly = _viewPly;
                  final mySide = card.orientation;
                  final GameBoardParams board;
                  if (viewPly != null) {
                    // Going through the line: the position after its first moves.
                    board = GameBoardParams.readonly(
                      variant: .standard,
                      position: positionAfterPath(card.path.take(viewPly).toList()),
                      lastMove: viewPly > 0 ? Move.parse(card.path[viewPly - 1]) : null,
                    );
                  } else if (_answered && _played != null) {
                    board = GameBoardParams.readonly(
                      variant: .standard,
                      position: position.play(_played!),
                      lastMove: _played,
                    );
                  } else {
                    board = GameBoardParams.interactive(
                      variant: .standard,
                      position: position,
                      playerSide: mySide == Side.white ? PlayerSide.white : PlayerSide.black,
                      lastMove: lastMove,
                      onMove: (move, {viaDragAndDrop}) => unawaited(_onMove(move)),
                    );
                  }
                  final canBack = (viewPly ?? card.path.length) > 0;
                  final canForward = viewPly != null;
                  return GameLayout(
                    key: ValueKey(card.id),
                    orientation: mySide,
                    boardParams: board,
                    // After a wrong move: the right one.
                    shapes: _answer == _Answer.wrong && viewPly == null && answer is NormalMove
                        ? ISet({Arrow(color: Flare.green, orig: answer.from, dest: answer.to)})
                        : null,
                    topTable: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.kind == TrainingKind.opening ? 'Opening' : 'Your mistake',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          Text(card.title, style: Styles.sectionTitle),
                          if (card.path.isNotEmpty)
                            Text(
                              pathSan(card.path),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    bottomTable: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            viewPly != null
                                ? 'Going through the game: come back to the end to play.'
                                : switch (_answer) {
                                    _Answer.waiting =>
                                      card.kind == TrainingKind.opening
                                          ? 'Your move: what does your repertoire play?'
                                          : 'Find the move you missed in your game.',
                                    _Answer.correct => 'Correct!',
                                    _Answer.wrong => 'Not this one. Play the move shown.',
                                    _Answer.corrected => "That's the move. It comes back later.",
                                  },
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: viewPly != null
                                  ? scheme.onSurfaceVariant
                                  : switch (_answer) {
                                      _Answer.waiting => null,
                                      _Answer.correct || _Answer.corrected => Flare.green,
                                      _Answer.wrong => Flare.red,
                                    },
                            ),
                          ),
                          // A mistake: what the game's move lost, and what the right one gets.
                          if (card.kind == TrainingKind.mistake && viewPly == null)
                            _MistakeEvals(card: card, position: position, showBest: _answered),
                        ],
                      ),
                    ),
                    userActionsBar: BottomBar(
                      cupertinoGlass: true,
                      children: [
                        if (_answered)
                          BottomBarButton(
                            key: const ValueKey('training-next'),
                            label: 'Next',
                            showLabel: true,
                            highlighted: true,
                            icon: Icons.arrow_forward,
                            onTap: () => _next(requeue: _answer == _Answer.corrected),
                          )
                        else
                          BottomBarButton(
                            label: 'Skip',
                            showLabel: true,
                            icon: Icons.skip_next,
                            onTap: () => _next(requeue: true),
                          ),
                        // Held down, they go through the moves.
                        RepeatButton(
                          onLongPress: canBack ? () => _step(card, -1) : null,
                          child: BottomBarButton(
                            label: 'Previous move',
                            icon: Icons.chevron_left,
                            showTooltip: false,
                            onTap: canBack ? () => _step(card, -1) : null,
                          ),
                        ),
                        RepeatButton(
                          onLongPress: canForward ? () => _step(card, 1) : null,
                          child: BottomBarButton(
                            label: 'Next move',
                            icon: Icons.chevron_right,
                            showTooltip: false,
                            onTap: canForward ? () => _step(card, 1) : null,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// The evaluations of a mistake: the move played in the game and what it lost, then (once found)
/// the best move and what it gets.
class const _MistakeEvals({
  required final TrainingCard card,

  /// The position of the mistake.
  required final Position position,
  required final bool showBest,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final before = card.beforeEval;
    final played = card.playedEval;
    final best = card.bestEval;
    final side = card.orientation;
    final scheme = ColorScheme.of(context);
    if (before == null || played == null || card.played == null) return const SizedBox.shrink();
    final loss = _evalGain(before, played, side);
    final gain = best != null ? _evalGain(played, best, side) : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'In your game: ${_san(position, card.played!)}  ',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                TextSpan(text: '${_evalText(before, side)} → '),
                TextSpan(
                  text: _evalText(played, side),
                  style: const TextStyle(color: Flare.red, fontWeight: FontWeight.w800),
                ),
                if (loss != null)
                  TextSpan(
                    text: '  (${loss.toStringAsFixed(1)})',
                    style: const TextStyle(color: Flare.red),
                  ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          if (showBest && best != null)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Best: ${_san(position, card.answer)}  ',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  TextSpan(
                    text: _evalText(best, side),
                    style: const TextStyle(color: Flare.green, fontWeight: FontWeight.w800),
                  ),
                  if (gain != null)
                    TextSpan(
                      text: '  (+${gain.toStringAsFixed(1)} on your move)',
                      style: const TextStyle(color: Flare.green),
                    ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
