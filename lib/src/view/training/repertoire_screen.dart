import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/explorer/opening_explorer.dart';
import 'package:lichess_mobile/src/model/game/game_board_params.dart';
import 'package:lichess_mobile/src/model/training/repertoire.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/training/training_session_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// The position after [path] (UCI moves from the start).
Position positionAfterPath(List<String> path) {
  Position position = Chess.initial;
  for (final uci in path) {
    final move = Move.parse(uci);
    if (move == null || !position.isLegal(move)) break;
    position = position.play(move);
  }
  return position;
}

/// Builds an opening repertoire on a board: the user picks their move in each of their positions
/// (lichess's games suggest moves), and their opponent's most played replies are added on their own.
class const RepertoireScreen({required final int repertoireId, super.key})
    extends ConsumerStatefulWidget {
  static Route<void> buildRoute(int repertoireId) =>
      buildScreenRoute(screen: RepertoireScreen(repertoireId: repertoireId));

  @override
  ConsumerState<RepertoireScreen> createState() => _RepertoireScreenState();
}

class _RepertoireScreenState() extends ConsumerState<RepertoireScreen> {
  /// The moves (UCI) from the start to the position shown.
  List<String> _path = [];

  /// Whether a move is being saved (and the replies after it fetched).
  bool _busy = false;

  RepertoireTreeNotifier get _notifier =>
      ref.read(repertoireTreeProvider(widget.repertoireId).notifier);

