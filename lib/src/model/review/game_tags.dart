import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding/binding.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';

/// Storage key of the tag list, a JSON list of [GameTag]s (backed up with Knightly's data).
const kTagListStorageKey = 'knightly.tagList';

/// Whether a tag marks a mistake or a good decision.
enum TagKind(final String label) {
  mistake('Mistakes'),
  good('Good decisions'),
}

/// A tag to put on a move.
@immutable
class const GameTag({
  required final String id,
  required final String label,
  required final TagKind kind,

  /// The discipline whose XP the tag earns, if any.
  final Discipline? discipline,
}) {
  factory fromJson(Map<String, dynamic> json) => GameTag(
    id: json['id'] as String,
    label: json['label'] as String,
    kind: TagKind.values.byName(json['kind'] as String),
    discipline: json['discipline'] != null
        ? Discipline.values.byName(json['discipline'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.name,
    'discipline': discipline?.name,
  };

  GameTag copyWith({String? label}) =>
      GameTag(id: id, label: label ?? this.label, kind: kind, discipline: discipline);

  @override
  bool operator ==(Object other) =>
      other is GameTag &&
      other.id == id &&
      other.label == label &&
      other.kind == kind &&
      other.discipline == discipline;

  @override
  int get hashCode => Object.hash(id, label, kind, discipline);
}

/// The tags a new tag list starts with.
const kStarterTags = [
  GameTag(id: 'hanging_piece', label: 'Hanging piece', kind: .mistake, discipline: .tactics),
  GameTag(id: 'missed_tactic', label: 'Missed tactic', kind: .mistake, discipline: .tactics),
  GameTag(
    id: 'calculation_error',
    label: 'Calculation error',
    kind: .mistake,
    discipline: .tactics,
  ),
  GameTag(id: 'time_trouble', label: 'Time trouble', kind: .mistake),
  GameTag(id: 'opening_mistake', label: 'Opening mistake', kind: .mistake, discipline: .openings),
  GameTag(
    id: 'endgame_technique',
    label: 'Endgame technique',
    kind: .mistake,
    discipline: .endgames,
  ),
  GameTag(id: 'positional_error', label: 'Positional error', kind: .mistake, discipline: .strategy),
  GameTag(id: 'good_move', label: 'Good move', kind: .good, discipline: .tactics),
  GameTag(id: 'good_plan', label: 'Good plan', kind: .good, discipline: .strategy),
];

/// The tag list: the starter tags, renamed or removed, and the user's own.
final tagListProvider = NotifierProvider<TagList, IList<GameTag>>(
  TagList.new,
  name: 'TagListProvider',
);

/// The stored tag list, or the starter tags.
IList<GameTag> readStoredTagList() {
  final stored = LichessBinding.instance.sharedPreferences.getString(kTagListStorageKey);
  if (stored == null) return kStarterTags.toIList();
  try {
    return (jsonDecode(stored) as List<dynamic>)
        .map((json) => GameTag.fromJson(json as Map<String, dynamic>))
        .toIList();
  } catch (e) {
    debugPrint('[TagList] Error reading the tag list: $e');
    return kStarterTags.toIList();
  }
}

class TagList() extends Notifier<IList<GameTag>> {
  @override
  IList<GameTag> build() => readStoredTagList();

  /// The tag with [id], also once removed from the list (its moves keep it).
  GameTag? byId(String id) =>
      state.firstWhereOrNull((tag) => tag.id == id) ??
      kStarterTags.firstWhereOrNull((tag) => tag.id == id);

  Future<void> add(String label, TagKind kind) => _save(
    state.add(
      GameTag(id: 'custom_${DateTime.now().millisecondsSinceEpoch}', label: label, kind: kind),
    ),
  );

  Future<void> rename(String id, String label) =>
      _save(state.map((tag) => tag.id == id ? tag.copyWith(label: label) : tag).toIList());

  Future<void> remove(String id) => _save(state.removeWhere((tag) => tag.id == id));

  /// Brings back the starter tags, keeping the user's own.
  Future<void> restoreStarterTags() => _save(
    [
      ...kStarterTags,
      ...state.where((tag) => !kStarterTags.any((starter) => starter.id == tag.id)),
    ].toIList(),
  );

  Future<void> _save(IList<GameTag> tags) async {
    state = tags;
    await LichessBinding.instance.sharedPreferences.setString(
      kTagListStorageKey,
      jsonEncode(tags.map((tag) => tag.toJson()).toList()),
    );
  }
}
