import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the lichess.org inbox in the browser, at the conversation with [user] if given.
///
/// Knightly can't show the inbox: lichess's API can't read the messages (only the official app
/// can). The browser needs to be signed in to lichess.org.
Future<bool> openInboxInBrowser([UserId? user]) => launchUrl(
  lichessUri(user != null ? '/inbox/$user' : '/inbox'),
  mode: LaunchMode.externalApplication,
);
