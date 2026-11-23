import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/tab_navigation.dart' show currentNavigatorKeyProvider;
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ota_update/ota_update.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

final _logger = Logger('AppUpdateService');

/// Where Knightly's releases are published: each release is tagged with the full version
/// (`v1.0.1+010001`) and has the APK as an asset.
const kKnightlyReleasesApi =
    'https://api.github.com/repos/itsabubakar/knightly-releases/releases/latest';

/// How long after the start the updates are looked for, so that they don't slow it down.
const kUpdateCheckDelay = Duration(seconds: 8);

/// The build number of a release tag (`v1.0.1+010001` → 10001), null if it has none.
int? releaseBuildNumber(String tag) {
  final plus = tag.indexOf('+');
  return plus < 0 ? null : int.tryParse(tag.substring(plus + 1));
}

/// A Knightly release on GitHub, newer than the installed app.
typedef AppRelease = ({String version, int buildNumber, String apkUrl, String notes});

/// The latest release in [json] (GitHub's "latest release"), if it's newer than
/// [installedBuildNumber] and has an APK.
AppRelease? newerRelease(Map<String, dynamic> json, int installedBuildNumber) {
  final tag = json['tag_name'] as String? ?? '';
  final build = releaseBuildNumber(tag);
  if (build == null || build <= installedBuildNumber) return null;
  final apk = (json['assets'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>()
      .where((asset) => (asset['name'] as String? ?? '').endsWith('.apk'))
      .firstOrNull;
  final url = apk?['browser_download_url'] as String?;
  if (url == null) return null;
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  return (
    version: version.split('+').first,
    buildNumber: build,
    apkUrl: url,
    notes: (json['body'] as String? ?? '').trim(),
  );
}

/// Knightly's own updates, outside a store: a new APK from its GitHub releases (downloaded, then
/// handed to Android's installer), and Shorebird's patches (downloaded on their own at the start;
/// the user is told to restart once one is ready).
final appUpdateServiceProvider = Provider<AppUpdateService>(
  AppUpdateService.new,
  name: 'AppUpdateServiceProvider',
);

class AppUpdateService(final Ref ref) {
  Timer? _timer;

  /// Looks for updates a moment after the start: Android release builds only.
  void start() {
    if (!kReleaseMode || !Platform.isAndroid) return;
    _timer = Timer(kUpdateCheckDelay, () async {
      final released = await _checkRelease();
      if (!released) await _checkPatch();
    });
    ref.onDispose(() => _timer?.cancel());
  }

  BuildContext? get _context => ref.read(currentNavigatorKeyProvider).currentContext;

  /// Offers the latest GitHub release if it's newer; returns whether it did.
  Future<bool> _checkRelease() async {
    try {
      final installed = int.tryParse(
        ref.read(preloadedDataProvider).requireValue.packageInfo.buildNumber,
      );
      if (installed == null) return false;
      final response = await http
          .get(
            Uri.parse(kKnightlyReleasesApi),
            headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Knightly'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return false;
      final release = newerRelease(jsonDecode(response.body) as Map<String, dynamic>, installed);
      final context = _context;
      if (release == null || context == null || !context.mounted) return false;
      final update = await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => PlatformAlertDialog(
          title: const Text('New version available'),
          content: Text(
            [
              'Knightly ${release.version} is ready to install.',
              if (release.notes.isNotEmpty) '\n${release.notes}',
            ].join('\n'),
          ),
          actions: [
            PlatformDialogAction(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Later'),
            ),
            PlatformDialogAction(
              cupertinoIsDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      if (update == true) _install(release);
      return true;
    } catch (e, st) {
      _logger.warning('Could not check for a new release', e, st);
      return false;
    }
  }

  /// Downloads the release's APK, showing the progress, then opens the installer.
  void _install(AppRelease release) {
    final context = _context;
    if (context == null || !context.mounted) return;
    final progress = ValueNotifier<String>('Downloading…');
    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    unawaited(
      showAdaptiveDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PlatformAlertDialog(
          title: Text('Updating to ${release.version}'),
          content: ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, text, _) => Text(text),
          ),
        ),
      ).whenComplete(() => dialogOpen = false),
    );
    void closeDialog() {
      if (dialogOpen) navigator.pop();
    }

    void fail(String message) {
      closeDialog();
      final context = _context;
      if (context != null && context.mounted) {
        showSnackBar(context, message, type: SnackBarType.error);
      }
    }

    try {
      OtaUpdate()
          .execute(release.apkUrl, destinationFilename: 'knightly-${release.version}.apk')
          .listen((event) {
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                progress.value = 'Downloading… ${event.value ?? ''}%';
              case OtaStatus.INSTALLING:
              case OtaStatus.INSTALLATION_DONE:
                closeDialog();
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                fail('Allow Knightly to install apps, then try again.');
              case OtaStatus.CANCELED:
                closeDialog();
              default:
                fail('The update could not be installed: ${event.value ?? event.status.name}');
            }
          }, onError: (Object e) => fail('The update could not be downloaded.'));
    } catch (e, st) {
      _logger.warning('Could not start the update', e, st);
      fail('The update could not be started.');
    }
  }

  /// Tells the user when a Shorebird patch has been downloaded and needs a restart.
  Future<void> _checkPatch() async {
    try {
      final updater = ShorebirdUpdater();
      if (!updater.isAvailable) return;
      var status = await updater.checkForUpdate();
      if (status == UpdateStatus.outdated) {
        await updater.update();
        status = await updater.checkForUpdate();
      }
      final context = _context;
      if (status == UpdateStatus.restartRequired && context != null && context.mounted) {
        showSnackBar(
          context,
          'An update is ready: close and reopen Knightly to use it.',
          type: SnackBarType.info,
        );
      }
    } catch (e, st) {
      _logger.warning('Could not check for a patch', e, st);
    }
  }
}
