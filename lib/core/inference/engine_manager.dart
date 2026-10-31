import 'dart:io';
import 'dart:math';

import '../catalog/catalog.dart';
import 'inference_engine.dart';

/// Loads the right models into the chat and guard engines.
abstract interface class ChatEngines {
  InferenceEngine get chat;
  InferenceEngine get guard;
  Future<void> ensureChat(InterestEntry entry);
  Future<void> ensureGuard();
}

class EngineManager implements ChatEngines {
  EngineManager({required this.catalog, required this.modelPath, required this.chat, required this.guard});

  final Catalog catalog;
  final String Function(BaseModel model) modelPath;
  @override
  final InferenceEngine chat;
  @override
  final InferenceEngine guard;

  /// Leave one performance core free for the UI.
  static int get defaultThreads => max(1, min(6, Platform.numberOfProcessors - 1));

  /// Metal on iOS; CPU on Android until Vulkan is validated per device.
  static int get defaultGpuLayers => Platform.isIOS ? -1 : 0;

  ModelHandle _handle(BaseModel m, int contextTokens, {int? threads}) => ModelHandle(
        id: m.id,
        path: modelPath(m),
        contextTokens: contextTokens,
        promptTemplate: m.promptTemplate,
        threads: threads ?? defaultThreads,
        gpuLayers: defaultGpuLayers,
      );

  @override
  Future<void> ensureChat(InterestEntry entry) => chat.load(_handle(catalog.baseModel(entry.baseModelId), entry.contextTokens));

  @override
  Future<void> ensureGuard() => guard.load(_handle(catalog.guardModel, 2048, threads: 2));
}
