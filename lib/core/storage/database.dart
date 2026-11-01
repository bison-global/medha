import 'dart:io';

import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

/// The app's single encrypted SQLite database (ARCHITECTURE.md §7, §9.2).
/// It holds chats, projects, document text and vectors, settings and the
/// report queue. Model and document files live beside it on disk.
class AppDatabase {
  AppDatabase._(this.db, {required this.hasFts});

  final Database db;

  /// Whether SQLite's FTS5 keyword index is available in this build.
  final bool hasFts;

  static const int schemaVersion = 2;

  static void _useCipherOnAndroid() {
    if (Platform.isAndroid) {
      // The static open() below shadows the library's `open`, hence the prefix.
      sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.android, openCipherOnAndroid);
    }
  }

  /// Opens (or creates) the encrypted database at [path] with a 256-bit key.
  ///
  /// Throws [StateError] if the SQLite build has no encryption support, so an
  /// unencrypted database can never be created by accident.
  static AppDatabase open(String path, {required String keyHex}) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(keyHex)) {
      throw ArgumentError('keyHex must be 64 lowercase hex characters');
    }
    _useCipherOnAndroid();
    final db = sqlite3.open(path);
    try {
      db.execute("PRAGMA key = \"x'$keyHex'\";");
      final cipher = db.select('PRAGMA cipher_version;');
      if (cipher.isEmpty || cipher.first.values.first == null) {
        throw StateError('Encrypted SQLite is not available in this build');
      }
      // Fails here with "file is not a database" if the key is wrong.
      db.select('SELECT count(*) FROM sqlite_master;');
      return AppDatabase._(db, hasFts: _configure(db));
    } on Object {
      db.dispose();
      rethrow;
    }
  }

  /// Unencrypted in-memory database, for tests and demo mode.
  static AppDatabase inMemory() {
    _useCipherOnAndroid();
    final db = sqlite3.openInMemory();
    return AppDatabase._(db, hasFts: _configure(db));
  }

  static bool _configure(Database db) {
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA journal_mode = WAL;');
    _migrate(db);
    return _ensureFts(db);
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
      if (current < 2) {
        db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          );
        ''');
        db.execute('ALTER TABLE chats ADD COLUMN project_id TEXT REFERENCES projects(id) ON DELETE SET NULL;');
        db.execute('ALTER TABLE chats ADD COLUMN ephemeral INTEGER NOT NULL DEFAULT 0;');
        db.execute("ALTER TABLE messages ADD COLUMN sources TEXT NOT NULL DEFAULT '';");
        db.execute('ALTER TABLE messages ADD COLUMN voice INTEGER NOT NULL DEFAULT 0;');
        db.execute('ALTER TABLE messages ADD COLUMN document_id TEXT;');
        db.execute('ALTER TABLE installed_entries ADD COLUMN base_model_id TEXT;');
        db.execute('''
          CREATE TABLE documents (
            id TEXT PRIMARY KEY,
            project_id TEXT REFERENCES projects(id) ON DELETE CASCADE,
            chat_id TEXT REFERENCES chats(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            ext TEXT NOT NULL,
            bytes INTEGER NOT NULL,
            path TEXT NOT NULL,
            status TEXT NOT NULL,
            truncated INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          );
        ''');
        db.execute('''
          CREATE TABLE doc_chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            ordinal INTEGER NOT NULL,
            text TEXT NOT NULL,
            embedding BLOB,
            emb_scale REAL NOT NULL DEFAULT 0,
            emb_model TEXT NOT NULL DEFAULT '',
            emb_dim INTEGER NOT NULL DEFAULT 0
          );
        ''');
        db.execute('CREATE INDEX doc_chunks_by_document ON doc_chunks(document_id, ordinal);');
        db.execute('''
          CREATE TABLE reports (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            reason TEXT NOT NULL,
            note TEXT NOT NULL,
            question TEXT,
            reply TEXT,
            entry_id TEXT,
            sent_at INTEGER
          );
        ''');
      }
      db.userVersion = schemaVersion;
      db.execute('COMMIT;');
    } on Object {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Creates the FTS5 keyword index (kept in sync by triggers). Returns false
  /// if this SQLite build has no FTS5; search then falls back to vectors only.
  static bool _ensureFts(Database db) {
    try {
      db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS doc_chunks_fts USING fts5(text, content='doc_chunks', content_rowid='id');
      ''');
      db.execute('''
        CREATE TRIGGER IF NOT EXISTS doc_chunks_ai AFTER INSERT ON doc_chunks BEGIN
          INSERT INTO doc_chunks_fts(rowid, text) VALUES (new.id, new.text);
        END;
      ''');
      db.execute('''
        CREATE TRIGGER IF NOT EXISTS doc_chunks_ad AFTER DELETE ON doc_chunks BEGIN
          INSERT INTO doc_chunks_fts(doc_chunks_fts, rowid, text) VALUES ('delete', old.id, old.text);
        END;
      ''');
      return true;
    } on SqliteException {
      return false;
    }
  }

  void close() => db.dispose();
}
