import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/board_api/board_api.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:lichess_mobile/src/model/common/socket.dart';
import 'package:lichess_mobile/src/model/common/uci.dart';
import 'package:lichess_mobile/src/model/game/game_repository.dart';
import 'package:lichess_mobile/src/model/game/game_socket_events.dart';
import 'package:lichess_mobile/src/model/local_analysis/local_analysis.dart';
import 'package:lichess_mobile/src/model/local_analysis/local_analysis_runner.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:logging/logging.dart';

part 'server_analysis_service.freezed.dart';

final _logger = Logger('ServerAnalysisService');

@freezed
sealed class const ServerAnalysisSource._() with _$ServerAnalysisSource {
  const factory game({required GameId gameId}) = _GameServerAnalysisSource;

  const factory studyChapter({required StudyId studyId, required StudyChapterId chapterId}) =
      _StudyChapterServerAnalysisSource;
}

const Duration kMaxWaitForServerAnalysis = Duration(minutes: 1);

/// Raised when the server refused to start an analysis, carrying the reason.
class ServerAnalysisRequestException(
  /// The reason the server refused.
  final ServerAnalysisRequestError error,

  /// The server's refusal text, shown to the user.
  final String message,
) {
  @override
  String toString() => 'ServerAnalysisRequestException: $error ($message)';
}

/// Why the server refused to start an analysis for a game.
enum ServerAnalysisRequestError() {
  alreadyAnalysed,
  concurrentAnalysis,
  weeklyLimitReached,
  dailyLimitReached,
  dailyIpLimitReached,
  notAnalysable,
  unknown,
}

/// The exact error strings `lila.fishnet.Analyser.Result` sends, keyed by the resulting error.
const _kServerAnalysisRequestErrors = {
  'This game is already analysed': ServerAnalysisRequestError.alreadyAnalysed,
  'You already have an ongoing requested analysis': ServerAnalysisRequestError.concurrentAnalysis,
  'You have reached the weekly analysis limit': ServerAnalysisRequestError.weeklyLimitReached,
  'You have reached the daily analysis limit': ServerAnalysisRequestError.dailyLimitReached,
  'You have reached the daily analysis limit on this IP':
      ServerAnalysisRequestError.dailyIpLimitReached,
  'This game is not analysable': ServerAnalysisRequestError.notAnalysable,
};

/// A provider for [ServerAnalysisService].
final serverAnalysisServiceProvider = Provider<ServerAnalysisService>((Ref ref) {
  return ServerAnalysisService(ref);
}, name: 'ServerAnalysisServiceProvider');

class ServerAnalysisService(final Ref ref) {
  StreamSubscription<SocketEvent>? _socketSubscription;

  final _currentAnalysis = ValueNotifier<ServerAnalysisSource?>(null);

  Completer<void>? _analysisCompleter;

  final _analysisProgress = ValueNotifier<(ServerAnalysisSource, ServerEvalEvent)?>(null);

  /// The current game being analyzed.
  ValueListenable<ServerAnalysisSource?> get currentAnalysis => _currentAnalysis;

  /// The last analysis progress event received from the server.
  ValueListenable<(ServerAnalysisSource, ServerEvalEvent)?> get lastAnalysisEvent =>
      _analysisProgress;

  SocketClient? _socketClient;

  /// Knightly's analysis being made on the phone, and its game.
  LocalAnalysisRunner? _localRunner;
  GameId? _localGameId;

