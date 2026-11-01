import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../inference/inference_engine.dart';
import '../settings/prefs.dart';
import 'database.dart';
import 'models.dart';

abstract interface class ChatRepository {
  /// All chats, newest first; only those in [projectId] when it is given.
  Future<List<ChatSummary>> listChats({String? projectId});
  Future<ChatSummary?> getChat(String id);
  Future<ChatSummary> createChat({required String entryId, String title = 'New chat', String? projectId, bool ephemeral = false});
  Future<void> renameChat(String id, String title);
  Future<List<ChatMessage>> messages(String chatId);

  /// Inserts or replaces a message and bumps the chat's `updatedAt`.
  Future<void> saveMessage(ChatMessage message);

  /// Deletes the chat, its messages and its attached files.
  Future<void> deleteChat(String id);
  Future<void> deleteAllChats();

  /// Erases chats made while "Save chat history" was off.
  Future<void> purgeEphemeral();
}

abstract interface class ModelRepository {
  Future<Map<String, InstalledModel>> installedModels();
  Future<Set<String>> installedEntries();

  /// Installed entry id → the base model it was installed with (it can be
  /// the low-memory fallback rather than the catalog's default).
  Future<Map<String, String?>> installedEntryBases();
  Future<void> markModelInstalled(InstalledModel model);
  Future<void> markEntryInstalled(String entryId, {String? baseModelId});
  Future<void> removeEntry(String entryId);
  Future<void> removeModel(String baseModelId);
}

