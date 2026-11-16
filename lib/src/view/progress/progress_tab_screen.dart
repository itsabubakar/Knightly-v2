import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/progress/progress_providers.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/model/user/user_repository_providers.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/account/account_menu.dart';
import 'package:lichess_mobile/src/view/account/profile_screen.dart';
import 'package:lichess_mobile/src/view/account/rating_pref_aware.dart';
import 'package:lichess_mobile/src/view/auth/sign_in_error.dart';
import 'package:lichess_mobile/src/view/auth/sign_in_options.dart';
import 'package:lichess_mobile/src/view/progress/achievements_section.dart';
import 'package:lichess_mobile/src/view/progress/journey_card.dart';
import 'package:lichess_mobile/src/view/progress/recent_form_card.dart';
import 'package:lichess_mobile/src/view/puzzle/dashboard_screen.dart';
import 'package:lichess_mobile/src/view/review/review_card.dart';
import 'package:lichess_mobile/src/view/user/user_stats_section.dart';
import 'package:lichess_mobile/src/widgets/haptic_refresh_indicator.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

/// The Progress tab: ratings, rating history, recent form and puzzle performance.
///
/// The streak, XP, levels and achievements will join it as they are built.
class const ProgressTabScreen({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authUser = ref.watch(authControllerProvider);
    final account = ref.watch(accountProvider).value;
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final signInState = ref.watch(signInMutation);
    ref.listen(signInMutation, (_, next) => showSignInErrorSnackBar(context, next));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) {
          ref.read(currentBottomTabProvider.notifier).state = BottomTab.home;
        }
      },
      child: PlatformScaffold(
        appBar: const PlatformAppBar(
          title: Text('Progress'),
          centerTitle: false,
          actions: [AccountMenuButton()],
        ),
        body: authUser == null
            ? Padding(
                padding: Styles.bodySectionPadding,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Sign in to see your ratings, recent form and puzzle performance.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16.0),
                    FilledButton(
                      onPressed: isOnline && signInState is! MutationPending
                          ? () => showSignInOptions(context, ref)
                          : null,
                      child: Text(context.l10n.signIn),
                    ),
                  ],
                ),
              )
            : HapticRefreshIndicator(
                onRefresh: () async {
                  try {
                    await Future.wait([
                      ref.read(progressionProvider.notifier).refresh(),
                      ref.refresh(accountProvider.future),
                      ref.refresh(recentFormProvider.future),
                      ref.refresh(userRatingHistoryProvider(authUser.user.id).future),
                    ]);
                  } catch (_) {
                    // Each section shows its own error.
                  }
                },
                child: ListView(
                  controller: progressScrollController,
                  children: [
                    const Padding(padding: Styles.bodySectionPadding, child: JourneyCard()),
                    const Padding(
                      padding: Styles.horizontalBodyPadding,
                      child: AchievementsSection(),
                    ),
                    const Padding(padding: Styles.bodySectionPadding, child: ReviewCard()),
                    const AccountPerfCards(padding: Styles.bodySectionPadding),
                    if (account != null)
                      Padding(
                        padding: Styles.horizontalBodyPadding,
                        child: RatingPrefAware(child: RatingHistoryCard(user: account)),
                      ),
                    const Padding(padding: Styles.bodySectionPadding, child: RecentFormCard()),
                    const PuzzleDashboardWidget(),
                  ],
                ),
              ),
      ),
    );
  }
}