  /// Request server analysis for a game.
  ///
  /// This will return a future that completes when the server analysis is launched (but not when
  /// it is finished).
  Future<void> requestAnalysis(ServerAnalysisSource source, [Side? side]) async {
    // Knightly: lichess only analyses games for the official app, so the analysis is made on the
    // phone instead.
    if (source case _GameServerAnalysisSource(:final gameId) when ref.read(useBoardApiProvider)) {
      return await _requestLocalAnalysis(gameId);
    }
    // If we are already listening for analysis updates of this exact game/study,
    // don't tear everything down and reconnect.
    if (_currentAnalysis.value == source &&
        _socketSubscription != null &&
        _analysisCompleter != null) {
      return;
    }

    _cancelAnalysis();

    final uri = Uri(
      path: switch (source) {
        _GameServerAnalysisSource(:final gameId) => '/watch/$gameId/${side?.name ?? Side.white}/v6',
        _StudyChapterServerAnalysisSource(:final studyId) => '/study/$studyId/socket/v6',
      },
    );

    _socketClient = SocketClient(
      uri,
      channelFactory: ref.read(webSocketChannelFactoryProvider),
      getSession: () => ref.read(authControllerProvider),
      packageInfo: ref.read(preloadedDataProvider).requireValue.packageInfo,
      deviceInfo: ref.read(preloadedDataProvider).requireValue.deviceInfo,
      sri: ref.read(preloadedDataProvider).requireValue.sri,
    );
    _socketClient!.connect();
    _analysisCompleter = Completer<void>();
    _socketSubscription = _socketClient!.stream.listen(
      (event) {
        if (event.topic == 'analysisProgress') {
          final data = ServerEvalEvent.fromJson(event.data as Map<String, dynamic>);

          _analysisProgress.value = (source, data);

          if (data.isAnalysisComplete) {
            if (_analysisCompleter != null && !_analysisCompleter!.isCompleted) {
              _analysisCompleter?.complete();
            }
          }
        }
      },
      onDone: () {
        _cancelAnalysis();
      },
      cancelOnError: true,
    );

    switch (source) {
      case _GameServerAnalysisSource(:final gameId):
        try {
          await ref.read(gameRepositoryProvider).requestServerAnalysis(gameId);
          _currentAnalysis.value = source;
        } on ServerException catch (e, st) {
          final error = _classifyRequestAnalysisError(e);
          switch (error) {
            case ServerAnalysisRequestError.alreadyAnalysed:
              _logger.fine('Game $gameId is already analysed, reading it from the socket');
              _currentAnalysis.value = source;
            case ServerAnalysisRequestError.concurrentAnalysis:
            case ServerAnalysisRequestError.weeklyLimitReached:
            case ServerAnalysisRequestError.dailyLimitReached:
            case ServerAnalysisRequestError.dailyIpLimitReached:
            case ServerAnalysisRequestError.notAnalysable:
              _logger.warning('Server refused to analyse game $gameId: $error', e, st);
              _cancelAnalysis();
              throw ServerAnalysisRequestException(error, e.message);
            case ServerAnalysisRequestError.unknown:
              _logger.severe('ServerException requesting server analysis', e, st);
              _cancelAnalysis();
              rethrow;
          }
        } catch (e, st) {
          _logger.severe('Error requesting server analysis', e, st);
          _cancelAnalysis();
          rethrow;
        }

      case _StudyChapterServerAnalysisSource(:final chapterId):
        _currentAnalysis.value = source;
        _socketClient!.firstConnection
            .timeout(const Duration(seconds: 3))
            .onError((e, st) {
              _logger.severe('Error connecting to analysis socket', e, st);
              _cancelAnalysis();
            })
            .whenComplete(() {
              _socketClient!.send('requestAnalysis', chapterId);
            });
    }

    _analysisCompleter?.future.timeout(kMaxWaitForServerAnalysis).whenComplete(() {
      _cancelAnalysis();
    });
  }

  /// Shows the analysis Knightly saved for [gameId], if any, and finishes its deep pass if it didn't.
  Future<void> restoreLocalAnalysis(GameId gameId) async {
    if (!ref.read(useBoardApiProvider) || _localGameId == gameId) return;
    final db = await ref.read(knightlyDatabaseProvider.future);
    if (await loadLocalAnalysis(db, gameId) == null) return;
    await _requestLocalAnalysis(gameId);
  }

  /// Knightly's computer analysis of [gameId], made on the phone: a quick pass shows the
  /// judgements within seconds, then a deep one refines them in the background. Each step is sent
  /// as lichess's server analysis progress is, and the analysis is saved.
  Future<void> _requestLocalAnalysis(GameId gameId) async {
    if (_localGameId == gameId) return;
    _cancelAnalysis();
    final source = ServerAnalysisSource.game(gameId: gameId);
    final db = await ref.read(knightlyDatabaseProvider.future);
    final game = await ref.read(gameRepositoryProvider).getGame(gameId);
    final initial = game.steps.first.position;
    final moves = [for (final step in game.steps.skip(1)) step.sanMove!];
    final stored = await loadLocalAnalysis(db, gameId);
    final saved = stored != null && stored.evals.length == moves.length + 1 ? stored : null;

    void emit(GameEvals evals) {
      _analysisProgress.value = (
        source,
        ServerEvalEvent.fromJson(
          makeAnalysisJson(
            gameId: gameId,
            initial: initial,
            moves: [for (final move in moves) move.move],
            evals: evals,
          ),
        ),
      );
    }

    if (saved != null) emit(saved.evals);
    if (saved != null && saved.deep) return;

    final runner = LocalAnalysisRunner(
      ref: ref,
      gameId: gameId,
      variant: game.meta.variant,
      initial: initial,
      moves: moves,
    );
    _localRunner = runner;
    _localGameId = gameId;
    _currentAnalysis.value = source;
    unawaited(() async {
      try {
        var evals = saved?.evals;
        if (evals == null) {
          evals = await runner.run(kQuickAnalysisTime, onProgress: emit);
          if (evals == null) return;
          await saveLocalAnalysis(db, gameId, evals, deep: false);
        }
        final deep = await runner.run(kDeepAnalysisTime, previous: evals, onProgress: emit);
        if (deep == null) return;
        await saveLocalAnalysis(db, gameId, deep, deep: true);
      } catch (e, st) {
        _logger.warning('Could not analyse $gameId', e, st);
      } finally {
        if (identical(_localRunner, runner)) {
          _localRunner = null;
          _localGameId = null;
          _currentAnalysis.value = null;
        }
      }
    }());
  }

