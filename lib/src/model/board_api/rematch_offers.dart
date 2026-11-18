import 'dart:async';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/board_api/board_events.dart';
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/challenge/challenge_repository.dart';
import 'package:lichess_mobile/src/model/common/id.dart';

/// The rematch offers the user received, by the game they're a rematch of.
///
/// lichess sends an opponent's rematch offer (from the website or the official app) through the
/// event stream as a challenge with `rematchOf`; it isn't in the challenges list. Accepting it
/// (as a challenge) starts the rematch.
final rematchOffersProvider = NotifierProvider<RematchOffers, IMap<GameId, Challenge>>(
  RematchOffers.new,
  name: 'RematchOffersProvider',
);

class RematchOffers() extends Notifier<IMap<GameId, Challenge>> {
  @override
  IMap<GameId, Challenge> build() {
    final me = ref.watch(authControllerProvider.select((user) => user?.user.id));
    final subscription = ref.watch(boardEventsProvider).stream.listen((event) {
      switch (event) {
        case BoardChallengeCreated(:final challenge)
            when challenge.rematchOf != null && challenge.challenger?.user.id != me:
          state = state.add(challenge.rematchOf!, challenge);
        case BoardChallengeCanceled(:final id):
          _removeChallenge(id);
        case BoardChallengeDeclined(:final challenge):
          _removeChallenge(challenge.id);
        // The rematch's game has the id of its challenge.
        case BoardGameStarted(:final id):
          _removeChallenge(ChallengeId(id.value));
        case _:
          break;
      }
    });
    ref.onDispose(subscription.cancel);
    return const IMapConst({});
  }

  void _removeChallenge(ChallengeId id) {
    state = state.removeWhere((_, challenge) => challenge.id == id);
  }

  /// Accepts the rematch of [gameId]; the game start then comes through the event stream.
  Future<void> accept(GameId gameId) async {
    final offer = state[gameId];
    if (offer == null) return;
    await ref.read(challengeRepositoryProvider).accept(offer.id);
    state = state.remove(gameId);
  }

  /// Declines the rematch of [gameId].
  Future<void> decline(GameId gameId) async {
    final offer = state[gameId];
    if (offer == null) return;
    state = state.remove(gameId);
    await ref.read(challengeRepositoryProvider).decline(offer.id);
  }
}
