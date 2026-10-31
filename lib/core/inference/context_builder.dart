import 'dart:math';

import '../catalog/catalog.dart';
import 'inference_engine.dart';

/// Builds the turns sent to the model: safety block + interest prompt, then
/// as many recent turns as fit the context window (ARCHITECTURE.md §5.4).
class ContextBuilder {
  const ContextBuilder({this.charsPerToken = 3.5, this.reserveTokens = 64});

  /// Conservative chars-per-token estimate; real tokenisation happens in
  /// llama.cpp, which rejects prompts that still don't fit.
  final double charsPerToken;
  final int reserveTokens;

  int estimateTokens(String s) => (s.length / charsPerToken).ceil() + 4;

  String systemPrompt(SafetyConfig safety, InterestEntry entry, {required bool crisis}) {
    final parts = [safety.systemPromptBlock, entry.systemPrompt, if (crisis) safety.crisisSystemPrompt];
    return parts.where((p) => p.trim().isNotEmpty).join('\n\n');
  }

  List<ChatTurn> build({
    required SafetyConfig safety,
    required InterestEntry entry,
    required List<ChatTurn> history,
    required bool crisis,
  }) {
    final system = ChatTurn(ChatRole.system, systemPrompt(safety, entry, crisis: crisis));
    final budget = entry.contextTokens - entry.maxNewTokens - entry.thinking.maxTokens - reserveTokens;
    var used = estimateTokens(system.content);

    final kept = <ChatTurn>[];
    for (final turn in history.reversed) {
      final cost = estimateTokens(turn.content);
      if (kept.isNotEmpty && used + cost > budget) break;
      kept.add(turn);
      used += cost;
    }

    // The newest user message is always kept, trimmed if it alone is too long.
    if (kept.isNotEmpty && used > budget) {
      final newest = kept.first;
      final fit = ((budget - estimateTokens(system.content)) * charsPerToken).floor();
      final allowedChars = min(max(fit, 200), newest.content.length);
      kept[0] = ChatTurn(newest.role, newest.content.substring(newest.content.length - allowedChars));
    }

    // A conversation must not start with an assistant turn after the system prompt.
    final ordered = kept.reversed.toList();
    while (ordered.isNotEmpty && ordered.first.role == ChatRole.assistant) {
      ordered.removeAt(0);
    }
    return [system, ...ordered];
  }
}