int _ms(DateTime t) => t.millisecondsSinceEpoch;
DateTime _dt(Object? v) => DateTime.fromMillisecondsSinceEpoch(v! as int);
DateTime? _dtOrNull(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

Future<void> _deleteFiles(Iterable<String> paths) async {
  for (final p in paths) {
    try {
      final f = File(p);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Best effort: a leftover file is cleaned up by the next storage sweep.
    }
  }
}

class SqliteChatRepository implements ChatRepository {
  SqliteChatRepository(this._database);
  final AppDatabase _database;
  Database get _db => _database.db;

  ChatSummary _chat(Row r) => ChatSummary(
        id: r['id'] as String,
        title: r['title'] as String,
        entryId: r['entry_id'] as String,
        createdAt: _dt(r['created_at']),
        updatedAt: _dt(r['updated_at']),
        projectId: r['project_id'] as String?,
        ephemeral: (r['ephemeral'] as int) == 1,
      );

  @override
  Future<List<ChatSummary>> listChats({String? projectId}) async => (projectId == null
          ? _db.select('SELECT * FROM chats ORDER BY updated_at DESC;')
          : _db.select('SELECT * FROM chats WHERE project_id = ? ORDER BY updated_at DESC;', [projectId]))
      .map(_chat)
      .toList();

  @override
  Future<ChatSummary?> getChat(String id) async {
    final rows = _db.select('SELECT * FROM chats WHERE id = ?;', [id]);
    return rows.isEmpty ? null : _chat(rows.first);
  }

  @override
  Future<ChatSummary> createChat({required String entryId, String title = 'New chat', String? projectId, bool ephemeral = false}) async {
    final now = DateTime.now();
    final chat = ChatSummary(
        id: newId(), title: title, entryId: entryId, createdAt: now, updatedAt: now, projectId: projectId, ephemeral: ephemeral);
    _db.execute(
      'INSERT INTO chats (id, title, entry_id, created_at, updated_at, project_id, ephemeral) VALUES (?, ?, ?, ?, ?, ?, ?);',
      [chat.id, chat.title, chat.entryId, _ms(now), _ms(now), projectId, ephemeral ? 1 : 0],
    );
    return chat;
  }

  @override
  Future<void> renameChat(String id, String title) async =>
      _db.execute('UPDATE chats SET title = ? WHERE id = ?;', [title, id]);

  @override
  Future<List<ChatMessage>> messages(String chatId) async => _db
      .select('SELECT * FROM messages WHERE chat_id = ? ORDER BY created_at, rowid;', [chatId])
      .map((r) => ChatMessage(
            id: r['id'] as String,
            chatId: r['chat_id'] as String,
            role: ChatRole.values.byName(r['role'] as String),
            kind: MessageKind.parse(r['kind'] as String),
            content: r['content'] as String,
            reasoning: r['reasoning'] as String,
            status: MessageStatus.parse(r['status'] as String),
            createdAt: _dt(r['created_at']),
            sources: (r['sources'] as String).isEmpty ? const [] : (r['sources'] as String).split('\n'),
            voice: (r['voice'] as int) == 1,
            documentId: r['document_id'] as String?,
          ))
      .toList();

  @override
  Future<void> saveMessage(ChatMessage m) async {
    _db.execute(
      '''INSERT INTO messages (id, chat_id, role, kind, content, reasoning, status, created_at, sources, voice, document_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET content = excluded.content, reasoning = excluded.reasoning,
           status = excluded.status, kind = excluded.kind, sources = excluded.sources;''',
      [
        m.id, m.chatId, m.role.name, m.kind.name, m.content, m.reasoning, m.status.name, _ms(m.createdAt),
        m.sources.join('\n'), m.voice ? 1 : 0, m.documentId,
      ],
    );
    _db.execute('UPDATE chats SET updated_at = ? WHERE id = ?;', [_ms(DateTime.now()), m.chatId]);
  }

  List<String> _attachmentPaths(String where, [List<Object?> args = const []]) => [
        for (final r in _db.select('SELECT d.path FROM documents d JOIN chats c ON c.id = d.chat_id WHERE $where;', args))
          r['path'] as String,
      ];

  @override
  Future<void> deleteChat(String id) async {
    final paths = _attachmentPaths('c.id = ?', [id]);
    _db.execute('DELETE FROM chats WHERE id = ?;', [id]);
    await _deleteFiles(paths);
  }

  @override
  Future<void> deleteAllChats() async {
    final paths = _attachmentPaths('1 = 1');
    _db.execute('DELETE FROM chats;');
    await _deleteFiles(paths);
  }

  @override
  Future<void> purgeEphemeral() async {
    final paths = _attachmentPaths('c.ephemeral = 1');
    _db.execute('DELETE FROM chats WHERE ephemeral = 1;');
    await _deleteFiles(paths);
  }
}

class SqliteModelRepository implements ModelRepository {
  SqliteModelRepository(this._database);
  final AppDatabase _database;
  Database get _db => _database.db;

  @override
  Future<Map<String, InstalledModel>> installedModels() async => {
        for (final r in _db.select('SELECT * FROM installed_models;'))
          r['base_model_id'] as String: InstalledModel(
            baseModelId: r['base_model_id'] as String,
            path: r['path'] as String,
            bytes: r['bytes'] as int,
            sha256: r['sha256'] as String,
            installedAt: _dt(r['installed_at']),
          ),
      };

  @override
  Future<Set<String>> installedEntries() async =>
      {for (final r in _db.select('SELECT entry_id FROM installed_entries;')) r['entry_id'] as String};

  @override
  Future<Map<String, String?>> installedEntryBases() async => {
        for (final r in _db.select('SELECT entry_id, base_model_id FROM installed_entries;'))
          r['entry_id'] as String: r['base_model_id'] as String?,
      };

  @override
  Future<void> markModelInstalled(InstalledModel m) async => _db.execute(
        'INSERT OR REPLACE INTO installed_models (base_model_id, path, bytes, sha256, installed_at) VALUES (?, ?, ?, ?, ?);',
        [m.baseModelId, m.path, m.bytes, m.sha256, _ms(m.installedAt)],
      );

  @override
  Future<void> markEntryInstalled(String entryId, {String? baseModelId}) async => _db.execute(
        'INSERT OR REPLACE INTO installed_entries (entry_id, installed_at, base_model_id) VALUES (?, ?, ?);',
        [entryId, _ms(DateTime.now()), baseModelId],
      );

  @override
  Future<void> removeEntry(String entryId) async =>
      _db.execute('DELETE FROM installed_entries WHERE entry_id = ?;', [entryId]);

  @override
  Future<void> removeModel(String baseModelId) async =>
      _db.execute('DELETE FROM installed_models WHERE base_model_id = ?;', [baseModelId]);
}

class ProjectRepository {
  ProjectRepository(this._database);
  final AppDatabase _database;
  Database get _db => _database.db;

  Project _project(Row r) => Project(
        id: r['id'] as String,
        name: r['name'] as String,
        color: r['color'] as int,
        createdAt: _dt(r['created_at']),
        updatedAt: _dt(r['updated_at']),
      );

  Future<List<Project>> list() async =>
      _db.select('SELECT * FROM projects ORDER BY updated_at DESC;').map(_project).toList();

  Future<Project?> get(String id) async {
    final rows = _db.select('SELECT * FROM projects WHERE id = ?;', [id]);
    return rows.isEmpty ? null : _project(rows.first);
  }

  Future<Project> create(String name, int color) async {
    final now = DateTime.now();
    final p = Project(id: newId(), name: name, color: color, createdAt: now, updatedAt: now);
    _db.execute('INSERT INTO projects (id, name, color, created_at, updated_at) VALUES (?, ?, ?, ?, ?);',
        [p.id, p.name, p.color, _ms(now), _ms(now)]);
    return p;
  }

  Future<void> rename(String id, String name) async =>
      _db.execute('UPDATE projects SET name = ?, updated_at = ? WHERE id = ?;', [name, _ms(DateTime.now()), id]);

  Future<void> touch(String id) async =>
      _db.execute('UPDATE projects SET updated_at = ? WHERE id = ?;', [_ms(DateTime.now()), id]);

  /// Deletes the project and its files. Its chats stay, moved out of the project.
  Future<void> delete(String id) async {
    final paths = [for (final r in _db.select('SELECT path FROM documents WHERE project_id = ?;', [id])) r['path'] as String];
    _db.execute('DELETE FROM projects WHERE id = ?;', [id]);
    await _deleteFiles(paths);
  }
}

/// A chunk ready to store: text plus an optional int8 vector.
class ChunkInput {
  const ChunkInput({required this.ordinal, required this.text, this.embedding, this.scale = 0, this.model = ''});
  final int ordinal;
  final String text;
  final Int8List? embedding;
  final double scale;
  final String model;
}

class DocumentRepository {
  DocumentRepository(this._database);
  final AppDatabase _database;
  Database get _db => _database.db;
  bool get hasKeywordSearch => _database.hasFts;

  DocumentRecord _doc(Row r) => DocumentRecord(
        id: r['id'] as String,
        projectId: r['project_id'] as String?,
        chatId: r['chat_id'] as String?,
        name: r['name'] as String,
        ext: r['ext'] as String,
        bytes: r['bytes'] as int,
        path: r['path'] as String,
        status: DocumentStatus.parse(r['status'] as String),
        truncated: (r['truncated'] as int) == 1,
        createdAt: _dt(r['created_at']),
      );

  Future<void> add(DocumentRecord d) async => _db.execute(
        '''INSERT INTO documents (id, project_id, chat_id, name, ext, bytes, path, status, truncated, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);''',
        [d.id, d.projectId, d.chatId, d.name, d.ext, d.bytes, d.path, d.status.name, d.truncated ? 1 : 0, _ms(d.createdAt)],
      );

  Future<void> setStatus(String id, DocumentStatus status, {bool truncated = false}) async =>
      _db.execute('UPDATE documents SET status = ?, truncated = ? WHERE id = ?;', [status.name, truncated ? 1 : 0, id]);

  Future<DocumentRecord?> get(String id) async {
    final rows = _db.select('SELECT * FROM documents WHERE id = ?;', [id]);
    return rows.isEmpty ? null : _doc(rows.first);
  }

  Future<List<DocumentRecord>> forProject(String projectId) async =>
      _db.select('SELECT * FROM documents WHERE project_id = ? ORDER BY created_at;', [projectId]).map(_doc).toList();

  Future<List<DocumentRecord>> forChat(String chatId) async =>
      _db.select('SELECT * FROM documents WHERE chat_id = ? ORDER BY created_at;', [chatId]).map(_doc).toList();

  Future<void> delete(String id) async {
    final rows = _db.select('SELECT path FROM documents WHERE id = ?;', [id]);
    _db.execute('DELETE FROM documents WHERE id = ?;', [id]);
    await _deleteFiles(rows.map((r) => r['path'] as String));
  }

  Future<void> insertChunks(String documentId, List<ChunkInput> chunks) async {
    final stmt = _db.prepare(
        'INSERT INTO doc_chunks (document_id, ordinal, text, embedding, emb_scale, emb_model, emb_dim) VALUES (?, ?, ?, ?, ?, ?, ?);');
    _db.execute('BEGIN;');
    try {
      for (final c in chunks) {
        stmt.execute([
          documentId,
          c.ordinal,
          c.text,
          c.embedding == null ? null : Uint8List.view(c.embedding!.buffer, c.embedding!.offsetInBytes, c.embedding!.length),
          c.scale,
          c.model,
          c.embedding?.length ?? 0,
        ]);
      }
      _db.execute('COMMIT;');
    } on Object {
      _db.execute('ROLLBACK;');
      rethrow;
    } finally {
      stmt.dispose();
    }
  }

  ChunkRecord _chunk(Row r) {
    final blob = r['embedding'] as Uint8List?;
    return ChunkRecord(
      id: r['id'] as int,
      documentId: r['document_id'] as String,
      documentName: r['name'] as String,
      ordinal: r['ordinal'] as int,
      text: r['text'] as String,
      embedding: blob == null ? null : Int8List.view(blob.buffer, blob.offsetInBytes, blob.length),
      scale: (r['emb_scale'] as num).toDouble(),
      model: r['emb_model'] as String,
    );
  }

  static const _scope = "(d.project_id = ? OR d.chat_id = ?) AND d.status = 'ready'";

  /// Every searchable chunk of a project's files and/or a chat's attachments.
  Future<List<ChunkRecord>> chunksInScope({String? projectId, String? chatId}) async => _db
      .select('SELECT c.*, d.name FROM doc_chunks c JOIN documents d ON d.id = c.document_id WHERE $_scope ORDER BY c.id;',
          [projectId, chatId])
      .map(_chunk)
      .toList();

  Future<List<ChunkRecord>> chunksByOrdinal(String documentId, Iterable<int> ordinals) async {
    final list = ordinals.toList();
    if (list.isEmpty) return const [];
    final marks = List.filled(list.length, '?').join(', ');
    return _db
        .select('SELECT c.*, d.name FROM doc_chunks c JOIN documents d ON d.id = c.document_id '
            'WHERE c.document_id = ? AND c.ordinal IN ($marks);', [documentId, ...list])
        .map(_chunk)
        .toList();
  }

  /// Keyword search (FTS5 BM25), best first. Empty if FTS5 is unavailable.
  Future<List<int>> keywordSearch(String query, {String? projectId, String? chatId, int limit = 20}) async {
    if (!_database.hasFts) return const [];
    final terms = RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(query.toLowerCase())
        .map((m) => m.group(0)!)
        .where((t) => t.length > 1)
        .toSet()
        .take(16)
        .map((t) => '"$t"')
        .toList();
    if (terms.isEmpty) return const [];
    try {
      return _db
          .select(
            'SELECT c.id FROM doc_chunks_fts f JOIN doc_chunks c ON c.id = f.rowid JOIN documents d ON d.id = c.document_id '
            'WHERE doc_chunks_fts MATCH ? AND $_scope ORDER BY bm25(doc_chunks_fts) LIMIT ?;',
            [terms.join(' OR '), projectId, chatId, limit],
          )
          .map((r) => r['id'] as int)
          .toList();
    } on SqliteException {
      return const [];
    }
  }
}

class SettingsRepository implements Prefs {
  SettingsRepository(this._database);
  final AppDatabase _database;
  Database get _db => _database.db;

  @override
  String? getString(String key) {
    final rows = _db.select('SELECT value FROM settings WHERE key = ?;', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  void setString(String key, String value) =>
      _db.execute('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?);', [key, value]);

  @override
  bool getBool(String key, {required bool fallback}) {
    final v = getString(key);
    return v == null ? fallback : v == 'true';
  }

  @override
  void setBool(String key, bool value) => setString(key, value ? 'true' : 'false');

  @override
  int getInt(String key, {required int fallback}) => int.tryParse(getString(key) ?? '') ?? fallback;

  @override
  void setInt(String key, int value) => setString(key, '$value');
}

class ReportRepository {
  ReportRepository(this._database);
  final AppDatabase _database;
  Database get _db => _database.db;

  Future<void> add(ReportRecord r) async => _db.execute(
        'INSERT INTO reports (id, created_at, reason, note, question, reply, entry_id, sent_at) VALUES (?, ?, ?, ?, ?, ?, ?, NULL);',
        [r.id, _ms(r.createdAt), r.reason, r.note, r.question, r.reply, r.entryId],
      );

  Future<List<ReportRecord>> pending() async => _db
      .select('SELECT * FROM reports WHERE sent_at IS NULL ORDER BY created_at;')
      .map((r) => ReportRecord(
            id: r['id'] as String,
            createdAt: _dt(r['created_at']),
            reason: r['reason'] as String,
            note: r['note'] as String,
            question: r['question'] as String?,
            reply: r['reply'] as String?,
            entryId: r['entry_id'] as String?,
            sentAt: _dtOrNull(r['sent_at']),
          ))
      .toList();

  /// A sent report keeps only its timestamp; its text is erased.
  Future<void> markSent(String id) async => _db.execute(
        "UPDATE reports SET sent_at = ?, note = '', question = NULL, reply = NULL WHERE id = ?;",
        [_ms(DateTime.now()), id],
      );
}

/// In-memory chat repository for tests.
class InMemoryChatRepository implements ChatRepository {
  final Map<String, ChatSummary> _chats = {};
  final Map<String, List<ChatMessage>> _messages = {};

  @override
  Future<List<ChatSummary>> listChats({String? projectId}) async => _chats.values
      .where((c) => projectId == null || c.projectId == projectId)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<ChatSummary?> getChat(String id) async => _chats[id];

  @override
  Future<ChatSummary> createChat({required String entryId, String title = 'New chat', String? projectId, bool ephemeral = false}) async {
    final now = DateTime.now();
    final c = ChatSummary(id: newId(), title: title, entryId: entryId, createdAt: now, updatedAt: now, projectId: projectId, ephemeral: ephemeral);
    _chats[c.id] = c;
    _messages[c.id] = [];
    return c;
  }

  @override
  Future<void> renameChat(String id, String title) async {
    final c = _chats[id];
    if (c != null) _chats[id] = c.copyWith(title: title);
  }

  @override
  Future<List<ChatMessage>> messages(String chatId) async => List.of(_messages[chatId] ?? const []);

  @override
  Future<void> saveMessage(ChatMessage m) async {
    final list = _messages.putIfAbsent(m.chatId, () => []);
    final i = list.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      list[i] = m;
    } else {
      list.add(m);
    }
    final c = _chats[m.chatId];
    if (c != null) _chats[m.chatId] = c.copyWith(updatedAt: DateTime.now());
  }

  @override
  Future<void> deleteChat(String id) async {
    _chats.remove(id);
    _messages.remove(id);
  }

  @override
  Future<void> deleteAllChats() async {
    _chats.clear();
    _messages.clear();
  }

  @override
  Future<void> purgeEphemeral() async {
    final gone = _chats.values.where((c) => c.ephemeral).map((c) => c.id).toList();
    for (final id in gone) {
      await deleteChat(id);
    }
  }
}

/// In-memory model repository for tests.
class InMemoryModelRepository implements ModelRepository {
  final Map<String, InstalledModel> models = {};
  final Map<String, String?> entryBases = {};
  Set<String> get entries => entryBases.keys.toSet();

  @override
  Future<Map<String, InstalledModel>> installedModels() async => Map.of(models);

  @override
  Future<Set<String>> installedEntries() async => entries;

  @override
  Future<Map<String, String?>> installedEntryBases() async => Map.of(entryBases);

  @override
  Future<void> markModelInstalled(InstalledModel m) async => models[m.baseModelId] = m;

  @override
  Future<void> markEntryInstalled(String entryId, {String? baseModelId}) async => entryBases[entryId] = baseModelId;

  @override
  Future<void> removeEntry(String entryId) async => entryBases.remove(entryId);

  @override
  Future<void> removeModel(String baseModelId) async => models.remove(baseModelId);
}
