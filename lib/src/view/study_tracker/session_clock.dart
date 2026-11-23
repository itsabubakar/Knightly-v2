import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:lichess_mobile/src/model/study_tracker/study_tracker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// A session's time as a clock: "0:08", "12:34", "1:02:03".
String formatSessionTime(Duration time) {
  final hours = time.inHours;
  final minutes = time.inMinutes.remainder(60);
  final seconds = time.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds' : '$minutes:$seconds';
}

/// The time spent on a screen (the analysis board, a study), counting from when it opens: a small
/// clock under the board. Nothing to start or stop: it stops when the screen closes, and the time
/// is saved as a study session of [category] (a minute or more, see [kMinStudySession]), with its
/// XP. It doesn't count while the app is in the background.
class const SessionClock({required final Discipline category, final StudyRef? study, super.key})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<SessionClock> createState() => _SessionClockState();
}

class _SessionClockState() extends ConsumerState<SessionClock> {
  final _startedAt = clock.now();

  /// The time counted before the app last went to the background.
  Duration _counted = Duration.zero;

  /// Since when it counts; null while the app is in the background.
  DateTime? _since = clock.now();

  Timer? _ticker;
  late final AppLifecycleListener _lifecycle;

  /// Kept from the start: the session is saved once the widget is gone.
  late final StudySessions _sessions;

  Duration get _elapsed =>
      _counted + (_since != null ? clock.now().difference(_since!) : Duration.zero);

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(studySessionsProvider.notifier);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _since != null) setState(() {});
    });
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (_since case final since?) {
          _counted += clock.now().difference(since);
          _since = null;
        }
      },
      onShow: () => _since ??= clock.now(),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    unawaited(
      _sessions.add(
        category: widget.category,
        mode: StudyMode.stopwatch,
        startedAt: _startedAt,
        duration: _elapsed,
        study: widget.study,
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = ColorScheme.of(context).onSurfaceVariant;
    return Semantics(
      label: 'Time on this session',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.timer, size: 16, color: color),
          const SizedBox(width: 4.0),
          Text(
            formatSessionTime(_elapsed),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// [footer] (under the board) with the [clock] at its end, or the clock alone.
class const BoardFooterWithClock({final Widget? footer, required final Widget clock, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: footer ?? const SizedBox.shrink()),
        Padding(padding: const EdgeInsets.only(left: 8.0, right: 4.0), child: clock),
      ],
    );
  }
}
