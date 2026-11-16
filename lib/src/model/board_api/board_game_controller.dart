import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:logging/logging.dart';

part 'board_game_controller.freezed.dart';

/// A live game of the user, played through the Board API.
final boardGameControllerProvider = AsyncNotifierProvider.autoDispose
    .family<BoardGameController, BoardGameState, GameId>(
      BoardGameController.new,
      name: 'BoardGameControllerProvider',
    );

/// A player of a Board API game.
class const BoardPlayer({
  final UserId? id,
  required final String name,
  final String? title,
  final int? rating,
  final bool provisional = false,
  final int? aiLevel,
}) {
  factory fromJson(Map<String, dynamic>? json) {
    final p = pick(json);
    final aiLevel = p('aiLevel').asIntOrNull();
    if (aiLevel != null) return BoardPlayer(name: 'Stockfish level $aiLevel', aiLevel: aiLevel);
    final id = p('id').asStringOrNull();
    return BoardPlayer(
      id: id != null ? UserId(id) : null,
      name: p('name').asStringOrNull() ?? id ?? 'Anonymous',
      title: p('title').asStringOrNull(),
      rating: p('rating').asIntOrNull(),
      provisional: p('provisional').asBoolOrNull() ?? false,
    );
  }
}

/// A chat message of a Board API game.
typedef BoardChatLine = ({String username, String text});

/// The game statuses lichess sends while the game is not over.
const _ongoingStatuses = {'created', 'started'};

@freezed
sealed class const BoardGameState._() with _$BoardGameState {
  const factory({
    required GameId id,
    required bool rated,
    required String speed,
    required Variant variant,
    required BoardPlayer white,
    required BoardPlayer black,

    /// The side of the user, null when the user doesn't play this game.
    required Side? mySide,
    required ({Duration initial, Duration increment})? clock,
    int? daysPerTurn,

    /// The moves as lichess sends them (UCI).
    required IList<String> moves,

    /// The moves in SAN, for the move list.
    required IList<String> sans,

    /// The position before the first move, then after each move.
    required IList<Position> positions,
    Move? lastMove,

    /// The clocks when [clockAt], the running one counting down since.
    Duration? whiteTime,
    Duration? blackTime,
    required DateTime clockAt,
    required String status,
    Side? winner,
    @Default(false) bool whiteOffersDraw,
    @Default(false) bool blackOffersDraw,
    @Default(false) bool whiteProposesTakeback,
    @Default(false) bool blackProposesTakeback,

    /// When the opponent left: the user can claim the victory from then.
    DateTime? canClaimVictoryAt,
    required IList<BoardChatLine> chat,

    /// The move sent to lichess and not confirmed yet.
    String? pendingMove,
  }) = _BoardGameState;

  Position get position => positions.last;

  Side get sideToMove => position.turn;

  bool get isOver => !_ongoingStatuses.contains(status);

  bool get isMyTurn => !isOver && mySide == sideToMove;

  /// Lichess starts the clocks after each side's first move.
  bool get clocksRunning => !isOver && (clock != null || daysPerTurn != null) && moves.length >= 2;

  /// A game can be aborted until both sides have moved.
  bool get canAbort => !isOver && moves.length < 2;

  bool get canResign => !isOver && mySide != null && moves.length >= 2;

  bool get opponentOffersDraw =>
      mySide == Side.white ? blackOffersDraw : mySide == Side.black && whiteOffersDraw;

  bool get iOfferDraw =>
      mySide == Side.white ? whiteOffersDraw : mySide == Side.black && blackOffersDraw;

  bool get opponentProposesTakeback =>
      mySide == Side.white ? blackProposesTakeback : mySide == Side.black && whiteProposesTakeback;

  bool get iProposeTakeback =>
      mySide == Side.white ? whiteProposesTakeback : mySide == Side.black && blackProposesTakeback;

  bool get isAgainstAi => white.aiLevel != null || black.aiLevel != null;

  BoardPlayer player(Side side) => side == Side.white ? white : black;

