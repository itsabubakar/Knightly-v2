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
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
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
  correct,
  wrong,
}

class _TrainingSessionScreenState() extends ConsumerState<TrainingSessionScreen> {
  /// The cards left, the current one first; null while loading.
  List<TrainingCard>? _queue;

  /// The cards answered wrong in this session (reviewed again, without a second schedule change).
  final _failed = <String>{};
  int _reviewed = 0;
  int _right = 0;
  _Answer _answer = _Answer.waiting;

  /// The move the user played, shown while a wrong answer is corrected.
  Move? _played;

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

  Future<void> _onMove(Move move) async {
    final card = _card;
    if (card == null) return;
    final correct = move.uci == card.answer || _sameCastling(card, move);
    final sound = ref.read(soundServiceProvider);
    if (_answer == _Answer.wrong) {
      // Correcting: only the right move goes on.
      if (!correct) return;
      unawaited(sound.play(Sound.move));
      setState(() => _played = null);
      _next(requeue: true);
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
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) _next();
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
    });
    if (queue.isEmpty) {
      ref.invalidate(trainingSummaryProvider);
      ref.invalidate(repertoiresProvider);
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
                  final shown = _played != null && _answer == _Answer.correct
                      ? position.play(_played!)
                      : position;
                  return GameLayout(
                    key: ValueKey(card.id),
                    orientation: card.orientation,
                    boardParams: _answer == _Answer.correct
                        ? GameBoardParams.readonly(
                            variant: .standard,
                            position: shown,
                            lastMove: _played,
                          )
                        : GameBoardParams.interactive(
                            variant: .standard,
                            position: position,
                            playerSide: card.orientation == Side.white
                                ? PlayerSide.white
                                : PlayerSide.black,
                            lastMove: lastMove,
                            onMove: (move, {viaDragAndDrop}) => unawaited(_onMove(move)),
                          ),
                    // After a wrong move: the right one.
                    shapes: _answer == _Answer.wrong && answer is NormalMove
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
                      child: Center(
                        child: Text(
                          switch (_answer) {
                            _Answer.waiting =>
                              card.kind == TrainingKind.opening
                                  ? 'Your move: what does your repertoire play?'
                                  : 'Find the move you missed in your game.',
                            _Answer.correct => 'Correct!',
                            _Answer.wrong => 'Not this one. Play the move shown.',
                          },
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: switch (_answer) {
                              _Answer.waiting => null,
                              _Answer.correct => Flare.green,
                              _Answer.wrong => Flare.red,
                            },
                          ),
                        ),
                      ),
                    ),
                    userActionsBar: BottomBar(
                      cupertinoGlass: true,
                      children: [
                        BottomBarButton(
                          label: 'Skip',
                          showLabel: true,
                          icon: Icons.skip_next,
                          onTap: _answer == _Answer.correct ? null : () => _next(requeue: true),
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
