import 'package:collection/collection.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/relation/following_user.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/aggregator.dart';
import 'package:lichess_mobile/src/network/http.dart';

/// A provider for [RelationRepository].
final relationRepositoryProvider = Provider<RelationRepository>((ref) {
  return RelationRepository(ref.watch(lichessClientProvider), ref.watch(aggregatorProvider));
}, name: 'RelationRepositoryProvider');

/// The list of users that the current user is following.
final followingProvider = FutureProvider.autoDispose<IList<User>>((ref) {
  return ref.read(relationRepositoryProvider).getAllFollowing();
});

class const RelationRepository(final LichessClient client, final Aggregator aggregator) {
  /// Fetches the list of users that the current user is following.
  Future<IList<User>> getAllFollowing() {
    return client.readNdJsonList(
      Uri(path: '/api/rel/following'),
      headers: {'Accept': 'application/x-ndjson'},
      mapper: User.fromServerJson,
    );
  }

  /// Fetches a list of users that the current user is following, limited to 10 users.
  ///
  /// This is for displaying a recent following carousel or a preview of the following list.
  /// It contains useful information such as the last seen time and whether the user is currently playing a game.
  ///
  /// Built from the public `/api/rel/following`, since `/api/mobile/following` accepts only the
  /// official app's tokens: it has no "currently playing" information.
  Future<IList<FollowingUser>> getRecentFollowing() async {
    final following = await getAllFollowing();
    final recent = following.sortedByCompare(
      (user) => user.seenAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      (a, b) => b.compareTo(a),
    );
    return recent
        .take(10)
        .map((user) => FollowingUser(user: user.lightUser, seenAt: user.seenAt))
        .toIList();
  }

  Future<void> follow(UserId userId) async {
    final uri = Uri(path: '/api/rel/follow/$userId');
    await client.postRead(uri);
  }

  Future<void> unfollow(UserId userId) async {
    final uri = Uri(path: '/api/rel/unfollow/$userId');
    await client.postRead(uri);
  }

  Future<void> block(UserId userId) async {
    final uri = Uri(path: '/api/rel/block/$userId');
    await client.postRead(uri);
  }

  Future<void> unblock(UserId userId) async {
    final uri = Uri(path: '/api/rel/unblock/$userId');
    await client.postRead(uri);
  }

  Future<void> deleteThread(UserId userId) async {
    final uri = Uri(path: '/inbox/$userId/delete');
    await client.postRead(uri);
  }
}
