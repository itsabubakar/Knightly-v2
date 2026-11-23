import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The file name of Knightly's own database, separate from the lichess one (`lichess_mobile.db`) so
/// that Knightly's tables never mix with the upstream schema and its migrations.
const kKnightlyDatabaseName = 'knightly.db';

/// The current version of [kKnightlyDatabaseName]'s schema.
const kKnightlyDatabaseVersion = 8;

/// A provider for Knightly's own [Database]: the data that only Knightly has (XP, achievements,
/// streak, tags, study sessions, goals), backed up by `KnightlyBackup`.
final knightlyDatabaseProvider = FutureProvider<Database>((Ref ref) async {
  if (Platform.isLinux) {
    databaseFactory = databaseFactoryFfi;
  }
  final directory = Platform.isLinux
      ? (await getApplicationSupportDirectory()).path
      : await getDatabasesPath();
  final db = await openKnightlyDatabase(databaseFactory, join(directory, kKnightlyDatabaseName));
  ref.onDispose(db.close);
  return db;
}, name: 'KnightlyDatabaseProvider');

/// Opens Knightly's database at [path].
///
/// Each schema version adds its tables in [_migrations]: version `n` is reached by running the
/// migrations `1` to `n`, for a new database and for an upgrade alike.
///
/// [singleInstance] is false in tests, so that an in-memory Knightly database is not the in-memory
/// app database, which has the same path.
Future<Database> openKnightlyDatabase(
  DatabaseFactory dbFactory,
  String path, {
  bool singleInstance = true,
}) {
  return dbFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: kKnightlyDatabaseVersion,
      singleInstance: singleInstance,
      onCreate: (db, version) => _migrate(db, from: 0, to: version),
      onUpgrade: (db, oldVersion, newVersion) => _migrate(db, from: oldVersion, to: newVersion),
    ),
  );
}

Future<void> _migrate(Database db, {required int from, required int to}) async {
  final batch = db.batch();
  for (var version = from + 1; version <= to; version++) {
    _migrations[version]!(batch);
  }
  await batch.commit(noResult: true);
}

final Map<int, void Function(Batch batch)> _migrations = {
  // A key-value store for small JSON values.
  1: (batch) {
    batch.execute('''
      CREATE TABLE kv (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  },
  // The XP history: one row per XP award, its id naming the rewarded activity (e.g. `game:<id>`) so
  // that an activity is never rewarded twice.
  2: (batch) {
    batch.execute('''
      CREATE TABLE xp_event (
        id TEXT NOT NULL,
        userId TEXT NOT NULL,
        source TEXT NOT NULL,
        xp INTEGER NOT NULL,
        discipline TEXT,
        createdAt INTEGER NOT NULL,
        PRIMARY KEY (id, userId)
      )
    ''');
    batch.execute('CREATE INDEX xp_event_user_date ON xp_event (userId, createdAt)');
  },
  // The counted games, with their speed and result, and the earned achievements.
  3: (batch) {
    batch.execute('''
      CREATE TABLE game_record (
        id TEXT NOT NULL,
        userId TEXT NOT NULL,
        speed TEXT NOT NULL,
        result TEXT NOT NULL,
        finishedAt INTEGER NOT NULL,
        PRIMARY KEY (id, userId)
      )
    ''');
    batch.execute('''
      CREATE TABLE achievement (
        id TEXT NOT NULL,
        userId TEXT NOT NULL,
        earnedAt INTEGER NOT NULL,
        seen INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id, userId)
      )
    ''');
  },
  // The reviewed games (with their lessons learned note) and their tagged moves.
  4: (batch) {
    batch.execute('''
      CREATE TABLE game_review (
        gameId TEXT NOT NULL,
        userId TEXT NOT NULL,
        opponent TEXT NOT NULL,
        playedAt INTEGER NOT NULL,
        orientation TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        updatedAt INTEGER NOT NULL,
        PRIMARY KEY (gameId, userId)
      )
    ''');
    batch.execute('''
      CREATE TABLE move_tag (
        gameId TEXT NOT NULL,
        userId TEXT NOT NULL,
        ply INTEGER NOT NULL,
        san TEXT NOT NULL,
        tag TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        PRIMARY KEY (gameId, userId, ply, tag)
      )
    ''');
  },
  // The study sessions: timed (stopwatch or countdown) or logged afterwards.
  5: (batch) {
    batch.execute('''
      CREATE TABLE study_session (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT NOT NULL,
        category TEXT NOT NULL,
        mode TEXT NOT NULL,
        startedAt INTEGER NOT NULL,
        durationSeconds INTEGER NOT NULL
      )
    ''');
    batch.execute('CREATE INDEX study_session_user_date ON study_session (userId, startedAt)');
  },
  // The lichess study a session was about, when it was started from one.
  6: (batch) {
    batch.execute('ALTER TABLE study_session ADD COLUMN studyId TEXT');
    batch.execute('ALTER TABLE study_session ADD COLUMN studyName TEXT');
  },
  // Knightly's computer analysis of games (made on the phone), and the user's comments on moves.
  7: (batch) {
    batch.execute('''
      CREATE TABLE game_analysis (
        gameId TEXT PRIMARY KEY,
        evals TEXT NOT NULL,
        deep INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE move_comment (
        gameId TEXT NOT NULL,
        moves TEXT NOT NULL,
        text TEXT NOT NULL,
        updatedAt INTEGER NOT NULL,
        PRIMARY KEY (gameId, moves)
      )
    ''');
  },
  // Training with spaced repetition: the cards (a position and the move to find, from an opening
  // repertoire or a mistake in a game), the repertoires and their moves, and the games looked
  // through for mistakes.
  8: (batch) {
    batch.execute('''
      CREATE TABLE training_card (
        id TEXT NOT NULL,
        userId TEXT NOT NULL,
        kind TEXT NOT NULL,
        sourceId TEXT NOT NULL,
        fen TEXT NOT NULL,
        answer TEXT NOT NULL,
        path TEXT NOT NULL,
        orientation TEXT NOT NULL,
        title TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        dueAt INTEGER NOT NULL,
        intervalDays REAL NOT NULL,
        ease REAL NOT NULL,
        reps INTEGER NOT NULL,
        lapses INTEGER NOT NULL,
        firstReviewedAt INTEGER,
        lastReviewedAt INTEGER,
        PRIMARY KEY (id, userId)
      )
    ''');
    batch.execute('CREATE INDEX training_card_due ON training_card (userId, dueAt)');
    batch.execute('''
      CREATE TABLE repertoire (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT NOT NULL,
        name TEXT NOT NULL,
        side TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE repertoire_move (
        repertoireId INTEGER NOT NULL,
        fen TEXT NOT NULL,
        uci TEXT NOT NULL,
        san TEXT NOT NULL,
        PRIMARY KEY (repertoireId, fen, uci)
      )
    ''');
    batch.execute('''
      CREATE TABLE mistake_scan (
        gameId TEXT NOT NULL,
        userId TEXT NOT NULL,
        scannedAt INTEGER NOT NULL,
        found INTEGER NOT NULL,
        PRIMARY KEY (gameId, userId)
      )
    ''');
  },
};
