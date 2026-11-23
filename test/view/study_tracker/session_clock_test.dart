import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:lichess_mobile/src/view/study_tracker/session_clock.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';

void main() {
  test('the time of a session', () {
    expect(formatSessionTime(const Duration(seconds: 8)), '0:08');
    expect(formatSessionTime(const Duration(minutes: 12, seconds: 34)), '12:34');
    expect(formatSessionTime(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  testWidgets('the clock runs from when the screen opens', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const Scaffold(
        body: Center(child: SessionClock(category: Discipline.analysis)),
      ),
    );
    await tester.pumpWidget(app);
    expect(find.text('0:00'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('0:08'), findsOneWidget);
    // Leaving: the clock stops (signed out here: nothing saved).
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
