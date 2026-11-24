import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/knightly/knightly_backup.dart';
import 'package:lichess_mobile/src/tab_navigation.dart' show currentNavigatorKeyProvider;
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

final _logger = Logger('BackupRestoreService');

/// After a reinstall, offers to restore Knightly's data from the newest daily backup, which
/// Android put back with the app (its own backup to the user's Google account takes Knightly's
/// backup files, see `res/xml/backup_rules.xml`).
final backupRestoreServiceProvider = Provider<BackupRestoreService>(
  BackupRestoreService.new,
  name: 'BackupRestoreServiceProvider',
);

class BackupRestoreService(final Ref ref) {
  Timer? _timer;

  /// Looks for a backup to restore at the start (release builds), before the progression's sync adds
  /// data of its own, and asks a moment later, once the app shows.
  void start() {
    if (!kReleaseMode) return;
    final found = ref.read(knightlyBackupProvider).backupToRestore();
    _timer = Timer(const Duration(seconds: 3), () => unawaited(offerRestore(found)));
    ref.onDispose(() => _timer?.cancel());
  }

  /// Asks whether to restore the backup Android brought back ([found], see
  /// [KnightlyBackup.backupToRestore]).
  Future<void> offerRestore(Future<AutoBackup?> found) async {
    final backup = await found;
    final context = ref.read(currentNavigatorKeyProvider).currentContext;
    if (backup == null || context == null || !context.mounted) return;
    final restore = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => PlatformAlertDialog(
        title: const Text('Restore your Knightly data?'),
        content: Text(
          'A backup from ${DateFormat.yMMMd().add_jm().format(backup.date)} was found: your XP, '
          'streak, achievements, mistake puzzles, study time and tags. Restore it?',
        ),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          PlatformDialogAction(
            cupertinoIsDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (restore != true) return;
    final backups = ref.read(knightlyBackupProvider);
    try {
      await backups.restore(await backups.readBackupFile(backup.file.path));
      final context = ref.read(currentNavigatorKeyProvider).currentContext;
      if (context != null && context.mounted) {
        showSnackBar(context, 'Your Knightly data is back.', type: SnackBarType.success);
      }
    } catch (e, st) {
      _logger.warning('Could not restore the backup', e, st);
      final context = ref.read(currentNavigatorKeyProvider).currentContext;
      if (context != null && context.mounted) {
        showSnackBar(context, 'The backup could not be restored.', type: SnackBarType.error);
      }
    }
  }
}
