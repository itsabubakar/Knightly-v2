import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:lichess_mobile/src/model/study_tracker/study_tracker.dart';
import 'package:lichess_mobile/src/view/study_tracker/study_timer_pill.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';

void main() {
  testWidgets('the pill shows above the navigator, as in the app', (tester) async {
    final timer = StudyTimer(
      mode: StudyMode.countdown,
      category: Discipline.openings,
      startedAt: DateTime.now(),
      planned: const Duration(minutes: 20),
      study: (id: const StudyId('abcd1234'), name: 'Caro-Kann repertoire'),
    );
    final app = await makeTestProviderScope(
      tester,
      defaultPreferences: {kStudyTimerStorageKey: jsonEncode(timer.toJson())},
      // Like `MaterialApp.builder` in app.dart: outside the navigator and its overlay.
      child: MaterialApp(
        builder: (context, child) => Stack(children: [child!, const StudyTimerPill()]),
        home: const Scaffold(body: Text('A screen')),
      ),
    );
    await tester.pumpWidget(app);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('A screen'), findsOneWidget);
    // Small at first: only the clock.
    expect(find.text('Caro-Kann repertoire'), findsNothing);
    expect(find.bySemanticsLabel('Pause'), findsNothing);

    // Dragged up, out of the way.
    final before = tester.getCenter(find.byIcon(Symbols.timer));
    await tester.drag(find.byIcon(Symbols.timer), const Offset(0, -200));
    await tester.pump();
    expect(tester.getCenter(find.byIcon(Symbols.timer)).dy, lessThan(before.dy - 150));

    await tester.tap(find.byIcon(Symbols.timer));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Caro-Kann repertoire'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Make the timer smaller'));
    await tester.pump();
    expect(find.text('Caro-Kann repertoire'), findsNothing);

    // Ends the pill's ticker.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
