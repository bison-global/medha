import '../catalog/catalog.dart';

enum ChatRole {
  system,
  user,
  assistant;

  String get wire => name;
}

class ChatTurn {
  const ChatTurn(this.role, this.content);
  final ChatRole role;
  final String content;

  @override
  String toString() => '${role.wire}: $content';
}

class GenerationParams {
  const GenerationParams({required this.sampling, required this.maxTokens, this.seed = 0xC0FFEE});
  final SamplingParams sampling;
  final int maxTokens;
  final int seed;
}

/// Where a model lives on disk and how to run it.
class ModelHandle {
  const ModelHandle({
    required this.id,
    required this.path,
    required this.contextTokens,
    required this.promptTemplate,
    this.threads = 4,
    this.gpuLayers = 0,
  });

  final String id;
  final String path;
  final int contextTokens;
  final String promptTemplate;
  final int threads;
  final int gpuLayers;
}

/// Runs one model. Implementations must never block the UI isolate.
abstract interface class InferenceEngine {
  String? get loadedModelId;

  Future<void> load(ModelHandle model);

  /// Streams decoded text as the model writes it. The stream ends when the
  /// model finishes, [GenerationParams.maxTokens] is reached or [cancel] is
  /// called. [assistantPrefix] is appended after the assistant header, so the
  /// model continues an answer it already started (used to close a capped
  /// reasoning block).
  Stream<String> generate(List<ChatTurn> turns, GenerationParams params, {String assistantPrefix = ''});

  /// Like [generate] but with a prompt that is already formatted (used by the
  /// guard model, whose prompt comes pre-rendered from the catalog).
  Stream<String> generateRaw(String prompt, GenerationParams params);

  Future<void> cancel();

  Future<void> unload();
}
