import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/view/progress/progress_tab_screen.dart';
import 'package:lichess_mobile/src/view/progress/recent_form_card.dart';
import 'package:material_ui/material_ui.dart';

import '../../mock_server_responses.dart';
import '../../model/auth/fake_auth_storage.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

void main() {
  testWidgets('asks to sign in when signed out', (tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const ProgressTabScreen());
    await tester.pumpWidget(app);
    await tester.pump();

    expect(find.textContaining('Sign in to see your ratings'), findsOneWidget);
    expect(find.byType(RecentFormCard), findsNothing);
  });

  testWidgets('shows the recent form of the signed in user', (tester) async {
    final mockClient = MockClient((request) {
      if (request.url.path == '/api/games/user/testuser') {
        return mockResponse(mockUserRecentGameResponse('testUser'), 200);
      }
      return mockResponse('', 404);
    });
    final app = await makeTestProviderScopeApp(
      tester,
      home: const ProgressTabScreen(),
      authUser: fakeAuthUser,
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => mockClient),
        ),
      },
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    // Below the journey and achievements cards.
    await tester.scrollUntilVisible(
      find.byType(RecentFormCard),
      300,
      // The screen's list, the first vertical scrollable (the achievements grid is inside it).
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .first,
    );

    expect(find.byType(RecentFormCard), findsOneWidget);
    expect(
      find.descendant(of: find.byType(RecentFormCard), matching: find.textContaining('Last ')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(RecentFormCard), matching: find.textContaining('% score')),
      findsOneWidget,
    );
  });
}
