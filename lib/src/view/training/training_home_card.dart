import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/training/mistake_puzzles.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/view/training/repertoire_list_screen.dart';
import 'package:lichess_mobile/src/view/training/training_session_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Home's training card: the opening moves and the mistakes to review today, the way in to the
/// review and to the repertoires.
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

  Future<void> _open(Route<void> route) async {
    await Navigator.of(context).push(route);
    ref.invalidate(trainingSummaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(trainingSummaryProvider).value;
    if (summary == null) return const SizedBox.shrink();
    final scheme = ColorScheme.of(context);
    final toReview = summary.openings + summary.mistakes;
    final empty = summary.openingCards == 0 && summary.mistakeCards == 0;
    // Nothing to review: a single line, the way in to the repertoires.
    if (toReview == 0) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.school_outlined),
          title: const Text('Training'),
          subtitle: Text(
            empty ? 'Build an opening repertoire to drill' : 'Nothing to review right now',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(RepertoireListScreen.buildRoute()),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Training', style: Styles.sectionTitle)),
                if (toReview > 0)
                  Text(
                    '$toReview to review',
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800),
                  ),
              ],
            ),
            const SizedBox(height: 8.0),
            Text(
              empty
                  ? 'Build an opening repertoire to drill your lines. Your mistakes in your '
                        'analysed games become puzzles here too.'
                  : [
                      if (summary.openingCards > 0) '${summary.openings} opening moves',
                      if (summary.mistakeCards > 0) '${summary.mistakes} of your mistakes',
                    ].join(' · '),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                if (toReview > 0)
                  FilledButton.icon(
                    icon: const Icon(Icons.school_outlined),
                    label: const Text('Review'),
                    onPressed: () => _open(TrainingSessionScreen.buildRoute()),
                  ),
                if (summary.mistakes > 0 && summary.openings > 0)
                  OutlinedButton(
                    onPressed: () => _open(
                      TrainingSessionScreen.buildRoute(
                        kind: TrainingKind.mistake,
                        title: 'Your mistakes',
                      ),
                    ),
                    child: const Text('Mistakes only'),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Repertoires'),
                  onPressed: () => _open(RepertoireListScreen.buildRoute()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
