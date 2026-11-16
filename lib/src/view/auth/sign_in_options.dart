import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Starts the OAuth browser sign in flow.
///
/// Knightly has no email login code alternative: lichess only issues those codes for the official
/// app.
///
/// Failures are reported through [signInMutation], so callers are expected to already listen to it
/// with `showSignInErrorSnackBar`.
Future<void> showSignInOptions(BuildContext context, WidgetRef ref) async {
  // The error is surfaced by the caller's [ref.listen] on [signInMutation]; ignore the rethrown
  // future so it does not become an unhandled exception.
  signInMutation.run(ref, (tsx) async {
    await tsx.get(authControllerProvider.notifier).signIn();
  }).ignore();
}
