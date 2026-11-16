import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/binding/binding.dart';
import 'package:lichess_mobile/src/db/knightly_database.dart';
import 'package:lichess_mobile/src/model/account/account_preferences.dart';
import 'package:lichess_mobile/src/model/progression/progression.dart';
import 'package:lichess_mobile/src/model/review/game_tags.dart';
import 'package:lichess_mobile/src/model/study/study_bookmarks.dart';
import 'package:lichess_mobile/src/model/study_tracker/study_tracker.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _logger = Logger('KnightlyBackup');

/// The prefix of the shared preferences keys holding Knightly's own data, which are backed up.
const kKnightlyPrefsPrefix = 'knightly.';

/// The `format` of a Knightly backup, to recognize its files.
const kKnightlyBackupFormat = 'knightly-backup';

/// The version of the backup file structure.
const kKnightlyBackupVersion = 1;

/// How often an automatic backup is made.
const kAutoBackupInterval = Duration(days: 7);

/// How many automatic backups are kept.
const kAutoBackupsKept = 4;

/// Thrown when a file is not a Knightly backup this version can restore.
class const InvalidBackupException(final String message) implements Exception {
  @override
  String toString() => message;
}

/// An automatic backup file.
typedef AutoBackup = ({File file, DateTime date});

/// A provider for [KnightlyBackup].
final knightlyBackupProvider = Provider<KnightlyBackup>((Ref ref) {
  return KnightlyBackup(ref);
}, name: 'KnightlyBackupProvider');

/// The automatic backups, newest first.
final autoBackupsProvider = FutureProvider.autoDispose<List<AutoBackup>>((Ref ref) {
  return ref.read(knightlyBackupProvider).listAutoBackups();
}, name: 'AutoBackupsProvider');

/// Exports Knightly's own data to a JSON backup and restores it.
///
/// Knightly's data lives only on this device: its database ([kKnightlyDatabaseName]) and its shared
/// preferences (keys starting with [kKnightlyPrefsPrefix]). Uninstalling the app or clearing its data
/// loses it, unless it was exported.
class KnightlyBackup(final Ref _ref) {
  /// All of Knightly's data as a JSON map.
  Future<Map<String, dynamic>> export() async {
    final prefs = LichessBinding.instance.sharedPreferences;
    final db = await _ref.read(knightlyDatabaseProvider.future);
    return {
      'format': kKnightlyBackupFormat,
      'version': kKnightlyBackupVersion,
      'databaseVersion': kKnightlyDatabaseVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'preferences': {
        for (final key in prefs.keys.where((key) => key.startsWith(kKnightlyPrefsPrefix)))
          key: _encodePref(prefs.get(key)),
      },
      'tables': {for (final table in await _tableNames(db)) table: await db.query(table)},
    };
  }

  /// Replaces all of Knightly's data with the [backup] made by [export].
  ///
  /// Throws an [InvalidBackupException] if [backup] is not a backup this version can restore.
  Future<void> restore(Map<String, dynamic> backup) async {
    if (backup['format'] != kKnightlyBackupFormat) {
      throw const InvalidBackupException('This file is not a Knightly backup.');
    }
    final version = backup['version'];
    if (version is! int || version > kKnightlyBackupVersion) {
      throw const InvalidBackupException('This backup was made by a newer version of Knightly.');
    }
    final databaseVersion = backup['databaseVersion'];
    if (databaseVersion is! int || databaseVersion > kKnightlyDatabaseVersion) {
      throw const InvalidBackupException('This backup was made by a newer version of Knightly.');
    }

    final preferences = (backup['preferences'] as Map<String, dynamic>?) ?? {};
    final tables = (backup['tables'] as Map<String, dynamic>?) ?? {};

    final db = await _ref.read(knightlyDatabaseProvider.future);
    final existingTables = await _tableNames(db);
    await db.transaction((txn) async {
      for (final table in existingTables) {
        await txn.delete(table);
        for (final row in (tables[table] as List<dynamic>?) ?? const []) {
          await txn.insert(table, Map<String, Object?>.from(row as Map));
        }
      }
    });

    final prefs = LichessBinding.instance.sharedPreferences;
    for (final key in prefs.keys.where((key) => key.startsWith(kKnightlyPrefsPrefix)).toList()) {
      await prefs.remove(key);
    }
    for (final MapEntry(:key, :value) in preferences.entries) {
      if (key.startsWith(kKnightlyPrefsPrefix)) {
        await _setPref(key, value as Map<String, dynamic>);
      }
    }

    // The providers that read the restored data.
    _ref.invalidate(studyBookmarksProvider);
    _ref.invalidate(accountPreferencesProvider);
    _ref.invalidate(progressionProvider);
    _ref.invalidate(studySessionsProvider);
    _ref.invalidate(studyTimerProvider);
    _ref.invalidate(tagListProvider);
  }