  /// Work out why the server refused to start an analysis, from the plain-text body it sends
  /// alongside the 400.
  static ServerAnalysisRequestError _classifyRequestAnalysisError(ServerException e) {
    if (e.statusCode != 400) {
      return ServerAnalysisRequestError.unknown;
    }
    for (final MapEntry(key: body, value: error) in _kServerAnalysisRequestErrors.entries) {
      if (e.message.endsWith(body)) {
        return error;
      }
    }
    return ServerAnalysisRequestError.unknown;
  }

  /// Cancel the ongoing server analysis, if any.
  void _cancelAnalysis() {
    _localRunner?.cancel();
    _localRunner = null;
    _localGameId = null;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _currentAnalysis.value = null;
    _analysisCompleter = null;
    if (_socketClient?.isDisposed != true) {
      _socketClient?.dispose();
      _socketClient = null;
    }
  }

  /// Removes the computer analysis from the mainline of [root]: the evaluations, judgements and
  /// comments, and the best lines (except the one [keep] is in, where the user is).
  static void clearComputerAnalysis(Root root, {UciPath? keep}) {
    var path = UciPath.empty;
    Node node = root;
    while (true) {
      if (node is Branch) {
        node.lichessAnalysisComments = null;
        node.nags = null;
      }
      final mainPath = path;
      node.children.removeWhere(
        (child) =>
            child.isComputerVariation && !(keep != null && keep.contains(mainPath + child.id)),
      );
      final next = node.children.firstOrNull;
      if (next == null) break;
      path = path + next.id;
      node = next;
    }
  }

  /// Merge the ongoing analysis from the server into the given node tree.
  static void mergeOngoingAnalysis(Node n1, Map<String, dynamic> n2) {
    final eval = n2['eval'] as Map<String, dynamic>?;
    final cp = eval?['cp'] as int?;
    final mate = eval?['mate'] as int?;
    final pgnEval = cp != null
        ? PgnEvaluation.pawns(pawns: cpToPawns(cp))
        : mate != null
        ? PgnEvaluation.mate(mate: mate)
        : null;
    final glyphs = n2['glyphs'] as List<dynamic>?;
    final glyph = glyphs?.first as Map<String, dynamic>?;
    final comments = n2['comments'] as List<dynamic>?;
    final comment = (comments?.first as Map<String, dynamic>?)?['text'] as String?;
    final children = n2['children'] as List<dynamic>? ?? [];
    final pgnComment = pgnEval != null ? PgnComment(eval: pgnEval, text: comment) : null;
    if (n1 is Branch) {
      if (pgnComment != null) {
        if (n1.lichessAnalysisComments == null) {
          n1.lichessAnalysisComments = [pgnComment];
        } else {
          n1.lichessAnalysisComments!.removeWhere((c) => c.eval != null);
          n1.lichessAnalysisComments!.add(pgnComment);
        }
      }
      if (glyph != null) {
        n1.nags ??= [glyph['id'] as int];
      }
    }
    for (final c in children) {
      final n2child = c as Map<String, dynamic>;
      final uci = n2child['uci'] as String;
      final n1child = n1.childById(UciCharPair.fromUci(uci));
      if (n1child != null) {
        mergeOngoingAnalysis(n1child, n2child);
      } else {
        final san = n2child['san'] as String;
        final move = Move.parse(uci)!;
        n1.addChild(
          Branch(
            position: n1.position.playUnchecked(move),
            sanMove: SanMove(san, move),
            isCollapsed: children.length > 1,
            isComputerVariation: true,
          ),
        );
        // The rest of the line.
        mergeOngoingAnalysis(n1.childById(UciCharPair.fromUci(uci))!, n2child);
      }
    }
  }
}

/// A provider that exposes the current game being analyzed by the server.
final currentAnalysisProvider =
    NotifierProvider.autoDispose<CurrentAnalysis, ServerAnalysisSource?>(
      CurrentAnalysis.new,
      name: 'CurrentAnalysisProvider',
    );

class CurrentAnalysis() extends Notifier<ServerAnalysisSource?> {
  @override
  ServerAnalysisSource? build() {
    final listenable = ref.watch(serverAnalysisServiceProvider).currentAnalysis;

    listenable.addListener(_listener);

    ref.onDispose(() {
      listenable.removeListener(_listener);
    });

    return listenable.value;
  }

  void _listener() {
    final source = ref.read(serverAnalysisServiceProvider).currentAnalysis.value;
    if (state != source) {
      state = source;
    }
  }
}
