import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/challenge/challenge_repository.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:logging/logging.dart';

/// The user's lichess event stream, connected while signed in.
///
/// Knightly learns about game starts (seeks, challenges, tournaments) and challenges from it, in
/// place of the official app's websocket.
final boardEventsProvider = Provider<BoardEvents>((Ref ref) {
  final signedIn = ref.watch(authControllerProvider.select((user) => user != null));
  final events = BoardEvents(ref.read(boardApiRepositoryProvider));
  if (signedIn && ref.watch(useBoardApiProvider)) events.connect();
  ref.onDispose(events.dispose);
  return events;
}, name: 'BoardEventsProvider');

class BoardEvents(final BoardApiRepository _repository) {
  static final _logger = Logger('BoardEvents');

  /// How long a game start is remembered, for flows that start waiting for it a bit late.
  static const _rememberStartsFor = Duration(minutes: 2);

  final _controller = StreamController<BoardEvent>.broadcast();
  final Map<GameId, (BoardGameStarted, DateTime)> _recentStarts = {};
  StreamSubscription<BoardEvent>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _failures = 0;

  /// The events, from now on.
  Stream<BoardEvent> get stream => _controller.stream;

  void connect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final stream = await _repository.streamEvents();
      if (_disposed) return;
      _failures = 0;
      _logger.info('Connected');
      await _subscription?.cancel();
      _subscription = stream.listen(
        _onEvent,
        onError: (Object e, StackTrace st) {
          _logger.warning('Event stream error', e, st);
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (e, st) {
      _logger.warning('Could not open the event stream', e, st);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _failures++;
    final delay = Duration(seconds: (_failures * 3).clamp(3, 30));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  void _onEvent(BoardEvent event) {
    if (event is BoardGameStarted) {
      final now = DateTime.now();
      _recentStarts.removeWhere((_, entry) => now.difference(entry.$2) > _rememberStartsFor);
      _recentStarts[event.id] = (event, now);
    }
    _controller.add(event);
  }

  /// Waits for the start of the game [id] (a challenge's game has the challenge's id).
  Future<BoardGameStarted> gameStarted(
    GameId id, {
    Duration timeout = const Duration(seconds: 20),
  }) {
    final recent = _recentStarts[id];
    if (recent != null) return Future.value(recent.$1);
    return stream
        .where((e) => e is BoardGameStarted && e.id == id)
        .cast<BoardGameStarted>()
        .first
        .timeout(timeout);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_controller.close());
  }
}

/// The challenge lists fetched after the event stream announced a change, for the challenge service
/// (the official app gets them from its websocket).
final knightlyChallengeLists = StreamController<ChallengesList>.broadcast();
