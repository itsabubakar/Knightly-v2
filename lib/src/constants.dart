import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

const kLichessHost = String.fromEnvironment('LICHESS_HOST', defaultValue: 'lichess.dev');

const kLichessWSHost = String.fromEnvironment(
  'LICHESS_WS_HOST',
  defaultValue: 'socket.lichess.dev',
);

const kLichessCDNHost = String.fromEnvironment(
  'LICHESS_CDN_HOST',
  defaultValue: 'https://lichess.org',
);

const kLichessOpeningExplorerHost = String.fromEnvironment(
  'LICHESS_OPENING_EXPLORER_HOST',
  defaultValue: 'explorer.lichess.org',
);

const kLichessTablebaseHost = String.fromEnvironment(
  'LICHESS_TABLEBASE_HOST',
  defaultValue: 'tablebase.lichess.org',
);

const kLichessCustomUriSchemeName = 'org.lichess.mobile';

/// Name of the app, sent to lichess in the user agent of every request.
const kAppName = 'Knightly';

/// The OAuth client id Knightly signs in with. Lichess accepts any client id without registration.
const kLichessClientId = 'knightly';

/// The custom URI scheme of the OAuth redirect: Knightly's own, so the official Lichess app
/// installed on the same device can't receive the login callback. The debug build (app id
/// `app.knightly.debug`) has its own too, so it can't receive the release app's (see the
/// `oauthScheme` placeholder in `android/app/build.gradle.kts`).
const kOAuthCustomUriSchemeName = kDebugMode
    ? 'app.knightly.debug'
    : kProfileMode
    ? 'app.knightly.profile'
    : 'app.knightly';

const kSRIStorageKey = 'socket_random_identifier';

const kFideRatingsUrl = 'https://ratings.fide.com/profile/';

// lichess
// https://github.com/lichess-org/lila/blob/4562a83cdb263c3ebf7e148c0f666f0ff92b91c7/modules/rating/src/main/Glicko.scala#L71
const kProvisionalDeviation = 110;
const kClueLessDeviation = 230;

const kMaintenanceDrawingAuthorUrl = 'https://www.pixiv.net/member.php?id=34624';
const kLichessMastodonUrl = 'https://mastodon.online/@lichess';
const kLichessBlueskyUrl = 'https://bsky.app/profile/lichess.org';
const kLichessDiscordUrl = 'https://discord.gg/lichess';

// UI
const double kCupertinoBarOpacity = 0.8;

const kGoldenRatio = 1.61803398875;

/// Use same box shadows as material widgets with elevation 1.
List<BoxShadow> get boardShadows =>
    defaultTargetPlatform == .iOS ? const <BoxShadow>[] : kElevationToShadow[1]!;

const kMaxClockTextScaleFactor = 1.94;
const kEmptyWidget = SizedBox.shrink();
const kTabletBoardTableSidePadding = 16.0;

/// Horizontal margin around the board on phones in portrait orientation, on screens where the board
/// does not span the whole screen width (analysis, learn, practice...).
///
/// It makes the board smaller, which leaves more vertical space below it.
const kPhoneBoardSideMargin = 12.0;

/// Horizontal margin around the board on phones with a short screen (`isShortVerticalScreen`) in
/// portrait orientation, wider than [kPhoneBoardSideMargin] to leave enough vertical space below
/// the board.
const kShortScreenBoardSideMargin = 32.0;

const kBottomBarHeight = 56.0;
const kMaterialPopupMenuMaxWidth = 500.0;

/// The threshold to detect screens with a small remaining height minus board.
const kSmallHeightMinusBoard = 200;
