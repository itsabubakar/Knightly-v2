import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/training/repertoire.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/training/repertoire_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// The user's opening repertoires: open one to build it or train it, add one, delete one.
class const RepertoireListScreen({super.key}) extends ConsumerWidget {
  static Route<void> buildRoute() => buildScreenRoute(screen: const RepertoireListScreen());

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final created = await showAdaptiveDialog<({String name, Side side})>(
      context: context,
      builder: (_) => const _NewRepertoireDialog(),
    );
    final userId = ref.read(authControllerProvider)?.user.id;
    if (created == null || userId == null) return;
    final db = await ref.read(knightlyDatabaseProvider.future);
    final id = await createRepertoire(db, userId, name: created.name, side: created.side);
    ref.invalidate(repertoiresProvider);
    if (context.mounted) await Navigator.of(context).push(RepertoireScreen.buildRoute(id));
    ref.invalidate(repertoiresProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Repertoire repertoire) async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => YesNoDialog(
        title: Text('Delete ${repertoire.name}?'),
        content: const Text('Its lines and their review history go too.'),
        onYes: () => Navigator.of(context).pop(true),
        onNo: () => Navigator.of(context).pop(false),
      ),
    );
    final userId = ref.read(authControllerProvider)?.user.id;
    if (confirmed != true || userId == null) return;
    final db = await ref.read(knightlyDatabaseProvider.future);
    await deleteRepertoire(db, userId, repertoire.id);
    ref.invalidate(repertoiresProvider);
    ref.invalidate(trainingSummaryProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repertoires = ref.watch(repertoiresProvider);
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Opening repertoires'),
        actions: [
          IconButton(
            tooltip: 'New repertoire',
            icon: const Icon(Icons.add),
            onPressed: () => _add(context, ref),
          ),
        ],
      ),
      body: switch (repertoires) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Padding(
            padding: Styles.bodyPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No repertoire yet', style: Styles.title),
                const SizedBox(height: 8.0),
                const Text(
                  'Pick your moves as White or Black on a board; Knightly adds your '
                  "opponent's most played replies, then drills you on them with spaced "
                  'repetition.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16.0),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('New repertoire'),
                  onPressed: () => _add(context, ref),
                ),
              ],
            ),
          ),
        ),
        AsyncData(:final value) => ListView(
          children: [
            ListSection(
              children: [
                for (final summary in value)
                  ListTile(
                    leading: Icon(
                      Icons.circle,
                      color: summary.repertoire.side == Side.white ? Colors.white : Colors.black,
                      shadows: const [Shadow(blurRadius: 1)],
                    ),
                    title: Text(summary.repertoire.name),
                    subtitle: Text(
                      '${summary.cards} moves · '
                      '${summary.due > 0 ? '${summary.due} to review' : 'nothing to review'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete ${summary.repertoire.name}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, ref, summary.repertoire),
                    ),
                    onTap: () async {
                      await Navigator.of(context)
                          .push(RepertoireScreen.buildRoute(summary.repertoire.id));
                      ref.invalidate(repertoiresProvider);
                    },
                  ),
              ],
            ),
          ],
        ),
        AsyncError() => const Center(child: Text('Could not load the repertoires.')),
        _ => const Center(child: CircularProgressIndicator.adaptive()),
      },
    );
  }
}

/// Asks the name and the side of a new repertoire.
class const _NewRepertoireDialog() extends StatefulWidget {
  @override
  State<_NewRepertoireDialog> createState() => _NewRepertoireDialogState();
}

class _NewRepertoireDialogState() extends State<_NewRepertoireDialog> {
  final _name = TextEditingController();
  Side _side = Side.white;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return PlatformAlertDialog(
      title: const Text('New repertoire'),
      content: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name, e.g. Sicilian Najdorf'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12.0),
            SegmentedButton<Side>(
              segments: const [
                ButtonSegment(value: Side.white, label: Text('As White')),
                ButtonSegment(value: Side.black, label: Text('As Black')),
              ],
              selected: {_side},
              onSelectionChanged: (selected) => setState(() => _side = selected.first),
            ),
          ],
        ),
      ),
      actions: [
        PlatformDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        PlatformDialogAction(
          cupertinoIsDefaultAction: true,
          onPressed: name.isEmpty
              ? null
              : () => Navigator.of(context).pop((name: name, side: _side)),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
