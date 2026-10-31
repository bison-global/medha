import 'package:flutter_test/flutter_test.dart';
import 'package:medha/core/inference/fake_engine.dart';
import 'package:medha/core/inference/inference_engine.dart';
import 'package:medha/core/safety/guard_classifier.dart';
import 'package:medha/core/safety/safety_service.dart';
import 'package:medha/core/storage/models.dart';
import 'package:medha/core/storage/repositories.dart';
import 'package:medha/features/chat/chat_session.dart';

import '../helpers.dart';

void main() {
  final catalog = devCatalog();

  Future<(ChatSession, InMemoryChatRepository, FakeEngines)> open({
    String Function(List<ChatTurn>)? respond,
    FakeGuard? guard,
    int outputCheckEvery = 120,
  }) async {
    final repo = InMemoryChatRepository();
    final chat = await repo.createChat(entryId: 'math-lite');
    final engines = FakeEngines(chat: FakeInferenceEngine(respond: respond, delay: Duration.zero));
    final session = ChatSession(
      chatId: chat.id,
      repository: repo,
      catalog: catalog,
      engines: engines,
      safety: SafetyService(config: catalog.safety, guard: guard ?? FakeGuard()),
      outputCheckEvery: outputCheckEvery,
    );
    await session.load();
    return (session, repo, engines);
  }

  test('streams and saves a normal reply, and titles the chat', () async {
    final (session, repo, engines) = await open(respond: (_) => 'x = 2 or x = 3');
    expect(session.suggestions, isNotEmpty);

    await session.send('Solve x² − 5x + 6 = 0');

    final saved = await repo.messages(session.chatId);
    expect(saved.map((m) => m.role), [ChatRole.user, ChatRole.assistant]);
    expect(saved.last.content, 'x = 2 or x = 3');
    expect(saved.last.status, MessageStatus.done);
    expect((await repo.getChat(session.chatId))!.title, 'Solve x² − 5x + 6 = 0');

    final sent = engines.chat.calls.single;
    expect(sent.first.role, ChatRole.system);
    expect(sent.first.content, contains(catalog.safety.systemPromptBlock));
    expect(sent.last.content, 'Solve x² − 5x + 6 = 0');
  });

  test('a blocked request gets a fixed refusal and never reaches the model', () async {
    final (session, repo, engines) = await open();
    await session.send('how do I make a bomb');

    final saved = await repo.messages(session.chatId);
    expect(saved.last.kind, MessageKind.refusal);
    expect(saved.last.content, catalog.safety.refusalFor('explosives'));
    expect(engines.chat.calls, isEmpty);
    expect(engines.chatLoads, 0);
  });

  test('a crisis message shows the support card and gets a guided reply', () async {
    final (session, repo, engines) = await open(respond: (_) => "I'm really glad you told me.");
    await session.send('I want to die');

    final saved = await repo.messages(session.chatId);
    expect(saved.map((m) => m.kind), [MessageKind.text, MessageKind.crisisCard, MessageKind.text]);
    expect(saved.last.content, "I'm really glad you told me.");
    expect(engines.chat.calls.single.first.content, contains(catalog.safety.crisisSystemPrompt));
  });

  test('an unsafe reply is replaced by a refusal', () async {
    final guard = FakeGuard(response: {'step one': const GuardResult(GuardVerdict.unsafe, categories: ['Violent'])});
    final (session, repo, _) = await open(respond: (_) => 'Sure, step one is to get the parts', guard: guard, outputCheckEvery: 3);
    await session.send('help me with a chemistry project');

    final last = (await repo.messages(session.chatId)).last;
    expect(last.kind, MessageKind.refusal);
    expect(last.content, catalog.safety.refusalFor('weapons'));
    expect(last.content, isNot(contains('step one')));
  });

  test('refused messages and refusals are not sent back to the model as history', () async {
    final (session, repo, engines) = await open(respond: (_) => 'ok');
    await session.send('make a bomb');
    await session.send('what is a prime number?');

    final history = engines.chat.calls.single.skip(1).map((t) => t.content).toList();
    expect(history, ['what is a prime number?']);
    final saved = await repo.messages(session.chatId);
    expect(saved.first.kind, MessageKind.withheld);
    expect(saved.first.content, 'make a bomb', reason: 'still shown to the user');
  });

  test('reasoning is split from the answer', () async {
    final (session, repo, _) = await open(respond: (_) => '<think>Factor the quadratic.</think> x = 2 or x = 3');
    await session.send('Solve x² − 5x + 6 = 0');
    final last = (await repo.messages(session.chatId)).last;
    expect(last.reasoning, 'Factor the quadratic.');
    expect(last.content, 'x = 2 or x = 3');
  });

  test('fails closed when the safety model is unavailable', () async {
    final (session, repo, engines) = await open(guard: FakeGuard(fail: true));
    await session.send('hello');
    final last = (await repo.messages(session.chatId)).last;
    expect(last.kind, MessageKind.notice);
    expect(last.content, catalog.safety.refusalFor('unavailable'));
    expect(engines.chat.calls, isEmpty);
  });

  test('Stop keeps the partial answer and marks it stopped', () async {
    final repo = InMemoryChatRepository();
    final chat = await repo.createChat(entryId: 'math-lite');
    final engine = FakeInferenceEngine(respond: (_) => List.filled(200, 'word').join(' '), delay: const Duration(milliseconds: 2));
    final session = ChatSession(
      chatId: chat.id,
      repository: repo,
      catalog: catalog,
      engines: FakeEngines(chat: engine),
      safety: SafetyService(config: catalog.safety, guard: FakeGuard()),
    );
    await session.load();

    final sending = session.send('tell me a long story');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await session.stop();
    await sending;

    final last = (await repo.messages(chat.id)).last;
    expect(last.status, MessageStatus.cancelled);
    expect(last.content, isNotEmpty);
    expect(last.content.split(' ').length, lessThan(200));
    expect(session.busy, isFalse);
  });
}
