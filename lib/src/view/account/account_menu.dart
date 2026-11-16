import 'package:auto_size_text/auto_size_text.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/account/profile_screen.dart';
import 'package:lichess_mobile/src/view/auth/sign_in_error.dart';
import 'package:lichess_mobile/src/view/auth/sign_in_options.dart';
import 'package:lichess_mobile/src/view/settings/settings_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the account menu ([AccountMenuScreen]).
///
/// On iOS it is the first page of a navigation sheet ([showAdaptiveNavigationSheet]) covering the
/// tab bar, in which the screens it opens are pushed. On Android it is pushed as a full-screen page
/// sliding from the right.
Future<void> showAccountMenu(BuildContext context) {
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return showAdaptiveNavigationSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const AccountMenuScreen(),
    );
  }

  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, a, b) => const AccountMenuScreen(),
      transitionsBuilder: (_, animation, b, child) {
        final tween = Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeInOut));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    ),
  );
}

/// Account menu screen, opened by [AccountMenuButton] with [showAccountMenu].
class const AccountMenuScreen({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AccountMenuScreen> createState() => _AccountMenuScreenState();
}

class _AccountMenuScreenState()
    extends ConsumerState<AccountMenuScreen>
    with WidgetsBindingObserver {
  bool _pendingKidModeRefresh = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingKidModeRefresh) {
      _pendingKidModeRefresh = false;
      ref.invalidate(accountProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final signInState = ref.watch(signInMutation);
    final signOutState = ref.watch(signOutMutation);

    ref.listen(signInMutation, (_, next) => showSignInErrorSnackBar(context, next));
    final account = ref.watch(accountProvider);
    final authUser = ref.watch(authControllerProvider);
    final kidMode = account.value?.kid ?? false;
    final LightUser? user = account.value?.lightUser ?? authUser?.user;

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text(context.l10n.mobileAccount),
        // On iOS the close button of the sheet is implied.
        automaticallyImplyLeading: Theme.of(context).platform == TargetPlatform.iOS,
        actions: [
          if (Theme.of(context).platform != TargetPlatform.iOS)
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        ],
      ),
      body: ListView(
        children: [
          if (user != null)
            ListSection(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  leading: switch (account) {
                    AsyncData(:final value) =>
                      value == null
                          ? const Icon(Icons.account_circle_outlined, size: 30)
                          : AccountAvatar(value),
                    _ => const Icon(Icons.account_circle_outlined, size: 30),
                  },
                  trailing: Theme.of(context).platform == TargetPlatform.iOS
                      ? const CupertinoListTileChevron()
                      : null,
                  title: AutoSizeText(
                    user.name,
                    style: Styles.callout,
                    maxLines: 1,
                    minFontSize: 14,
                    maxFontSize: 18,
                    overflow: TextOverflow.ellipsis,
                  ),
                  enabled: isOnline,
                  onTap: () {
                    _navigate(context, ProfileScreen.buildRoute());
                  },
                ),
                if (kidMode)
                  ListTile(
                    textColor: Theme.of(context).colorScheme.primary,
                    iconColor: Theme.of(context).colorScheme.primary,
                    leading: const Icon(Symbols.sentiment_satisfied, weight: 600),
                    title: Text(
                      context.l10n.kidModeIsEnabled,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      _pendingKidModeRefresh = true;
                      launchUrl(lichessUri('/account/kid'));
                    },
                  ),
              ],
            )
          else ...[
            Center(
              child: FilledButton.tonal(
                onPressed: isOnline
                    ? switch (signInState) {
                        MutationPending() => null,
                        _ => () => showSignInOptions(context, ref),
                      }
                    : null,
                child: Text(context.l10n.signIn),
              ),
            ),
          ],
          ListSection(
            children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.settingsSettings),
                onTap: () {
                  _navigate(context, SettingsScreen.buildRoute());
                },
              ),
              if (user != null)
                switch (signOutState) {
                  MutationPending() => const ListTile(
                    leading: Icon(Icons.logout_outlined),
                    enabled: false,
                    title: Center(child: ButtonLoadingIndicator()),
                  ),
                  _ => ListTile(
                    leading: const Icon(Icons.logout_outlined),
                    title: Text(context.l10n.logOut),
                    enabled: isOnline,
                    onTap: () => _showSignOutConfirmDialog(context, ref),
                  ),
                },
            ],
          ),
          const SocketPingRatingListTile(),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, Route<dynamic> route) {
    Navigator.of(context).push(route);
  }

  void _showSignOutConfirmDialog(BuildContext context, WidgetRef ref) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      showCupertinoActionSheet<void>(
        context: context,
        actions: [
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.logOut),
            isDestructiveAction: true,
            onPressed: () async {
              await signOutMutation.run(ref, (tsx) async {
                await tsx.get(authControllerProvider.notifier).signOut();
              });
            },
          ),
        ],
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(context.l10n.logOut),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.l10n.cancel),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await signOutMutation.run(ref, (tsx) async {
                    await tsx.get(authControllerProvider.notifier).signOut();
                  });
                },
                child: Text(context.l10n.mobileOkButton),
              ),
            ],
          );
        },
      );
    }
  }
}

/// Avatar button that opens the account menu ([showAccountMenu]).
class const AccountMenuButton({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AccountMenuButton> createState() => _AccountMenuButtonState();
}

class _AccountMenuButtonState() extends ConsumerState<AccountMenuButton> {
  static const _materialAnonIconSize = 30.0;
  static const _cupertinoAnonIconSize = 32.0;

  /// Size of the button on iOS, where it fills the glass capsule of the navigation bar.
  static const _cupertinoButtonSize = 44.0;
  static const _cupertinoAvatarRadius = 20.0;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    void openMenu() => showAccountMenu(context);

    return switch (account) {
      AsyncData(:final value) => IconButton(
        padding: isIOS ? EdgeInsets.zero : null,
        constraints: isIOS
            ? const BoxConstraints.tightFor(
                width: _cupertinoButtonSize,
                height: _cupertinoButtonSize,
              )
            : null,
        tooltip: value == null ? context.l10n.signIn : value.username,
        icon: value == null
            ? Icon(
                Icons.account_circle_outlined,
                size: isIOS ? _cupertinoAnonIconSize : _materialAnonIconSize,
              )
            : AccountAvatar(
                value,
                radius: isIOS ? _cupertinoAvatarRadius : _materialAnonIconSize / 2 + 1,
              ),
        onPressed: openMenu,
      ),
      _ => IconButton(
        padding: isIOS ? EdgeInsets.zero : null,
        constraints: isIOS
            ? const BoxConstraints.tightFor(
                width: _cupertinoButtonSize,
                height: _cupertinoButtonSize,
              )
            : null,
        icon: Icon(
          Icons.account_circle_outlined,
          size: isIOS ? _cupertinoAnonIconSize : _materialAnonIconSize,
        ),
        tooltip: context.l10n.signIn,
        onPressed: openMenu,
      ),
    };
  }
}