  Future<void> _play(RepertoireTree tree, Move move) async {
    final position = positionAfterPath(_path);
    if (!position.isLegal(move)) return;
    final known = tree.movesAt(position).any((m) => m.uci == move.uci);
    final path = [..._path];
    setState(() {
      _path = [...path, move.uci];
      _busy = !known;
    });
    if (known) return;
    try {
      await _notifier.addMove(path, move);
    } catch (_) {
      if (mounted) showSnackBar(context, 'Could not save the move.', type: SnackBarType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(RepertoireMove move) async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => YesNoDialog(
        title: Text('Remove ${move.san}?'),
        content: const Text('The moves after it go too, unless another line reaches them.'),
        onYes: () => Navigator.of(context).pop(true),
        onNo: () => Navigator.of(context).pop(false),
      ),
    );
    if (confirmed == true) await _notifier.removeMove(_path, move.uci);
  }

  Future<void> _fillReplies() async {
    setState(() => _busy = true);
    try {
      await _notifier.addTopReplies(_path, positionAfterPath(_path));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showToDo(RepertoireTree tree) {
    final toDo = tree.positionsToFill();
    showAdaptiveBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => BottomSheetScrollableContainer(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              toDo.isEmpty ? 'Nothing left to do' : 'Your move to choose (${toDo.length})',
              style: Styles.title,
            ),
          ),
          if (toDo.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Every line has your move, down to move 10.'),
            ),
          for (final path in toDo)
            ListTile(
              title: Text(path.isEmpty ? 'Start position' : pathSan(path)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() => _path = path);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(repertoireTreeProvider(widget.repertoireId));
    final tree = treeAsync.value;
    final scheme = ColorScheme.of(context);
    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(tree?.repertoire.name ?? 'Repertoire')),
      extendBodyBehindAppBar: false,
      body: switch (treeAsync) {
        AsyncError(:final error) => Center(child: Text('Could not load the repertoire.\n$error')),
        _ when tree == null => const Center(child: CircularProgressIndicator.adaptive()),
        _ => SafeArea(
          child: Builder(
            builder: (context) {
              final position = positionAfterPath(_path);
              final mine = tree.isMine(position);
              final moves = tree.movesAt(position);
              final lastMove = _path.isNotEmpty ? Move.parse(_path.last) : null;
              final toDo = tree.positionsToFill().length;
              return GameLayout(
                orientation: tree.repertoire.side,
                boardParams: GameBoardParams.interactive(
                  variant: .standard,
                  position: position,
                  playerSide: PlayerSide.both,
                  lastMove: lastMove,
                  onMove: (move, {viaDragAndDrop}) => unawaited(_play(tree, move)),
                ),
                topTable: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _path.isEmpty ? 'Start position' : pathSan(_path),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4.0),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              mine
                                  ? (moves.isEmpty ? 'Your move: choose one' : 'Your move')
                                  : "Your opponent's replies",
                              style: Styles.sectionTitle,
                            ),
                          ),
                          if (_busy)
                            const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                bottomTable: _MovesPanel(
                  mine: mine,
                  moves: moves.toList(),
                  fen: position.fen,
                  onFollow: (move) => setState(() => _path = [..._path, move.uci]),
                  onRemove: _remove,
                  onAdd: (uci) {
                    final move = Move.parse(uci);
                    if (move != null) unawaited(_play(tree, move));
                  },
                ),
                userActionsBar: BottomBar(
                  cupertinoGlass: true,
                  children: [
                    BottomBarButton(
                      label: 'Back',
                      icon: Icons.chevron_left,
                      onTap: _path.isEmpty
                          ? null
                          : () => setState(() => _path = _path.sublist(0, _path.length - 1)),
                    ),
                    BottomBarButton(
                      label: 'Start',
                      icon: Icons.first_page,
                      onTap: _path.isEmpty ? null : () => setState(() => _path = []),
                    ),
                    if (!mine)
                      BottomBarButton(
                        label: 'Add top replies',
                        icon: Icons.playlist_add,
                        onTap: _busy ? null : _fillReplies,
                      ),
                    BottomBarButton(
                      label: toDo > 0 ? 'To do ($toDo)' : 'To do',
                      showLabel: true,
                      icon: Icons.checklist,
                      highlighted: toDo > 0,
                      onTap: () => _showToDo(tree),
                    ),
                    BottomBarButton(
                      label: 'Train',
                      showLabel: true,
                      icon: Icons.school_outlined,
                      onTap: () => Navigator.of(context).push(
                        TrainingSessionScreen.buildRoute(
                          kind: TrainingKind.opening,
                          sourceId: tree.repertoire.id.toString(),
                          title: tree.repertoire.name,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      },
    );
  }
}

/// The moves of the repertoire in the position, and lichess's most played moves there to add.
class const _MovesPanel({
  required final bool mine,
  required final List<RepertoireMove> moves,
  required final String fen,
  required final void Function(RepertoireMove move) onFollow,
  required final void Function(RepertoireMove move) onRemove,
  required final void Function(String uci) onAdd,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.of(context);
    final explorer = ref.watch(repertoireExplorerProvider(fen)).value;
    final total = explorer == null ? 0 : explorer.white + explorer.draws + explorer.black;
    final suggestions = [
      for (final move in explorer?.moves ?? const <OpeningMove>[])
        if (!moves.any((m) => m.uci == move.uci)) move,
    ].take(5);
    String share(OpeningMove move) {
      final games = move.white + move.draws + move.black;
      return total == 0 ? '' : '${(games * 100 / total).round()}%';
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      children: [
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: [
            for (final move in moves)
              InputChip(
                label: Text(move.san, style: const TextStyle(fontWeight: FontWeight.w700)),
                avatar: mine ? const Icon(Icons.star, size: 16, color: Flare.orange) : null,
                onPressed: () => onFollow(move),
                onDeleted: () => onRemove(move),
                deleteButtonTooltipMessage: 'Remove ${move.san}',
              ),
          ],
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8.0),
          Text(
            mine ? 'Most played here (tap to make it your move)' : 'Other replies played here',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 4.0),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: [
              for (final move in suggestions)
                ActionChip(
                  label: Text('${move.san} ${share(move)}'),
                  onPressed: () => onAdd(move.uci),
                ),
            ],
          ),
        ] else if (explorer == null && moves.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              mine ? 'Play your move on the board.' : 'Play a reply on the board.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
