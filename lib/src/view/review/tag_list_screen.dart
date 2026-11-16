import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/review/game_tags.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The tag list: rename or remove tags, add your own, bring back the starter ones.
class const TagListScreen({super.key}) extends ConsumerWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const TagListScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagListProvider);
    final tagList = ref.read(tagListProvider.notifier);
    return PlatformScaffold(
      appBar: const PlatformAppBar(title: Text('Tags')),
      body: ListView(
        children: [
          for (final kind in TagKind.values)
            ListSection(
              header: Text(kind.label),
              children: [
                for (final tag in tags.where((tag) => tag.kind == kind))
                  ListTile(
                    title: Text(tag.label),
                    onTap: () => _editTag(
                      context,
                      title: 'Rename tag',
                      kind: kind,
                      initial: tag.label,
                    ).then((label) => label != null ? tagList.rename(tag.id, label) : null),
                    trailing: IconButton(
                      tooltip: 'Remove ${tag.label}',
                      icon: const Icon(Symbols.delete),
                      onPressed: () => tagList.remove(tag.id),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Symbols.add),
                  title: Text('Add a tag to ${kind.label.toLowerCase()}'),
                  onTap: () => _editTag(context, title: 'New tag', kind: kind).then((label) {
                    if (label != null) tagList.add(label, kind);
                  }),
                ),
              ],
            ),
          ListSection(
            children: [
              ListTile(
                leading: const Icon(Symbols.restart_alt),
                title: const Text('Restore the starter tags'),
                subtitle: const Text('Keeps your own tags'),
                onTap: tagList.restoreStarterTags,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Asks for a tag name; null if cancelled.
  Future<String?> _editTag(
    BuildContext context, {
    required String title,
    required TagKind kind,
    String? initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showAdaptiveDialog<String>(
      context: context,
      builder: (context) => PlatformAlertDialog(
        title: Text(title),
        content: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: kind == .mistake ? 'e.g. Rushed move' : null),
          ),
        ),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          PlatformDialogAction(
            cupertinoIsDefaultAction: true,
            onPressed: () {
              final label = controller.text.trim();
              Navigator.of(context).pop(label.isEmpty ? null : label);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}
