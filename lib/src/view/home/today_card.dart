import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/view/progress/journey_card.dart';
import 'package:lichess_mobile/src/view/progress/streak_strip.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The hero card at the top of the Home dashboard: today's games and the Rapid rating.
///
/// The streak and XP will join it once they exist.
class const TodayCard({
  required final AsyncValue<IList<LightExportedGameWithPov>> recentGames,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hidden with the "Show ratings: No" preference, and until the preference is known, so that the
    // rating never flashes.
    final showRatingsPref = ref.watch(showRatingsPrefProvider).value;
    final showRatings = showRatingsPref != null && showRatingsPref != ShowRatings.no;
    final rapid = showRatings ? ref.watch(accountProvider).value?.perfs[Perf.rapid] : null;
    final progression = ref.watch(progressionProvider).value;
    final now = DateTime.now();
    // The recent games are the latest few only: enough for a day of play.
    final todayGames = (recentGames.value ?? const IListConst<LightExportedGameWithPov>([])).where((
      g,
    ) {
      final playedAt = g.game.lastMoveAt.toLocal();
      final isFinished = g.game.status != .created && g.game.status != .started;
      return isFinished &&
          playedAt.year == now.year &&
          playedAt.month == now.month &&
          playedAt.day == now.day;
    }).toList();

    const white = Colors.white;
    final whiteSoft = Colors.white.withValues(alpha: 0.82);

    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(20.0)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Flare.orange, Color(0xFFFF9A3C)],
        ),
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TODAY',
            style: TextStyle(
              color: whiteSoft,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8.0),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${todayGames.length}',
                style: const TextStyle(
                  color: white,
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 8.0),
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Text(
                  todayGames.length == 1 ? 'game played' : 'games played',
                  style: TextStyle(color: whiteSoft, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              if (rapid != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rapid',
                      style: TextStyle(color: whiteSoft, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${rapid.rating}${rapid.provisional == true ? '?' : ''}',
                          style: const TextStyle(
                            color: white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (rapid.progression != 0) ...[
                          const SizedBox(width: 4.0),
                          Icon(
                            rapid.progression > 0 ? Symbols.trending_up : Symbols.trending_down,
                            color: white,
                            size: 18,
                          ),
                          Text(
                            '${rapid.progression.abs()}',
                            style: const TextStyle(color: white, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16.0),
          if (progression != null) ...[
            Row(
              children: [
                const Icon(Symbols.local_fire_department, fill: 1, color: white, size: 22),
                const SizedBox(width: 6.0),
                Text(
                  progression.currentStreak == 1
                      ? '1-day streak'
                      : '${progression.currentStreak}-day streak',
                  style: const TextStyle(color: white, fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const Spacer(),
                if (progression.streakFreezes > 0) ...[
                  const Icon(Symbols.ac_unit, color: white, size: 18),
                  const SizedBox(width: 4.0),
                  Text(
                    '${progression.streakFreezes}',
                    style: const TextStyle(color: white, fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10.0),
            StreakStrip(days: progression.lastWeek, onAccent: true),
            const SizedBox(height: 16.0),
            Row(
              children: [
                LevelBadge(roman: progression.level.roman, size: 30),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    'Lv ${progression.level.number} · ${progression.level.title}',
                    style: const TextStyle(color: white, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '+${progression.xpToday} XP today',
                  style: const TextStyle(color: white, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(4.0)),
              child: LinearProgressIndicator(
                value: progression.level.progress,
                minHeight: 6,
                color: white,
                backgroundColor: white.withValues(alpha: 0.3),
              ),
            ),
            if (todayGames.isEmpty) const SizedBox(height: 16.0),
          ],
          if (todayGames.isEmpty)
            Text(
              'No games yet today. Play one from the quick pairing below.',
              style: TextStyle(color: whiteSoft, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}
