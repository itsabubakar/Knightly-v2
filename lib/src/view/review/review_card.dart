import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/review/game_insights.dart';
import 'package:lichess_mobile/src/model/review/game_review.dart';
import 'package:lichess_mobile/src/model/review/game_tags.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/view/review/reviewed_games_screen.dart';
import 'package:lichess_mobile/src/view/review/tag_list_screen.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The periods of the game insights.
enum InsightsPeriod(final String label, final int? days) {
  week('7 days', 7),
  month('30 days', 30),
  quarter('90 days', 90),
  custom('Custom', null),
}

/// Game insights: what the reviewed games of a period say, the most frequent tags, and links to the
/// reviewed games and the tags.
///
/// Shows nothing when signed out.
class const ReviewCard({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState() extends ConsumerState<ReviewCard> {
  InsightsPeriod _period = InsightsPeriod.month;
  DateTimeRange? _customRange;

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
    );
    if (range != null && mounted) {
      setState(() {
        _period = InsightsPeriod.custom;
        _customRange = range;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authControllerProvider) == null) return const SizedBox.shrink();
    ref.watch(tagListProvider);
    final tagList = ref.read(tagListProvider.notifier);
    final games = ref.watch(reviewedGamesProvider).value ?? const IListConst<ReviewedGame>([]);
    final scheme = ColorScheme.of(context);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final (DateTime? from, DateTime? to) = switch (_period) {
      InsightsPeriod.custom when _customRange != null => (
        _customRange!.start,
        _customRange!.end.add(const Duration(days: 1)),
      ),
      InsightsPeriod.custom => (null, null),
      _ => (today.subtract(Duration(days: _period.days! - 1)), null),
    };
    final insights = computeGameInsights(
      games,
      kindOf: (id) => tagList.byId(id)?.kind,
      from: from,
      to: to,
    );
    final topTags = insights.tagCounts.take(5).toList();
    final maxCount = topTags.isEmpty ? 1 : topTags.first.count;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Game insights', style: Styles.sectionTitle),
            const SizedBox(height: 12.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                for (final period in InsightsPeriod.values)
                  ChoiceChip(
                    label: Text(
                      period == InsightsPeriod.custom && _customRange != null
                          ? '${DateFormat.MMMd().format(_customRange!.start)} – '
                                '${DateFormat.MMMd().format(_customRange!.end)}'
                          : period.label,
                    ),
                    selected: _period == period,
                    onSelected: (_) => period == InsightsPeriod.custom
                        ? _pickCustomRange()
                        : setState(() => _period = period),
                  ),
              ],
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                _InsightTile(value: insights.gamesReviewed, label: 'Games reviewed'),
                const SizedBox(width: 8.0),
                _InsightTile(
                  value: insights.gamesWithMistakes,
                  label: 'Games with mistakes',
                  color: Flare.red,
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            Row(
              children: [
                _InsightTile(value: insights.timeTroubleGames, label: 'Time trouble games'),
                const SizedBox(width: 8.0),
                _InsightTile(
                  value: insights.strongGames,
                  label: 'Strong games',
                  color: Flare.green,
                ),
              ],
            ),
            const SizedBox(height: 20.0),
            Text('Most frequent tags', style: Styles.sectionTitle.copyWith(fontSize: 16)),
            const SizedBox(height: 8.0),
            if (topTags.isEmpty)
              Text(
                'No tagged moves in this period yet. Open one of your finished games, tap the tag '
                'button on a move, and note the lessons learned from the analysis menu.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              for (final (:tagId, :count) in topTags)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(tagList.byId(tagId)?.label ?? tagId)),
                          Text('$count', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 4.0),
                      ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(4.0)),
                        child: LinearProgressIndicator(
                          value: count / maxCount,
                          minHeight: 8,
                          color: tagList.byId(tagId)?.kind == TagKind.good
                              ? Flare.green
                              : Flare.orange,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 8.0),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Symbols.rate_review),
                    label: const Text('Reviewed games'),
                    onPressed: () => Navigator.of(context).push(ReviewedGamesScreen.buildRoute()),
                  ),
                ),
                const SizedBox(width: 8.0),
                OutlinedButton.icon(
                  icon: const Icon(Symbols.sell),
                  label: const Text('Tags'),
                  onPressed: () => Navigator.of(context).push(TagListScreen.buildRoute()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class const _InsightTile({
  required final int value,
  required final String label,
  final Color? color,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(Radius.circular(12.0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: color ?? scheme.onSurface,
              ),
            ),
            Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
