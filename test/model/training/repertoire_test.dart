import 'dart:convert';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/training/repertoire.dart';
import 'package:lichess_mobile/src/model/training/training_cards.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../auth/fake_auth_storage.dart';

Map<String, Object?> _move(String uci, String san, int games) => {
  'uci': uci,
  'san': san,
  'white': games ~/ 3,
  'draws': games ~/ 3,
  'black': games - 2 * (games ~/ 3),
};

/// lichess's explorer: after 1. e4, Black's replies; elsewhere, nothing.
http.Response _explorer(http.Request request) {
  if (request.url.path != '/lichess') return http.Response('', 404);
  final fen = request.url.queryParameters['fen']!;
  final moves = fen.startsWith('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b')
      ? [
          _move('c7c5', 'c5', 900),
          _move('e7e5', 'e5', 800),
          _move('e7e6', 'e6', 400),
          _move('c7c6', 'c6', 300),
        ]
      : <Map<String, Object?>>[];
  return http.Response(
    jsonEncode({'white': 10, 'draws': 10, 'black': 10, 'moves': moves}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  Future<(ProviderContainer, int)> setUpRepertoire({Side side = Side.white}) async {
    final container = await makeContainer(
      authUser: fakeAuthUser,
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => MockClient((request) async => _explorer(request))),
        ),
      },
    );
    final db = await container.read(knightlyDatabaseProvider.future);
    final id = await createRepertoire(db, fakeAuthUser.user.id, name: 'Open games', side: side);
    container.listen(repertoireTreeProvider(id), (_, _) {});
    return (container, id);
  }

  Future<List<Map<String, Object?>>> cards(ProviderContainer container) async {
    final db = await container.read(knightlyDatabaseProvider.future);
    return await db.query('training_card', orderBy: 'id');
  }

  test("the user's move becomes a card, and the opponent's top 3 replies come after it", () async {
    final (container, id) = await setUpRepertoire();
    final notifier = container.read(repertoireTreeProvider(id).notifier);
    await notifier.addMove(const [], Move.parse('e2e4')!);

    final tree = await container.read(repertoireTreeProvider(id).future);
    expect(tree.movesAt(Chess.initial).map((m) => m.san), ['e4']);
    final afterE4 = Chess.initial.play(Move.parse('e2e4')!);
    expect(tree.movesAt(afterE4).map((m) => m.san), unorderedEquals(['c5', 'e5', 'e6']));
    expect((await cards(container)).single['answer'], 'e2e4');

    // The user's move to choose against each reply.
    expect(tree.positionsToFill(), hasLength(3));
    expect(tree.positionsToFill().first.first, 'e2e4');
  });

  test("a new move of the user's replaces the old one, and its line goes", () async {
    final (container, id) = await setUpRepertoire();
    final notifier = container.read(repertoireTreeProvider(id).notifier);
    await notifier.addMove(const [], Move.parse('e2e4')!);
    await notifier.addMove(const ['e2e4', 'c7c5'], Move.parse('g1f3')!);
    expect(await cards(container), hasLength(2));

    await notifier.addMove(const [], Move.parse('d2d4')!);
    final tree = await container.read(repertoireTreeProvider(id).future);
    expect(tree.movesAt(Chess.initial).map((m) => m.san), ['d4']);
    // 1. e4's line can't be reached any more: its moves and cards are gone.
    final afterE4 = Chess.initial.play(Move.parse('e2e4')!);
    expect(tree.movesAt(afterE4), isEmpty);
    expect((await cards(container)).map((c) => c['answer']), ['d2d4']);
  });

  test("removing an opponent's reply removes the user's move after it", () async {
    final (container, id) = await setUpRepertoire();
    final notifier = container.read(repertoireTreeProvider(id).notifier);
    await notifier.addMove(const [], Move.parse('e2e4')!);
    await notifier.addMove(const ['e2e4', 'c7c5'], Move.parse('g1f3')!);
    await notifier.removeMove(const ['e2e4'], 'c7c5');
    expect((await cards(container)).map((c) => c['answer']), ['e2e4']);
  });

  test('as Black: the start is not to do, the first card is the reply to White', () async {
    final (container, id) = await setUpRepertoire(side: Side.black);
    var tree = await container.read(repertoireTreeProvider(id).future);
    expect(tree.positionsToFill(), isEmpty);
    final notifier = container.read(repertoireTreeProvider(id).notifier);
    await notifier.addMove(const [], Move.parse('e2e4')!);
    tree = await container.read(repertoireTreeProvider(id).future);
    expect(tree.positionsToFill(), [
      ['e2e4'],
    ]);
    await notifier.addMove(const ['e2e4'], Move.parse('c7c5')!);
    final card = (await cards(container)).single;
    expect(card['answer'], 'c7c5');
    expect(card['orientation'], 'black');
    expect(card['path'], 'e2e4');
  });

  test('deleting a repertoire deletes its cards', () async {
    final (container, id) = await setUpRepertoire();
    await container
        .read(repertoireTreeProvider(id).notifier)
        .addMove(const [], Move.parse('e2e4')!);
    final db = await container.read(knightlyDatabaseProvider.future);
    await deleteRepertoire(db, fakeAuthUser.user.id, id);
    expect(await cards(container), isEmpty);
    expect((await readTrainingQueue(db, fakeAuthUser.user.id, now: DateTime.now())).fresh, isEmpty);
  });
}
