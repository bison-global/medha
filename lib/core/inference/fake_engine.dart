import 'inference_engine.dart';

/// A scripted engine for tests and UI development (`--dart-define=MEDHA_FAKE_ENGINE=true`).
/// It streams [respond]'s answer word by word.
class FakeInferenceEngine implements InferenceEngine {
  FakeInferenceEngine({String Function(List<ChatTurn> turns)? respond, String Function(String prompt)? respondRaw, this.delay = const Duration(milliseconds: 25)})
      : _respond = respond ?? _defaultRespond,
        _respondRaw = respondRaw ?? ((_) => 'Safety: Safe\nCategories: None');

  final String Function(List<ChatTurn>) _respond;
  final String Function(String) _respondRaw;
  final Duration delay;

  String? _loaded;
  bool _cancelled = false;
  final List<List<ChatTurn>> calls = [];
  final List<String> rawCalls = [];

  @override
  String? get loadedModelId => _loaded;

  @override
  Future<void> load(ModelHandle model) async => _loaded = model.id;

  @override
  final List<String> prefixes = [];

  @override
  Stream<String> generate(List<ChatTurn> turns, GenerationParams params, {String assistantPrefix = ''}) {
    calls.add(List.of(turns));
    prefixes.add(assistantPrefix);
    return _stream(_respond(turns), params.maxTokens);
  }

  @override
  Stream<String> generateRaw(String prompt, GenerationParams params) {
    rawCalls.add(prompt);
    return _stream(_respondRaw(prompt), params.maxTokens);
  }

  Stream<String> _stream(String text, int maxTokens) async* {
    _cancelled = false;
    final pieces = RegExp(r'\S+\s*|\s+').allMatches(text).map((m) => m.group(0)!).toList();
    var n = 0;
    for (final p in pieces) {
      if (_cancelled || n >= maxTokens) return;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (_cancelled) return;
      n++;
      yield p;
    }
  }

  @override
  Future<void> cancel() async => _cancelled = true;

  @override
  Future<void> unload() async => _loaded = null;

  static String _defaultRespond(List<ChatTurn> turns) {
    final last = turns.lastWhere((t) => t.role == ChatRole.user, orElse: () => const ChatTurn(ChatRole.user, ''));
    return 'This is Medha running in demo mode, so there is no real model loaded. '
        'You asked: "${last.content}". With a downloaded model, the answer would be generated here on your phone.';
  }
}
