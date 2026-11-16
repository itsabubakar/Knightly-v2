import 'dart:async';

import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/board_api/board_events.dart';
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/service/create_game_service.dart';
import 'package:logging/logging.dart';

/// [CreateGameService] through the Board API: seeks and challenges over HTTP streams, game starts
/// from the user's event stream (the official app uses websockets that accept only its login).
class BoardApiCreateGameService(super.log, {required super.ref, required super.sri})
    extends CreateGameService {
  static final _logger = Logger('BoardApiCreateGameService');

  BoardApiRepository get _repository => ref.read(boardApiRepositoryProvider);
  BoardEvents get _events => ref.read(boardEventsProvider);

  /// The pending lobby seek: the seek lasts while its stream is listened to.
  StreamSubscription<Map<String, dynamic>>? _seekSubscription;
  Completer<GameSeekResponse>? _seekCompleter;

  /// The pending real-time challenge, kept alive while its stream is listened to.
  ChallengeId? _challengeId;
  StreamSubscription<Map<String, dynamic>>? _challengeSubscription;
  final _challengeDone = Completer<String>();
  Completer<ChallengeResponse>? _challengeCompleter;

  @override
  Future<GameSeekResponse> newLobbyGame(GameSeek seek) async {
    ref.read(recentGameSeekProvider.notifier).addSeek(seek);
    if (_seekCompleter != null) throw StateError('Already creating a game.');
    final completer = Completer<GameSeekResponse>();
    _seekCompleter = completer;

    // The game start comes through the event stream, not the seek's stream.
    final events = _events.stream.listen((event) {
      if (event is BoardGameStarted &&
          event.isRealTime &&
          !event.hasMoved &&
          (event.source == 'lobby' || event.source == 'pool') &&
          !completer.isCompleted) {
        completer.complete(GameSeekCreated(fullId: event.fullId));
      }
    });
    Timer? endedTimer;

    try {
      var actualSeek = seek;
      if (seek.ratingDelta != null) {
        final account = await ref.read(accountProvider.future);
        if (account != null) actualSeek = actualSeek.withRatingRangeOf(account);
      }
      _logger.info('Seeking a game');
      final stream = await _repository.seek(actualSeek.requestBody);
      if (completer.isCompleted) return await completer.future;
      _seekSubscription = stream.listen(
        (_) {},
        onError: (Object e, StackTrace st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
        // Lichess closes the seek when it pairs it: the game start follows on the event stream.
        onDone: () => endedTimer = Timer(const Duration(seconds: 15), () {
          if (!completer.isCompleted) completer.complete(const GameSeekCancelled());
        }),
        cancelOnError: true,
      );
    } catch (e, st) {
      _logger.warning('Failed to create seek', e, st);
      if (!completer.isCompleted) completer.completeError(e, st);
    }

    try {
      return await completer.future;
    } finally {
      endedTimer?.cancel();
      await events.cancel();
      await _seekSubscription?.cancel();
      _seekSubscription = null;
      _seekCompleter = null;
    }
  }

  @override
  Future<void> newCorrespondenceGame(GameSeek seek) {
    _logger.info('Creating a correspondence seek');
    return _repository.seekCorrespondence(seek.requestBody);
  }

  @override
  Future<Challenge> newOpenOrRealTimeChallenge(ChallengeRequest challengeReq) async {
    final destUser = challengeReq.destUser;
    // An open challenge doesn't expire: the original flow creates and joins it.
    if (destUser == null) return await super.newOpenOrRealTimeChallenge(challengeReq);
    if (_challengeId != null) throw StateError('Already creating a challenge.');

    final stream = await _repository.createKeptAliveChallenge(destUser.id, {
      for (final MapEntry(:key, :value) in challengeReq.toRequestBody.entries)
        if (value != null) key: value.toString(),
    });
    final challenge = Completer<Challenge>();
    _challengeSubscription = stream.listen(
      (json) {
        if (!challenge.isCompleted) {
          challenge.complete(
            Challenge.fromServerJson((json['challenge'] as Map<String, dynamic>?) ?? json),
          );
        } else if (json['done'] case final String done when !_challengeDone.isCompleted) {
          _challengeDone.complete(done);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!challenge.isCompleted) challenge.completeError(e, st);
      },
      onDone: () {
        if (!challenge.isCompleted) {
          challenge.completeError(StateError('The challenge could not be created.'));
        }
      },
    );
    final created = await challenge.future;
    _challengeId = created.id;
    return created;
  }

  @override
  Future<ChallengeResponse> waitForChallengeResponse(Challenge challenge) {
    final keepAlive = ref.keepAlive();
    final completer = Completer<ChallengeResponse>();
    _challengeCompleter = completer;
    final gameId = GameId(challenge.id.value);

    void accepted() {
      unawaited(
        _events
            .gameStarted(gameId)
            .then((started) {
              if (!completer.isCompleted) {
                completer.complete(ChallengeResponseAccepted(gameFullId: started.fullId));
              }
            })
            .catchError((Object e, StackTrace st) {
              if (!completer.isCompleted) completer.completeError(e, st);
            }),
      );
    }

    final events = _events.stream.listen((event) {
      switch (event) {
        case BoardGameStarted(:final id) when id == gameId:
          accepted();
        case BoardChallengeDeclined(challenge: final declined) when declined.id == challenge.id:
          if (!completer.isCompleted) {
            completer.complete(
              ChallengeResponseDeclined(
                challenge: challenge,
                declineReason: declined.declineReason,
              ),
            );
          }
        case BoardChallengeCanceled(:final id) when id == challenge.id:
          if (!completer.isCompleted) completer.complete(const ChallengeResponseCancelled());
        case _:
          break;
      }
    });

    if (challenge.destUser != null) {
      unawaited(
        _challengeDone.future.then((done) async {
          if (completer.isCompleted) return;
          switch (done) {
            case 'accepted':
              accepted();
            case 'declined':
              final updated = await challengeRepository.show(challenge.id);
              if (!completer.isCompleted) {
                completer.complete(
                  ChallengeResponseDeclined(
                    challenge: challenge,
                    declineReason: updated.declineReason,
                  ),
                );
              }
            default:
              if (!completer.isCompleted) completer.complete(const ChallengeResponseCancelled());
          }
        }),
      );
    }

    return completer.future.whenComplete(() async {
      await events.cancel();
      await _challengeSubscription?.cancel();
      _challengeSubscription = null;
      _challengeId = null;
      _challengeCompleter = null;
      keepAlive.close();
    });
  }

  @override
  Future<ChallengeDeclineReason?> newCorrespondenceChallenge(ChallengeRequest challengeReq) async {
    _logger.info('Creating a correspondence challenge');
    final challenge = await challengeRepository.create(challengeReq);
    // A bot declines at once: wait a little for it.
    try {
      final declined = await _events.stream
          .where((e) => e is BoardChallengeDeclined && e.challenge.id == challenge.id)
          .cast<BoardChallengeDeclined>()
          .first
          .timeout(const Duration(seconds: 1));
      return declined.challenge.declineReason ?? ChallengeDeclineReason.generic;
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<void> cancelSeek() async {
    final completer = _seekCompleter;
    if (completer == null) return;
    _logger.info('Cancelling the seek');
    // Closing the seek's connection cancels it.
    await _seekSubscription?.cancel();
    _seekSubscription = null;
    if (!completer.isCompleted) completer.complete(const GameSeekCancelled());
  }

  @override
  Future<void> cancelChallenge() async {
    final id = _challengeId;
    if (id == null) return;
    _logger.info('Cancelling the challenge');
    await _challengeSubscription?.cancel();
    _challengeSubscription = null;
    await challengeRepository.cancel(id);
    final completer = _challengeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(const ChallengeResponseCancelled());
    }
  }

  @override
  void dispose() {
    unawaited(_seekSubscription?.cancel());
    unawaited(_challengeSubscription?.cancel());
    super.dispose();
  }
}
