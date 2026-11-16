import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/progression/achievements.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The icon of an achievement [category].
IconData achievementIcon(AchievementCategory category) => switch (category) {
  .games => Symbols.swords,
  .puzzles => Symbols.extension,
  .levels => Symbols.military_tech,
  .streak => Symbols.local_fire_department,
  .review => Symbols.sell,
  .study => Symbols.menu_book,
};

/// The achievements as a grid of badges: earned ones in color, the others with their progress.
///
/// Shows nothing when signed out.
class const AchievementsSection({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progression = ref.watch(progressionProvider).value;
    if (progression == null) return const SizedBox.shrink();
    final earned = progression.achievements.where((a) => a.earnedAt != null).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Achievements', style: Styles.sectionTitle)),
                Text(
                  '$earned / ${progression.achievements.length}',
                  style: TextStyle(
                    color: ColorScheme.of(context).primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8.0,
              crossAxisSpacing: 8.0,
              childAspectRatio: 0.82,
              children: [
                for (final progress in progression.achievements) AchievementBadge(progress),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// An achievement's badge; shows its details on tap.
class const AchievementBadge(final AchievementProgress progress, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final achievement = progress.achievement;
    final isEarned = progress.earnedAt != null;
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(12.0)),
      onTap: () => _showDetails(context),
      child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(Radius.circular(12.0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isEarned ? Flare.orange : scheme.surfaceContainerHighest,
              ),
              child: Icon(
                achievementIcon(achievement.category),
                color: isEarned ? Colors.white : scheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6.0),
            Text(
              achievement.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isEarned ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            Text(
              isEarned
                  ? '✓'
                  : !achievement.metric.isMeasured
                  ? 'Coming soon'
                  : '${progress.current.clamp(0, achievement.target)}/${achievement.target}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final achievement = progress.achievement;
    final earnedAt = progress.earnedAt;
    showAdaptiveDialog<void>(
      context: context,
      builder: (context) => PlatformAlertDialog(
        title: Text(achievement.name),
        content: Text(
          [
            achievement.description,
            [
              if (achievement.xp > 0) '+${achievement.xp} XP',
              if (achievement.awardsFreeze) '+1 streak freeze',
            ].join(' · '),
            if (earnedAt != null)
              'Earned on ${DateFormat.yMMMd().format(earnedAt)}'
            else if (!achievement.metric.isMeasured)
              'Coming soon'
            else
              'Progress: ${progress.current.clamp(0, achievement.target)}/${achievement.target}',
          ].where((line) => line.isNotEmpty).join('\n\n'),
        ),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
