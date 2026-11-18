import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake lichess Board API: the stream lines are pushed by the test, the POSTs are recorded.
class FakeBoardApi() {
  /// The lines of `/api/board/game/stream/<id>`.
  final gameLines = StreamController<Map<String, dynamic>>();

  /// The lines of `/api/stream/event`.
  final eventLines = StreamController<Map<String, dynamic>>.broadcast();

  /// The paths of the POST requests, with their form body.
  final posts = <(String, String)>[];

  /// The JSON answers of GET requests, by path (others are 404s).
  final getResponses = <String, Object>{};

  /// The JSON answers of POST requests, by path.
  final postResponses = <String, Map<String, dynamic>>{};

  http.Client client() => MockClient.streaming((request, bodyStream) async {
    final path = request.url.path;
    if (path.startsWith('/api/board/game/stream/')) {
      return http.StreamedResponse(_ndjson(gameLines.stream), 200);
    }
    if (path == '/api/stream/event') {
      return http.StreamedResponse(_ndjson(eventLines.stream), 200);
    }
    if (request.method == 'POST') {
      posts.add((path, await bodyStream.bytesToString()));
      final json = postResponses[path] ?? {'ok': true};
      return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(json))), 200);
    }
    if (getResponses[path] case final json?) {
      return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(json))), 200);
    }
    return http.StreamedResponse(Stream.value(utf8.encode('')), 404);
  });

  Stream<List<int>> _ndjson(Stream<Map<String, dynamic>> lines) =>
      lines.map((line) => utf8.encode('${jsonEncode(line)}\n'));

  /// Closes the streams; not awaited: closing a stream nobody listened to never completes.
  void close() {
    unawaited(gameLines.close());
    unawaited(eventLines.close());
  }
}

/// A `gameFull` line of a Rapid 10+5 game, or of a correspondence game with [daysPerTurn]; white is
/// the test user.
Map<String, dynamic> gameFullJson({
  String id = 'abcdefgh',
  String moves = '',
  String whiteId = 'testuser',
  String blackId = 'opponent',
  String status = 'started',
  int? daysPerTurn,
  int wtime = 600000,
  int btime = 600000,
}) => {
  'type': 'gameFull',
  'id': id,
  'rated': true,
  'variant': {'key': 'standard', 'name': 'Standard'},
  if (daysPerTurn == null) 'clock': {'initial': 600000, 'increment': 5000},
  'daysPerTurn': ?daysPerTurn,
  'speed': daysPerTurn == null ? 'rapid' : 'correspondence',
  'initialFen': 'startpos',
  'white': {'id': whiteId, 'name': whiteId, 'rating': 1500},
  'black': {'id': blackId, 'name': blackId, 'rating': 1550, 'title': 'FM'},
  'state': gameStateJson(moves: moves, status: status, wtime: wtime, btime: btime),
};

/// A `gameState` line.
Map<String, dynamic> gameStateJson({
  String moves = '',
  String status = 'started',
  String? winner,
  int wtime = 600000,
  int btime = 600000,
  bool bdraw = false,
  bool btakeback = false,
}) => {
  'type': 'gameState',
  'moves': moves,
  'wtime': wtime,
  'btime': btime,
  'winc': 5000,
  'binc': 5000,
  'status': status,
  'winner': ?winner,
  'wdraw': false,
  'bdraw': bdraw,
  'wtakeback': false,
  'btakeback': btakeback,
};

/// A `gameStart` line of the event stream.
Map<String, dynamic> gameStartJson({
  String id = 'abcdefgh',
  String source = 'lobby',
  String speed = 'rapid',
  bool hasMoved = false,
}) => {
  'type': 'gameStart',
  'game': {
    'gameId': id,
    'fullId': '${id}wxyz',
    'color': 'white',
    'speed': speed,
    'source': source,
    'hasMoved': hasMoved,
  },
};

/// A challenge as lichess sends it, from [challengerId] to [destId]; [rematchOf] makes it a rematch
/// offer.
Map<String, dynamic> challengeJson({
  String id = 'H9fIRZUk',
  String challengerId = 'opponent',
  String destId = 'testuser',
  String? rematchOf,
}) => {
  'id': id,
  'url': 'https://lichess.org/$id',
  'status': 'created',
  'challenger': {'id': challengerId, 'name': challengerId, 'rating': 1550},
  'destUser': {'id': destId, 'name': destId, 'rating': 1500},
  'variant': {'key': 'standard', 'name': 'Standard', 'short': 'Std'},
  'rated': true,
  'speed': 'rapid',
  'timeControl': {'type': 'clock', 'limit': 600, 'increment': 5, 'show': '10+5'},
  'color': 'random',
  'direction': 'in',
  'rematchOf': ?rematchOf,
};
