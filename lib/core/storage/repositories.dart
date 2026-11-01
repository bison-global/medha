import 'package:sqlite3/sqlite3.dart';

import '../inference/inference_engine.dart';
import 'database.dart';
import 'models.dart';

abstract interface class ChatRepository {
  Future<List<ChatSummary>> listChats();
  Future<ChatSummary?> getChat(String id);
  Future<ChatSummary> createChat({required String entryId, String title = 'New chat'});
  Future<void> renameChat(String id, String title);
  Future<List<ChatMessage>> messages(String chatId);

  /// Inserts or replaces a message and bumps the chat's `updatedAt`.
  Future<void> saveMessage(ChatMessage message);
  Future<void> deleteChat(String id);
  Future<void> deleteAllChats();
}

abstract interface class ModelRepository {
  Future<Map<String, InstalledModel>> installedModels();
  Future<Set<String>> installedEntries();
  Future<void> markModelInstalled(InstalledModel model);
  Future<void> markEntryInstalled(String entryId);
  Future<void> removeEntry(String entryId);
  Future<void> removeModel(String baseModelId);
}

int _ms(DateTime t) => t.millisecondsSinceEpoch;
DateTime _dt(Object? v) => DateTime.fromMillisecondsSinceEpoch(v! as int);

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
      );

  @override
  Future<List<ChatSummary>> listChats() async =>
      _db.select('SELECT * FROM chats ORDER BY updated_at DESC;').map(_chat).toList();

  @override
  Future<ChatSummary?> getChat(String id) async {
    final rows = _db.select('SELECT * FROM chats WHERE id = ?;', [id]);
    return rows.isEmpty ? null : _chat(rows.first);
  }

  @override
  Future<ChatSummary> createChat({required String entryId, String title = 'New chat'}) async {
    final now = DateTime.now();
    final chat = ChatSummary(id: newId(), title: title, entryId: entryId, createdAt: now, updatedAt: now);
    _db.execute(
      'INSERT INTO chats (id, title, entry_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?);',
      [chat.id, chat.title, chat.entryId, _ms(now), _ms(now)],
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
          ))
      .toList();

  @override
  Future<void> saveMessage(ChatMessage m) async {
    _db.execute(
      '''INSERT INTO messages (id, chat_id, role, kind, content, reasoning, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET content = excluded.content, reasoning = excluded.reasoning,
           status = excluded.status, kind = excluded.kind;''',
      [m.id, m.chatId, m.role.name, m.kind.name, m.content, m.reasoning, m.status.name, _ms(m.createdAt)],
    );
    _db.execute('UPDATE chats SET updated_at = ? WHERE id = ?;', [_ms(DateTime.now()), m.chatId]);
  }

  @override
  Future<void> deleteChat(String id) async => _db.execute('DELETE FROM chats WHERE id = ?;', [id]);

  @override
  Future<void> deleteAllChats() async => _db.execute('DELETE FROM chats;');
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
  Future<void> markModelInstalled(InstalledModel m) async => _db.execute(
        'INSERT OR REPLACE INTO installed_models (base_model_id, path, bytes, sha256, installed_at) VALUES (?, ?, ?, ?, ?);',
        [m.baseModelId, m.path, m.bytes, m.sha256, _ms(m.installedAt)],
      );

  @override
  Future<void> markEntryInstalled(String entryId) async => _db.execute(
        'INSERT OR REPLACE INTO installed_entries (entry_id, installed_at) VALUES (?, ?);',
        [entryId, _ms(DateTime.now())],
      );

  @override
  Future<void> removeEntry(String entryId) async =>
      _db.execute('DELETE FROM installed_entries WHERE entry_id = ?;', [entryId]);

  @override
  Future<void> removeModel(String baseModelId) async =>
      _db.execute('DELETE FROM installed_models WHERE base_model_id = ?;', [baseModelId]);
}

/// In-memory repositories for tests and demo mode.
class InMemoryChatRepository implements ChatRepository {
  final Map<String, ChatSummary> _chats = {};
  final Map<String, List<ChatMessage>> _messages = {};

  @override
  Future<List<ChatSummary>> listChats() async =>
      _chats.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<ChatSummary?> getChat(String id) async => _chats[id];

  @override
  Future<ChatSummary> createChat({required String entryId, String title = 'New chat'}) async {
    final now = DateTime.now();
    final c = ChatSummary(id: newId(), title: title, entryId: entryId, createdAt: now, updatedAt: now);
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
}

class InMemoryModelRepository implements ModelRepository {
  final Map<String, InstalledModel> models = {};
  final Set<String> entries = {};

  @override
  Future<Map<String, InstalledModel>> installedModels() async => Map.of(models);

  @override
  Future<Set<String>> installedEntries() async => Set.of(entries);

  @override
  Future<void> markModelInstalled(InstalledModel m) async => models[m.baseModelId] = m;

  @override
  Future<void> markEntryInstalled(String entryId) async => entries.add(entryId);

  @override
  Future<void> removeEntry(String entryId) async => entries.remove(entryId);

  @override
  Future<void> removeModel(String baseModelId) async => models.remove(baseModelId);
}
