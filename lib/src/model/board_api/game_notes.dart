import 'package:lichess_mobile/src/binding/binding.dart';
import 'package:lichess_mobile/src/model/common/id.dart';

/// The user's private notes on a game, kept on the phone (lichess's game notes are only for the
/// official app).
String _storageKey(GameId id) => 'knightly.gameNote.$id';

/// The notes on the game [id], empty when there are none.
String readGameNote(GameId id) =>
    LichessBinding.instance.sharedPreferences.getString(_storageKey(id)) ?? '';

/// Saves [text] as the notes on the game [id]; blank notes are removed.
Future<void> writeGameNote(GameId id, String text) {
  final prefs = LichessBinding.instance.sharedPreferences;
  return text.trim().isEmpty
      ? prefs.remove(_storageKey(id))
      : prefs.setString(_storageKey(id), text);
}
