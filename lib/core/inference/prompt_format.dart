import 'inference_engine.dart';

/// Formats a conversation for models whose GGUF template llama.cpp can't
/// apply natively. The catalog's `promptTemplate` picks the format.
String formatPrompt(String template, List<ChatTurn> turns, {bool addAssistant = true}) {
  switch (template) {
    case 'gemma':
      return _gemma(turns, addAssistant);
    case 'chatml':
    default:
      return _chatml(turns, addAssistant);
  }
}

String _chatml(List<ChatTurn> turns, bool addAssistant) {
  final b = StringBuffer();
  for (final t in turns) {
    b
      ..write('<|im_start|>')
      ..write(t.role.wire)
      ..write('\n')
      ..write(t.content)
      ..write('<|im_end|>\n');
  }
  if (addAssistant) b.write('<|im_start|>assistant\n');
  return b.toString();
}

/// Gemma has no system role: the system text is folded into the first user turn.
String _gemma(List<ChatTurn> turns, bool addAssistant) {
  final b = StringBuffer();
  final system = turns.where((t) => t.role == ChatRole.system).map((t) => t.content).join('\n\n');
  var systemPending = system.isNotEmpty;
  for (final t in turns) {
    if (t.role == ChatRole.system) continue;
    final role = t.role == ChatRole.assistant ? 'model' : 'user';
    b.write('<start_of_turn>$role\n');
    if (systemPending && t.role == ChatRole.user) {
      b
        ..write(system)
        ..write('\n\n');
      systemPending = false;
    }
    b
      ..write(t.content)
      ..write('<end_of_turn>\n');
  }
  if (addAssistant) b.write('<start_of_turn>model\n');
  return b.toString();
}
