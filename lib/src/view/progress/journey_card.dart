import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/progression/achievements.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/view/progress/streak_strip.dart';
import 'package:lichess_mobile/src/view/study_tracker/study_tracker_screen.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

final _number = NumberFormat.decimalPattern();

/// "Your chess journey": the level, its title, the XP and what earned it.
///
/// Shows nothing when signed out.
class const JourneyCard({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    switch (ref.watch(progressionProvider)) {
      case AsyncData(value: null):
        return const SizedBox.shrink();
      case AsyncData(value: final progression?):
        final level = progression.level;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your chess journey', style: Styles.sectionTitle),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    LevelBadge(roman: level.roman, size: 72),
                    const SizedBox(width: 16.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Level ${level.number}',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            level.title,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4.0),
                          Text(
                            '${_number.format(level.totalXp)} XP',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${_number.format(level.xpToNextLevel)} XP until next level',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(6.0)),
                  child: LinearProgressIndicator(
                    value: level.progress,
                    minHeight: 10,
                    color: Flare.orange,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    _StatTile(value: '+${_number.format(progression.xpToday)}', label: 'XP today'),
                    const SizedBox(width: 8.0),
                    _StatTile(
                      value: _number.format(progression.gamesPlayed),
                      label: 'Games played',
                    ),
                    const SizedBox(width: 8.0),
                    _StatTile(
                      value: _number.format(progression.puzzlesSolved),
                      label: 'Puzzles solved',
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    _StatTile(value: formatStudyTime(progression.studyTime), label: 'Study time'),
                    const SizedBox(width: 8.0),
                    _StatTile(
                      value: _number.format(progression.studySessions),
                      label: 'Study sessions',
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    const Icon(
                      Symbols.local_fire_department,
                      fill: 1,
                      color: Flare.orange,
                      size: 22,
                    ),
                    const SizedBox(width: 6.0),
                    Text(
                      '${progression.currentStreak}-day streak',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    Text(
                      'Longest: ${progression.longestStreak}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10.0),
                StreakStrip(days: progression.lastWeek),
                const SizedBox(height: 12.0),
                Row(
                  children: [
                    const Icon(Symbols.ac_unit, size: 18, color: Color(0xFF6EC6FF)),
                    const SizedBox(width: 6.0),
                    Text(
                      '${progression.streakFreezes} / $kMaxStreakFreezes streak freezes',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),
                Text(
                  'Counting since ${DateFormat.yMMMd().format(progression.startedAt)}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      case AsyncError():
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Could not load your progression.'),
          ),
        );
      case _:
        return const Card(
          child: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
        );
    }
  }
}

/// The level in Roman numerals, in an orange disc.
class const LevelBadge({required final String roman, required final double size, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9A3C), Flare.orange],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.14),
        child: FittedBox(
          child: Text(
            roman,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 28,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

class const _StatTile({required final String value, required final String label})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(Radius.circular(12.0)),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2.0),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
