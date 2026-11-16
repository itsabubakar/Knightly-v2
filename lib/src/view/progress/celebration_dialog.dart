import 'package:lichess_mobile/src/model/progression/levels.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/view/progress/achievements_section.dart';
import 'package:lichess_mobile/src/view/progress/journey_card.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Shows the [celebrations] one after the other.
Future<void> showCelebrations(BuildContext context, Iterable<Celebration> celebrations) async {
  for (final celebration in celebrations) {
    if (!context.mounted) return;
    await showAdaptiveDialog<void>(
      context: context,
      builder: (context) => CelebrationDialog(celebration),
    );
  }
}

/// A level reached or an achievement earned.
class const CelebrationDialog(final Celebration celebration, {super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final (Widget badge, String title, String text) = switch (celebration) {
      LevelUp(:final level) => (
        LevelBadge(roman: romanNumeral(level), size: 88),
        'Level $level!',
        'You are now ${levelTitle(level)}. +1 streak freeze',
      ),
      AchievementEarned(:final achievement) => (
        Container(
          width: 88,
          height: 88,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFE7201)),
          child: Icon(achievementIcon(achievement.category), color: Colors.white, size: 44),
        ),
        achievement.name,
        [
          achievement.description,
          if (achievement.xp > 0) '+${achievement.xp} XP',
          if (achievement.awardsFreeze) '+1 streak freeze',
        ].join(' · '),
      ),
    };
    return PlatformAlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8.0),
          badge,
          const SizedBox(height: 16.0),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8.0),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        PlatformDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Awesome!'),
        ),
      ],
    );
  }
}