  /// The time left of [side], counting down while it's its turn.
  Duration? timeLeft(Side side, DateTime now) {
    final time = side == Side.white ? whiteTime : blackTime;
    if (time == null) return null;
    if (!clocksRunning || side != sideToMove || pendingMove != null) return time;
    final left = time - now.difference(clockAt);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Replays [moves] from [initial]: the positions, the SAN moves and the last move.
({IList<Position> positions, IList<String> sans, Move? lastMove}) replayMoves(
  Position initial,
  Iterable<String> moves,
) {
  final positions = <Position>[initial];
  final sans = <String>[];
  Move? lastMove;
  for (final uci in moves) {
    final parsed = Move.parse(uci);
    if (parsed == null) break;
    final position = positions.last;
    final move = parsed is NormalMove ? position.normalizeMove(parsed) : parsed;
    if (!position.isLegal(move)) break;
    final (next, san) = position.makeSan(move);
    positions.add(next);
    sans.add(san);
    lastMove = move;
  }
  return (positions: positions.lock, sans: sans.lock, lastMove: lastMove);
}

/// The move as lichess expects it: castling as the king's two squares move in standard chess.
String boardApiUci(Move move, {required bool isCastling, required Variant variant}) {
  final uci = move.uci;
  if (isCastling && variant != Variant.chess960) return altCastles[uci] ?? uci;
  return uci;
}

class BoardGameController(final GameId gameId) extends AsyncNotifier<BoardGameState> {
  static final _logger = Logger('BoardGameController');

  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _reconnectTimer;
  Completer<void>? _firstState;
  BoardGameState? _latest;
  Position? _initial;

  BoardApiRepository get _repository => ref.read(boardApiRepositoryProvider);

  @override
  Future<BoardGameState> build() async {
    ref.onDispose(() {
      _reconnectTimer?.cancel();
      unawaited(_subscription?.cancel());
    });
    _firstState = Completer<void>();
    await _connect();
    await _firstState!.future;
    return _latest!;
  }

  Future<void> _connect() async {
    try {
      final stream = await _repository.streamGame(gameId);
      if (!ref.mounted) return;
      await _subscription?.cancel();
      _subscription = stream.listen(
        _onMessage,
        onError: (Object e, StackTrace st) => _onDisconnected(e, st),
        onDone: () => _onDisconnected(null, null),
        cancelOnError: true,
      );
    } catch (e, st) {
      _onDisconnected(e, st);
    }
  }

  void _onDisconnected(Object? error, StackTrace? st) {
    if (!ref.mounted) return;
    final first = _firstState;
    if (first != null && !first.isCompleted) {
      first.completeError(error ?? StateError('The game stream closed.'), st);
      return;
    }
    if (_latest?.isOver ?? false) return;
    _logger.info('Game stream closed, reconnecting', error, st);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), _connect);
  }

  void _onMessage(Map<String, dynamic> json) {
    final current = _latest;
    final BoardGameState? next = switch (json['type']) {
      'gameFull' => _fromGameFull(json),
      'gameState' when current != null => _withServerState(current, json),
      'chatLine' when current != null => current.copyWith(
        chat: current.chat.add((
          username: json['username'] as String? ?? '',
          text: json['text'] as String? ?? '',
        )),
      ),
      'opponentGone' when current != null => current.copyWith(
        canClaimVictoryAt: json['gone'] == true
            ? DateTime.now().add(Duration(seconds: (json['claimWinInSeconds'] as int?) ?? 0))
            : null,
      ),
      _ => null,
    };
    if (next == null) return;
    _latest = next;
    final first = _firstState;
    if (first != null && !first.isCompleted) {
      first.complete();
    } else {
      state = AsyncData(next);
    }
  }

  BoardGameState _fromGameFull(Map<String, dynamic> json) {
    final p = pick(json).required();
    final variantKey = p('variant', 'key').asStringOrNull() ?? 'standard';
    final variant = Variant.values.firstWhere(
      (v) => v.name == variantKey,
      orElse: () => Variant.standard,
    );
    final initialFen = p('initialFen').asStringOrNull();
    _initial = initialFen != null && initialFen != 'startpos'
        ? Position.setupPosition(variant.rule, Setup.parseFen(initialFen))
        : variant == Variant.chess960 || variant == Variant.fromPosition
        ? Chess.initial
        : variant.initialPosition;
    final white = BoardPlayer.fromJson(json['white'] as Map<String, dynamic>?);
    final black = BoardPlayer.fromJson(json['black'] as Map<String, dynamic>?);
    final me = ref.read(authControllerProvider)?.user.id;
    final initialMs = p('clock', 'initial').asIntOrNull();
    final incrementMs = p('clock', 'increment').asIntOrNull();
    final base = BoardGameState(
      id: gameId,
      rated: p('rated').asBoolOrNull() ?? false,
      speed: p('speed').asStringOrNull() ?? 'rapid',
      variant: variant,
      white: white,
      black: black,
      mySide: me == null
          ? null
          : white.id == me
          ? Side.white
          : black.id == me
          ? Side.black
          : null,
      clock: initialMs != null && incrementMs != null
          ? (
              initial: Duration(milliseconds: initialMs),
              increment: Duration(milliseconds: incrementMs),
            )
          : null,
      daysPerTurn: p('daysPerTurn').asIntOrNull(),
      moves: const IListConst([]),
      sans: const IListConst([]),
      positions: IList([_initial!]),
      clockAt: DateTime.now(),
      status: 'started',
      chat: const IListConst([]),
    );
    return _withServerState(base, (json['state'] as Map<String, dynamic>?) ?? const {});
  }

