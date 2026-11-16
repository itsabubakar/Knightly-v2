import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/study_tracker/study_tracker.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/view/study_tracker/study_tracker_screen.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The running study timer, floating above every screen of the app.
///
/// Small (the clock) until tapped, then shows the study, pause and stop; dragged up or down out of
/// the way. Its name opens the study timer screen. Ends a countdown when it's over, and celebrates
/// it.
class const StudyTimerPill({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<StudyTimerPill> createState() => _StudyTimerPillState();
}

class _StudyTimerPillState() extends ConsumerState<StudyTimerPill> {
  Timer? _ticker;
  bool _finishing = false;

  /// Small, only the clock, unless the user opens it.
  bool _expanded = false;

  /// Where the user dragged it: its distance from the bottom of the screen.
  double? _bottom;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (!mounted) return;
    final timer = ref.read(studyTimerProvider);
    if (timer == null) return;
    if (!_finishing && !timer.isPaused && timer.isOver(DateTime.now())) {
      _finishing = true;
      final studied = await ref.read(studyTimerProvider.notifier).stop();
      _finishing = false;
      final navigatorContext = ref.read(currentNavigatorKeyProvider).currentContext;
      if (studied != null && navigatorContext != null && navigatorContext.mounted) {
        await showAdaptiveDialog<void>(
          context: navigatorContext,
          builder: (context) => PlatformAlertDialog(
            title: const Text('Session complete'),
            content: Text(
              '${formatStudyTime(studied)} of ${disciplineLabel(timer.category).toLowerCase()} '
              'studied. +${studyXp(studied)} XP',
            ),
            actions: [
              PlatformDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Great!'),
              ),
            ],
          ),
        );
      }
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(studyTimerProvider);
    if (timer == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final padding = MediaQuery.paddingOf(context);
    final height = MediaQuery.sizeOf(context).height;
    // Above the tab bar and the board screens' bottom bar, until the user drags it elsewhere.
    final double bottom = (_bottom ?? padding.bottom + 96).clamp(
      padding.bottom + 8,
      math.max(padding.bottom + 8, height - padding.top - 64),
    );
    const white = TextStyle(color: Colors.white, fontWeight: FontWeight.w800);
    final clock = Text(
      formatClock(timer.remaining(now) ?? timer.elapsed(now)),
      style: white.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
    return Positioned(
      right: 12,
      bottom: bottom,
      child: GestureDetector(
        // Dragged up or down, out of the way of what's below it.
        onVerticalDragUpdate: (details) => setState(() => _bottom = bottom - details.delta.dy),
        child: Material(
          color: Flare.orange.withValues(alpha: timer.isPaused ? 0.75 : 0.92),
          elevation: 6,
          shape: const StadiumBorder(),
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(6.0, 2.0, 2.0, 2.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => ref
                            .read(currentNavigatorKeyProvider)
                            .currentState
                            ?.push(StudyTrackerScreen.buildRoute()),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                // A long study name is shortened, never the clock.
                                constraints: BoxConstraints(
                                  maxWidth: math.min(150.0, MediaQuery.sizeOf(context).width / 3),
                                ),
                                child: Text(
                                  timer.study?.name ?? disciplineLabel(timer.category),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: white,
                                ),
                              ),
                              const Text(' · ', style: white),
                              clock,
                            ],
                          ),
                        ),
                      ),
                      // No tooltips: the pill is above the navigator, which has the overlay they
                      // need.
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          timer.isPaused ? Symbols.play_arrow : Symbols.pause,
                          color: Colors.white,
                          semanticLabel: timer.isPaused ? 'Resume' : 'Pause',
                        ),
                        onPressed: () => timer.isPaused
                            ? ref.read(studyTimerProvider.notifier).resume()
                            : ref.read(studyTimerProvider.notifier).pause(),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Symbols.stop,
                          color: Colors.white,
                          semanticLabel: 'Stop & save',
                        ),
                        onPressed: () => ref.read(studyTimerProvider.notifier).stop(),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Symbols.chevron_right,
                          color: Colors.white,
                          semanticLabel: 'Make the timer smaller',
                        ),
                        onPressed: () => setState(() => _expanded = false),
                      ),
                    ],
                  ),
                )
              : InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => setState(() => _expanded = true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          timer.isPaused ? Symbols.pause : Symbols.timer,
                          color: Colors.white,
                          size: 16,
                          semanticLabel: 'Study timer',
                        ),
                        const SizedBox(width: 4.0),
                        clock,
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
