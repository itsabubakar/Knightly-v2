import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/progression/achievements.dart';
import 'package:lichess_mobile/src/model/progression/levels.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../../mock_server_responses.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';
import '../auth/fake_auth_storage.dart';
import '../puzzle/mock_server_responses.dart';

/// A container for the signed in test user whose progression started at [startedAt], answering
/// with the test games and puzzles, and recording the requests in [requests].
Future<ProviderContainer> progressionContainer({
  required DateTime startedAt,
  List<http.Request>? requests,
}) async {
  final client = MockClient((request) {
    requests?.add(request);
    return switch (request.url.path) {
      // 2 played blitz games in January 2023, and one never started.
      '/api/games/user/testuser' => mockResponse(mockUserRecentGameResponse('testUser'), 200),
      // 3 puzzles solved in June 2024.
      '/api/puzzle/activity' => mockResponse(mockActivityResponse, 200),
      _ => mockResponse('', 404),
    };
  });
  final container = await makeContainer(
    authUser: fakeAuthUser,
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
        (ref) => FakeHttpClientFactory(() => client),
      ),
    },
  );
  final db = await container.read(knightlyDatabaseProvider.future);
  await db.insert('kv', {
    'key': 'progression:testuser',
    'value': jsonEncode({'startedAt': startedAt.millisecondsSinceEpoch}),
  });
  return container;
}

