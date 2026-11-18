import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/ongoing_games_notifier.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/board_api/board_events.dart';
import 'package:lichess_mobile/src/model/board_api/board_game_controller.dart';
import 'package:lichess_mobile/src/model/board_api/rematch_offers.dart';
import 'package:lichess_mobile/src/model/challenge/challenge_repository.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:logging/logging.dart';

final boardGameServiceProvider = Provider<BoardGameService>((Ref ref) {
  final service = BoardGameService(ref);
  ref.onDispose(service.dispose);
  return service;
}, name: 'BoardGameServiceProvider');

/// Follows the user's lichess event stream (Board API):
///
/// - opens a real-time game that starts (or is going on) and isn't on screen: a seek paired, a
///   challenge accepted, a tournament pairing, a game left open when the app was closed;
/// - refreshes the challenges and the ongoing games when they change.
class BoardGameService(final Ref ref) {
  static final _logger = Logger('BoardGameService');

  /// Time for the screen that started a game (seek, challenge) to show it first.
  static const _openDelay = Duration(milliseconds: 1500);

  StreamSubscription<BoardEvent>? _subscription;
  ProviderSubscription<BoardEvents>? _eventsSubscription;

  void start() {
    if (!ref.read(useBoardApiProvider)) return;
    // Collects the rematch offers from now on, for the game screens.
    ref.read(rematchOffersProvider);
    // The events object is rebuilt at sign in and sign out.
    _eventsSubscription = ref.listen<BoardEvents>(boardEventsProvider, (_, events) {
      unawaited(_subscription?.cancel());
      _subscription = events.stream.listen(_onEvent);
    }, fireImmediately: true);
  }

  void _onEvent(BoardEvent event) {
    switch (event) {
      case BoardGameStarted(:final id, :final fullId, isRealTime: true):
        ref.invalidate(ongoingGamesProvider);
        Timer(_openDelay, () {
          if (ref.read(openBoardGamesProvider).contains(id)) return;
          final navigator = ref.read(currentNavigatorKeyProvider).currentState;
          if (navigator == null) return;
          _logger.info('Opening game $id');
          unawaited(
            navigator.pushHidingTabBar(GameScreen.buildRoute(source: ExistingGameSource(fullId))),
          );
        });
      case BoardGameStarted() || BoardGameFinished():
        ref.invalidate(ongoingGamesProvider);
      case BoardChallengeCreated() || BoardChallengeCanceled() || BoardChallengeDeclined():
        unawaited(_refreshChallenges());
    }
  }

  Future<void> _refreshChallenges() async {
    try {
      knightlyChallengeLists.add(await ref.read(challengeRepositoryProvider).list());
    } catch (e, st) {
      _logger.warning('Could not refresh the challenges', e, st);
    }
  }

  void dispose() {
    _eventsSubscription?.close();
    unawaited(_subscription?.cancel());
  }
}
