import '../catalog/catalog.dart';
import '../inference/inference_engine.dart';

enum GuardVerdict { safe, controversial, unsafe }

class GuardResult {
  const GuardResult(this.verdict, {this.categories = const [], this.refusal});

  final GuardVerdict verdict;

  /// Category names as the guard model writes them (e.g. "Violent").
  final List<String> categories;

  /// Response checks only: whether the reply was itself a refusal.
  final bool? refusal;

  bool get isSelfHarm => categories.any((c) => c.toLowerCase().contains('self-harm') || c.toLowerCase().contains('suicide'));

  @override
  String toString() => 'GuardResult(${verdict.name}, $categories)';
}

class GuardUnavailableException implements Exception {
  GuardUnavailableException(this.message);
  final String message;
  @override
  String toString() => 'GuardUnavailableException: $message';
}

/// Parses Qwen3Guard-Gen output, e.g.
/// `Safety: Unsafe\nCategories: Violent\nRefusal: No`.
/// Returns null if the text is not in that format.
GuardResult? parseGuardOutput(String text) {
  final safety = RegExp(r'Safety:\s*(Safe|Unsafe|Controversial)', caseSensitive: false).firstMatch(text);
  if (safety == null) return null;
  final verdict = switch (safety.group(1)!.toLowerCase()) {
    'unsafe' => GuardVerdict.unsafe,
    'controversial' => GuardVerdict.controversial,
    _ => GuardVerdict.safe,
  };
  final cats = RegExp(r'Categories:\s*([^\n]+)', caseSensitive: false).firstMatch(text)?.group(1);
  final categories = cats == null
      ? const <String>[]
      : cats.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty && c.toLowerCase() != 'none').toList();
  final refusalText = RegExp(r'Refusal:\s*(Yes|No)', caseSensitive: false).firstMatch(text)?.group(1);
  return GuardResult(verdict, categories: categories, refusal: refusalText == null ? null : refusalText.toLowerCase() == 'yes');
}

abstract interface class GuardClassifier {
  Future<GuardResult> checkPrompt(String userText);
  Future<GuardResult> checkResponse(String userText, String assistantText);
}

/// Fills `{{user}}` / `{{assistant}}` in one pass, so text that itself
/// contains a placeholder can't inject into the other slot.
String fillGuardTemplate(String template, {required String user, String assistant = ''}) =>
    template.replaceAllMapped(RegExp(r'\{\{(user|assistant)\}\}'), (m) => m.group(1) == 'user' ? user : assistant);

/// Layer 2 and 4: runs the guard model (Qwen3Guard-Gen-0.6B) on-device.
class ModelGuardClassifier implements GuardClassifier {
  ModelGuardClassifier({required this.engine, required this.config, this.maxInputChars = 6000});

  final InferenceEngine engine;
  final SafetyConfig config;

  /// Long inputs are clipped (start and end kept) to bound guard latency.
  final int maxInputChars;

  static const _params = GenerationParams(sampling: SamplingParams.greedy, maxTokens: 48);

  String _clip(String s) {
    if (s.length <= maxInputChars) return s;
    final half = maxInputChars ~/ 2;
    return '${s.substring(0, half)}\n…\n${s.substring(s.length - half)}';
  }

  Future<GuardResult> _run(String prompt) async {
    if (engine.loadedModelId == null) throw GuardUnavailableException('Safety model is not loaded');
    final out = StringBuffer();
    try {
      await for (final chunk in engine.generateRaw(prompt, _params)) {
        out.write(chunk);
      }
    } on Object catch (e) {
      throw GuardUnavailableException('$e');
    }
    final parsed = parseGuardOutput(out.toString());
    if (parsed == null) throw GuardUnavailableException('Unexpected safety model output');
    return parsed;
  }

  @override
  Future<GuardResult> checkPrompt(String userText) =>
      _run(fillGuardTemplate(config.guardPromptTemplate, user: _clip(userText)));

  @override
  Future<GuardResult> checkResponse(String userText, String assistantText) => _run(
      fillGuardTemplate(config.guardResponseTemplate, user: _clip(userText), assistant: _clip(assistantText)));
}
