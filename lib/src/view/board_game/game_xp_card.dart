import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/view/progress/journey_card.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// What a finished game gave, first thing in the end of game popup: the XP and why, the level bar
/// filling up, a level up, the streak.
class const GameXpCard({required final Future<GameXpAward?> award, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GameXpAward?>(
      future: award,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final award = snapshot.data;
        if (award == null) return const SizedBox.shrink();
        final scheme = ColorScheme.of(context);
        final level = award.after.level;
        final levelUp = level.number > award.before.number;
        final reason = award.xp == 0 && gameXp(award.speed) == 0
            ? '${_speedLabel(award.speed)} games give no XP'
            : award.xp == 0
            ? 'Games under 10 moves give no XP'
            : '${_speedLabel(award.speed)} · ${award.moves} moves';
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+${award.xp} XP',
              style: const TextStyle(
                color: Flare.orange,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            Text(reason, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (levelUp) ...[
              const SizedBox(height: 8.0),
              Text(
                'Level up! Lv ${level.number} · ${level.title}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
            const SizedBox(height: 12.0),
            Row(
              children: [
                LevelBadge(roman: level.roman, size: 28),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lv ${level.number} · ${level.title}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4.0),
                      // Fills up from where the level was before the game.
                      TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: levelUp ? 0 : award.before.progress,
                          end: level.progress,
                        ),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, progress, _) => ClipRRect(
                          borderRadius: const BorderRadius.all(Radius.circular(4.0)),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            color: Flare.orange,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (award.after.currentStreak > 0) ...[
              const SizedBox(height: 10.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Symbols.local_fire_department, fill: 1, color: Flare.orange, size: 20),
                  const SizedBox(width: 4.0),
                  Text(
                    '${award.after.currentStreak}-day streak',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

String _speedLabel(Speed speed) => switch (speed) {
  Speed.ultraBullet => 'UltraBullet',
  Speed.bullet => 'Bullet',
  Speed.blitz => 'Blitz',
  Speed.rapid => 'Rapid',
  Speed.classical => 'Classical',
  Speed.correspondence => 'Correspondence',
};
