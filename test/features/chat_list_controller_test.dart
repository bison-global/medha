import 'package:flutter_test/flutter_test.dart';
import 'package:medha/core/storage/repositories.dart';
import 'package:medha/features/chat/chat_list_controller.dart';

void main() {
  test('delete hides a chat at once and removes it after the undo window', () async {
    final repo = InMemoryChatRepository();
    final a = await repo.createChat(entryId: 'math-lite', title: 'A');
    await repo.createChat(entryId: 'math-lite', title: 'B');
    final list = ChatListController(repo, undoWindow: const Duration(milliseconds: 50));
    await list.refresh();
    expect(list.chats, hasLength(2));

    list.delete(a.id);
    expect(list.chats.map((c) => c.title), ['B']);
    expect(await repo.getChat(a.id), isNotNull, reason: 'not committed yet');

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(await repo.getChat(a.id), isNull);
    expect(list.chats.map((c) => c.title), ['B']);
  });

  test('undo brings the chat back and nothing is deleted', () async {
    final repo = InMemoryChatRepository();
    final a = await repo.createChat(entryId: 'math-lite', title: 'A');
    final list = ChatListController(repo, undoWindow: const Duration(milliseconds: 50));
    await list.refresh();

    list.delete(a.id);
    list.undo(a.id);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(await repo.getChat(a.id), isNotNull);
    expect(list.chats, hasLength(1));
  });

  test('delete all clears everything', () async {
    final repo = InMemoryChatRepository();
    await repo.createChat(entryId: 'math-lite');
    await repo.createChat(entryId: 'math-lite');
    final list = ChatListController(repo);
    await list.refresh();
    await list.deleteAll();
    expect(list.chats, isEmpty);
    expect(await repo.listChats(), isEmpty);
  });
}
