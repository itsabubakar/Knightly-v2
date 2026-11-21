import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/board_api/board_events.dart';
import 'package:lichess_mobile/src/model/board_api/board_game_controller.dart';
import 'package:lichess_mobile/src/model/board_api/game_notes.dart';
import 'package:lichess_mobile/src/model/board_api/rematch_offers.dart';
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/challenge/challenges.dart';
import 'package:lichess_mobile/src/model/common/game.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/game_board_params.dart';
import 'package:lichess_mobile/src/model/game/material_diff.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/service/create_game_service.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/immersive_mode.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_screen.dart';
import 'package:lichess_mobile/src/view/board_game/game_xp_card.dart';
import 'package:lichess_mobile/src/view/game/correspondence_clock_widget.dart';
import 'package:lichess_mobile/src/view/game/game_player.dart' show ConfirmMove;
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/view/play/play_lichess_ai_sheet.dart';
import 'package:lichess_mobile/src/view/settings/board_settings_screen.dart';
import 'package:lichess_mobile/src/view/user/challenge_requests_screen.dart';
import 'package:lichess_mobile/src/view/user/user_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/material_diff.dart';
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

  /// Whether a rematch is being created.
  bool _rematching = false;

  /// How many chat messages the user has seen.
  int _chatSeen = 0;

  /// The move waiting for the user's confirmation (the "Move confirmation" setting), and the ply
  /// it was played at: it's dropped once the game has moved on.
  ({Move move, int ply})? _moveToConfirm;

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

  /// Shows the move [delta] plies away from the one shown; the last one is the live position.
  void _step(int delta) {
    final game = ref.read(boardGameControllerProvider(_id)).value;
    if (game == null) return;
    final lastPly = game.sans.length;
    final ply = ((_viewPly ?? lastPly) + delta).clamp(0, lastPly);
    setState(() => _viewPly = ply >= lastPly ? null : ply);
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

  /// Counts the game for the user's progression at once, for the end of game popup; null when it
  /// doesn't count (not the user's game, aborted, not started).
  Future<GameXpAward?> _countGame(BoardGameState game) async {
    final mySide = game.mySide;
    final speed = Speed.values.firstWhereOrNull((speed) => speed.name == game.speed);
    if (mySide == null || speed == null || !game.wasPlayed) return null;
    try {
      return await ref
          .read(progressionProvider.notifier)
          .addFinishedGame(
            id: _id,
            speed: speed,
            plies: game.moves.length,
            result: game.winner == null
                ? GameResult.draw
                : game.winner == mySide
                ? GameResult.win
                : GameResult.loss,
          );
    } catch (_) {
      // The next sync counts it.
      return null;
    }
  }

  void _showResult(BoardGameState game) {
    final award = _countGame(game);
    showAdaptiveDialog<void>(
      context: context,
      builder: (context) => PlatformAlertDialog(
        // What the game gave comes first, then the result.
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GameXpCard(award: award),
            const SizedBox(height: 16.0),
            Text(
              boardGameResult(game),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ],
        ),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (_canRematch(game))
            PlatformDialogAction(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(_rematch(game));
              },
              child: const Text('Rematch'),
            ),
          if (game.wasPlayed)
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

  /// The analysis board of a correspondence game going on: the moves and the opening explorer, no
  /// engine (lichess doesn't allow one during a game).
  void _openCorrespondenceAnalysis(BoardGameState game) {
    Navigator.of(context).push(
      AnalysisScreen.buildRoute(
        AnalysisOptions.pgn(
          id: _id,
          orientation: game.mySide ?? Side.white,
          pgn: game.pgn,
          variant: game.variant,
          isComputerAnalysisAllowed: false,
          initialMoveCursor: game.sans.length,
        ),
      ),
    );
  }

  Future<void> _openChat(BoardGameState game) async {
    setState(() => _chatSeen = game.chat.length);
    await showAdaptiveBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BoardGameChatSheet(gameId: _id, myName: game.player(game.mySide!).name),
    );
    if (!mounted) return;
    setState(
      () => _chatSeen = ref.read(boardGameControllerProvider(_id)).value?.chat.length ?? _chatSeen,
    );
  }

  /// Whether the user can ask for a rematch of [game]: the opponent is the lichess AI or a user.
  bool _canRematch(BoardGameState game) {
    final mySide = game.mySide;
    if (!game.isOver || mySide == null) return false;
    final opponent = game.player(mySide.opposite);
    return opponent.aiLevel != null || opponent.id != null;
  }

  /// A new game with the same settings and the colors swapped: at once against the lichess AI, a
  /// new challenge to a user (lichess's own rematch is only for the official app).
  /// Accepts the opponent's rematch offer, then opens the rematch.
  Future<void> _acceptRematch() async {
    final offer = ref.read(rematchOffersProvider)[_id];
    if (offer == null || _rematching) return;
    final navigator = Navigator.of(context);
    setState(() => _rematching = true);
    try {
      final events = ref.read(boardEventsProvider);
      await ref.read(rematchOffersProvider.notifier).accept(_id);
      // The rematch's game has the id of its challenge.
      final fullId = await startedGameFullId(ref, events, GameId(offer.id.value));
      if (fullId == null) throw StateError('The rematch was not found.');
      if (!mounted) return;
      navigator.pushReplacement(GameScreen.buildRoute(source: ExistingGameSource(fullId)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _rematching = false);
      showSnackBar(context, 'Could not accept the rematch.', type: SnackBarType.error);
    }
  }

  Future<void> _rematch(BoardGameState game) async {
    final mySide = game.mySide;
    if (mySide == null || _rematching) return;
    // The opponent asked first: that's the rematch.
    if (ref.read(rematchOffersProvider)[_id] != null) return await _acceptRematch();
    final opponent = game.player(mySide.opposite);
    final color = mySide.opposite;
    final clock = game.clock != null
        ? (time: game.clock!.initial, increment: game.clock!.increment)
        : null;
    final navigator = Navigator.of(context);
    setState(() => _rematching = true);
    try {
      if (opponent.aiLevel case final level?) {
        final events = ref.read(boardEventsProvider);
        final id = await ref
            .read(boardApiRepositoryProvider)
            .challengeAi(level: level, clock: clock, days: game.daysPerTurn, color: color);
        final fullId = await startedGameFullId(ref, events, id);
        if (fullId == null) throw StateError('The game $id was not found.');
        if (!mounted) return;
        navigator.pushReplacement(GameScreen.buildRoute(source: ExistingGameSource(fullId)));
        return;
      }
      final request = ChallengeRequest(
        destUser: LightUser(id: opponent.id!, name: opponent.name, title: opponent.title),
        variant: game.variant,
        timeControl: clock != null
            ? ChallengeTimeControlType.clock
            : game.daysPerTurn != null
            ? ChallengeTimeControlType.correspondence
            : ChallengeTimeControlType.unlimited,
        clock: clock,
        days: game.daysPerTurn,
        rated: game.rated,
        sideChoice: color == Side.white ? SideChoice.white : SideChoice.black,
        initialFen: game.variant == .fromPosition ? game.positions.first.fen : null,
      );
      if (clock != null) {
        // The game screen waits for the opponent's answer, then opens the game.
        final source = UserChallengeSource(request);
        ref.invalidate(gameScreenLoaderProvider(source));
        navigator.pushReplacement(GameScreen.buildRoute(source: source));
        return;
      }
      final declined = await ref
          .read(createGameServiceProvider)
          .newCorrespondenceChallenge(request);
      if (!mounted) return;
      setState(() => _rematching = false);
      showSnackBar(
        context,
        declined != null
            ? '${opponent.name} declined the rematch.'
            : 'Rematch sent to ${opponent.name}.',
        type: declined != null ? SnackBarType.error : SnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _rematching = false);
      showSnackBar(
        context,
        e is ServerException && e.jsonError?['error'] != null
            ? 'Could not start a rematch: ${e.jsonError!['error']}'
            : 'Could not start a rematch.',
        type: SnackBarType.error,
      );
    }
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
      final rematchOffer = ref.watch(rematchOffersProvider.select((offers) => offers[_id]));
      // Hidden until the setting is known.
      final takebacksAllowed = switch (ref.watch(accountPreferencesProvider)) {
        AsyncData(:final value) => game.takebacksAllowed(value.takeback),
        _ => false,
      };
      final confirmsMoves = switch (ref.watch(accountPreferencesProvider)) {
        AsyncData(:final value) => game.confirmsMoves(value.submitMove),
        _ => false,
      };
      final viewPly = _viewPly != null && _viewPly! < lastPly ? _viewPly : null;
      final moveToConfirm = switch (_moveToConfirm) {
        (:final move, :final ply) when ply == lastPly && game.isMyTurn => move,
        _ => null,
      };
      final livePosition = moveToConfirm != null
          ? game.position.playUnchecked(moveToConfirm)
          : game.position;
      final position = viewPly != null ? game.positions[viewPly] : livePosition;
      // The board stays interactive on the opponent's turn: a move then is a premove (if enabled
      // in the board settings), played as soon as the opponent's move arrives.
      final interactive =
          viewPly == null && !game.isOver && game.mySide != null && moveToConfirm == null;
      void send(Move move) =>
          unawaited(_run(() => _controller.userMove(move), 'The move was not accepted.'));
      // A move on the user's turn waits for its confirmation when the setting asks for it; a
      // premove doesn't, as on lichess.
      void play(Move move) {
        if (confirmsMoves && game.isMyTurn && game.position.isLegal(move)) {
          setState(() => _moveToConfirm = (move: move, ply: lastPly));
        } else {
          send(move);
        }
      }

      layout = GameLayout(
        orientation: bottomSide,
        onPremove: send,
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
                lastMove: viewPly == null ? moveToConfirm ?? game.lastMove : null,
              ),
        topTable: BoardGamePlayer(
          game: game,
          position: position,
          side: bottomSide.opposite,
          timeLeft: game.timeLeft(bottomSide.opposite, now),
        ),
        bottomTable: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BoardGamePlayer(
              game: game,
              position: position,
              side: bottomSide,
              timeLeft: game.timeLeft(bottomSide, now),
            ),
            if (moveToConfirm != null && viewPly == null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ConfirmMove(
                  onConfirm: () {
                    setState(() => _moveToConfirm = null);
                    send(moveToConfirm);
                  },
                  onCancel: () => setState(() => _moveToConfirm = null),
                ),
              ),
            if (game.isOver) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  boardGameResult(game),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              if (rematchOffer != null)
                BoardGameOffer(
                  text: '${rematchOffer.challenger?.user.name ?? 'Your opponent'} wants a rematch',
                  onAccept: _acceptRematch,
                  onDecline: () => _run(
                    () => ref.read(rematchOffersProvider.notifier).decline(_id),
                    'Could not decline the rematch.',
                  ),
                ),
            ] else if (game.opponentOffersDraw)
              BoardGameOffer(
                text: 'Your opponent offers a draw',
                onAccept: () => _run(_controller.offerOrAcceptDraw, 'Could not accept the draw.'),
                onDecline: () => _run(_controller.declineDraw, 'Could not decline the draw.'),
              )
            else if (game.opponentProposesTakeback && takebacksAllowed)
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
            if (_canRematch(game))
              BottomBarButton(
                label: 'Rematch',
                showLabel: true,
                icon: Icons.replay,
                onTap: _rematching ? null : () => _rematch(game),
              ),
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
            if (!game.isOver && takebacksAllowed)
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
            // Held down, they go through the moves.
            RepeatButton(
              onLongPress: (viewPly ?? lastPly) > 0 ? () => _step(-1) : null,
              child: BottomBarButton(
                label: 'Previous move',
                icon: Icons.chevron_left,
                showTooltip: false,
                onTap: (viewPly ?? lastPly) > 0 ? () => _step(-1) : null,
              ),
            ),
            RepeatButton(
              onLongPress: viewPly != null ? () => _step(1) : null,
              child: BottomBarButton(
                label: 'Next move',
                icon: Icons.chevron_right,
                showTooltip: false,
                onTap: viewPly != null ? () => _step(1) : null,
              ),
            ),
          ],
        ),
      );
    }
    // Chat with the opponent: not with the AI, nor in kid mode.
    final kidMode = ref.watch(kidModeProvider).value ?? true;
    final canChat = value != null && value.mySide != null && !value.isAgainstAi && !kidMode;
    final unreadChat = canChat
        ? value.chat
              .skip(_chatSeen)
              .where((line) => line.username != value.player(value.mySide!).name)
              .length
        : 0;
    // Challenges received meanwhile, to see without leaving the game.
    final incomingChallenges = switch (ref.watch(challengesProvider)) {
      AsyncData(:final value) => value.inward.length,
      _ => 0,
    };
    return PlatformScaffold(
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: false,
      appBar: PlatformAppBar(
        title: Text(value != null ? _title(value) : 'Game'),
        actions: [
          if (canChat)
            IconButton(
              tooltip: 'Chat',
              icon: Badge.count(
                count: unreadChat,
                isLabelVisible: unreadChat > 0,
                child: const Icon(Icons.chat_bubble_outline),
              ),
              onPressed: () => _openChat(value),
            ),
          if (incomingChallenges > 0)
            IconButton(
              tooltip: 'Challenges',
              icon: Badge.count(
                count: incomingChallenges,
                child: const Icon(LichessIcons.crossed_swords),
              ),
              onPressed: () => Navigator.of(context).push(ChallengeRequestsScreen.buildRoute()),
            ),
          IconButton(
            tooltip: 'Flip board',
            icon: const Icon(Icons.swap_vert),
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
          if (value != null && value.isCorrespondence && value.mySide != null && !value.isOver) ...[
            IconButton(
              tooltip: 'Analysis board',
              icon: const Icon(Icons.biotech_outlined),
              onPressed: () => _openCorrespondenceAnalysis(value),
            ),
            IconButton(
              tooltip: 'Notes',
              icon: const Icon(Icons.edit_note),
              onPressed: () => showAdaptiveBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => BoardGameNotesSheet(gameId: _id),
              ),
            ),
          ],
          IconButton(
            tooltip: 'Board settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(BoardSettingsScreen.buildRoute()),
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

/// A player of a Board API game: name, rating (as the "Show ratings" setting allows) and clock.
class const BoardGamePlayer({
  required final BoardGameState game,

  /// The position on the board, for the material difference.
  required final Position position,
  required final Side side,
  required final Duration? timeLeft,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = game.player(side);
    final materialFormat = ref.watch(
      boardPreferencesProvider.select((prefs) => prefs.materialDifferenceFormat),
    );
    // Hidden until the setting is known, rather than flashed.
    final showRating = switch (ref.watch(showRatingsPrefProvider)) {
      AsyncData(value: ShowRatings.yes) => true,
      AsyncData(value: ShowRatings.exceptInGame) => game.isOver,
      _ => false,
    };
    final scheme = ColorScheme.of(context);
    final active = !game.isOver && game.sideToMove == side;
    final userId = player.id;
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  // Opens the player's profile.
                  onTap: userId == null
                      ? null
                      : () => Navigator.of(context).push(
                          UserScreen.buildRoute(
                            LightUser(id: userId, name: player.name, title: player.title),
                          ),
                        ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (player.title != null)
                          TextSpan(
                            text: '${player.title} ',
                            style: const TextStyle(
                              color: Flare.orange,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        TextSpan(
                          text: player.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (showRating && player.rating != null)
                          TextSpan(
                            text: ' ${player.rating}${player.provisional ? '?' : ''}',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (materialFormat.visible)
                  MaterialDifferenceDisplay(
                    materialDiff: MaterialDiff.fromPosition(position).bySide(side),
                    materialDifferenceFormat: materialFormat,
                  ),
              ],
            ),
          ),
          if (timeLeft != null && game.daysPerTurn != null)
            CorrespondenceClock(
              duration: timeLeft!,
              active: active && game.clocksRunning,
              // Restarts from the time left whenever lichess sends it.
              resetId: game.clockAt.millisecondsSinceEpoch,
            )
          else if (timeLeft != null)
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

/// The user's private notes on a game, saved on the phone as they're typed.
class const BoardGameNotesSheet({required final GameId gameId, super.key}) extends StatefulWidget {
  @override
  State<BoardGameNotesSheet> createState() => _BoardGameNotesSheetState();
}

class _BoardGameNotesSheetState() extends State<BoardGameNotesSheet> {
  late final _controller = TextEditingController(text: readGameNote(widget.gameId));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: Styles.bodyPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Notes', style: Styles.title),
              const SizedBox(height: 4.0),
              Text(
                'Only you see them; they stay on this phone.',
                style: TextStyle(color: ColorScheme.of(context).onSurfaceVariant),
              ),
              const SizedBox(height: 12.0),
              TextField(
                controller: _controller,
                autofocus: _controller.text.isEmpty,
                minLines: 5,
                maxLines: 12,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Plans, ideas, what to watch for...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (text) => writeGameNote(widget.gameId, text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// lichess's quick chat phrases.
const kQuickChatPhrases = [
  'Hello',
  'Good luck',
  'Have fun!',
  'You too!',
  'Good game',
  'Well played',
  'Thank you',
];

/// The chat of a game with the opponent: the messages, lichess's quick phrases and a text box.
class const BoardGameChatSheet({
  required final GameId gameId,

  /// The user's name, to show their own messages on the right.
  required final String myName,
  super.key,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<BoardGameChatSheet> createState() => _BoardGameChatSheetState();
}

class _BoardGameChatSheetState() extends ConsumerState<BoardGameChatSheet> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      // The message comes back through the game stream, like the opponent's.
      await ref.read(boardGameControllerProvider(widget.gameId).notifier).sendChat(message);
      if (mounted && _text.text.trim() == message) _text.clear();
    } catch (_) {
      if (mounted) showSnackBar(context, 'Could not send the message.', type: SnackBarType.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(boardGameControllerProvider(widget.gameId).select((s) => s.value?.chat));
    final lines = chat?.reversed.toList() ?? const <BoardChatLine>[];
    final scheme = ColorScheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: Styles.bodyPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Chat', style: Styles.title),
              const SizedBox(height: 8.0),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
                child: lines.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Text(
                          'No messages yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        shrinkWrap: true,
                        itemCount: lines.length,
                        itemBuilder: (context, index) {
                          final line = lines[index];
                          final mine = line.username == widget.myName;
                          final system = line.username == 'lichess';
                          return Align(
                            alignment: system
                                ? Alignment.center
                                : mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3.0),
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                              constraints: const BoxConstraints(maxWidth: 280),
                              decoration: BoxDecoration(
                                color: system
                                    ? Colors.transparent
                                    : mine
                                    ? scheme.primaryContainer
                                    : scheme.surfaceContainerHighest,
                                borderRadius: const BorderRadius.all(Radius.circular(14.0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!mine && !system)
                                    Text(
                                      line.username,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  Text(
                                    line.text,
                                    style: system
                                        ? TextStyle(
                                            color: scheme.onSurfaceVariant,
                                            fontStyle: FontStyle.italic,
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8.0),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final phrase in kQuickChatPhrases)
                      Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ActionChip(
                          label: Text(phrase),
                          onPressed: _sending ? null : () => _send(phrase),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8.0),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLength: 140,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        counterText: '',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    icon: const Icon(Icons.send),
                    onPressed: _sending ? null : () => _send(_text.text),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
