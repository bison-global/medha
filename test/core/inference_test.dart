import 'package:flutter_test/flutter_test.dart';
import 'package:medha/core/inference/context_builder.dart';
import 'package:medha/core/inference/inference_engine.dart';
import 'package:medha/core/inference/prompt_format.dart';
import 'package:medha/core/inference/thinking.dart';

import '../helpers.dart';

void main() {
  group('formatPrompt', () {
    const turns = [
      ChatTurn(ChatRole.system, 'S'),
      ChatTurn(ChatRole.user, 'U1'),
      ChatTurn(ChatRole.assistant, 'A1'),
      ChatTurn(ChatRole.user, 'U2'),
    ];

    test('chatml', () {
      expect(
        formatPrompt('chatml', turns),
        '<|im_start|>system\nS<|im_end|>\n<|im_start|>user\nU1<|im_end|>\n'
        '<|im_start|>assistant\nA1<|im_end|>\n<|im_start|>user\nU2<|im_end|>\n<|im_start|>assistant\n',
      );
    });

    test('gemma folds the system prompt into the first user turn', () {
      expect(
        formatPrompt('gemma', turns),
        '<start_of_turn>user\nS\n\nU1<end_of_turn>\n<start_of_turn>model\nA1<end_of_turn>\n'
        '<start_of_turn>user\nU2<end_of_turn>\n<start_of_turn>model\n',
      );
    });
  });

  group('ThinkingSplitter', () {
    test('separates reasoning from the answer as text streams in', () {
      final s = ThinkingSplitter();
      s.add('<thi');
      expect(s.undecided, isTrue);
      expect(s.answer, '');
      s.add('nk>Factor it.');
      expect(s.inReasoning, isTrue);
      expect(s.reasoning, 'Factor it.');
      expect(s.answer, '');
      s.add('</think>\n\nx = 2 or x = 3');
      expect(s.inReasoning, isFalse);
      expect(s.reasoning, 'Factor it.');
      expect(s.answer, 'x = 2 or x = 3');
    });

    test('passes plain answers straight through', () {
      final s = ThinkingSplitter()..add('Hello there');
      expect(s.answer, 'Hello there');
      expect(s.reasoning, '');
    });
  });

  group('ContextBuilder', () {
    final catalog = devCatalog();
    final entry = catalog.interestEntry('math-lite');
    const builder = ContextBuilder();

    test('starts with the safety block and the interest prompt', () {
      final turns = builder.build(
        safety: catalog.safety,
        entry: entry,
        history: const [ChatTurn(ChatRole.user, 'hi')],
        crisis: false,
      );
      expect(turns.first.role, ChatRole.system);
      expect(turns.first.content, startsWith(catalog.safety.systemPromptBlock));
      expect(turns.first.content, contains(entry.systemPrompt));
      expect(turns.first.content, isNot(contains(catalog.safety.crisisSystemPrompt)));
      expect(turns.last.content, 'hi');
    });

    test('adds the crisis prompt when asked', () {
      final turns = builder.build(safety: catalog.safety, entry: entry, history: const [ChatTurn(ChatRole.user, 'hi')], crisis: true);
      expect(turns.first.content, contains(catalog.safety.crisisSystemPrompt));
    });

    test('drops the oldest turns to fit the context window', () {
      final long = 'x' * 2000;
      final history = [
        for (var i = 0; i < 20; i++) ...[
          ChatTurn(ChatRole.user, 'q$i $long'),
          ChatTurn(ChatRole.assistant, 'a$i $long'),
        ],
        const ChatTurn(ChatRole.user, 'latest question'),
      ];
      final turns = builder.build(safety: catalog.safety, entry: entry, history: history, crisis: false);
      final total = turns.fold<int>(0, (n, t) => n + builder.estimateTokens(t.content));
      expect(total, lessThanOrEqualTo(entry.contextTokens - entry.maxNewTokens - entry.thinking.maxTokens));
      expect(turns.last.content, 'latest question');
      expect(turns[1].role, ChatRole.user, reason: 'history must not start with an assistant turn');
      expect(turns.length, lessThan(history.length + 1));
    });
  });
}
