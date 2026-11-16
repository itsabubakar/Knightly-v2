import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/view/progress/progress_tab_screen.dart';

import '../../test_provider_scope.dart';

void main() {
  testWidgets('asks to sign in when signed out', (tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const ProgressTabScreen());
    await tester.pumpWidget(app);
    await tester.pump();

    expect(find.textContaining('Sign in to see your ratings'), findsOneWidget);
  });
}
