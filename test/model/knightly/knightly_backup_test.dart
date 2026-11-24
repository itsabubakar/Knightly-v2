import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/binding/binding.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/knightly/knightly_backup.dart';
import 'package:lichess_mobile/src/model/study/study_bookmarks.dart';

import '../../test_container.dart';

void main() {
  test('exports the Knightly preferences and tables, and nothing else', () async {
    final container = await makeContainer();
    final prefs = LichessBinding.instance.sharedPreferences;
    await prefs.setString(kStudyBookmarksStorageKey, '[]');
    await prefs.setInt('knightly.someCount', 3);
    await prefs.setString('some.lichess.pref', 'not Knightly data');
    final db = await container.read(knightlyDatabaseProvider.future);
    await db.insert('kv', {'key': 'streak', 'value': '{"days":12}'});

    final backup = await container.read(knightlyBackupProvider).export();

    expect(backup['format'], kKnightlyBackupFormat);
    final preferences = backup['preferences'] as Map<String, dynamic>;
    expect(preferences[kStudyBookmarksStorageKey], {'type': 'string', 'value': '[]'});
    expect(preferences['knightly.someCount'], {'type': 'int', 'value': 3});
    expect(preferences.containsKey('some.lichess.pref'), isFalse);
    expect((backup['tables'] as Map<String, dynamic>)['kv'], [
      {'key': 'streak', 'value': '{"days":12}'},
    ]);
  });

  test('restoring a backup replaces all the Knightly data', () async {
    final container = await makeContainer();
    final prefs = LichessBinding.instance.sharedPreferences;
    final db = await container.read(knightlyDatabaseProvider.future);
    await prefs.setInt('knightly.someCount', 3);
    await db.insert('kv', {'key': 'streak', 'value': '{"days":12}'});
    final backup = await container.read(knightlyBackupProvider).export();

    // Data changed after the backup.
    await prefs.setInt('knightly.someCount', 99);
    await prefs.setString('knightly.addedLater', 'gone after restore');
    await db.delete('kv');
    await db.insert('kv', {'key': 'other', 'value': '1'});

    await container.read(knightlyBackupProvider).restore(backup);

    expect(prefs.getInt('knightly.someCount'), 3);
    expect(prefs.getString('knightly.addedLater'), isNull);
    expect(await db.query('kv'), [
      {'key': 'streak', 'value': '{"days":12}'},
    ]);
  });

  test('a new install has no data: nothing to back up, a restored backup to offer', () async {
    final container = await makeContainer();
    final backups = container.read(knightlyBackupProvider);
    expect(await backups.hasData(), isFalse);

    final db = await container.read(knightlyDatabaseProvider.future);
    await db.insert('xp_event', {
      'id': 'game:abcdefgh',
      'userId': 'testuser',
      'source': 'game',
      'xp': 15,
      'createdAt': DateTime(2026, 11, 24).millisecondsSinceEpoch,
    });
    expect(await backups.hasData(), isTrue);
    // With data of its own, no backup is offered to restore over it.
    expect(await backups.backupToRestore(), isNull);
  });

  test('refuses what is not a Knightly backup', () async {
    final container = await makeContainer();
    final backup = container.read(knightlyBackupProvider);

    await expectLater(
      backup.restore({'format': 'something-else'}),
      throwsA(isA<InvalidBackupException>()),
    );
    await expectLater(
      backup.restore({
        'format': kKnightlyBackupFormat,
        'version': kKnightlyBackupVersion + 1,
        'databaseVersion': kKnightlyDatabaseVersion,
      }),
      throwsA(isA<InvalidBackupException>()),
    );
  });
}
