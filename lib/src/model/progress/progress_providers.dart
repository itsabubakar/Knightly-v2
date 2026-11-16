import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/game/exported_game.dart';
import 'package:lichess_mobile/src/model/game/game_repository.dart';

/// How many of the latest games the recent form shows.
const kRecentFormGames = 30;

/// The latest [kRecentFormGames] games of the signed in user, newest first, for their recent form.
///
/// Empty when signed out.
final recentFormProvider = FutureProvider.autoDispose<IList<LightExportedGameWithPov>>((Ref ref) {
  final authUser = ref.watch(authControllerProvider);
  if (authUser == null) return Future.value(const IListConst([]));
  return ref.read(gameRepositoryProvider).getUserGames(authUser.user.id, max: kRecentFormGames);
}, name: 'RecentFormProvider');
