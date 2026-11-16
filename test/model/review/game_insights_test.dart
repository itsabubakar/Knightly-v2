import 'package:dartchess/dartchess.dart' show Side;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/review/game_insights.dart';
import 'package:lichess_mobile/src/model/review/game_review.dart';
import 'package:lichess_mobile/src/model/review/game_tags.dart';

ReviewedGame _game(String id, DateTime playedAt, List<String> tags) => (
  info: (gameId: GameId(id), opponent: 'Bob', playedAt: playedAt, orientation: Side.white),
  tags: [for (final (i, tag) in tags.indexed) (ply: i + 1, san: 'e4', tagId: tag)].toIList(),
  note: '',
);

TagKind? _kindOf(String id) => kStarterTags.where((tag) => tag.id == id).firstOrNull?.kind;

void main() {
  final games = [
    _game('game0001', DateTime(2026, 11, 15), ['hanging_piece', 'time_trouble']),
    _game('game0002', DateTime(2026, 11, 14), ['good_move', 'good_plan']),
    _game('game0003', DateTime(2026, 11, 13), ['hanging_piece', 'missed_tactic', 'hanging_piece']),
    _game('game0004', DateTime(2026, 10, 1), ['hanging_piece']),
  ];

  test('counts the games with mistakes, time trouble and strong games', () {
    final insights = computeGameInsights(games, kindOf: _kindOf);

    expect(insights.gamesReviewed, 4);
    expect(insights.gamesWithMistakes, 3);
    expect(insights.timeTroubleGames, 1);
    expect(insights.strongGames, 1);
  });

  test('ranks the tags by frequency', () {
    final insights = computeGameInsights(games, kindOf: _kindOf);

    expect(insights.tagCounts.first, (tagId: 'hanging_piece', count: 4));
    expect(insights.tagCounts.length, 5);
  });

  test('keeps only the games of the period', () {
    final insights = computeGameInsights(
      games,
      kindOf: _kindOf,
      from: DateTime(2026, 11, 14),
      to: DateTime(2026, 11, 16),
    );

    expect(insights.gamesReviewed, 2);
    expect(insights.tagCounts.first.count, 1);
  });
}
