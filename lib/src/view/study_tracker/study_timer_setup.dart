import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:lichess_mobile/src/model/study_tracker/study_tracker.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/view/study_tracker/study_tracker_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The choices of a new study timer: category, countdown (and its length) or stopwatch.
class const StudyTimerSetup({
  required final void Function(StudyMode mode, Discipline category, Duration? planned) onStart,
  final Discipline initialCategory = Discipline.tactics,
  super.key,
}) extends StatefulWidget {
  @override
  State<StudyTimerSetup> createState() => _StudyTimerSetupState();
}

class _StudyTimerSetupState() extends State<StudyTimerSetup> {
  late Discipline _category = widget.initialCategory;
  StudyMode _mode = StudyMode.countdown;
  int _countdownMinutes = 20;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('What are you studying?', style: Styles.sectionTitle),
        const SizedBox(height: 8.0),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: [
            for (final discipline in Discipline.values)
              ChoiceChip(
                label: Text(disciplineLabel(discipline)),
                selected: _category == discipline,
                onSelected: (_) => setState(() => _category = discipline),
              ),
          ],
        ),
        const SizedBox(height: 16.0),
        const Text('Timer', style: Styles.sectionTitle),
        const SizedBox(height: 8.0),
        Wrap(
          spacing: 8.0,
          children: [
            ChoiceChip(
              avatar: const Icon(Symbols.hourglass_top, size: 18),
              label: const Text('Countdown'),
              selected: _mode == StudyMode.countdown,
              onSelected: (_) => setState(() => _mode = StudyMode.countdown),
            ),
            ChoiceChip(
              avatar: const Icon(Symbols.timer, size: 18),
              label: const Text('Stopwatch'),
              selected: _mode == StudyMode.stopwatch,
              onSelected: (_) => setState(() => _mode = StudyMode.stopwatch),
            ),
          ],
        ),
        if (_mode == StudyMode.countdown) ...[
          const SizedBox(height: 8.0),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              for (final minutes in kCountdownChoices)
                ChoiceChip(
                  label: Text('$minutes min'),
                  selected: _countdownMinutes == minutes,
                  onSelected: (_) => setState(() => _countdownMinutes = minutes),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16.0),
        FilledButton.icon(
          icon: const Icon(Symbols.play_arrow),
          label: const Text('Start studying'),
          onPressed: () => widget.onStart(
            _mode,
            _category,
            _mode == StudyMode.countdown ? Duration(minutes: _countdownMinutes) : null,
          ),
        ),
        const SizedBox(height: 8.0),
        Text(
          'The timer keeps running on every screen of the app. +1 XP per minute.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }
}

/// Shows the sheet that starts a study timer for [study]; [onStarted] runs once it's started
/// (e.g. to open the study).
Future<void> showStartStudyTimerSheet(
  BuildContext context, {
  required StudyRef study,
  VoidCallback? onStarted,
}) {
  return showAdaptiveBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => StartStudyTimerSheet(study: study, onStarted: onStarted),
  );
}

/// Starts a study timer for a lichess study; tells when one is already running.
class const StartStudyTimerSheet({
  required final StudyRef study,
  final VoidCallback? onStarted,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(studyTimerProvider);
    final scheme = ColorScheme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: Styles.bodyPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Study timer', style: Styles.title),
            const SizedBox(height: 4.0),
            Text(
              study.name,
              style: TextStyle(color: scheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16.0),
            if (running != null) ...[
              Text(
                'A study timer is already running: '
                '${running.study?.name ?? disciplineLabel(running.category)}. Stop it first.',
              ),
              const SizedBox(height: 12.0),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onStarted?.call();
                },
                child: Text(onStarted != null ? 'Open the study anyway' : 'Close'),
              ),
            ] else
              StudyTimerSetup(
                initialCategory: Discipline.openings,
                onStart: (mode, category, planned) async {
                  await ref
                      .read(studyTimerProvider.notifier)
                      .start(mode, category, planned: planned, study: study);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  onStarted?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}