void main() {
  group('PlayerLevel', () {
    test('follows the level curve', () {
      expect(xpAtLevelStart(1), 0);
      expect(xpAtLevelStart(2), 100);
      expect(xpAtLevelStart(3), 225);
      expect(xpAtLevelStart(8), 1225);
      expect(xpAtLevelStart(9), 1500);
    });

    test('gives the level, title and XP to the next level', () {
      const level = PlayerLevel(totalXp: 1240);
      expect(level.number, 8);
      expect(level.roman, 'VIII');
      expect(level.title, 'The Practitioner');
      expect(level.xpToNextLevel, 260);
      expect(const PlayerLevel(totalXp: 0).number, 1);
      expect(const PlayerLevel(totalXp: 99).number, 1);
      expect(const PlayerLevel(totalXp: 100).number, 2);
    });

    test('writes Roman numerals', () {
      expect(romanNumeral(4), 'IV');
      expect(romanNumeral(9), 'IX');
      expect(romanNumeral(14), 'XIV');
      expect(romanNumeral(40), 'XL');
    });
  });

  group('progressionProvider', () {
    test('is null when signed out', () async {
      final container = await makeContainer();
      expect(await container.read(progressionProvider.future), isNull);
    });

    test('awards XP for the games played and puzzles solved since the start', () async {
      final requests = <http.Request>[];
      final startedAt = DateTime(2023);
      final container = await progressionContainer(startedAt: startedAt, requests: requests);

      final progression = (await container.read(progressionProvider.future))!;

      // 2 blitz games (5 XP each), 3 puzzles (2 XP each), the "First Move" achievement (10 XP) and
      // the streak day of the games (5 XP).
      expect(progression.gamesPlayed, 2);
      expect(progression.puzzlesSolved, 3);
      expect(progression.totalXp, 31);
      // Played on one day of January 2023, the streak ended long ago.
      expect(progression.longestStreak, 1);
      expect(progression.currentStreak, 0);
      expect(progression.startedAt, startedAt);
      // The first sync asks for the activity since the start.
      final gamesRequest = requests.firstWhere((r) => r.url.path == '/api/games/user/testuser');
      expect(gamesRequest.url.queryParameters['since'], '${startedAt.millisecondsSinceEpoch}');
    });

    test('never awards XP twice for the same activity', () async {
      final container = await progressionContainer(startedAt: DateTime(2023));
      await container.read(progressionProvider.future);

      await container.read(progressionProvider.notifier).refresh();
      final progression = (await container.read(progressionProvider.future))!;

      expect(progression.totalXp, 31);
      expect(progression.gamesPlayed, 2);
    });

    test('counts a game that just ended at once, and only once', () async {
      final container = await progressionContainer(startedAt: DateTime(2023));
      final before = (await container.read(progressionProvider.future))!;

      // A Rapid game of 45 moves: 15 XP × 1.25.
      final award = await container
          .read(progressionProvider.notifier)
          .addFinishedGame(
            id: const GameId('rapid123'),
            speed: Speed.rapid,
            plies: 89,
            result: GameResult.loss,
            finishedAt: DateTime.now(),
          );
      expect(award?.xp, 19);
      expect(award?.moves, 45);
      expect(award?.before, before.level);
      expect(award?.after.gamesPlayed, before.gamesPlayed + 1);
      final counted = (await container.read(progressionProvider.future))!;
      expect(counted.gamesPlayed, before.gamesPlayed + 1);

      // Counted again (the popup shown twice): the same XP, nothing added.
      final again = await container
          .read(progressionProvider.notifier)
          .addFinishedGame(
            id: const GameId('rapid123'),
            speed: Speed.rapid,
            plies: 89,
            result: GameResult.loss,
            finishedAt: DateTime.now(),
          );
      expect(again?.xp, 19);
      expect(again?.after.totalXp, award?.after.totalXp);
    });

    test('ignores what happened before the start', () async {
      // After the games of January 2023, before the puzzles of June 2024.
      final container = await progressionContainer(startedAt: DateTime(2024));

      final progression = (await container.read(progressionProvider.future))!;

      expect(progression.gamesPlayed, 0);
      expect(progression.puzzlesSolved, 3);
      expect(progression.totalXp, 6);
    });

    test('awards the achievements reached, once, and celebrates them once', () async {
      final container = await progressionContainer(startedAt: DateTime(2023));

      final progression = (await container.read(progressionProvider.future))!;

      final firstMove = progression.achievements.firstWhere(
        (a) => a.achievement.id == 'first_move',
      );
      expect(firstMove.earnedAt, isNotNull);
      final puzzleRookie = progression.achievements.firstWhere(
        (a) => a.achievement.id == 'puzzle_rookie',
      );
      expect(puzzleRookie.earnedAt, isNull);
      expect(puzzleRookie.current, 3);
      expect(progression.celebrations.map((c) => (c as AchievementEarned).achievement.id), [
        'first_move',
      ]);

      await container.read(progressionProvider.notifier).markCelebrated();
      expect(container.read(progressionProvider).value!.celebrations, isEmpty);

      // Syncing again neither awards it again nor celebrates it again.
      await container.read(progressionProvider.notifier).refresh();
      final refreshed = (await container.read(progressionProvider.future))!;
      expect(refreshed.totalXp, 31);
      expect(refreshed.celebrations, isEmpty);
    });

    test('gives a freeze per level-up, holding at most 3', () async {
      final container = await progressionContainer(startedAt: DateTime(2030));
      final db = await container.read(knightlyDatabaseProvider.future);
      // Level 7 at once (975 XP and up): 6 level-ups, and the "Apprentice" achievement (level 5).
      await db.insert('xp_event', {
        'id': 'test:1',
        'userId': 'testuser',
        'source': 'test',
        'xp': 1000,
        'createdAt': DateTime(2030).millisecondsSinceEpoch,
      });

      final progression = (await container.read(progressionProvider.future))!;

      expect(progression.level.number, 7);
      expect(progression.streakFreezes, kMaxStreakFreezes);
      expect(
        progression.achievements.firstWhere((a) => a.achievement.id == 'apprentice').earnedAt,
        isNotNull,
      );
      expect(progression.celebrations.first, isA<LevelUp>());
      expect((progression.celebrations.first as LevelUp).level, 7);
      expect(progression.celebrations.whereType<AchievementEarned>().map((c) => c.achievement.id), [
        'apprentice',
      ]);
    });
  });
}
