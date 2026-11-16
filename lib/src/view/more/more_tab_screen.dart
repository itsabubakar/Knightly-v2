import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/account/account_menu.dart';
import 'package:lichess_mobile/src/view/account/profile_screen.dart';
import 'package:lichess_mobile/src/view/analysis/analysis_screen.dart';
import 'package:lichess_mobile/src/view/board_editor/board_editor_screen.dart';
import 'package:lichess_mobile/src/view/clock/clock_tool_screen.dart';
import 'package:lichess_mobile/src/view/explorer/opening_explorer_screen.dart';
import 'package:lichess_mobile/src/view/more/import_pgn_screen.dart';
import 'package:lichess_mobile/src/view/relation/friend_screen.dart';
import 'package:lichess_mobile/src/view/settings/backup_screen.dart';
import 'package:lichess_mobile/src/view/settings/settings_screen.dart';
import 'package:lichess_mobile/src/view/user/player_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/knightly_message.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:material_ui/material_ui.dart';

class const MoreTabScreen({super.key}) extends ConsumerWidget {
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
          title: Text(context.l10n.profile),
          centerTitle: false,
          actions: const [AccountMenuButton()],
        ),
        body: const _Body(),
      ),
    );
  }
}

class const _Body() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final authUser = ref.watch(authControllerProvider);

    return ListTileTheme.merge(
      iconColor: Theme.of(context).colorScheme.primary,
      child: ListView(
        controller: profileScrollController,
        children: [
          const _AccountSection(),
          ListSection(
            header: SettingsSectionTitle(context.l10n.tools),
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.importPgn),
                onTap: () => Navigator.of(context).push(ImportPgnScreen.buildRoute()),
              ),
              ListTile(
                leading: const Icon(Icons.biotech_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.analysis),
                onTap: () => Navigator.of(context).pushHidingTabBar(
                  AnalysisScreen.buildRoute(
                    const AnalysisOptions.standalone(variant: Variant.standard),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.explore_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.openingExplorer),
                enabled: isOnline,
                onTap: () {
                  if (authUser == null) {
                    showSnackBar(context, context.l10n.youNeedAnAccountToDoThat);
                    return;
                  }

                  Navigator.of(context).pushHidingTabBar(
                    OpeningExplorerScreen.buildRoute(
                      const AnalysisOptions.pgn(
                        id: StringId('standalone_opening_explorer'),
                        orientation: Side.white,
                        pgn: '',
                        isComputerAnalysisAllowed: false,
                        variant: Variant.standard,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.boardEditor),
                onTap: () => Navigator.of(context).pushHidingTabBar(
                  BoardEditorScreen.buildRoute((
                    initialVariant: Variant.standard,
                    initialFen: null,
                    initialOrientation: null,
                  )),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.alarm_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.clock),
                onTap: () {
                  Navigator.of(context).pushHidingTabBar(ClockToolScreen.buildRoute());
                },
              ),
            ],
          ),
          ListSection(
            header: SettingsSectionTitle(context.l10n.community),
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.groups_3_outlined),
                title: Text(context.l10n.players),
                enabled: isOnline,
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                onTap: () {
                  Navigator.of(context).push(PlayerScreen.buildRoute());
                },
              ),
              if (authUser != null)
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(context.l10n.friends),
                  enabled: isOnline,
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  onTap: () {
                    Navigator.of(context).push(FriendScreen.buildRoute());
                  },
                ),
            ],
          ),
          Padding(
            padding: Styles.bodySectionPadding,
            child: KnightlyMessage(style: TextTheme.of(context).bodyMedium),
          ),
        ],
      ),
    );
  }
}

class const _AccountSection() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final authUser = ref.watch(authControllerProvider);
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    final user = authUser?.user;

    return ListSection(
      header: user != null ? SettingsSectionTitle(user.name) : null,
      hasLeading: true,
      children: [
        if (user != null) ...[
          ListTile(
            leading: const Icon(Icons.person_outlined),
            title: Text(context.l10n.profile),
            trailing: isIOS ? const CupertinoListTileChevron() : null,
            enabled: isOnline,
            onTap: () {
              Navigator.of(context).push(ProfileScreen.buildRoute());
            },
          ),
        ],
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: Text(context.l10n.settingsSettings),
          trailing: isIOS ? const CupertinoListTileChevron() : null,
          onTap: () {
            Navigator.of(context).push(SettingsScreen.buildRoute());
          },
        ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Backup & restore'),
          trailing: isIOS ? const CupertinoListTileChevron() : null,
          onTap: () {
            Navigator.of(context).push(BackupScreen.buildRoute());
          },
        ),
      ],
    );
  }
}
