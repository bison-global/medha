import 'dart:io';

import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

/// The app's single encrypted SQLite database (ARCHITECTURE.md §7, §9.2).
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int schemaVersion = 1;

  /// Opens (or creates) the encrypted database at [path] with a 256-bit key.
  ///
  /// Throws [StateError] if the SQLite build has no encryption support, so an
  /// unencrypted database can never be created by accident.
  static AppDatabase open(String path, {required String keyHex}) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(keyHex)) {
      throw ArgumentError('keyHex must be 64 lowercase hex characters');
    }
    if (Platform.isAndroid) {
      open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    }
    final db = sqlite3.open(path);
    try {
      db.execute("PRAGMA key = \"x'$keyHex'\";");
      final cipher = db.select('PRAGMA cipher_version;');
      if (cipher.isEmpty || cipher.first.values.first == null) {
        throw StateError('Encrypted SQLite is not available in this build');
      }
      // Fails here with "file is not a database" if the key is wrong.
      db.select('SELECT count(*) FROM sqlite_master;');
      _configure(db);
      return AppDatabase._(db);
    } on Object {
      db.dispose();
      rethrow;
    }
  }

  /// Unencrypted in-memory database for tests.
  static AppDatabase inMemory() {
    final db = sqlite3.openInMemory();
    _configure(db);
    return AppDatabase._(db);
  }

  static void _configure(Database db) {
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA journal_mode = WAL;');
    _migrate(db);
  }

  static void _migrate(Database db) {
    final current = db.userVersion;
    if (current >= schemaVersion) return;
    db.execute('BEGIN;');
    try {
      if (current < 1) {
        db.execute('''
          CREATE TABLE chats (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            entry_id TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          );
        ''');
        db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
            role TEXT NOT NULL,
            kind TEXT NOT NULL,
            content TEXT NOT NULL,
            reasoning TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL,
            created_at INTEGER NOT NULL
          );
        ''');
        db.execute('CREATE INDEX messages_by_chat ON messages(chat_id, created_at);');
        db.execute('''
          CREATE TABLE installed_models (
            base_model_id TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            bytes INTEGER NOT NULL,
            sha256 TEXT NOT NULL,
            installed_at INTEGER NOT NULL
          );
        ''');
        db.execute('''
          CREATE TABLE installed_entries (
            entry_id TEXT PRIMARY KEY,
            installed_at INTEGER NOT NULL
          );
        ''');
        db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);');
      }
      db.userVersion = schemaVersion;
      db.execute('COMMIT;');
    } on Object {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void close() => db.dispose();
}
