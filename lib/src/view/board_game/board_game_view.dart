import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/account/ongoing_game.dart';
import 'package:lichess_mobile/src/model/account/ongoing_games_notifier.dart';
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
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/game_board_params.dart';
import 'package:lichess_mobile/src/model/game/game_preferences.dart';
import 'package:lichess_mobile/src/model/game/game_repository.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/game/material_diff.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/model/tournament/tournament_repository.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/model/user/user_repository_providers.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/service/create_game_service.dart';
import 'package:lichess_mobile/src/service/move_feedback.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/lichess_colors.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/chessboard.dart';
import 'package:lichess_mobile/src/utils/immersive_mode.dart';
import 'package:lichess_mobile/src/utils/l10n.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/lichess_assets.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_screen.dart';
import 'package:lichess_mobile/src/view/board_game/game_xp_card.dart';
import 'package:lichess_mobile/src/view/game/correspondence_clock_widget.dart';
import 'package:lichess_mobile/src/view/game/game_common_widgets.dart';
import 'package:lichess_mobile/src/view/game/game_player.dart' show ConfirmMove;
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/view/game/status_l10n.dart';
import 'package:lichess_mobile/src/view/play/play_lichess_ai_sheet.dart';
import 'package:lichess_mobile/src/view/settings/board_settings_screen.dart';
import 'package:lichess_mobile/src/view/tournament/tournament_screen.dart';
import 'package:lichess_mobile/src/view/user/challenge_requests_screen.dart';
import 'package:lichess_mobile/src/view/user/user_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/android_gesture_exclusion.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/material_diff.dart';
import 'package:lichess_mobile/src/widgets/network_image.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:lichess_mobile/src/widgets/platform_context_menu_button.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The result of a finished Board API game, e.g. "1-0 · Checkmate".
String boardGameResult(BuildContext context, BoardGameState game) {
  final score = switch (game.winner) {
    Side.white => '1-0',
    Side.black => '0-1',
    null when game.status == 'aborted' || game.status == 'noStart' => null,
    null => '½-½',
  };
  // lichess's own wording, in the app's language.
  final status = GameStatus.values.firstWhereOrNull((status) => status.name == game.status);
  final reason = status != null
      ? gameStatusL10n(
          context,
          variant: game.variant,
          status: status,
          lastPosition: game.position,
          winner: game.winner,
          isThreefoldRepetition: game.isThreefoldRepetition,
        )
      : game.status;
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

  /// Whether the game is bookmarked on lichess, once known.
  bool? _bookmarked;

  /// Whether the game's arena allows berserk, once read.
  bool _berserkable = false;

  Future<void> _loadTournament(TournamentId id) async {
    try {
      final tournament = await ref.read(tournamentRepositoryProvider).getTournament(id);
      if (mounted) setState(() => _berserkable = tournament.berserkable);
    } catch (_) {
      // No berserk button.
    }
  }

  /// Leaves the arena for now: no new pairing until the user joins again.
  Future<void> _pauseTournament(TournamentId id) async {
    try {
      await ref.read(tournamentRepositoryProvider).withdraw(id);
      if (mounted) showSnackBar(context, 'Tournament paused.', type: SnackBarType.success);
    } catch (_) {
      if (mounted) {
        showSnackBar(context, 'Could not pause the tournament.', type: SnackBarType.error);
      }
    }
  }

  /// When the last move was played, for a correspondence game: read from lichess, then the time
  /// a move arrives.
  DateTime? _lastMoveAt;

  /// Reads what the game stream doesn't say: whether the game is bookmarked, when the last move
  /// was played.
  Future<void> _loadExport() async {
    try {
      final exported = await ref.read(gameRepositoryProvider).getGame(_id, withBookmarked: true);
      if (!mounted) return;
      setState(() {
        _bookmarked = exported.data.bookmarked ?? false;
        _lastMoveAt ??= exported.data.lastMoveAt;
      });
    } catch (_) {
      // The menu offers to bookmark it; no last move time.
    }
  }

  Future<void> _toggleBookmark() async {
    final bookmark = !(_bookmarked ?? false);
    setState(() => _bookmarked = bookmark);
    try {
      await ref.read(accountRepositoryProvider).bookmark(_id, bookmark: bookmark);
    } catch (_) {
      if (!mounted) return;
      setState(() => _bookmarked = !bookmark);
      showSnackBar(context, 'Could not change the bookmark.', type: SnackBarType.error);
    }
  }

  /// The user's next correspondence game where it's their turn, if any.
  OngoingGame? _nextCorrespondenceGame() => ref
      .watch(ongoingGamesProvider)
      .value
      ?.firstWhereOrNull(
        (game) => game.isMyTurn && game.speed == Speed.correspondence && game.id != _id,
      );

  /// Opens [next] in place of this game.
  void _openGame(OngoingGame next) =>
      Navigator.of(context)
          .pushReplacement(GameScreen.buildRoute(source: ExistingGameSource(next.fullId)));

  /// What the game gave, counted once when it ends: the result popup shows it again.
  Future<GameXpAward?>? _award;

  /// The rating changes of the game (white, black), read from lichess once it's over.
  ({int? white, int? black})? _ratingDiffs;

  /// Reads the rating changes of the game, once it's over and rated: lichess has them a moment
  /// after the end.
  Future<void> _loadRatingDiffs(BoardGameState game) async {
    if (!game.rated || !game.wasPlayed || _ratingDiffs != null) return;
    for (final wait in const [Duration(seconds: 1), Duration(seconds: 4)]) {
      await Future<void>.delayed(wait);
      if (!mounted) return;
      try {
        final exported = await ref.read(gameRepositoryProvider).getGame(_id);
        final diffs = (white: exported.white.ratingDiff, black: exported.black.ratingDiff);
        if (diffs.white != null || diffs.black != null) {
          if (mounted) setState(() => _ratingDiffs = diffs);
          return;
        }
      } catch (_) {
        // Tried again, or left without.
      }
    }
  }

  /// Whether the low time sound was played since the user's clock went under the threshold.
  bool _lowTimeWarned = false;

  /// Plays the low time sound once when the user's clock goes under the emergency threshold, as
  /// the account's "Clock sound" setting allows; again after it has gone back above (increment).
  void _checkLowTime(BoardGameState game) {
    final threshold = game.emergencyThreshold;
    final mySide = game.mySide;
    if (threshold == null || mySide == null) return;
    final left = game.timeLeft(mySide, DateTime.now());
    if (left == null) return;
    if (left > threshold) {
      _lowTimeWarned = false;
    } else if (!_lowTimeWarned && game.clocksRunning && game.isMyTurn) {
      _lowTimeWarned = true;
      unawaited(() async {
        if (await ref.read(clockSoundProvider.future) && mounted) {
          await ref.read(soundServiceProvider).play(Sound.lowTime);
        }
      }());
    }
  }

  @override
  void initState() {
    super.initState();
    _openGames = ref.read(openBoardGamesProvider)..add(_id);
    unawaited(_loadExport());
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final game = ref.read(boardGameControllerProvider(_id)).value;
      if (mounted && game != null && game.clocksRunning) {
        _checkLowTime(game);
        setState(() {});
      }
    });
    ref.listenManual<BoardGameState?>(boardGameControllerProvider(_id).select((s) => s.value), (
      previous,
      next,
    ) {
      if (next == null) return;
      if (previous == null && next.isOver) unawaited(_loadRatingDiffs(next));
      if (previous == null && next.tournamentId != null && !next.isOver) {
        unawaited(_loadTournament(next.tournamentId!));
      }
      // A player went berserk.
      if (previous != null &&
          (next.whiteBerserk && !previous.whiteBerserk ||
              next.blackBerserk && !previous.blackBerserk)) {
        unawaited(ref.read(soundServiceProvider).play(Sound.berserk));
      }
      if (previous == null) {
        // A new game of the user's, as it opens: the start "dong", as on lichess.
        if (next.mySide != null && next.moves.isEmpty && !next.isOver) {
          unawaited(ref.read(soundServiceProvider).play(Sound.dong));
        }
        return;
      }
      if (next.moves.length > previous.moves.length) {
        setState(() => _lastMoveAt = DateTime.now());
        // The sound, and the vibration the board settings ask for.
        final san = next.sans.isNotEmpty ? next.sans.last : '';
        final feedback = ref.read(moveFeedbackServiceProvider);
        final check = san.contains('+') || san.contains('#');
        if (san.contains('x')) {
          feedback.captureFeedback(next.variant, check: check);
        } else {
          feedback.moveFeedback(check: check);
        }
      }
      if (next.isOver && !previous.isOver) {
        // The game is over: the screen may sleep again.
        unawaited(WakelockPlus.disable());
        unawaited(ref.read(soundServiceProvider).play(Sound.dong));
        _showResult(next);
        unawaited(_loadRatingDiffs(next));
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
    _showPly(game, ((_viewPly ?? lastPly) + delta).clamp(0, lastPly));
  }

  /// Shows the position at [ply] (the live one at the last ply), with the sound of the move that
  /// led to it.
  void _showPly(BoardGameState game, int ply, {bool haptic = false}) {
    final lastPly = game.sans.length;
    final current = _viewPly ?? lastPly;
    setState(() => _viewPly = ply >= lastPly ? null : ply);
    if (ply == current || ply == 0) return;
    final san = game.sans[ply - 1];
    unawaited(ref.read(soundServiceProvider).play(san.contains('x') ? Sound.capture : Sound.move));
    if (haptic && ref.read(boardPreferencesProvider).hapticFeedback) {
      unawaited(HapticFeedback.lightImpact());
    }
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
    final award = _award ??= _countGame(game);
    final victor = switch (game.winner) {
      Side.white => context.l10n.whiteIsVictorious,
      Side.black => context.l10n.blackIsVictorious,
      null => null,
    };
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
              boardGameResult(context, game),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            if (victor != null) Text(victor, textAlign: TextAlign.center),
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
          if (game.tournamentId case final tournamentId?)
            PlatformDialogAction(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(this.context).push(TournamentScreen.buildRoute(tournamentId));
              },
              child: const Text('Back to tournament'),
            ),
          if (_canSeekNewOpponent(game))
            PlatformDialogAction(
              onPressed: () {
                Navigator.of(context).pop();
                _newOpponent(game);
              },
              child: const Text('New opponent'),
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

  /// Whether a new opponent can be sought with this game's settings: a real-time game against a
  /// person, over.
  bool _canSeekNewOpponent(BoardGameState game) =>
      game.isOver &&
      game.mySide != null &&
      !game.isAgainstAi &&
      game.clock != null &&
      game.tournamentId == null;

  /// Seeks a new opponent with this game's time control, variant and rating mode, in place of
  /// this screen.
  void _newOpponent(BoardGameState game) {
    final clock = game.clock!;
    Navigator.of(context).pushReplacement(
      GameScreen.buildRoute(
        source: LobbySource(
          GameSeek(
            clock: (clock.initial, clock.increment),
            rated: game.rated,
            variant: game.variant,
          ),
        ),
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
      final accountPrefs = ref.watch(accountPreferencesProvider).value;
      final overrides = ref.watch(boardGameOverridesProvider(_id));
      final confirmsMoves =
          accountPrefs != null &&
          game.confirmsMoves(accountPrefs.submitMove) &&
          (overrides.confirmMoves ?? true);
      final autoQueen = accountPrefs?.autoQueen == AutoQueen.always && overrides.autoQueen == false
          ? AutoQueen.premove
          : accountPrefs?.autoQueen;
      final zenMode = boardGameZenMode(game, accountPrefs, overrides);
      final blindfold = ref.watch(gamePreferencesProvider.select((p) => p.blindfoldMode ?? false));
      final confirmResignAndDraw = ref.watch(
        boardPreferencesProvider.select((prefs) => prefs.confirmResignAndDraw),
      );
      final nextGame = game.isCorrespondence ? _nextCorrespondenceGame() : null;
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
        boardSettingsOverrides: BoardSettingsOverrides(
          // The "Promote to Queen automatically" setting.
          autoQueenPromotion: autoQueen == AutoQueen.always,
          autoQueenPromotionOnPremove:
              autoQueen == AutoQueen.always || autoQueen == AutoQueen.premove,
          // No premoves in correspondence, as on lichess.
          enablePremoves: game.isCorrespondence ? false : null,
          // No piece animation in bullet, as on lichess: there's no time to watch it.
          animationDuration: game.speed == 'bullet' || game.speed == 'ultraBullet'
              ? Duration.zero
              : null,
          blindfoldMode: blindfold,
        ),
        // Zen mode: no move list.
        zenMode: zenMode,
        // Atomic chess: the explosion of the last capture.
        explosionSquares: viewPly == null && game.positions.length >= 2
            ? atomicExplosionSquares(game.positions[game.positions.length - 2], game.lastMove)
            : null,
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
          ratingDiff: bottomSide.opposite == Side.white ? _ratingDiffs?.white : _ratingDiffs?.black,
          zenMode: zenMode,
          position: position,
          side: bottomSide.opposite,
          timeLeft: game.timeLeft(bottomSide.opposite, now),
        ),
        bottomTable: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BoardGamePlayer(
              game: game,
              ratingDiff: bottomSide == Side.white ? _ratingDiffs?.white : _ratingDiffs?.black,
              zenMode: zenMode,
              position: position,
              side: bottomSide,
              timeLeft: game.timeLeft(bottomSide, now),
            ),
            // Correspondence: when the last move was played, under the clocks.
            if (game.isCorrespondence && !game.isOver && _lastMoveAt != null)
              Text(
                'Last move ${relativeDate(context.l10n, _lastMoveAt!)}',
                style: TextStyle(color: ColorScheme.of(context).onSurfaceVariant, fontSize: 12),
              ),
            if (moveToConfirm != null && viewPly == null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ConfirmMove(
                  onConfirm: () {
                    setState(() => _moveToConfirm = null);
                    unawaited(ref.read(soundServiceProvider).play(Sound.confirmation));
                    send(moveToConfirm);
                  },
                  onCancel: () => setState(() => _moveToConfirm = null),
                ),
              ),
            if (game.isOver) ...[
              // The result: tapped, its popup again once closed.
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: GestureDetector(
                  onTap: () => _showResult(game),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          boardGameResult(context, game),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 6.0),
                      const Icon(Icons.info_outline, size: 18, semanticLabel: 'Show result'),
                    ],
                  ),
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
            ] else if (game.isCorrespondence &&
                game.mySide != null &&
                !game.isMyTurn &&
                nextGame != null)
              TextButton.icon(
                icon: const Icon(Icons.skip_next),
                label: const Text('Next game: your turn'),
                onPressed: () => _openGame(nextGame),
              )
            else if (game.isThreefoldRepetition && game.mySide != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: FilledButton(
                  // lichess takes a draw "yes" on a threefold repetition as the claim.
                  onPressed: () => _run(_controller.offerOrAcceptDraw, 'Could not claim the draw.'),
                  child: const Text('Threefold repetition: claim a draw'),
                ),
              )
            else if (game.opponentOffersDraw)
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
                    : Wrap(
                        spacing: 8.0,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton(
                            onPressed: () =>
                                _run(_controller.claimVictory, 'Could not claim victory.'),
                            child: const Text('Opponent left: claim victory'),
                          ),
                          OutlinedButton(
                            onPressed: () => _run(_controller.claimDraw, 'Could not claim a draw.'),
                            child: const Text('Call it a draw'),
                          ),
                        ],
                      ),
              ),
          ],
        ),
        moves: game.sans.toList(),
        currentMoveIndex: viewPly ?? lastPly,
        onSelectMove: (ply) => _showPly(game, ply, haptic: true),
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
                    ? confirmResignAndDraw
                          ? () => _confirm(
                              'Resign the game?',
                              _controller.resign,
                              'Could not resign.',
                            )
                          : () => _run(_controller.resign, 'Could not resign.')
                    : null,
              ),
            // An arena that allows it, before the user's first move.
            if (_berserkable &&
                !game.isOver &&
                game.mySide != null &&
                game.clock != null &&
                !game.isBerserk(game.mySide!) &&
                game.moves.length < 2)
              BottomBarButton(
                label: 'Berserk',
                icon: LichessIcons.body_cut,
                onTap: () => _run(_controller.berserk, 'Could not go berserk.'),
              ),
            if (!game.isOver)
              BottomBarButton(
                label: game.iOfferDraw ? 'Cancel draw offer' : 'Offer draw',
                icon: Icons.handshake_outlined,
                highlighted: game.iOfferDraw,
                onTap: game.iOfferDraw
                    // lichess takes "no" from the side offering as withdrawing it.
                    ? () => _run(_controller.declineDraw, 'Could not cancel the draw offer.')
                    : game.isAgainstAi || game.moves.length < 2
                    ? null
                    : confirmResignAndDraw
                    ? () => _confirm(
                        'Offer a draw?',
                        _controller.offerOrAcceptDraw,
                        'Could not offer a draw.',
                      )
                    : () => _run(_controller.offerOrAcceptDraw, 'Could not offer a draw.'),
              ),
            if (!game.isOver && takebacksAllowed)
              BottomBarButton(
                label: game.iProposeTakeback ? 'Cancel takeback' : 'Propose takeback',
                icon: Icons.undo,
                highlighted: game.iProposeTakeback,
                onTap: game.iProposeTakeback
                    // As for the draw: "no" from the side proposing withdraws it.
                    ? () => _run(_controller.declineTakeback, 'Could not cancel the takeback.')
                    : game.moves.isEmpty || game.isAgainstAi
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
    final chatEnabled = ref.watch(gamePreferencesProvider.select((p) => p.enableChat ?? true));
    final zenMode =
        value != null &&
        boardGameZenMode(
          value,
          ref.watch(accountPreferencesProvider).value,
          ref.watch(boardGameOverridesProvider(_id)),
        );
    final canChat =
        value != null &&
        value.mySide != null &&
        !value.isAgainstAi &&
        !kidMode &&
        chatEnabled &&
        !zenMode &&
        // No chat in arena games, as on lichess.
        value.tournamentId == null;
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
    final menuNextGame = value != null && value.isCorrespondence ? _nextCorrespondenceGame() : null;
    return PlatformScaffold(
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: false,
      appBar: PlatformAppBar(
        title: value == null
            ? const Text('Game')
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (Speed.values.firstWhereOrNull((speed) => speed.name == value.speed)
                      case final speed?) ...[
                    Icon(Perf.fromVariantAndSpeed(value.variant, speed).icon, size: 20),
                    const SizedBox(width: 6.0),
                  ],
                  Flexible(
                    child: Text(
                      value.reconnecting ? 'Reconnecting…' : _title(value),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
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
          if (value != null)
            ContextMenuIconButton(
              icon: const Icon(Icons.more_vert),
              semanticsLabel: 'More',
              actions: [
                if (menuNextGame != null)
                  ContextMenuAction(
                    icon: Icons.skip_next,
                    label: 'Next game: your turn',
                    onPressed: () => _openGame(menuNextGame),
                  ),
                if (value.tournamentId case final tournamentId?) ...[
                  ContextMenuAction(
                    icon: Icons.emoji_events_outlined,
                    label: 'Back to tournament',
                    onPressed: () =>
                        Navigator.of(context).push(TournamentScreen.buildRoute(tournamentId)),
                  ),
                  if (value.isOver)
                    ContextMenuAction(
                      icon: Icons.pause,
                      label: 'Pause tournament',
                      onPressed: () => _pauseTournament(tournamentId),
                    ),
                ],
                ContextMenuAction(
                  icon: _bookmarked == true ? Icons.bookmark : Icons.bookmark_border,
                  label: _bookmarked == true ? 'Remove bookmark' : 'Bookmark',
                  onPressed: _toggleBookmark,
                ),
                ...makeFinishedGameShareMenuActions(
                  context,
                  ref,
                  gameId: _id,
                  orientation: value.mySide ?? Side.white,
                  finished: value.isOver,
                ),
              ],
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: value == null
                ? null
                : () => showAdaptiveBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => BoardGameSettingsSheet(game: value),
                  ),
          ),
        ],
      ),
      body: switch (game) {
        AsyncData(value: final game) => WakelockWidget(
          shouldEnableOnFocusGained: () => !game.isOver,
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
            child: SafeArea(
              // Android: full screen while playing a real-time game (board settings).
              child: Theme.of(context).platform == TargetPlatform.android
                  ? AndroidImmersiveModeWidget(
                      enabled:
                          !game.isOver &&
                          game.mySide != null &&
                          game.clock != null &&
                          (ref.watch(
                                boardPreferencesProvider.select(
                                  (prefs) => prefs.immersiveModeWhilePlaying,
                                ),
                              ) ??
                              false),
                      child: layout!,
                    )
                  : layout!,
            ),
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

/// What the user changed for one game in its settings sheet, over the account's settings: move
/// confirmation, auto-queen, zen mode. Null where the account's setting applies.
typedef BoardGameOverrides = ({bool? confirmMoves, bool? autoQueen, bool? zenMode});

/// The settings the user changed for a game, while its screen is open.
final boardGameOverridesProvider = NotifierProvider.autoDispose
    .family<BoardGameOverridesNotifier, BoardGameOverrides, GameId>(
      BoardGameOverridesNotifier.new,
      name: 'BoardGameOverridesProvider',
    );

class BoardGameOverridesNotifier(final GameId gameId) extends Notifier<BoardGameOverrides> {
  @override
  BoardGameOverrides build() => (confirmMoves: null, autoQueen: null, zenMode: null);

  void setConfirmMoves(bool value) =>
      state = (confirmMoves: value, autoQueen: state.autoQueen, zenMode: state.zenMode);

  void setAutoQueen(bool value) =>
      state = (confirmMoves: state.confirmMoves, autoQueen: value, zenMode: state.zenMode);

  void setZenMode(bool value) =>
      state = (confirmMoves: state.confirmMoves, autoQueen: state.autoQueen, zenMode: value);
}

/// Whether zen mode (no names, chat nor moves) is on for [game]: the account's "Zen mode" setting
/// (during games, or always: then after them too), unless the user changed it for this game.
bool boardGameZenMode(BoardGameState game, AccountPrefState? prefs, BoardGameOverrides overrides) =>
    overrides.zenMode ??
    switch (prefs?.zenMode) {
      Zen.yes => true,
      Zen.gameAuto => !game.isOver,
      _ => false,
    };

/// The settings of a game, from its app bar: sound, move confirmation and auto-queen (when the
/// account's settings use them), zen mode, chat, blindfold, and the board settings.
class const BoardGameSettingsSheet({required final BoardGameState game, super.key})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrides = ref.watch(boardGameOverridesProvider(game.id));
    final overridesNotifier = ref.read(boardGameOverridesProvider(game.id).notifier);
    final accountPrefs = ref.watch(accountPreferencesProvider).value;
    final gamePrefs = ref.watch(gamePreferencesProvider);
    final isSoundEnabled = ref.watch(generalPreferencesProvider).isSoundEnabled;
    final canChat = game.mySide != null && !game.isAgainstAi;
    return BottomSheetScrollableContainer(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ListSection(
          header: const Text('Settings'),
          materialFilledCard: true,
          children: [
            SwitchSettingTile(
              title: const Text('Sound'),
              value: isSoundEnabled,
              onChanged: (_) => ref.read(generalPreferencesProvider.notifier).toggleSoundEnabled(),
            ),
            // For this game only, when the account's setting asks for it.
            if (accountPrefs != null && game.confirmsMoves(accountPrefs.submitMove))
              SwitchSettingTile(
                title: const Text('Move confirmation'),
                value: overrides.confirmMoves ?? true,
                onChanged: overridesNotifier.setConfirmMoves,
              ),
            if (accountPrefs?.autoQueen == AutoQueen.always)
              SwitchSettingTile(
                title: const Text('Promote to Queen automatically'),
                value: overrides.autoQueen ?? true,
                onChanged: overridesNotifier.setAutoQueen,
              ),
            SwitchSettingTile(
              title: const Text('Zen mode'),
              subtitle: const Text('Hides the names, the chat and the moves'),
              value: boardGameZenMode(game, accountPrefs, overrides),
              onChanged: overridesNotifier.setZenMode,
            ),
            if (canChat)
              SwitchSettingTile(
                title: const Text('Chat'),
                value: gamePrefs.enableChat ?? true,
                onChanged: (_) => ref.read(gamePreferencesProvider.notifier).toggleChat(),
              ),
            SwitchSettingTile(
              title: const Text('Blindfold'),
              subtitle: const Text('Hides the pieces'),
              value: gamePrefs.blindfoldMode ?? false,
              onChanged: (_) => ref.read(gamePreferencesProvider.notifier).toggleBlindfoldMode(),
            ),
            ListTile(
              title: const Text('Board settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(BoardSettingsScreen.buildRoute()),
            ),
          ],
        ),
      ],
    );
  }
}

/// A player of a Board API game: name, rating (as the "Show ratings" setting allows) and clock.
class const BoardGamePlayer({
  required final BoardGameState game,

  /// The player's rating change, once the game is over.
  final int? ratingDiff,

  /// Zen mode: only the clock.
  final bool zenMode = false,

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
    // The patron wings and the flair, from the player's profile.
    final profile = userId != null && !zenMode ? ref.watch(userProvider(userId)).value : null;
    // The score of the player against the other, in their games together.
    final otherId = game.player(side.opposite).id;
    final crosstable = userId != null && otherId != null && game.mySide != null && !zenMode
        ? ref.watch(crosstableProvider((userId1: userId, userId2: otherId, matchup: false))).value
        : null;
    final headToHead = crosstable != null && crosstable.nbGames > 0
        ? crosstable.users[userId!]
        : null;
    final clockTenths =
        ref.watch(clockTenthsProvider).value ?? defaultAccountPreferences.clockTenths;
    final clockPosition = ref.watch(
      boardPreferencesProvider.select((prefs) => prefs.clockPosition),
    );
    final Widget? clock = timeLeft != null && game.daysPerTurn != null
        ? CorrespondenceClock(
            duration: timeLeft!,
            active: active && game.clocksRunning,
            // Restarts from the time left whenever lichess sends it.
            resetId: game.clockAt.millisecondsSinceEpoch,
          )
        : timeLeft != null
        ? Clock(
            timeLeft: timeLeft!,
            active: active && game.clocksRunning,
            emergencyThreshold: game.emergencyThreshold,
            clockTenths: clockTenths,
          )
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Row(
        children: [
          if (clock != null && clockPosition == ClockPosition.left) ...[
            clock,
            const SizedBox(width: 12.0),
          ],
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
                if (!zenMode) ...[
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
                          if (profile?.isPatron == true)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4.0),
                                child: PatronIcon(size: 16, color: profile!.patronColor),
                              ),
                            ),
                          if (player.title != null)
                            TextSpan(
                              text: '${player.title} ',
                              style: TextStyle(
                                // A bot's title as lichess shows it.
                                color: player.title == 'BOT' ? LichessColors.fancy : Flare.orange,
                                fontWeight: player.title == 'BOT' ? null : FontWeight.w800,
                              ),
                            ),
                          TextSpan(
                            text: player.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (profile?.flair case final flair?)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4.0),
                                child: HttpNetworkImageWidget(
                                  lichessFlairSrc(flair),
                                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                  width: 16,
                                  height: 16,
                                ),
                              ),
                            ),
                          if (game.isBerserk(side))
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsets.only(left: 4.0),
                                child: Icon(
                                  LichessIcons.body_cut,
                                  size: 16,
                                  color: Flare.orange,
                                  semanticLabel: 'Berserk',
                                ),
                              ),
                            ),
                          if (showRating && player.rating != null)
                            TextSpan(
                              text: ' ${player.rating}${player.provisional ? '?' : ''}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          if (headToHead != null)
                            TextSpan(
                              text: ' · ${_score(headToHead)}',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          if (showRating && ratingDiff != null)
                            TextSpan(
                              text: ratingDiff! > 0 ? ' +$ratingDiff' : ' $ratingDiff',
                              style: TextStyle(
                                color: ratingDiff! > 0
                                    ? Flare.green
                                    : ratingDiff! < 0
                                    ? Flare.red
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
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
              ],
            ),
          ),
          if (clock != null && clockPosition == ClockPosition.right)
            clock
          else if (clock == null && game.daysPerTurn != null && active)
            Text(
              game.mySide == side ? 'Your turn' : 'Waiting',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// A head to head score: whole points, with a half.
String _score(double score) {
  final whole = score.floor();
  final half = score - whole >= 0.5;
  return half ? (whole == 0 ? '½' : '$whole½') : '$whole';
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
