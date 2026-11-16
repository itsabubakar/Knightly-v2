import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/knightly/knightly_backup.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/utils/share.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// Picks the backup file to restore. Can be overridden in tests.
final pickBackupFileProvider = Provider<Future<PlatformFile?> Function()>((ref) {
  return () => FilePicker.pickFile();
});

/// Exports Knightly's own data to a file, and restores it from a file or an automatic backup.
class const BackupScreen({super.key}) extends ConsumerWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const BackupScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoBackups = ref.watch(autoBackupsProvider);
    return PlatformScaffold(
      appBar: const PlatformAppBar(title: Text('Backup & restore')),
      body: ListView(
        children: [
          const Padding(
            padding: Styles.bodySectionPadding,
            child: Text(
              "Knightly's own data (bookmarks, changed settings, and soon XP, achievements, streak, "
              'tags and study sessions) is kept only on this phone. Export it to keep a copy: '
              'uninstalling the app or clearing its data deletes it.',
            ),
          ),
          ListSection(
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Export a backup'),
                subtitle: const Text('Save or send the backup file anywhere'),
                onTap: () => _export(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.restore_page_outlined),
                title: const Text('Restore from a file'),
                subtitle: const Text('Replaces all of Knightly’s data on this phone'),
                onTap: () => _restoreFromFile(context, ref),
              ),
            ],
          ),
          ListSection(
            header: const Text('Automatic backups'),
            hasLeading: true,
            children: switch (autoBackups) {
              AsyncData(value: final backups) when backups.isEmpty => [
                const ListTile(title: Text('None yet: one is made every week.')),
              ],
              AsyncData(value: final backups) => [
                for (final backup in backups)
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(_formatDate(backup.date)),
                    trailing: const Text('Restore'),
                    onTap: () => _confirmAndRestore(
                      context,
                      ref,
                      () => ref.read(knightlyBackupProvider).readBackupFile(backup.file.path),
                    ),
                  ),
              ],
              AsyncError() => [const ListTile(title: Text('Could not list the backups.'))],
              _ => [const ListTile(title: Text('Loading…'))],
            },
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ref.read(knightlyBackupProvider).exportToFile();
      if (!context.mounted) return;
      await launchShareDialog(
        context,
        ShareParams(files: [XFile(file.path, mimeType: 'application/json')]),
      );
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context, 'Could not export the backup: $e', type: SnackBarType.error);
      }
    }
  }

  Future<void> _restoreFromFile(BuildContext context, WidgetRef ref) async {
    final picked = await ref.read(pickBackupFileProvider)();
    final path = picked?.path;
    if (path == null || !context.mounted) return;
    await _confirmAndRestore(
      context,
      ref,
      () => ref.read(knightlyBackupProvider).readBackupFile(path),
    );
  }

  Future<void> _confirmAndRestore(
    BuildContext context,
    WidgetRef ref,
    Future<Map<String, dynamic>> Function() readBackup,
  ) async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => PlatformAlertDialog(
        title: const Text('Restore this backup?'),
        content: const Text(
          "All of Knightly's data on this phone is replaced by the backup's. This can't be undone.",
        ),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          PlatformDialogAction(
            cupertinoIsDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(knightlyBackupProvider).restore(await readBackup());
      if (context.mounted) showSnackBar(context, 'Backup restored.');
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context, 'Could not restore: $e', type: SnackBarType.error);
      }
    }
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
