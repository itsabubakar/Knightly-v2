import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/board_api/board_game_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/game/game_board_params.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/utils/immersive_mode.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// The result of a finished Board API game, e.g. "1-0 · Checkmate".
String boardGameResult(BoardGameState game) {
  final score = switch (game.winner) {
    Side.white => '1-0',
    Side.black => '0-1',
    null when game.status == 'aborted' || game.status == 'noStart' => null,
    null => '½-½',
  };
  final loser = game.winner?.opposite;
  final reason = switch (game.status) {
    'mate' => 'Checkmate',
    'resign' => '${loser == Side.white ? 'White' : 'Black'} resigned',
    'outoftime' || 'timeout' => 'Time out',
    'stalemate' => 'Stalemate',
    'draw' => 'Draw',
    'aborted' => 'Game aborted',
    'noStart' => 'The game did not start',
    'cheat' => 'Cheat detected',
    final other => other,
  };
  return score != null ? '$score · $reason' : reason;
}

/// A live game of the user, played through lichess's Board API.
///
/// No engine, no analysis while the game is going on (fair play).
class const BoardGameView({required final GameFullId fullId, super.key})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<BoardGameView> createState() => _BoardGameViewState();
}

class _BoardGameViewState() extends ConsumerState<BoardGameView> {
  late final GameId _id = widget.fullId.gameId;
  late final OpenBoardGames _openGames;
  Timer? _ticker;

  /// The ply shown while browsing the moves, null for the live position.
  int? _viewPly;
  bool _flipped = false;

