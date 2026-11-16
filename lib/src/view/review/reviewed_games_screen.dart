import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/review/game_review.dart';
import 'package:lichess_mobile/src/model/review/game_tags.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_screen.dart';
import 'package:lichess_mobile/src/view/review/tag_list_screen.dart';
import 'package:lichess_mobile/src/view/review/tag_move_sheet.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The games the user tagged or reviewed, filterable by tag; opens a game at its tagged move.
class const ReviewedGamesScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const ReviewedGamesScreen());
  }

  @override
  ConsumerState<ReviewedGamesScreen> createState() => _ReviewedGamesScreenState();
}

/// The periods the reviewed games can be filtered by.
enum ReviewPeriod(final String label, final int? days) {
  all('All time', null),
  week('7 days', 7),
  twoWeeks('14 days', 14),
  month('30 days', 30),
  custom('Custom', null),
}

class _ReviewedGamesScreenState() extends ConsumerState<ReviewedGamesScreen> {
  /// The tag the games are filtered by, if any.
  String? _filter;

  /// The period the games are filtered by.
  ReviewPeriod _period = ReviewPeriod.all;

  /// The dates of the [ReviewPeriod.custom] period.
  DateTimeRange? _customRange;

  /// Whether a game played at [playedAt] is in the period.
  bool _isInPeriod(DateTime playedAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      ReviewPeriod.all => true,
      ReviewPeriod.custom =>
        _customRange == null ||
            (!playedAt.isBefore(_customRange!.start) &&
                playedAt.isBefore(_customRange!.end.add(const Duration(days: 1)))),
      // Today and the days before it: "7 days" is today and the 6 previous days.
      _ => !playedAt.isBefore(today.subtract(Duration(days: _period.days! - 1))),
    };
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2010),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (range != null && mounted) {
      setState(() {
        _period = ReviewPeriod.custom;
        _customRange = range;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tagListProvider);
    final tagList = ref.read(tagListProvider.notifier);
    final Widget body;
    switch (ref.watch(reviewedGamesProvider)) {
      case AsyncData(value: final games) when games.isEmpty:
        body = const Center(
          child: Padding(
            padding: Styles.bodyPadding,
            child: Text(
              'No reviewed games yet. Open one of your finished games, tap the tag button on a '
              'move, and note the lessons learned from the analysis menu.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      case AsyncData(value: final games):
        final usedTags = {for (final game in games) ...game.tags.map((t) => t.tagId)};
        final shown = games
            .where((game) => _isInPeriod(game.info.playedAt))
            .where((game) => _filter == null || game.tags.any((tag) => tag.tagId == _filter))
            .toList();
        body = ListView(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: Styles.horizontalBodyPadding.add(const EdgeInsets.only(top: 12.0)),
              child: Row(
                spacing: 8.0,
                children: [
                  for (final period in ReviewPeriod.values)
                    ChoiceChip(
                      avatar: period == ReviewPeriod.custom
                          ? const Icon(Symbols.date_range, size: 18)
                          : null,
                      label: Text(
                        period == ReviewPeriod.custom && _customRange != null
                            ? '${DateFormat.MMMd().format(_customRange!.start)} – '
                                  '${DateFormat.MMMd().format(_customRange!.end)}'
                            : period.label,
                      ),
                      selected: _period == period,
                      onSelected: (_) => period == ReviewPeriod.custom
                          ? _pickCustomRange()
                          : setState(() => _period = period),
                    ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: Styles.horizontalBodyPadding.add(const EdgeInsets.only(top: 12.0)),
              child: Row(
                spacing: 8.0,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final tagId in usedTags)
                    ChoiceChip(
                      label: Text(tagList.byId(tagId)?.label ?? tagId),
                      selected: _filter == tagId,
                      onSelected: (_) => setState(() => _filter = tagId),
                    ),
                ],
              ),
            ),
            if (shown.isEmpty)
              const Padding(
                padding: Styles.bodySectionPadding,
                child: Text('No reviewed games in this period with this tag.'),
              )
            else
              ListSection(
                children: [for (final game in shown) ReviewedGameTile(game: game, filter: _filter)],
              ),
          ],
        );
      case AsyncError():
        body = const Center(child: Text('Could not load the reviewed games.'));
      case _:
        body = const Center(child: CircularProgressIndicator());
    }
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Reviewed games'),
        actions: [
          IconButton(
            tooltip: 'Edit tags',
            icon: const Icon(Symbols.sell),
            onPressed: () => Navigator.of(context).push(TagListScreen.buildRoute()),
          ),
        ],
      ),
      body: body,
    );
  }
}

/// A reviewed game: its opponent, date, tagged moves and note; opens it at its first tagged move.
class const ReviewedGameTile({
  required final ReviewedGame game,

  /// Only the moves with this tag are shown and opened, if any.
  final String? filter,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(tagListProvider);
    final tagList = ref.read(tagListProvider.notifier);
    final shownTags = filter == null
        ? game.tags.toList()
        : game.tags.where((tag) => tag.tagId == filter).toList();
    return ListTile(
      title: Text('vs ${game.info.opponent}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat.yMMMd().format(game.info.playedAt)),
          for (final tag in shownTags)
            Text(
              '${moveLabel(tag.ply, tag.san)} · ${tagList.byId(tag.tagId)?.label ?? tag.tagId}',
              style: TextStyle(
                color: tagList.byId(tag.tagId)?.kind == TagKind.good ? Flare.green : Flare.red,
              ),
            ),
          if (game.note.isNotEmpty)
            Text(
              '“${game.note}”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
        ],
      ),
      onTap: () => Navigator.of(context).pushHidingTabBar(
        AnalysisScreen.buildRoute(
          AnalysisOptions.archivedGame(
            orientation: game.info.orientation,
            gameId: game.info.gameId,
            initialMoveCursor: shownTags.isEmpty ? 0 : shownTags.first.ply,
          ),
        ),
      ),
    );
  }
}
