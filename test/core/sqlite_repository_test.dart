// Needs the host's SQLite library (libsqlite3) — CI installs it.
import 'package:flutter_test/flutter_test.dart';
import 'package:medha/core/inference/inference_engine.dart';
import 'package:medha/core/storage/database.dart';
import 'package:medha/core/storage/models.dart';
import 'package:medha/core/storage/repositories.dart';

void main() {
  late AppDatabase db;
  late SqliteChatRepository chats;
  late SqliteModelRepository models;

  setUp(() {
    db = AppDatabase.inMemory();
    chats = SqliteChatRepository(db);
    models = SqliteModelRepository(db);
  });

  tearDown(() => db.close());

  test('stores chats and messages, newest chat first', () async {
    final a = await chats.createChat(entryId: 'math-lite', title: 'A');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final b = await chats.createChat(entryId: 'math-lite', title: 'B');
    expect((await chats.listChats()).map((c) => c.id), [b.id, a.id]);

    final m = ChatMessage.create(chatId: a.id, role: ChatRole.user, content: 'hi');
    await chats.saveMessage(m);
    await chats.saveMessage(m.copyWith(content: 'hi there'));
    await chats.saveMessage(ChatMessage.create(chatId: a.id, role: ChatRole.assistant, content: 'hello', kind: MessageKind.refusal));

    final saved = await chats.messages(a.id);
    expect(saved.map((x) => x.content), ['hi there', 'hello']);
    expect(saved.last.kind, MessageKind.refusal);
    expect((await chats.listChats()).first.id, a.id, reason: 'a new message bumps the chat');
  });

  test('deleting a chat deletes its messages', () async {
    final a = await chats.createChat(entryId: 'math-lite');
    await chats.saveMessage(ChatMessage.create(chatId: a.id, role: ChatRole.user, content: 'x'));
    await chats.deleteChat(a.id);
    expect(await chats.getChat(a.id), isNull);
    expect(db.db.select('SELECT count(*) AS n FROM messages;').first['n'], 0);
  });

  test('records installed models and entries', () async {
    await models.markModelInstalled(
      InstalledModel(baseModelId: 'm', path: '/x/m.gguf', bytes: 10, sha256: 'ab', installedAt: DateTime(2026)),
    );
    await models.markEntryInstalled('math-lite');
    expect((await models.installedModels())['m']!.path, '/x/m.gguf');
    expect(await models.installedEntries(), {'math-lite'});
    await models.removeEntry('math-lite');
    expect(await models.installedEntries(), isEmpty);
  });

  test('open() rejects a malformed key', () {
    expect(() => AppDatabase.open('unused.db', keyHex: 'short'), throwsArgumentError);
  });
}
