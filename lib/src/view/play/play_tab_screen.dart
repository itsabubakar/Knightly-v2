import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/account/account_menu.dart';
import 'package:lichess_mobile/src/view/play/play_menu.dart';
import 'package:lichess_mobile/src/view/play/quick_game_matrix.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

/// The Play tab: quick pairing, creating a game, challenges and the offline modes.
class const PlayTabScreen({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) {
          ref.read(currentBottomTabProvider.notifier).state = BottomTab.home;
        }
      },
      child: PlatformScaffold(
        appBar: PlatformAppBar(
          title: Text(context.l10n.play),
          centerTitle: false,
          actions: const [AccountMenuButton()],
        ),
        body: ListView(
          controller: playScrollController,
          children: const [
            Padding(padding: Styles.bodySectionPadding, child: QuickGameMatrix()),
            PlayMenu(),
          ],
        ),
      ),
    );
  }
}
