import 'package:lichess_mobile/src/binding/binding_knightly.dart';
import 'package:lichess_mobile/src/bootstrap.dart';

Future<void> main() {
  return bootstrapApp(KnightlyBinding.ensureInitialized);
}
