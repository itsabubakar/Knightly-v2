import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/progress/progress_providers.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:material_ui/material_ui.dart';

/// The results of the latest games as a row of colored squares, newest first, with a summary.
class const RecentFormCard({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final Widget content;
    switch (ref.watch(recentFormProvider)) {
      case AsyncData(:final value):
        final games = value
            .where((g) => g.game.status != .created && g.game.status != .started)
            .toList();
        if (games.isEmpty) {
          content = const Text('No finished games yet.');
          break;
        }
        final wins = games.where((g) => g.game.winner == g.pov).length;
        final losses = games.where((g) => g.game.winner != null && g.game.winner != g.pov).length;
        final draws = games.length - wins - losses;
        final score = ((wins + draws / 2) / games.length * 100).round();
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last ${games.length} games', style: Styles.sectionTitle),
            const SizedBox(height: 12.0),
            Wrap(
              spacing: 6.0,
              runSpacing: 6.0,
              children: [
                for (final g in games)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: g.game.winner == null
                          ? scheme.outline
                          : g.game.winner == g.pov
                          ? Flare.green
                          : Flare.red,
                      borderRadius: const BorderRadius.all(Radius.circular(6.0)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12.0),
            Text(
              '$wins won · $draws drawn · $losses lost · $score% score',
              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ],
        );
      case AsyncError():
        content = const Text('Could not load your recent games.');
      case _:
        content = const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
    }
    return Card(
      child: Padding(padding: const EdgeInsets.all(16.0), child: content),
    );
  }
}
