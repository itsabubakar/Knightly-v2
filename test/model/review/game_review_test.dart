import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/model/review/game_review.dart';
import 'package:lichess_mobile/src/model/review/game_tags.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';
import '../auth/fake_auth_storage.dart';

const _gameId = GameId('abcd1234');

final ReviewedGameInfo _info = (
  gameId: _gameId,
  opponent: 'Bob',
  playedAt: DateTime(2026, 11, 15),
  orientation: Side.white,
);

/// A signed in container with no lichess activity, its progression loaded.
Future<ProviderContainer> _container() async {
  final container = await makeContainer(
    authUser: fakeAuthUser,
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
        (ref) => FakeHttpClientFactory(() => MockClient((_) => mockResponse('', 404))),
      ),
    },
  );
  await container.read(progressionProvider.future);
  return container;
}

void main() {
  test('tagging a move earns XP, untagging takes it back', () async {
    final container = await _container();
    // Kept alive like the tag sheet does by watching it.
    container.listen(gameReviewProvider(_gameId), (_, _) {});
    container.listen(reviewedGamesProvider, (_, _) {});
    final review = container.read(gameReviewProvider(_gameId).notifier);
    await container.read(gameReviewProvider(_gameId).future);

    await review.toggleTag(ply: 27, san: 'Nxe5', tagId: 'hanging_piece', info: _info);

    expect((await container.read(gameReviewProvider(_gameId).future)).tagsAt(27), {
      'hanging_piece',
    });
    // 5 XP for the tag, 15 for the "Honest Mirror" achievement (first mistake tagged).
    final progression = container.read(progressionProvider).value!;
    expect(progression.totalXp, kMoveTaggedXp + 15);
    expect(
      progression.achievements.firstWhere((a) => a.achievement.id == 'honest_mirror').earnedAt,
      isNotNull,
    );
    final games = await container.read(reviewedGamesProvider.future);
    expect(games.single.info.opponent, 'Bob');
    expect(games.single.tags.single.san, 'Nxe5');

    await review.toggleTag(ply: 27, san: 'Nxe5', tagId: 'hanging_piece', info: _info);

    expect((await container.read(gameReviewProvider(_gameId).future)).tagsAt(27), isEmpty);
    // The achievement stays earned, with its XP.
    expect(container.read(progressionProvider).value!.totalXp, 15);
    expect(await container.read(reviewedGamesProvider.future), isEmpty);
  });

  test('a lessons learned note makes the game reviewed, once', () async {
    final container = await _container();
    // Kept alive like the tag sheet does by watching it.
    container.listen(gameReviewProvider(_gameId), (_, _) {});
    container.listen(reviewedGamesProvider, (_, _) {});
    final review = container.read(gameReviewProvider(_gameId).notifier);
    await container.read(gameReviewProvider(_gameId).future);

    await review.saveNote('  Check every capture.  ', _info);
    await review.saveNote('Check every capture before moving.', _info);

    expect(
      (await container.read(gameReviewProvider(_gameId).future)).note,
      'Check every capture before moving.',
    );
    expect(container.read(progressionProvider).value!.totalXp, kGameReviewedXp);
    expect((await container.read(reviewedGamesProvider.future)).single.note, isNotEmpty);

    await review.saveNote('', _info);

    expect(container.read(progressionProvider).value!.totalXp, 0);
  });

  test('the tag list can be edited', () async {
    final container = await makeContainer();
    final tagList = container.read(tagListProvider.notifier);
    expect(container.read(tagListProvider), kStarterTags);

    await tagList.add('Rushed move', TagKind.mistake);
    await tagList.rename('good_plan', 'Great plan');
    await tagList.remove('time_trouble');

    final tags = container.read(tagListProvider);
    expect(tags.any((tag) => tag.label == 'Rushed move' && tag.kind == TagKind.mistake), isTrue);
    expect(tags.firstWhere((tag) => tag.id == 'good_plan').label, 'Great plan');
    expect(tags.any((tag) => tag.id == 'time_trouble'), isFalse);
    // A removed tag is still known, for the moves that have it.
    expect(tagList.byId('time_trouble')?.label, 'Time trouble');

    await tagList.restoreStarterTags();

    expect(container.read(tagListProvider).any((tag) => tag.id == 'time_trouble'), isTrue);
    expect(container.read(tagListProvider).any((tag) => tag.label == 'Rushed move'), isTrue);
  });
}
