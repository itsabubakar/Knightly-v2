import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/binding/binding.dart';
import 'package:lichess_mobile/src/model/study/study_bookmarks.dart';
import 'package:lichess_mobile/src/model/study_tracker/study_tracker.dart';
import 'package:lichess_mobile/src/view/study/study_bookmarks_view.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';

final _bookmarks = jsonEncode([
  {
    'id': 'abcd1234',
    'name': 'Endgame essentials',
    'ownerName': 'Coach',
    'nbChapters': 12,
    'bookmarkedAt': '2026-11-16T10:00:00.000',
  },
  {
    'id': 'efgh5678',
    'name': 'Caro-Kann repertoire',
    'ownerName': null,
    'nbChapters': 5,
    'bookmarkedAt': '2026-11-15T10:00:00.000',
  },
]);

void main() {
  testWidgets('lists the bookmarked studies and removes a bookmark', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const BookmarkedStudiesScreen(),
      defaultPreferences: {kStudyBookmarksStorageKey: _bookmarks},
    );
    await tester.pumpWidget(app);

    expect(find.text('Endgame essentials'), findsOneWidget);
    expect(find.text('Caro-Kann repertoire'), findsOneWidget);
    expect(find.text('Coach · 12 Chapters'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove bookmark').first);
    await tester.pump();

    expect(find.text('Endgame essentials'), findsNothing);
    expect(find.text('Caro-Kann repertoire'), findsOneWidget);
    // The removal is saved.
    final stored = LichessBinding.instance.sharedPreferences.getString(kStudyBookmarksStorageKey);
    expect(stored, isNot(contains('Endgame essentials')));
  });

  testWidgets('the Home section shows nothing without bookmarks', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const Scaffold(body: BookmarkedStudiesSection()),
    );
    await tester.pumpWidget(app);

    expect(find.text('Bookmarked studies'), findsNothing);
  });

  testWidgets('the Home section shows at most the latest bookmarks', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const Scaffold(body: BookmarkedStudiesSection(maxItems: 1)),
      defaultPreferences: {kStudyBookmarksStorageKey: _bookmarks},
    );
    await tester.pumpWidget(app);

    expect(find.text('Bookmarked studies'), findsOneWidget);
    expect(find.text('Endgame essentials'), findsOneWidget);
    expect(find.text('Caro-Kann repertoire'), findsNothing);
  });

  testWidgets('a bookmarked study starts a study timer, countdown or stopwatch', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const BookmarkedStudiesScreen(),
      defaultPreferences: {kStudyBookmarksStorageKey: _bookmarks},
    );
    await tester.pumpWidget(app);

    await tester.tap(find.byTooltip('Start a study timer').first);
    await tester.pumpAndSettle();
    expect(find.text('Study timer'), findsOneWidget);
    expect(find.text('Countdown'), findsOneWidget);

    await tester.tap(find.text('Stopwatch'));
    await tester.pump();
    await tester.tap(find.text('Start studying'));
    await tester.pump();

    final stored = LichessBinding.instance.sharedPreferences.getString(kStudyTimerStorageKey)!;
    final timer = StudyTimer.fromJson(jsonDecode(stored) as Map<String, dynamic>);
    expect(timer.mode, StudyMode.stopwatch);
    expect(timer.study?.name, 'Endgame essentials');

    // The study opens; leave it before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
