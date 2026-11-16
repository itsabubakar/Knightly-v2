import 'package:dartchess/dartchess.dart' show Side;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_preferences.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/review/game_review.dart';
import 'package:lichess_mobile/src/model/review/game_tags.dart';
import 'package:lichess_mobile/src/model/review/move_judgement.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/review/tag_list_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The [ReviewedGameInfo] of [game], seen from [mySide].
ReviewedGameInfo reviewedGameInfo(BuildContext context, ExportedGame game, Side mySide) => (
  gameId: game.id,
  opponent: game.playerOf(mySide.opposite).fullName(context.l10n),
  playedAt: game.data.lastMoveAt,
  orientation: mySide,
);

/// The label of the move played at [ply] (the number of half moves made), e.g. "14. Nxe5" or
/// "14… Nxe5".
String moveLabel(int ply, String san) =>
    ply.isOdd ? '${(ply + 1) ~/ 2}. $san' : '${ply ~/ 2}… $san';

/// The verdict of lichess's computer analysis on a move, from its NAGs, if a mistake.
String? analysisVerdict(Iterable<int>? nags) => switch (nags) {
  final n? when n.contains(4) => 'Blunder',
  final n? when n.contains(2) => 'Mistake',
  final n? when n.contains(6) => 'Inaccuracy',
  _ => null,
};

/// Puts tags on the move at [ply] of the user's game, and removes them.
///
/// Suggests what to tag from lichess's computer analysis ([verdict]), and from the engine of the
/// analysis board, which compares the positions before and after the move.
class const TagMoveSheet({
  required final ReviewedGameInfo info,
  required final int ply,
  required final String san,

  /// The analysis of the game, whose engine judges the move.
  required final AnalysisOptions options,

  /// The path of the move in the analysis tree.
  required final UciPath path,

  /// The verdict of lichess's computer analysis on the move (see [analysisVerdict]), suggesting to
  /// tag it.
  final String? verdict,
  super.key,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<TagMoveSheet> createState() => _TagMoveSheetState();
}

class _TagMoveSheetState() extends ConsumerState<TagMoveSheet> {
  /// Whether the engine is being asked to judge the move.
  bool _checking = false;

  /// Has the engine evaluate the position before the move, which it hasn't looked at yet: the
  /// board steps back to it, waits for a deep enough evaluation, and steps forward again.
  Future<void> _checkWithEngine() async {
    final controller = ref.read(analysisControllerProvider(widget.options).notifier);
    setState(() => _checking = true);
    controller.userPrevious();
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final root = ref.read(analysisControllerProvider(widget.options)).value?.root;
      final before = root?.branchesOn(widget.path.penultimate).lastOrNull ?? root;
      final eval = before?.eval;
      if (eval != null && eval.depth >= kEngineCheckDepth) break;
    }
    controller.userNext();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final ply = widget.ply;
    final san = widget.san;
    final review = ref.watch(gameReviewProvider(info.gameId));
    final tags = ref.watch(tagListProvider);
    final selected = review.value?.tagsAt(ply) ?? const ISetConst<String>({});
    final analysis = ref.watch(analysisControllerProvider(widget.options)).value;
    final engineOn =
        analysis?.isEngineAvailable(ref.watch(engineEvaluationPreferencesProvider)) ?? false;
    final judgement = analysis != null ? judgeMove(analysis.root, widget.path) : null;
    final engineSuggests =
        judgement != null &&
        (judgement.verdict == .inaccuracy ||
            judgement.verdict == .mistake ||
            judgement.verdict == .blunder);
    return BottomSheetScrollableContainer(
      padding: const EdgeInsets.all(16.0),
      children: [
        Text('Tag ${moveLabel(ply, san)}', style: Styles.title),
        if (widget.verdict != null)
          _Suggestion(
            text:
                "Lichess's analysis marks this move as a ${widget.verdict!.toLowerCase()}. "
                'What went wrong?',
          ),
        if (judgement != null)
          _Suggestion(
            isMistake: engineSuggests,
            text: [
              'Engine: ${verdictLabel(judgement.verdict)}',
              if (judgement.bestSan != null) 'best was ${judgement.bestSan}',
              'depth ${judgement.depth}',
            ].join(' · '),
          )
        else if (engineOn)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: OutlinedButton.icon(
              icon: _checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.memory),
              label: Text(_checking ? 'Checking…' : 'Check with engine'),
              onPressed: _checking ? null : _checkWithEngine,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Text(
              'Turn the engine on in the bottom bar to have it judge this move.',
              style: TextStyle(color: ColorScheme.of(context).onSurfaceVariant),
            ),
          ),
        for (final kind in TagKind.values) ...[
          const SizedBox(height: 16.0),
          Text(kind.label, style: Styles.sectionTitle),
          const SizedBox(height: 8.0),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              for (final tag in tags.where((tag) => tag.kind == kind))
                FilterChip(
                  label: Text(tag.label),
                  selected: selected.contains(tag.id),
                  onSelected: review.hasValue
                      ? (_) => ref
                            .read(gameReviewProvider(info.gameId).notifier)
                            .toggleTag(ply: ply, san: san, tagId: tag.id, info: info)
                      : null,
                ),
            ],
          ),
        ],
        const SizedBox(height: 16.0),
        Row(
          children: [
            Text(
              '+$kMoveTaggedXp XP per tag',
              style: TextStyle(color: ColorScheme.of(context).onSurfaceVariant),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Symbols.edit),
              label: const Text('Edit tags'),
              onPressed: () => Navigator.of(context).push(TagListScreen.buildRoute()),
            ),
          ],
        ),
      ],
    );
  }
}

/// The depth the engine check waits for in the position before the move.
const kEngineCheckDepth = 14;

/// A suggestion to tag the move, or the engine's verdict when it's a good one.
class const _Suggestion({required final String text, final bool isMistake = true})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = isMistake ? Flare.red : Flare.green;
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: const BorderRadius.all(Radius.circular(12.0)),
        ),
        child: Row(
          children: [
            Icon(isMistake ? Symbols.lightbulb : Symbols.check_circle, color: color),
            const SizedBox(width: 8.0),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

/// Edits the lessons learned note of the user's game: a game with a note is reviewed.
Future<void> showReviewNoteDialog(BuildContext context, WidgetRef ref, ReviewedGameInfo info) {
  return showAdaptiveDialog<void>(
    context: context,
    builder: (context) => _ReviewNoteDialog(info: info),
  );
}

class const _ReviewNoteDialog({required final ReviewedGameInfo info})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ReviewNoteDialog> createState() => _ReviewNoteDialogState();
}

class _ReviewNoteDialogState() extends ConsumerState<_ReviewNoteDialog> {
  final _controller = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(gameReviewProvider(widget.info.gameId));
    if (!_initialized && review.hasValue) {
      _controller.text = review.value!.note;
      _initialized = true;
    }
    return PlatformAlertDialog(
      title: const Text('Lessons learned'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'What will you do differently next time? A game with a lesson noted is reviewed: '
            '+$kGameReviewedXp XP.',
          ),
          const SizedBox(height: 12.0),
          Material(
            type: MaterialType.transparency,
            child: TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. Check every capture before moving'),
            ),
          ),
        ],
      ),
      actions: [
        PlatformDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        PlatformDialogAction(
          cupertinoIsDefaultAction: true,
          onPressed: review.hasValue
              ? () async {
                  await ref
                      .read(gameReviewProvider(widget.info.gameId).notifier)
                      .saveNote(_controller.text, widget.info);
                  if (context.mounted) Navigator.of(context).pop();
                }
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
