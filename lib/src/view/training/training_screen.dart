import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/training/mistake_puzzles.dart';
import 'package:lichess_mobile/src/model/training/repertoire.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/training/repertoire_list_screen.dart';
import 'package:lichess_mobile/src/view/training/training_session_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

/// Training, in two parts: the opening repertoires, and the puzzles made from the user's mistakes
/// in their games.
class const TrainingScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const TrainingScreen());

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState() extends ConsumerState<TrainingScreen> {
  bool _scanning = false;

  void _refresh() {
    ref.invalidate(trainingSummaryProvider);
    ref.invalidate(mistakeGamesProvider);
    ref.invalidate(repertoiresProvider);
  }

  Future<void> _open(Route<void> route) async {
    await Navigator.of(context).push(route);
    _refresh();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final found = await ref.read(mistakePuzzleServiceProvider).scanRecentGames(now: true);
    if (!mounted) return;
    setState(() => _scanning = false);
    _refresh();
    showSnackBar(
      context,
      found == 0
          ? 'No new mistakes with one clear answer in your recent games.'
          : '$found new ${found == 1 ? 'puzzle' : 'puzzles'} from your games.',
      type: found == 0 ? SnackBarType.info : SnackBarType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(trainingSummaryProvider).value;
    final games = ref.watch(mistakeGamesProvider).value ?? const IListConst<MistakeGame>([]);
    final repertoires = ref.watch(repertoiresProvider).value?.length ?? 0;
    final scheme = ColorScheme.of(context);
    final openings = summary?.openings ?? 0;
    final mistakes = summary?.mistakes ?? 0;
    return PlatformScaffold(
      appBar: const PlatformAppBar(title: Text('Training')),
      body: ListView(
        children: [
          ListSection(
            header: const Text('Openings'),
            children: [
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Opening repertoires'),
                subtitle: Text(
                  repertoires == 0
                      ? 'Build your lines as White or Black, and drill them'
                      : '$repertoires ${repertoires == 1 ? 'repertoire' : 'repertoires'}'
                            '${openings > 0 ? ' · $openings to review' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(RepertoireListScreen.buildRoute()),
              ),
              if (openings > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 12.0),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.school_outlined),
                    label: Text('Train openings ($openings)'),
                    onPressed: () => _open(
                      TrainingSessionScreen.buildRoute(
                        kind: TrainingKind.opening,
                        title: 'Openings',
                      ),
                    ),
                  ),
                ),
            ],
          ),
          ListSection(
            header: const Text('Mistakes from your games'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      games.isEmpty
                          ? 'Your mistakes and blunders with one clear answer become puzzles: '
                                'from the games you analyse, and from your recent rapid and '
                                'slower games.'
                          : '${summary?.mistakeCards ?? 0} puzzles from ${games.length} '
                                '${games.length == 1 ? 'game' : 'games'}'
                                '${mistakes > 0 ? ' · $mistakes to review' : ''}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12.0),
                    if (mistakes > 0) ...[
                      FilledButton.icon(
                        icon: const Icon(Icons.extension_outlined),
                        label: Text('Train mistakes ($mistakes)'),
                        onPressed: () => _open(
                          TrainingSessionScreen.buildRoute(
                            kind: TrainingKind.mistake,
                            title: 'Your mistakes',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                    ],
                    OutlinedButton.icon(
                      icon: _scanning
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: Text(_scanning ? 'Looking through your games…' : 'Look for mistakes now'),
                      onPressed: _scanning ? null : _scan,
                    ),
                  ],
                ),
              ),
              for (final game in games)
                ListTile(
                  leading: const Icon(Icons.extension_outlined),
                  title: Text(game.title),
                  subtitle: Text(
                    '${game.puzzles} ${game.puzzles == 1 ? 'puzzle' : 'puzzles'}'
                    '${game.due > 0 ? ' · ${game.due} to review' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    TrainingSessionScreen.buildRoute(
                      kind: TrainingKind.mistake,
                      sourceId: game.gameId,
                      title: game.title,
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: Styles.bodyPadding,
            child: Text(
              'A card answered right comes back in a day, then 3 days, then later and later; '
              'one answered wrong comes back soon. New cards come in at most '
              '$kNewCardsPerDay a day.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
