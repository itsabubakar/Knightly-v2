import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/ongoing_games_notifier.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/board_api/board_events.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:material_ui/material_ui.dart';

/// The time controls offered against the lichess AI: the Board API allows Blitz against it.
const kLichessAiClocks = [
  (minutes: 5, increment: 3),
  (minutes: 10, increment: 0),
  (minutes: 10, increment: 5),
  (minutes: 15, increment: 10),
  (minutes: 30, increment: 0),
  (minutes: 30, increment: 20),
];

/// Starts a game against the lichess AI (Stockfish on lichess's servers), played live in Knightly.
class const PlayLichessAiSheet({required final NavigatorState navigator, super.key})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<PlayLichessAiSheet> createState() => _PlayLichessAiSheetState();
}

class _PlayLichessAiSheetState() extends ConsumerState<PlayLichessAiSheet> {
  int _level = 3;
  var _clock = kLichessAiClocks[1];

  /// The side of the user, random when null.
  Side? _color;
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final events = ref.read(boardEventsProvider);
      final id = await ref
          .read(boardApiRepositoryProvider)
          .challengeAi(
            level: _level,
            clock: (
              time: Duration(minutes: _clock.minutes),
              increment: Duration(seconds: _clock.increment),
            ),
            color: _color,
          );
      // The full id (which the game screen needs) comes with the game start event, or else from
      // the ongoing games.
      final fullId = await events
          .gameStarted(id, timeout: const Duration(seconds: 8))
          .then<GameFullId?>((started) => started.fullId)
          .catchError((Object _) async {
            ref.invalidate(ongoingGamesProvider);
            final ongoing = await ref.read(ongoingGamesProvider.future);
            return ongoing.firstWhereOrNull((game) => game.id == id)?.fullId;
          });
      if (!mounted) return;
      if (fullId == null) throw StateError('The game $id was not found.');
      Navigator.of(context).pop();
      await widget.navigator.pushHidingTabBar(
        GameScreen.buildRoute(source: ExistingGameSource(fullId)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      final message = e is ServerException && e.jsonError?['error'] != null
          ? 'Could not start the game: ${e.jsonError!['error']}'
          : 'Could not start the game.';
      showSnackBar(context, message, type: SnackBarType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return SafeArea(
      child: Padding(
        padding: Styles.bodyPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Play the lichess AI', style: Styles.title),
            const SizedBox(height: 4.0),
            Text(
              'Stockfish on lichess, played live in Knightly. Casual, it counts for your streak and '
              'XP.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16.0),
            const Text('Level', style: Styles.sectionTitle),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 6.0,
              runSpacing: 6.0,
              children: [
                for (var level = 1; level <= 8; level++)
                  ChoiceChip(
                    label: Text('$level'),
                    selected: _level == level,
                    onSelected: (_) => setState(() => _level = level),
                  ),
              ],
            ),
            const SizedBox(height: 16.0),
            const Text('Time control', style: Styles.sectionTitle),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 6.0,
              runSpacing: 6.0,
              children: [
                for (final clock in kLichessAiClocks)
                  ChoiceChip(
                    label: Text('${clock.minutes}+${clock.increment}'),
                    selected: _clock == clock,
                    onSelected: (_) => setState(() => _clock = clock),
                  ),
              ],
            ),
            const SizedBox(height: 16.0),
            const Text('Your color', style: Styles.sectionTitle),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 6.0,
              children: [
                for (final (side, label) in [
                  (Side.white, 'White'),
                  (null, 'Random'),
                  (Side.black, 'Black'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _color == side,
                    onSelected: (_) => setState(() => _color = side),
                  ),
              ],
            ),
            const SizedBox(height: 20.0),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _starting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: const Text('Play'),
                onPressed: _starting ? null : _start,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
