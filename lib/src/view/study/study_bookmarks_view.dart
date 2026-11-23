import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/study/study_bookmarks.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/study/study_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

/// The latest bookmarked studies, with a link to all of them. Shows nothing without bookmarks.
class const BookmarkedStudiesSection({final int maxItems = 3, super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(studyBookmarksProvider);
    if (bookmarks.isEmpty) return const SizedBox.shrink();
    return ListSection(
      header: const Text('Bookmarked studies'),
      onHeaderTap: () => Navigator.of(context).push(BookmarkedStudiesScreen.buildRoute()),
      hasLeading: true,
      children: [
        for (final bookmark in bookmarks.take(maxItems)) BookmarkedStudyTile(bookmark: bookmark),
      ],
    );
  }
}

/// A bookmarked study; opens it on tap. Its timer button starts a study timer (countdown or
/// stopwatch) for it, then opens it.
class const BookmarkedStudyTile({
  required final StudyBookmark bookmark,
  final Widget? trailing,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    void openStudy() =>
        Navigator.of(context)
            .pushHidingTabBar(StudyScreen.buildRoute((id: bookmark.id, initialChapter: null)));
    return ListTile(
      leading: Icon(LichessIcons.study, color: ColorScheme.of(context).primary),
      title: Text(bookmark.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (bookmark.ownerName != null) bookmark.ownerName!,
          context.l10n.studyNbChapters(bookmark.nbChapters),
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          trailing ??
              (Theme.of(context).platform == TargetPlatform.iOS
                  ? const CupertinoListTileChevron()
                  : const SizedBox.shrink()),
        ],
      ),
      onTap: openStudy,
    );
  }
}

/// All the bookmarked studies, most recent first, each with a button to remove its bookmark.
class const BookmarkedStudiesScreen({super.key}) extends ConsumerWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const BookmarkedStudiesScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(studyBookmarksProvider);
    return PlatformScaffold(
      appBar: const PlatformAppBar(title: Text('Bookmarked studies')),
      body: bookmarks.isEmpty
          ? const Center(
              child: Padding(
                padding: Styles.bodyPadding,
                child: Text(
                  'No bookmarked studies yet. Open a study and choose "Bookmark" in its menu.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                ListSection(
                  hasLeading: true,
                  children: [
                    for (final bookmark in bookmarks)
                      BookmarkedStudyTile(
                        bookmark: bookmark,
                        trailing: IconButton(
                          tooltip: 'Remove bookmark',
                          icon: const Icon(Icons.bookmark_remove_outlined),
                          onPressed: () =>
                              ref.read(studyBookmarksProvider.notifier).remove(bookmark.id),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