  /// Writes [export] to a new file in the temporary directory, to share it.
  Future<File> exportToFile() async {
    final directory = await getTemporaryDirectory();
    final file = File(join(directory.path, 'knightly-backup-${_fileDate(DateTime.now())}.json'));
    return await file.writeAsString(jsonEncode(await export()));
  }

  /// Reads a backup file, as [restore] expects it.
  Future<Map<String, dynamic>> readBackupFile(String path) async {
    try {
      return jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    } catch (e) {
      throw const InvalidBackupException('This file is not a Knightly backup.');
    }
  }

  /// Makes an automatic backup if the latest one is older than [kAutoBackupInterval], keeping the
  /// [kAutoBackupsKept] newest ones. Never throws.
  Future<void> autoBackupIfDue() async {
    try {
      final backups = await listAutoBackups();
      final now = DateTime.now();
      if (backups.isNotEmpty && now.difference(backups.first.date) < kAutoBackupInterval) {
        return;
      }
      final directory = await _autoBackupsDirectory();
      await File(join(directory.path, 'auto-${_fileDate(now)}.json'))
          .writeAsString(jsonEncode(await export()));
      for (final old in (await listAutoBackups()).skip(kAutoBackupsKept)) {
        await old.file.delete();
      }
      _logger.info('Automatic backup made.');
    } catch (e, st) {
      _logger.warning('Could not make an automatic backup:', e, st);
    }
  }

  /// The automatic backups, newest first.
  Future<List<AutoBackup>> listAutoBackups() async {
    final directory = await _autoBackupsDirectory();
    final backups = <AutoBackup>[
      for (final entity in directory.listSync())
        if (entity is File && basename(entity.path).startsWith('auto-'))
          (file: entity, date: entity.lastModifiedSync()),
    ];
    backups.sort((a, b) => b.date.compareTo(a.date));
    return backups;
  }

  Future<Directory> _autoBackupsDirectory() async {
    final directory = Directory(
      join((await getApplicationSupportDirectory()).path, 'knightly_backups'),
    );
    if (!directory.existsSync()) await directory.create(recursive: true);
    return directory;
  }

  Future<List<String>> _tableNames(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
      "AND name != 'android_metadata'",
    );
    return [for (final row in rows) row['name']! as String];
  }

  Future<void> _setPref(String key, Map<String, dynamic> encoded) async {
    final prefs = LichessBinding.instance.sharedPreferences;
    final value = encoded['value'];
    switch (encoded['type']) {
      case 'string':
        await prefs.setString(key, value as String);
      case 'int':
        await prefs.setInt(key, value as int);
      case 'double':
        await prefs.setDouble(key, (value as num).toDouble());
      case 'bool':
        await prefs.setBool(key, value as bool);
      case 'stringList':
        await prefs.setStringList(key, (value as List<dynamic>).cast<String>());
    }
  }
}

/// A shared preference value with its type, since JSON can't tell an int from a double.
Map<String, dynamic> _encodePref(Object? value) => switch (value) {
  final String v => {'type': 'string', 'value': v},
  final int v => {'type': 'int', 'value': v},
  final double v => {'type': 'double', 'value': v},
  final bool v => {'type': 'bool', 'value': v},
  final List<String> v => {'type': 'stringList', 'value': v},
  _ => {'type': 'unknown', 'value': null},
};

String _fileDate(DateTime date) =>
    '${date.year}-${_two(date.month)}-${_two(date.day)}-${_two(date.hour)}${_two(date.minute)}';

String _two(int n) => n.toString().padLeft(2, '0');
