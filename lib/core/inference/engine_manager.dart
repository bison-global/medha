import 'dart:io';
import 'dart:math';

import '../catalog/catalog.dart';
import 'inference_engine.dart';

/// Loads the right models into the chat, guard and embedding engines.
abstract interface class ChatEngines {
  InferenceEngine get chat;
  InferenceEngine get guard;
  EmbeddingEngine get embedder;
  Future<void> ensureChat(InterestEntry entry);
  Future<void> ensureGuard();

  /// Loads the document-search model. Returns false if it isn't installed.
  Future<bool> ensureEmbedder();
}

class EngineManager implements ChatEngines {
  EngineManager({
    required this.catalog,
    required this.modelPath,
    required this.adapterPath,
    required this.baseFor,
    required this.isInstalled,
    required this.chat,
    required this.guard,
    required this.embedder,
  });

  final Catalog catalog;
  final String Function(BaseModel model) modelPath;
  final String Function(AdapterFile adapter) adapterPath;

  /// The base model an entry was installed with (may be the fallback).
  final Future<String> Function(InterestEntry entry) baseFor;
  final Future<bool> Function(BaseModel model) isInstalled;

  @override
  final InferenceEngine chat;
  @override
  final InferenceEngine guard;
  @override
  final EmbeddingEngine embedder;

  /// Leave one performance core free for the UI.
  static int get defaultThreads => max(1, min(6, Platform.numberOfProcessors - 1));

  /// Metal on iOS; CPU on Android until Vulkan is validated per device.
  static int get defaultGpuLayers => Platform.isIOS ? -1 : 0;

  ModelHandle _handle(BaseModel m, int contextTokens, {int? threads, String? adapter, double adapterScale = 1}) => ModelHandle(
        id: m.id,
        path: modelPath(m),
        contextTokens: contextTokens,
        promptTemplate: m.promptTemplate,
        threads: threads ?? defaultThreads,
        gpuLayers: defaultGpuLayers,
        adapterPath: adapter,
        adapterScale: adapterScale,
      );

  @override
  Future<void> ensureChat(InterestEntry entry) async {
    final base = catalog.baseModel(await baseFor(entry));
    final a = entry.adapter;
    // Add-ons are trained for the default base, so skip them on the fallback.
    final useAdapter = a != null && a.url.isNotEmpty && base.id == entry.baseModelId && await File(adapterPath(a)).exists();
    await chat.load(_handle(base, entry.contextTokens,
        adapter: useAdapter ? adapterPath(a) : null, adapterScale: a?.scale ?? 1));
  }

  @override
  Future<void> ensureGuard() => guard.load(_handle(catalog.guardModel, 2048, threads: 2));

  @override
  Future<bool> ensureEmbedder() async {
    final m = catalog.embeddingModel;
    if (m == null || !await isInstalled(m)) return false;
    await embedder.load(modelPath(m));
    return true;
  }
}
