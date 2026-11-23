import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:lichess_mobile/src/model/study_tracker/study_tracker.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/study/study_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The countdown lengths offered.
const kCountdownChoices = [10, 20, 30, 45, 60];

/// The label of a study category.
String disciplineLabel(Discipline discipline) => switch (discipline) {
  .tactics => 'Tactics',
  .strategy => 'Strategy',
  .openings => 'Openings',
  .endgames => 'Endgames',
  .analysis => 'Analysis',
};

/// [duration] as a clock: `1:05:09` or `05:09`.
String formatClock(Duration duration) {
  final h = duration.inHours;
  final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// [duration] in short words: `1h 05m` or `25m`.
String formatStudyTime(Duration duration) => duration.inHours > 0
    ? '${duration.inHours}h ${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}m'
    : '${duration.inMinutes}m';

/// Starts, follows and stops study sessions; logs past ones; lists them.
class const StudyTrackerScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const StudyTrackerScreen());
  }

  @override
  ConsumerState<StudyTrackerScreen> createState() => _StudyTrackerScreenState();
}

class _StudyTrackerScreenState() extends ConsumerState<StudyTrackerScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Redraws the running timer every second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(studyTimerProvider) != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(studyTimerProvider);
    final sessions = ref.watch(studySessionsProvider);
    final scheme = ColorScheme.of(context);
    final now = DateTime.now();
    return PlatformScaffold(
      appBar: const PlatformAppBar(title: Text('Study timer')),
      body: ListView(
        padding: Styles.bodyPadding,
        children: [
          if (timer != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      '${disciplineLabel(timer.category)} · '
                      '${timer.mode == StudyMode.countdown ? 'Countdown' : 'Stopwatch'}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                    ),
                    if (timer.study case final study?)
                      TextButton.icon(
                        icon: const Icon(Symbols.menu_book, size: 18),
                        label: Text(study.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onPressed: () => Navigator.of(context).pushHidingTabBar(
                          StudyScreen.buildRoute((id: study.id, initialChapter: null)),
                        ),
                      ),
                    const SizedBox(height: 8.0),
                    Text(
                      formatClock(timer.remaining(now) ?? timer.elapsed(now)),
                      style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900),
                    ),
                    if (timer.isPaused) const Text('Paused', style: TextStyle(color: Flare.orange)),
                    const SizedBox(height: 16.0),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(timer.isPaused ? Symbols.play_arrow : Symbols.pause),
                            label: Text(timer.isPaused ? 'Resume' : 'Pause'),
                            onPressed: () => timer.isPaused
                                ? ref.read(studyTimerProvider.notifier).resume()
                                : ref.read(studyTimerProvider.notifier).pause(),
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Symbols.stop),
                            label: const Text('Stop & save'),
                            onPressed: () => ref.read(studyTimerProvider.notifier).stop(),
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => ref.read(studyTimerProvider.notifier).discard(),
                      child: const Text('Discard this session'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Your time on the analysis board and in studies counts on its own: the clock '
                  'under the board runs while the screen is open, and the session is saved when '
                  'you leave it (+1 XP a minute).',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          const SizedBox(height: 16.0),
          OutlinedButton.icon(
            icon: const Icon(Symbols.edit_calendar),
            label: const Text('Log a past session'),
            onPressed: () => _logSession(context),
          ),
          const SizedBox(height: 16.0),
          switch (sessions) {
            AsyncData(value: final list) when list.isNotEmpty => ListSection(
              header: const Text('Sessions'),
              children: [
                for (final session in list.take(50))
                  ListTile(
                    title: Text(
                      '${disciplineLabel(session.category)} · ${formatStudyTime(session.duration)}',
                    ),
                    subtitle: Text(
                      [
                        ?session.study?.name,
                        '${DateFormat.yMMMd().add_Hm().format(session.startedAt)} · ${switch (session.mode) {
                          StudyMode.stopwatch => 'Stopwatch',
                          StudyMode.countdown => 'Countdown',
                          StudyMode.manual => 'Logged',
                        }}',
                      ].join('\n'),
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete session',
                      icon: const Icon(Symbols.delete),
                      onPressed: () => ref.read(studySessionsProvider.notifier).delete(session.id),
                    ),
                  ),
              ],
            ),
            AsyncData() => const SizedBox.shrink(),
            AsyncError() => const Text('Could not load the sessions.'),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ],
      ),
    );
  }

  Future<void> _logSession(BuildContext context) async {
    var category = Discipline.tactics;
    var minutes = 30;
    var date = DateTime.now();
    final saved = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => PlatformAlertDialog(
          title: const Text('Log a past session'),
          content: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6.0,
                  runSpacing: 6.0,
                  children: [
                    for (final discipline in Discipline.values)
                      ChoiceChip(
                        label: Text(disciplineLabel(discipline)),
                        selected: category == discipline,
                        onSelected: (_) => setDialogState(() => category = discipline),
                      ),
                  ],
                ),
                const SizedBox(height: 12.0),
                Text('$minutes minutes', style: const TextStyle(fontWeight: FontWeight.w700)),
                Slider(
                  value: minutes.toDouble(),
                  min: 5,
                  max: 180,
                  divisions: 35,
                  onChanged: (value) => setDialogState(() => minutes = value.round()),
                ),
                TextButton.icon(
                  icon: const Icon(Symbols.calendar_today),
                  label: Text(DateFormat.yMMMd().format(date)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2010),
                      lastDate: DateTime.now(),
                      initialDate: date,
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            PlatformDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            PlatformDialogAction(
              cupertinoIsDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await ref
        .read(studySessionsProvider.notifier)
        .add(
          category: category,
          mode: StudyMode.manual,
          startedAt: date,
          duration: Duration(minutes: minutes),
        );
  }
}
