import 'package:lichess_mobile/src/binding/binding.dart';
import 'package:lichess_mobile/src/binding/crashlytics.dart';

/// Concrete implementation of [LichessBinding] for Knightly: no Firebase at all.
///
/// Knightly has its own application id, which lichess's Firebase project doesn't know, and lichess
/// only sends push notifications to its own app anyway.
class KnightlyBinding() extends LichessBindingBase {
  factory ensureInitialized() {
    return LichessBinding.ensureInitialized(() => KnightlyBinding());
  }

  @override
  Future<void> initializeFirebase() async {}

  @override
  bool get pushNotificationsEnabled => false;

  @override
  Crashlytics get firebaseCrashlytics => const NoOpCrashlytics();
}
