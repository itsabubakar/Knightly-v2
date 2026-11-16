import 'dart:async';
import 'dart:convert';

import 'package:dartchess/dartchess.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show Request;
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/network/http.dart';

/// Knightly plays live games through lichess's Board API (https://lichess.org/api#tag/Board):
/// the official app's game websocket only accepts the official app's login.
final boardApiRepositoryProvider = Provider<BoardApiRepository>((Ref ref) {
  return BoardApiRepository(ref.watch(lichessClientProvider));
}, name: 'BoardApiRepositoryProvider');

/// An event of the user's event stream (`/api/stream/event`).
sealed class const BoardEvent();

/// A game of the user started (or was already going on when the stream connected).
class const BoardGameStarted({
  required final GameId id,
  required final GameFullId fullId,
  required final Side color,
  required final String speed,
  required final String source,
  required final bool hasMoved,
}) extends BoardEvent {
  bool get isRealTime => speed != 'correspondence';

  factory fromJson(Map<String, dynamic> json) {
    final game = pick(json, 'game').required();
    return BoardGameStarted(
      id: GameId(game('gameId').asStringOrThrow()),
      fullId: GameFullId(game('fullId').asStringOrThrow()),
      color: game('color').asStringOrThrow() == 'black' ? Side.black : Side.white,
      speed: game('speed').asStringOrNull() ?? 'rapid',
      source: game('source').asStringOrNull() ?? '',
      hasMoved: game('hasMoved').asBoolOrNull() ?? false,
    );
  }
}

/// A game of the user finished.
class const BoardGameFinished(final GameId id) extends BoardEvent;

/// A challenge was created, by the user or for the user.
class const BoardChallengeCreated(final Challenge challenge) extends BoardEvent;

/// A challenge was canceled by its challenger.
class const BoardChallengeCanceled(final ChallengeId id) extends BoardEvent;

/// A challenge was declined.
class const BoardChallengeDeclined(final Challenge challenge) extends BoardEvent;

/// Parses an event of the event stream, or null for the event types Knightly doesn't use.
BoardEvent? parseBoardEvent(Map<String, dynamic> json) {
  switch (json['type']) {
    case 'gameStart':
      return BoardGameStarted.fromJson(json);
    case 'gameFinish':
      final game = pick(json, 'game').required();
      return BoardGameFinished(GameId(game('gameId').asStringOrThrow()));
    case 'challenge':
      return BoardChallengeCreated(Challenge.fromServerJson(_challengeJson(json)));
    case 'challengeCanceled':
      return BoardChallengeCanceled(ChallengeId(_challengeJson(json)['id'] as String));
    case 'challengeDeclined':
      return BoardChallengeDeclined(Challenge.fromServerJson(_challengeJson(json)));
  }
  return null;
}

Map<String, dynamic> _challengeJson(Map<String, dynamic> json) =>
    (json['challenge'] as Map<String, dynamic>?) ?? json;

class const BoardApiRepository(final LichessClient client) {
  /// Opens an nd-json stream: one JSON object per line, empty lines (keep alive) skipped.
  ///
  /// Cancelling the subscription closes the connection.
  Future<Stream<Map<String, dynamic>>> openStream(
    String method,
    String path, {
    Map<String, String>? body,
  }) async {
    final url = lichessUri(path);
    final request = Request(method, url)..headers['Accept'] = 'application/x-ndjson';
    if (body != null) request.bodyFields = body;
    final response = await client.send(request);
    if (response.statusCode >= 400) {
      final text = await response.stream.bytesToString();
      Map<String, dynamic>? jsonError;
      try {
        jsonError = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {}
      throw ServerException(
        response.statusCode,
        'Request to $url failed with status ${response.statusCode}',
        url,
        jsonError,
      );
    }
    return response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>);
  }

  /// The user's events: games starting and finishing, challenges.
  Future<Stream<BoardEvent>> streamEvents() async {
    final stream = await openStream('GET', '/api/stream/event');
    return stream.map(parseBoardEvent).where((e) => e != null).cast<BoardEvent>();
  }

  /// The state of a game: a `gameFull` first, then `gameState`, `chatLine` and `opponentGone`.
  Future<Stream<Map<String, dynamic>>> streamGame(GameId id) =>
      openStream('GET', '/api/board/game/stream/$id');

  Future<void> move(GameId id, String uci, {bool offeringDraw = false}) =>
      _post('/api/board/game/$id/move/$uci', query: offeringDraw ? {'offeringDraw': 'true'} : null);

  Future<void> abort(GameId id) => _post('/api/board/game/$id/abort');

  Future<void> resign(GameId id) => _post('/api/board/game/$id/resign');

  /// Offers or accepts a draw ([accept] true), or declines one.
  Future<void> draw(GameId id, {required bool accept}) =>
      _post('/api/board/game/$id/draw/${accept ? 'yes' : 'no'}');

  /// Proposes or accepts a takeback ([accept] true), or declines or cancels one.
  Future<void> takeback(GameId id, {required bool accept}) =>
      _post('/api/board/game/$id/takeback/${accept ? 'yes' : 'no'}');

  Future<void> claimVictory(GameId id) => _post('/api/board/game/$id/claim-victory');

  Future<void> claimDraw(GameId id) => _post('/api/board/game/$id/claim-draw');

  Future<void> berserk(GameId id) => _post('/api/board/game/$id/berserk');

  Future<void> chat(GameId id, String text) =>
      _post('/api/board/game/$id/chat', body: {'room': 'player', 'text': text});

  /// Starts a game against the lichess AI (Stockfish, [level] 1 to 8); returns its id.
  Future<GameId> challengeAi({
    required int level,
    ({Duration time, Duration increment})? clock,
    int? days,
    Side? color,
  }) async {
    final json = await client.postReadJson(
      Uri(path: '/api/challenge/ai'),
      body: {
        'level': '$level',
        if (clock != null) 'clock.limit': '${clock.time.inSeconds}',
        if (clock != null) 'clock.increment': '${clock.increment.inSeconds}',
        if (days != null) 'days': '$days',
        if (color != null) 'color': color.name,
      },
      mapper: (json) => json,
    );
    return GameId(json['id'] as String);
  }

  /// Creates a challenge kept alive while the stream is listened to (a real-time challenge
  /// expires after 20 seconds otherwise).
  ///
  /// The first line is the challenge, the last one `{"done": "accepted"}` (or `declined`,
  /// `canceled`).
  Future<Stream<Map<String, dynamic>>> createKeptAliveChallenge(
    UserId destUser,
    Map<String, String> body,
  ) => openStream('POST', '/api/challenge/$destUser', body: {...body, 'keepAliveStream': 'true'});

  /// Seeks a real-time opponent: the seek lasts while the stream is listened to. The game start
  /// comes through the event stream.
  Future<Stream<Map<String, dynamic>>> seek(Map<String, String> body) =>
      openStream('POST', '/api/board/seek', body: body);

  /// Creates a correspondence seek (it stays in the lobby without a connection).
  Future<void> seekCorrespondence(Map<String, String> body) async {
    await client.postRead(Uri(path: '/api/board/seek'), body: body);
  }

  Future<void> _post(String path, {Map<String, String>? query, Map<String, String>? body}) async {
    await client.postRead(
      Uri(path: path, queryParameters: query),
      body: body,
    );
  }
}

/// Whether games are played through the Board API (Knightly), or through the official app's
/// websocket (lichess's code, still tested by its own tests, which override this to false).
final useBoardApiProvider = Provider<bool>((Ref ref) => true, name: 'UseBoardApiProvider');
