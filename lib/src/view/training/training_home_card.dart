import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/training/mistake_puzzles.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/view/training/training_screen.dart';
import 'package:lichess_mobile/src/view/training/training_session_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Home's training card: the puzzles from the user's mistakes to review today, their training, and
/// the way in to the mistakes screen. (The openings trainer is set aside for now.)
///
/// It also starts the quiet look through the user's recent games for mistakes, once per session.
class const TrainingHomeCard({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<TrainingHomeCard> createState() => _TrainingHomeCardState();
}

class _TrainingHomeCardState() extends ConsumerState<TrainingHomeCard> {
  Timer? _scanTimer;

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // A moment after Home shows, so that it doesn't slow its start.
    _scanTimer = Timer(const Duration(seconds: 5), () async {
      if (!mounted) return;
      await ref.read(mistakePuzzleServiceProvider).scanRecentGames();
      if (mounted) ref.invalidate(trainingSummaryProvider);
    });
  }

  /// Opens [route]; a board screen ([board]) hides the tab bar.
  Future<void> _open(Route<void> route, {bool board = false}) async {
    final navigator = Navigator.of(context);
    await (board ? navigator.pushHidingTabBar(route) : navigator.push(route));
    ref.invalidate(trainingSummaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(trainingSummaryProvider).value;
    if (summary == null) return const SizedBox.shrink();
    final due = summary.mistakes;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.extension_outlined),
        title: const Text('Your mistakes'),
        subtitle: Text(
          due > 0
              ? '$due to review'
              : summary.mistakeCards == 0
              ? 'Your mistakes in your games become puzzles'
              : 'Nothing to review right now',
        ),
        trailing: due > 0
            ? FilledButton(
                onPressed: () => _open(
                  TrainingSessionScreen.buildRoute(
                    kind: TrainingKind.mistake,
                    title: 'Your mistakes',
                  ),
                  board: true,
                ),
                child: const Text('Train'),
              )
            : const Icon(Icons.chevron_right),
        onTap: () => _open(TrainingScreen.buildRoute()),
      ),
    );
  }
}
