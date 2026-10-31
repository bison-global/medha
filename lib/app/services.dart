import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/catalog/catalog.dart';
import '../core/catalog/catalog_service.dart';
import '../core/download/model_downloader.dart';
import '../core/download/model_installer.dart';
import '../core/inference/engine_manager.dart';
import '../core/inference/fake_engine.dart';
import '../core/inference/inference_engine.dart';
import '../core/inference/llama_engine.dart';
import '../core/safety/guard_classifier.dart';
import '../core/safety/safety_service.dart';
import '../core/storage/database.dart';
import '../core/storage/repositories.dart';
import '../core/storage/secure_keys.dart';

/// Build-time switches (`--dart-define`).
abstract final class BuildFlags {
  /// Scripted engine + simulated downloads, for UI work without model files.
  static const demo = bool.fromEnvironment('MEDHA_FAKE_ENGINE');

  /// Allows the unsigned development catalog. Always on in debug builds.
  static const allowUnsignedCatalog = bool.fromEnvironment('MEDHA_ALLOW_UNSIGNED_CATALOG');

  /// Where to fetch catalog updates from (empty = bundled catalog only).
  static const catalogUrl = String.fromEnvironment('MEDHA_CATALOG_URL');
}

/// Everything the app needs, created once at startup.
class AppServices {
  AppServices({
    required this.catalog,
    required this.chatRepository,
    required this.modelRepository,
    required this.engines,
    required this.installer,
    required this.safety,
    required this.demo,
  });

  final Catalog catalog;
  final ChatRepository chatRepository;
  final ModelRepository modelRepository;
  final ChatEngines engines;
  final Installer installer;
  final SafetyService safety;
  final bool demo;

  static Future<AppServices> create({required bool demo}) async {
    final support = await getApplicationSupportDirectory();

    final catalogService = CatalogService(
      verifier: CatalogVerifier(allowUnsigned: kDebugMode || demo || BuildFlags.allowUnsignedCatalog),
      cacheFile: File(p.join(support.path, 'catalog.json')),
      loadBundled: () => rootBundle.loadString('assets/catalog/catalog.dev.json'),
      remoteUrl: BuildFlags.catalogUrl.isEmpty ? null : Uri.parse(BuildFlags.catalogUrl),
    );
    final catalog = await catalogService.load();

    final ChatRepository chats;
    final ModelRepository models;
    if (demo) {
      chats = InMemoryChatRepository();
      models = InMemoryModelRepository();
    } else {
      final db = AppDatabase.open(p.join(support.path, 'medha.db'), keyHex: await SecureKeys().databaseKey());
      chats = SqliteChatRepository(db);
      models = SqliteModelRepository(db);
    }

    final modelsDir = Directory(p.join(support.path, 'models'));
    String modelPath(BaseModel m) => p.join(modelsDir.path, m.fileName);

    final ChatEngines engines = EngineManager(
      catalog: catalog,
      modelPath: modelPath,
      chat: demo ? FakeInferenceEngine() : LlamaEngine(debugName: 'medha-chat'),
      guard: demo ? FakeInferenceEngine(delay: Duration.zero) : LlamaEngine(debugName: 'medha-guard'),
    );

    final Installer installer = demo
        ? DemoInstaller(catalog: catalog, repository: models)
        : ModelInstaller(
            catalog: catalog,
            repository: models,
            downloader: BackgroundModelDownloader(supportDirectory: support),
            modelsDirectory: modelsDir,
            warmUp: (model, path) async {
              final probe = LlamaEngine(debugName: 'medha-warmup');
              try {
                await probe.load(ModelHandle(
                  id: model.id,
                  path: path,
                  contextTokens: 512,
                  promptTemplate: model.promptTemplate,
                  threads: EngineManager.defaultThreads,
                  gpuLayers: EngineManager.defaultGpuLayers,
                ));
              } finally {
                await probe.dispose();
              }
            },
          );

    final safety = SafetyService(
      config: catalog.safety,
      guard: ModelGuardClassifier(engine: engines.guard, config: catalog.safety),
    );

    return AppServices(
      catalog: catalog,
      chatRepository: chats,
      modelRepository: models,
      engines: engines,
      installer: installer,
      safety: safety,
      demo: demo,
    );
  }
}
