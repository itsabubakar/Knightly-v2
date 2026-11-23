import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';

class FakeSoundService() implements SoundService {
  /// The sounds played, in order.
  final List<Sound> played = [];

  @override
  Future<void> play(Sound sound, {double? volume}) async => played.add(sound);

  @override
  Future<void> playCaptureSound(Variant variant, {double? volume}) async {}

  @override
  Future<void> changeTheme(SoundTheme theme, {bool playSound = false}) async {}

  @override
  Future<void> release() async {}
}
