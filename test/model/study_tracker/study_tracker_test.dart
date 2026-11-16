import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lichess_mobile/src/binding/binding.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/model/progression/xp_rules.dart';
import 'package:lichess_mobile/src/model/study_tracker/study_tracker.dart';
import 'package:lichess_mobile/src/network/http.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';
import '../auth/fake_auth_storage.dart';

final _start = DateTime(2026, 11, 16, 10);

/// A signed in container with no lichess activity, its progression loaded.
Future<ProviderContainer> _container() async {
  final container = await makeContainer(
    authUser: fakeAuthUser,
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
        (ref) => FakeHttpClientFactory(() => MockClient((_) => mockResponse('', 404))),
      ),
    },
  );
  container.listen(studySessionsProvider, (_, _) {});
  await container.read(progressionProvider.future);
  return container;
}

void main() {
  group('StudyTimer', () {
    test('a countdown counts down and ends at its length', () {
      final timer = StudyTimer(
        mode: StudyMode.countdown,
        category: Discipline.endgames,
        startedAt: _start,
        planned: const Duration(minutes: 20),
      );
      final later = _start.add(const Duration(minutes: 5));
      expect(timer.elapsed(later), const Duration(minutes: 5));
      expect(timer.remaining(later), const Duration(minutes: 15));
      expect(timer.isOver(later), isFalse);

      final afterEnd = _start.add(const Duration(minutes: 25));
      expect(timer.elapsed(afterEnd), const Duration(minutes: 20));
      expect(timer.isOver(afterEnd), isTrue);
    });

    test('a paused timer stops counting', () {
      final timer = StudyTimer(
        mode: StudyMode.stopwatch,
        category: Discipline.tactics,
        startedAt: _start,
      ).paused(_start.add(const Duration(minutes: 10)));
      expect(timer.elapsed(_start.add(const Duration(minutes: 30))), const Duration(minutes: 10));

      final resumed = timer.resumed(_start.add(const Duration(minutes: 30)));
      expect(resumed.elapsed(_start.add(const Duration(minutes: 35))), const Duration(minutes: 15));
    });

    test('a forgotten stopwatch counts at most 3 hours', () {
      final timer = StudyTimer(
        mode: StudyMode.stopwatch,
        category: Discipline.openings,
        startedAt: _start,
      );
      expect(timer.elapsed(_start.add(const Duration(hours: 10))), kMaxStopwatchDuration);
    });

    test('survives the app being closed', () async {
      final container = await _container();
      await container
          .read(studyTimerProvider.notifier)
          .start(StudyMode.countdown, Discipline.strategy, planned: const Duration(minutes: 30));

      // A new start of the app reads it back.
      final stored = LichessBinding.instance.sharedPreferences.getString(kStudyTimerStorageKey)!;
      final restored = StudyTimer.fromJson(jsonDecode(stored) as Map<String, dynamic>);
      expect(restored.category, Discipline.strategy);
      expect(restored.planned, const Duration(minutes: 30));
    });

    test('a timer started from a study keeps it, paused or not', () {
      final timer = StudyTimer(
        mode: StudyMode.stopwatch,
        category: Discipline.openings,
        startedAt: _start,
        study: (id: const StudyId('abcd1234'), name: 'Caro-Kann repertoire'),
      ).paused(_start.add(const Duration(minutes: 5)));
      final restored = StudyTimer.fromJson(
        jsonDecode(jsonEncode(timer.toJson())) as Map<String, dynamic>,
      );
      expect(restored.study?.name, 'Caro-Kann repertoire');
      expect(restored.resumed(_start.add(const Duration(minutes: 6))).study?.id.value, 'abcd1234');
    });
  });

  group('StudySessions', () {
    test('a session earns 1 XP per minute, deleting it takes it back', () async {
      final container = await _container();
      final sessions = container.read(studySessionsProvider.notifier);

      await sessions.add(
        category: Discipline.endgames,
        mode: StudyMode.manual,
        startedAt: _start,
        duration: const Duration(minutes: 25, seconds: 40),
      );

      final progression = container.read(progressionProvider).value!;
      expect(progression.totalXp, 25);
      expect(progression.studyTime, const Duration(minutes: 25, seconds: 40));
      expect(progression.studySessions, 1);

      final session = (await container.read(studySessionsProvider.future)).single;
      await sessions.delete(session.id);

      expect(container.read(progressionProvider).value!.totalXp, 0);
      expect(await container.read(studySessionsProvider.future), isEmpty);
    });

    test('a session under a minute does not count', () async {
      final container = await _container();
      await container
          .read(studySessionsProvider.notifier)
          .add(
            category: Discipline.tactics,
            mode: StudyMode.stopwatch,
            startedAt: _start,
            duration: const Duration(seconds: 40),
          );
      expect(await container.read(studySessionsProvider.future), isEmpty);
    });

    test('a session keeps the study it was about', () async {
      final container = await _container();
      await container
          .read(studySessionsProvider.notifier)
          .add(
            category: Discipline.openings,
            mode: StudyMode.countdown,
            startedAt: _start,
            duration: const Duration(minutes: 20),
            study: (id: const StudyId('abcd1234'), name: 'Caro-Kann repertoire'),
          );

      final session = (await container.read(studySessionsProvider.future)).single;
      expect(session.study?.id, const StudyId('abcd1234'));
      expect(session.study?.name, 'Caro-Kann repertoire');
    });

    test('10 hours of study earn "Deep Focus"', () async {
      final container = await _container();
      await container
          .read(studySessionsProvider.notifier)
          .add(
            category: Discipline.analysis,
            mode: StudyMode.manual,
            startedAt: _start,
            duration: const Duration(hours: 10),
          );

      final deepFocus = container
          .read(progressionProvider)
          .value!
          .achievements
          .firstWhere((a) => a.achievement.id == 'deep_focus');
      expect(deepFocus.earnedAt, isNotNull);
    });
  });
}
