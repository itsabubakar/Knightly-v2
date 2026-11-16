import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/coordinate_training/coordinate_training_screen.dart';
import 'package:lichess_mobile/src/view/learn/learn_screen.dart';
import 'package:lichess_mobile/src/view/practice/practice_screen.dart';
import 'package:lichess_mobile/src/view/study/study_bookmarks_view.dart';
import 'package:lichess_mobile/src/view/study/study_list_screen.dart';
import 'package:lichess_mobile/src/view/study_tracker/study_tracker_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The learning section of the Train tab: chess basics, practice, coordinates and studies.
class const LearnMenu({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final chevron = Theme.of(context).platform == TargetPlatform.iOS
        ? const CupertinoListTileChevron()
        : null;
    return ListTileTheme.merge(
      iconColor: Theme.of(context).colorScheme.primary,
      // No header: section headers are buttons, too small a tap target without an action.
      child: ListSection(
        hasLeading: true,
        children: [
          ListTile(
            leading: const Icon(Symbols.timer),
            trailing: chevron,
            title: const Text('Study timer', style: Styles.callout),
            onTap: () => Navigator.of(context).push(StudyTrackerScreen.buildRoute()),
          ),
          ListTile(
            leading: const Icon(Symbols.chess_pawn),
            trailing: chevron,
            title: Text(context.l10n.chessBasics, style: Styles.callout),
            onTap: () => Navigator.of(context).push(LearnScreen.buildRoute()),
          ),
          ListTile(
            leading: const Icon(Symbols.exercise),
            trailing: chevron,
            title: Text(context.l10n.practice, style: Styles.callout),
            onTap: () => Navigator.of(context).push(PracticeScreen.buildRoute()),
          ),
          ListTile(
            leading: const Icon(Symbols.where_to_vote),
            trailing: chevron,
            title: Text(context.l10n.coordinatesCoordinateTraining, style: Styles.callout),
            onTap: () =>
                Navigator.of(context).pushHidingTabBar(CoordinateTrainingScreen.buildRoute()),
          ),
          ListTile(
            leading: const Icon(Symbols.local_library),
            trailing: chevron,
            title: Text(context.l10n.studyMenu, style: Styles.callout),
            onTap: () => Navigator.of(context).pushHidingTabBar(StudyListScreen.buildRoute()),
          ),
          ListTile(
            leading: const Icon(Symbols.bookmark),
            trailing: chevron,
            title: const Text('Bookmarked studies', style: Styles.callout),
            onTap: () => Navigator.of(context).push(BookmarkedStudiesScreen.buildRoute()),
          ),
        ],
      ),
    );
  }
}
