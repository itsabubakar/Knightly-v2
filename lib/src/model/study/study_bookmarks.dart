import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding/binding.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/study/study.dart';

/// Storage key of the bookmarked studies, a JSON list of [StudyBookmark]s.
const kStudyBookmarksStorageKey = 'knightly.studyBookmarks';

/// A study bookmarked in Knightly, kept on this device.
///
/// Knightly's replacement for lichess's study likes, which it can't save (the study socket only
/// accepts the official app's token) nor list (the favorites page rejects API tokens).
@immutable
class const StudyBookmark({
  required final StudyId id,
  required final String name,
  required final String? ownerName,
  required final int nbChapters,
  required final DateTime bookmarkedAt,
}) {
  factory fromStudy(Study study) => StudyBookmark(
    id: study.id,
    name: study.name,
    ownerName: study.owner?.user.name,
    nbChapters: study.chapters.length,
    bookmarkedAt: DateTime.now(),
  );

  factory fromJson(Map<String, dynamic> json) => StudyBookmark(
    id: StudyId(json['id'] as String),
    name: json['name'] as String,
    ownerName: json['ownerName'] as String?,
    nbChapters: json['nbChapters'] as int,
    bookmarkedAt: DateTime.parse(json['bookmarkedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id.value,
    'name': name,
    'ownerName': ownerName,
    'nbChapters': nbChapters,
    'bookmarkedAt': bookmarkedAt.toIso8601String(),
  };
}

/// The bookmarked studies, most recently bookmarked first.
final studyBookmarksProvider = NotifierProvider<StudyBookmarks, IList<StudyBookmark>>(
  StudyBookmarks.new,
  name: 'StudyBookmarksProvider',
);

class StudyBookmarks() extends Notifier<IList<StudyBookmark>> {
  @override
  IList<StudyBookmark> build() {
    final stored = LichessBinding.instance.sharedPreferences.getString(kStudyBookmarksStorageKey);
    if (stored == null) return const IListConst([]);
    try {
      return (jsonDecode(stored) as List<dynamic>)
          .map((json) => StudyBookmark.fromJson(json as Map<String, dynamic>))
          .toIList();
    } catch (e) {
      debugPrint('[StudyBookmarks] Error reading the bookmarked studies: $e');
      return const IListConst([]);
    }
  }

  bool isBookmarked(StudyId id) => state.any((bookmark) => bookmark.id == id);

  /// Bookmarks [study], or removes its bookmark if it is bookmarked.
  Future<void> toggle(Study study) =>
      isBookmarked(study.id) ? remove(study.id) : _save(state.insert(0, .fromStudy(study)));

  Future<void> remove(StudyId id) => _save(state.removeWhere((bookmark) => bookmark.id == id));

  Future<void> _save(IList<StudyBookmark> bookmarks) async {
    state = bookmarks;
    await LichessBinding.instance.sharedPreferences.setString(
      kStudyBookmarksStorageKey,
      jsonEncode(bookmarks.map((bookmark) => bookmark.toJson()).toList()),
    );
  }
}
