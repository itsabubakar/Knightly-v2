import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:lichess_mobile/src/widgets/pgn.dart';
import 'package:material_ui/material_ui.dart';

import '../test_provider_scope.dart';

/// 1. e4 e5, with the computer's comment and the user's on 1. e4.
ViewRoot _tree() {
  final root = Root.fromPgnGame(PgnGame.parsePgn('1. e4 e5 *'));
  final e4 = root.mainline.first;
  e4.lichessAnalysisComments = [const PgnComment(text: 'Inaccuracy. d4 was best.')];
  e4.comments = [const PgnComment(text: 'I wanted to play the Italian')];
  return root.view;
}

Future<void> _show(
  WidgetTester tester, {
  required bool showComments,
  required bool? showUserComments,
}) async {
  final app = await makeTestProviderScopeApp(
    tester,
    home: Scaffold(
      body: SingleChildScrollView(
        child: DebouncedPgnTreeView(
          root: _tree(),
          currentPath: UciPath.empty,
          pgnRootComments: null,
          shouldShowComments: showComments,
          shouldShowUserComments: showUserComments,
        ),
      ),
    ),
  );
  await tester.pumpWidget(app);
}

bool _shows(WidgetTester tester, String text) =>
    find.textContaining(text, findRichText: true).evaluate().isNotEmpty;

void main() {
  testWidgets("the user's comments are apart from the computer's, with their own switch", (
    tester,
  ) async {
    await _show(tester, showComments: true, showUserComments: true);
    expect(_shows(tester, 'd4 was best'), isTrue);
    expect(_shows(tester, 'the Italian'), isTrue);
    // The user's comment is marked with a pen.
    expect(find.byIcon(Icons.edit_note), findsOneWidget);

    // The computer's comments hidden: the user's stay.
    await _show(tester, showComments: false, showUserComments: true);
    expect(_shows(tester, 'd4 was best'), isFalse);
    expect(_shows(tester, 'the Italian'), isTrue);

    // The user's hidden: the computer's stay.
    await _show(tester, showComments: true, showUserComments: false);
    expect(_shows(tester, 'd4 was best'), isTrue);
    expect(_shows(tester, 'the Italian'), isFalse);
  });

  testWidgets('without a switch of their own, all the comments are the same', (tester) async {
    await _show(tester, showComments: true, showUserComments: null);
    expect(_shows(tester, 'the Italian'), isTrue);
    expect(find.byIcon(Icons.edit_note), findsNothing);

    await _show(tester, showComments: false, showUserComments: null);
    expect(_shows(tester, 'd4 was best'), isFalse);
    expect(_shows(tester, 'the Italian'), isFalse);
  });
}