  @override
  void initState() {
    super.initState();
    _openGames = ref.read(openBoardGamesProvider)..add(_id);
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && (ref.read(boardGameControllerProvider(_id)).value?.clocksRunning ?? false)) {
        setState(() {});
      }
    });
    ref.listenManual<BoardGameState?>(boardGameControllerProvider(_id).select((s) => s.value), (
      previous,
      next,
    ) {
      if (previous == null || next == null) return;
      if (next.moves.length > previous.moves.length) {
        final san = next.sans.isNotEmpty ? next.sans.last : '';
        unawaited(
          ref.read(soundServiceProvider).play(san.contains('x') ? Sound.capture : Sound.move),
        );
      }
      if (next.isOver && !previous.isOver) {
        unawaited(ref.read(soundServiceProvider).play(Sound.dong));
        _showResult(next);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _openGames.remove(_id);
    super.dispose();
  }

  BoardGameController get _controller => ref.read(boardGameControllerProvider(_id).notifier);

  Future<void> _run(Future<void> Function() action, String failure) async {
    try {
      await action();
    } catch (_) {
      if (mounted) showSnackBar(context, failure, type: SnackBarType.error);
    }
  }

  void _openAnalysis(BoardGameState game) {
    Navigator.of(context).push(
      AnalysisScreen.buildRoute(
        AnalysisOptions.archivedGame(
          orientation: game.mySide ?? Side.white,
          gameId: _id,
          initialMoveCursor: 0,
        ),
      ),
    );
  }

  void _showResult(BoardGameState game) {
    showAdaptiveDialog<void>(
      context: context,
      builder: (context) => PlatformAlertDialog(
        title: Text(boardGameResult(game)),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (game.status != 'aborted' && game.status != 'noStart')
            PlatformDialogAction(
              cupertinoIsDefaultAction: true,
              onPressed: () {
                Navigator.of(context).pop();
                _openAnalysis(game);
              },
              child: const Text('Analysis board'),
            ),
        ],
      ),
    );
  }

  Future<void> _confirm(String title, Future<void> Function() action, String failure) {
    return showAdaptiveDialog<void>(
      context: context,
      builder: (context) => YesNoDialog(
        title: Text(title),
        onNo: () => Navigator.of(context).pop(),
        onYes: () {
          Navigator.of(context).pop();
          unawaited(_run(action, failure));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(boardGameControllerProvider(_id));
    final value = game.value;
    Widget? layout;
    if (value != null) {
      final game = value;
      final now = DateTime.now();
      final mySide = game.mySide ?? Side.white;
      final bottomSide = _flipped ? mySide.opposite : mySide;
      final lastPly = game.sans.length;
      final viewPly = _viewPly != null && _viewPly! < lastPly ? _viewPly : null;
      final position = viewPly != null ? game.positions[viewPly] : game.position;
      // The board stays interactive on the opponent's turn: a move then is a premove (if enabled
      // in the board settings), played as soon as the opponent's move arrives.
      final interactive = viewPly == null && !game.isOver && game.mySide != null;
      void play(Move move) =>
          unawaited(_run(() => _controller.userMove(move), 'The move was not accepted.'));

      layout = GameLayout(
        orientation: bottomSide,
        onPremove: play,
        boardParams: interactive
            ? GameBoardParams.interactive(
                variant: game.variant,
                position: position,
                playerSide: mySide == Side.white ? PlayerSide.white : PlayerSide.black,
                lastMove: game.lastMove,
                onMove: (move, {viaDragAndDrop}) => play(move),
              )
            : GameBoardParams.readonly(
                variant: game.variant,
                position: position,
                lastMove: viewPly == null ? game.lastMove : null,
              ),
        topTable: BoardGamePlayer(
          game: game,
          side: bottomSide.opposite,
          timeLeft: game.timeLeft(bottomSide.opposite, now),
        ),
        bottomTable: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BoardGamePlayer(game: game, side: bottomSide, timeLeft: game.timeLeft(bottomSide, now)),
            if (game.isOver)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  boardGameResult(game),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              )
            else if (game.opponentOffersDraw)
              BoardGameOffer(
                text: 'Your opponent offers a draw',
                onAccept: () => _run(_controller.offerOrAcceptDraw, 'Could not accept the draw.'),
                onDecline: () => _run(_controller.declineDraw, 'Could not decline the draw.'),
              )
            else if (game.opponentProposesTakeback)
              BoardGameOffer(
                text: 'Your opponent proposes a takeback',
                onAccept: () =>
                    _run(_controller.proposeOrAcceptTakeback, 'Could not accept the takeback.'),
                onDecline: () =>
                    _run(_controller.declineTakeback, 'Could not decline the takeback.'),
              )
            else if (game.canClaimVictoryAt case final claimAt?)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: now.isBefore(claimAt)
                    ? Text(
                        'Your opponent left the game. You can claim victory in '
                        '${claimAt.difference(now).inSeconds + 1} s.',
                      )
                    : FilledButton(
                        onPressed: () => _run(_controller.claimVictory, 'Could not claim victory.'),
                        child: const Text('Opponent left: claim victory'),
                      ),
              ),
          ],
        ),
        moves: game.sans.toList(),
        currentMoveIndex: viewPly ?? lastPly,
        onSelectMove: (ply) => setState(() => _viewPly = ply >= lastPly ? null : ply),
        userActionsBar: BottomBar(
          cupertinoGlass: true,
          children: [
            if (game.isOver)
              BottomBarButton(
                label: 'Analysis board',
                showLabel: true,
                icon: Icons.biotech_outlined,
                onTap: game.status == 'aborted' || game.status == 'noStart'
                    ? null
                    : () => _openAnalysis(game),
              )
            else if (game.canAbort)
              BottomBarButton(
                label: 'Abort',
                icon: Icons.cancel_outlined,
                onTap: () => _confirm('Abort the game?', _controller.abort, 'Could not abort.'),
              )
            else
              BottomBarButton(
                label: 'Resign',
                icon: Icons.flag_outlined,
                onTap: game.canResign
                    ? () => _confirm('Resign the game?', _controller.resign, 'Could not resign.')
                    : null,
              ),
            if (!game.isOver)
              BottomBarButton(
                label: game.iOfferDraw ? 'Draw offered' : 'Offer draw',
                icon: Icons.handshake_outlined,
                highlighted: game.iOfferDraw,
                onTap: game.iOfferDraw || game.isAgainstAi || game.moves.length < 2
                    ? null
                    : () => _run(_controller.offerOrAcceptDraw, 'Could not offer a draw.'),
              ),
            if (!game.isOver)
              BottomBarButton(
                label: game.iProposeTakeback ? 'Takeback proposed' : 'Propose takeback',
                icon: Icons.undo,
                highlighted: game.iProposeTakeback,
                onTap: game.iProposeTakeback || game.moves.isEmpty || game.isAgainstAi
                    ? null
                    : () => _run(
                        _controller.proposeOrAcceptTakeback,
                        'Could not propose a takeback.',
                      ),
              ),
            BottomBarButton(
              label: 'Previous move',
              icon: Icons.chevron_left,
              onTap: (viewPly ?? lastPly) > 0
                  ? () => setState(() => _viewPly = (viewPly ?? lastPly) - 1)
                  : null,
            ),
            BottomBarButton(
              label: 'Next move',
              icon: Icons.chevron_right,
              onTap: viewPly != null
                  ? () => setState(() => _viewPly = viewPly + 1 >= lastPly ? null : viewPly + 1)
                  : null,
            ),
          ],
        ),
      );
    }
    return PlatformScaffold(
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: false,
      appBar: PlatformAppBar(
        title: Text(value != null ? _title(value) : 'Game'),
        actions: [
          IconButton(
            tooltip: 'Flip board',
            icon: const Icon(Icons.swap_vert),
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
        ],
      ),
      body: switch (game) {
        AsyncData(value: final game) => WakelockWidget(
          child: PopScope(
            // A real-time game can't be left by mistake while it's going on.
            canPop: game.isOver || game.clock == null || game.mySide == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) {
                showSnackBar(
                  context,
                  'The game is going on: resign or abort it first.',
                  type: SnackBarType.info,
                );
              }
            },
            child: SafeArea(child: layout!),
          ),
        ),
        AsyncError(:final error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load the game.\n$error', textAlign: TextAlign.center),
                const SizedBox(height: 12.0),
                FilledButton(
                  onPressed: () => ref.invalidate(boardGameControllerProvider(_id)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator.adaptive()),
      },
    );
  }

  String _title(BoardGameState game) {
    final clock = game.clock;
    final control = clock != null
        ? '${clock.initial.inMinutes}+${clock.increment.inSeconds}'
        : game.daysPerTurn != null
        ? '${game.daysPerTurn} days'
        : 'Unlimited';
    return '$control · ${game.rated ? 'Rated' : 'Casual'}';
  }
}

