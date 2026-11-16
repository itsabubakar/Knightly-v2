import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:lichess_mobile/src/model/review/game_review.dart';
import 'package:lichess_mobile/src/model/review/game_tags.dart';

/// The id of the starter tag for time trouble.
const kTimeTroubleTagId = 'time_trouble';

/// What the reviewed games of a period say: how many had mistakes, time trouble, or were strong,
/// and which tags come back most.
@immutable
class const GameInsights({
  required final int gamesReviewed,

  /// The games with at least one mistake tag.
  required final int gamesWithMistakes,

  /// The games tagged with time trouble.
  required final int timeTroubleGames,

  /// The games with good decisions tagged and no mistakes.
  required final int strongGames,

  /// The tags by how many moves have them, most frequent first.
  required final IList<({String tagId, int count})> tagCounts,
});

/// The [GameInsights] of the [games] played from [from] (included) to [to] (excluded); all of them
/// when null. [kindOf] tells the kind of a tag, null when unknown.
GameInsights computeGameInsights(
  Iterable<ReviewedGame> games, {
  required TagKind? Function(String tagId) kindOf,
  DateTime? from,
  DateTime? to,
}) {
  final inPeriod = games.where(
    (game) =>
        (from == null || !game.info.playedAt.isBefore(from)) &&
        (to == null || game.info.playedAt.isBefore(to)),
  );
  var reviewed = 0;
  var withMistakes = 0;
  var timeTrouble = 0;
  var strong = 0;
  final counts = <String, int>{};
  for (final game in inPeriod) {
    reviewed++;
    final kinds = game.tags.map((tag) => kindOf(tag.tagId)).toSet();
    final hasMistake = kinds.contains(TagKind.mistake);
    if (hasMistake) withMistakes++;
    if (game.tags.any((tag) => tag.tagId == kTimeTroubleTagId)) timeTrouble++;
    if (!hasMistake && kinds.contains(TagKind.good)) strong++;
    for (final tag in game.tags) {
      counts[tag.tagId] = (counts[tag.tagId] ?? 0) + 1;
    }
  }
  final tagCounts = counts.entries.map((e) => (tagId: e.key, count: e.value)).toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  return GameInsights(
    gamesReviewed: reviewed,
    gamesWithMistakes: withMistakes,
    timeTroubleGames: timeTrouble,
    strongGames: strong,
    tagCounts: tagCounts.toIList(),
  );
}