  BoardGameState _withServerState(BoardGameState current, Map<String, dynamic> json) {
    final p = pick(json);
    final movesText = p('moves').asStringOrNull() ?? '';
    final moves = movesText.isEmpty ? <String>[] : movesText.split(' ');
    final replay = moves.length == current.moves.length && current.pendingMove == null
        ? (positions: current.positions, sans: current.sans, lastMove: current.lastMove)
        : replayMoves(_initial ?? current.positions.first, moves);
    final winner = p('winner').asStringOrNull();
    // A correspondence game's time left is in `wtime` and `btime` too; an unlimited one's is the
    // largest int.
    final hasClock = current.clock != null || current.daysPerTurn != null;
    final wtime = p('wtime').asIntOrNull().takeIfTimeLeft();
    final btime = p('btime').asIntOrNull().takeIfTimeLeft();
    return current.copyWith(
      moves: moves.lock,
      positions: replay.positions,
      sans: replay.sans,
      lastMove: replay.lastMove,
      whiteTime: hasClock && wtime != null ? Duration(milliseconds: wtime) : null,
      blackTime: hasClock && btime != null ? Duration(milliseconds: btime) : null,
      clockAt: DateTime.now(),
      status: p('status').asStringOrNull() ?? current.status,
      winner: winner == 'white'
          ? Side.white
          : winner == 'black'
          ? Side.black
          : null,
      whiteOffersDraw: p('wdraw').asBoolOrNull() ?? false,
      blackOffersDraw: p('bdraw').asBoolOrNull() ?? false,
      whiteProposesTakeback: p('wtakeback').asBoolOrNull() ?? false,
      blackProposesTakeback: p('btakeback').asBoolOrNull() ?? false,
      pendingMove: null,
    );
  }

  /// Plays [move] on the board right away and sends it to lichess.
  Future<void> userMove(Move move) async {
    final current = state.value;
    if (current == null || !current.isMyTurn || current.pendingMove != null) return;
    final position = current.position;
    if (!position.isLegal(move)) return;
    final (next, san) = position.makeSan(move);
    final uci = boardApiUci(move, isCastling: san.startsWith('O-O'), variant: current.variant);
    final played = current.copyWith(
      moves: current.moves.add(uci),
      positions: current.positions.add(next),
      sans: current.sans.add(san),
      lastMove: move,
      pendingMove: uci,
      // The opponent's clock starts now: keep the user's time as it was.
      whiteTime: current.timeLeft(Side.white, DateTime.now()),
      blackTime: current.timeLeft(Side.black, DateTime.now()),
      clockAt: DateTime.now(),
    );
    _latest = played;
    state = AsyncData(played);
    try {
      await _repository.move(gameId, uci);
    } catch (e, st) {
      _logger.warning('Could not play $uci', e, st);
      // Back to the last position lichess confirmed, unless it already sent a newer one.
      if (ref.mounted && _latest?.pendingMove == uci) {
        _latest = current;
        state = AsyncData(current);
      }
      rethrow;
    }
  }

  Future<void> resign() => _repository.resign(gameId);

  Future<void> abort() => _repository.abort(gameId);

  Future<void> offerOrAcceptDraw() => _repository.draw(gameId, accept: true);

  Future<void> declineDraw() => _repository.draw(gameId, accept: false);

  Future<void> proposeOrAcceptTakeback() => _repository.takeback(gameId, accept: true);

  Future<void> declineTakeback() => _repository.takeback(gameId, accept: false);

  Future<void> claimVictory() => _repository.claimVictory(gameId);

  Future<void> sendChat(String text) => _repository.chat(gameId, text);
}

/// The live games on screen, so that a game start from the event stream doesn't open them twice.
final openBoardGamesProvider = Provider<OpenBoardGames>(
  (Ref ref) => OpenBoardGames(),
  name: 'OpenBoardGamesProvider',
);

class OpenBoardGames() {
  final Set<GameId> _ids = {};

  bool contains(GameId id) => _ids.contains(id);

  void add(GameId id) => _ids.add(id);

  void remove(GameId id) => _ids.remove(id);
}

extension on int? {
  /// Null for lichess's "no time limit" value, the largest int.
  int? takeIfTimeLeft() => this == null || this! >= 2147483647 ? null : this;
}