/// A player of a Board API game: name, rating and clock.
class const BoardGamePlayer({
  required final BoardGameState game,
  required final Side side,
  required final Duration? timeLeft,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final player = game.player(side);
    final scheme = ColorScheme.of(context);
    final active = !game.isOver && game.sideToMove == side;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 12,
            color: side == Side.white ? Colors.white : Colors.black,
            shadows: const [Shadow(blurRadius: 1)],
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (player.title != null)
                    TextSpan(
                      text: '${player.title} ',
                      style: const TextStyle(color: Flare.orange, fontWeight: FontWeight.w800),
                    ),
                  TextSpan(
                    text: player.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (player.rating != null)
                    TextSpan(
                      text: ' ${player.rating}${player.provisional ? '?' : ''}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (timeLeft != null)
            Clock(
              timeLeft: timeLeft!,
              active: active && game.clocksRunning,
              emergencyThreshold: const Duration(seconds: 20),
            )
          else if (game.daysPerTurn != null && active)
            Text(
              game.mySide == side ? 'Your turn' : 'Waiting',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// An offer of the opponent (draw, takeback), with accept and decline buttons.
class const BoardGameOffer({
  required final String text,
  required final VoidCallback onAccept,
  required final VoidCallback onDecline,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, left: 12.0, right: 12.0),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          TextButton(onPressed: onDecline, child: const Text('Decline')),
          FilledButton(onPressed: onAccept, child: const Text('Accept')),
        ],
      ),
    );
  }
}
