import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../catalog/catalog.dart';
import '../device/device_memory.dart';
import '../storage/models.dart';
import '../storage/repositories.dart';
import 'model_downloader.dart';

enum InstallStage { preparing, downloading, verifying, optimizing, done, failed }

class InstallState {
  const InstallState(this.stage, {this.modelName = '', this.fraction = 0, this.receivedBytes = 0, this.totalBytes = 0, this.error});

  final InstallStage stage;
  final String modelName;

  /// Overall progress across every file this install needs (0–1).
  final double fraction;
  final int receivedBytes;
  final int totalBytes;
  final String? error;

  bool get isFinished => stage == InstallStage.done || stage == InstallStage.failed;
}

class IntegrityException implements Exception {
  IntegrityException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Whether a tier can run on this phone (ARCHITECTURE.md §5.3, §10).
enum TierFit {
  fits,

  /// Runs on the smaller fallback model because RAM is low.
  fallback,

  /// Not enough RAM even for the fallback.
  tooBig,
}

class TierPlan {
  const TierPlan(this.fit, this.baseModelId, {this.ramMb});
  final TierFit fit;
  final String baseModelId;
  final int? ramMb;
}

abstract interface class Installer {
  Future<TierPlan> plan(InterestEntry entry);

  /// Bytes still to download for [entry] (0 when every file is on the phone).
  Future<int> downloadBytes(InterestEntry entry);
  Stream<InstallState> install(InterestEntry entry, {required bool wifiOnly});

  Future<bool> embedderInstalled();
  Stream<InstallState> installEmbedder({required bool wifiOnly});

  /// Removes a subject, and any model file no other installed subject uses.
  Future<void> uninstall(String entryId);

  /// Bytes on disk used by Medha's model files.
  Future<int> storageBytes();
}

/// Downloads, verifies and registers everything one interest needs:
/// its base model (or the low-memory fallback), its add-on, and the safety
/// guard model if it isn't installed yet. Files already on the phone are reused.
class ModelInstaller implements Installer {
  ModelInstaller({
    required this.catalog,
    required this.repository,
    required this.downloader,
    required this.modelsDirectory,
    required this.warmUp,
    this.memory = const SystemDeviceMemory(),
    Future<String> Function(String path)? hashFile,
  }) : _hash = hashFile ?? sha256OfFile;

  final Catalog catalog;
  final ModelRepository repository;
  final ModelDownloader downloader;
  final Directory modelsDirectory;
  final DeviceMemory memory;

  /// Test-loads a model after download ("Optimizing for this phone").
  final Future<void> Function(BaseModel model, String path) warmUp;
  final Future<String> Function(String path) _hash;

  String pathFor(BaseModel m) => p.join(modelsDirectory.path, m.fileName);
  String adapterPath(AdapterFile a) => p.join(modelsDirectory.path, a.fileName);

  @override
  Future<TierPlan> plan(InterestEntry entry) async {
    final ram = await memory.totalRamMb();
    final base = catalog.baseModel(entry.baseModelId);
    if (ram == null || ram >= base.minRamMb) return TierPlan(TierFit.fits, base.id, ramMb: ram);
    final fb = entry.fallbackBaseModelId;
    if (fb != null && ram >= catalog.baseModel(fb).minRamMb) return TierPlan(TierFit.fallback, fb, ramMb: ram);
    return TierPlan(TierFit.tooBig, base.id, ramMb: ram);
  }

  Future<bool> _isInstalled(BaseModel m) async {
    final rec = (await repository.installedModels())[m.id];
    return rec != null && rec.sha256 == m.sha256.toLowerCase() && await File(rec.path).exists();
  }

  /// Files the entry needs that are not on the phone yet.
  Future<List<_FileSpec>> _missing(InterestEntry entry, String baseId) async {
    final out = <_FileSpec>[];
    for (final m in {catalog.guardModel, catalog.baseModel(baseId)}) {
      if (!await _isInstalled(m)) out.add(_FileSpec.model(m, pathFor(m)));
    }
    final a = entry.adapter;
    if (a != null && a.url.isNotEmpty && !await File(adapterPath(a)).exists()) {
      out.add(_FileSpec.adapter(a, adapterPath(a)));
    }
    return out;
  }

  @override
  Future<int> downloadBytes(InterestEntry entry) async {
    final plan = await this.plan(entry);
    return (await _missing(entry, plan.baseModelId)).fold<int>(0, (sum, f) => sum + f.bytes);
  }

  Stream<InstallState> _download(List<_FileSpec> files, {required bool wifiOnly, required Future<void> Function() finish, required String label}) {
    var cancelled = false;
    String? currentFile;
    final out = StreamController<InstallState>();
    // Leaving the install screen cancels the download in progress.
    out.onCancel = () async {
      cancelled = true;
      final f = currentFile;
      if (f != null) await downloader.cancel(f);
    };
    () async {
      try {
        out.add(const InstallState(InstallStage.preparing));
        final total = files.fold<int>(0, (sum, f) => sum + f.bytes);
        var done = 0;
        final partial = Directory(p.join(modelsDirectory.path, 'partial'));

        // Check every file first, so nothing is downloaded for an entry
        // that can't be completed.
        for (final f in files) {
          if (f.sha256.isEmpty || f.url.isEmpty) {
            throw IntegrityException('The catalog has no download or checksum for ${f.name}. Build one with tool/make_catalog.dart.');
          }
        }
        for (final f in files) {
          if (cancelled) return;
          currentFile = f.fileName;
          final file = await downloader.download(
            url: Uri.parse(f.url),
            directory: partial,
            fileName: f.fileName,
            wifiOnly: wifiOnly,
            onProgress: (x) {
              final received = done + (f.bytes * x).round();
              out.add(InstallState(InstallStage.downloading,
                  modelName: f.name, fraction: total == 0 ? 1 : received / total, receivedBytes: received, totalBytes: total));
            },
          );
          currentFile = null;
          if (cancelled) return;

          out.add(InstallState(InstallStage.verifying,
              modelName: f.name, fraction: total == 0 ? 1 : (done + f.bytes) / total, receivedBytes: done + f.bytes, totalBytes: total));
          final hash = await _hash(file.path);
          if (hash.toLowerCase() != f.sha256.toLowerCase()) {
            await file.delete();
            throw IntegrityException('${f.name} did not pass its integrity check. Please try again.');
          }

          await modelsDirectory.create(recursive: true);
          await file.rename(f.targetPath);
          final model = f.model;
          if (model != null) {
            await repository.markModelInstalled(InstalledModel(
              baseModelId: model.id,
              path: f.targetPath,
              bytes: model.bytes,
              sha256: model.sha256.toLowerCase(),
              installedAt: DateTime.now(),
            ));
          }
          done += f.bytes;
        }

        out.add(InstallState(InstallStage.optimizing, modelName: label, fraction: 1, receivedBytes: total, totalBytes: total));
        await finish();
        out.add(InstallState(InstallStage.done, modelName: label, fraction: 1, receivedBytes: total, totalBytes: total));
      } on Object catch (e) {
        out.add(InstallState(InstallStage.failed, error: e.toString()));
      } finally {
        await out.close();
      }
    }();
    return out.stream;
  }

  @override
  Stream<InstallState> install(InterestEntry entry, {required bool wifiOnly}) async* {
    final plan = await this.plan(entry);
    if (plan.fit == TierFit.tooBig) {
      yield InstallState(InstallStage.failed,
          error: 'This phone has about ${((plan.ramMb ?? 0) / 1024).toStringAsFixed(1)} GB of memory, which is not enough for ${entry.displayName}. Try the Lite size.');
      return;
    }
    final base = catalog.baseModel(plan.baseModelId);
    final files = await _missing(entry, base.id);
    yield* _download(files, wifiOnly: wifiOnly, label: base.name, finish: () async {
      await warmUp(base, pathFor(base));
      await repository.markEntryInstalled(entry.id, baseModelId: base.id);
    });
  }

  @override
  Future<bool> embedderInstalled() async {
    final m = catalog.embeddingModel;
    return m != null && await _isInstalled(m);
  }

  @override
  Stream<InstallState> installEmbedder({required bool wifiOnly}) async* {
    final m = catalog.embeddingModel;
    if (m == null) {
      yield const InstallState(InstallStage.done);
      return;
    }
    final files = await _isInstalled(m) ? <_FileSpec>[] : [_FileSpec.model(m, pathFor(m))];
    yield* _download(files, wifiOnly: wifiOnly, label: m.name, finish: () async {});
  }

  @override
  Future<void> uninstall(String entryId) async {
    await repository.removeEntry(entryId);
    final remaining = await repository.installedEntryBases();
    final inUse = <String>{
      catalog.safety.guardModelId,
      if (catalog.embeddingModelId != null) catalog.embeddingModelId!,
      for (final e in remaining.entries) e.value ?? catalog.interestEntry(e.key).baseModelId,
    };
    for (final rec in (await repository.installedModels()).values) {
      if (inUse.contains(rec.baseModelId)) continue;
      final f = File(rec.path);
      if (await f.exists()) await f.delete();
      await repository.removeModel(rec.baseModelId);
    }
    final entry = catalog.interests.where((e) => e.id == entryId).firstOrNull;
    final a = entry?.adapter;
    if (a != null) {
      final stillUsed = remaining.keys.any((id) => catalog.interestEntry(id).adapter?.id == a.id);
      final f = File(adapterPath(a));
      if (!stillUsed && await f.exists()) await f.delete();
    }
  }

  @override
  Future<int> storageBytes() async {
    var total = 0;
    for (final rec in (await repository.installedModels()).values) {
      final f = File(rec.path);
      if (await f.exists()) total += await f.length();
    }
    return total;
  }
}

class _FileSpec {
  _FileSpec.model(BaseModel m, this.targetPath)
      : model = m,
        name = m.name,
        url = m.url,
        bytes = m.bytes,
        sha256 = m.sha256,
        fileName = m.fileName;

  _FileSpec.adapter(AdapterFile a, this.targetPath)
      : model = null,
        name = 'subject add-on',
        url = a.url,
        bytes = a.bytes,
        sha256 = a.sha256,
        fileName = a.fileName;

  final BaseModel? model;
  final String name;
  final String url;
  final int bytes;
  final String sha256;
  final String fileName;
  final String targetPath;
}

/// Demo mode: pretends to download so the UI can be developed without
/// model files (`--dart-define=MEDHA_FAKE_ENGINE=true`).
class DemoInstaller implements Installer {
  DemoInstaller({required this.catalog, required this.repository, this.step = const Duration(milliseconds: 60)});

  final Catalog catalog;
  final ModelRepository repository;
  final Duration step;
  bool _embedder = false;

  @override
  Future<TierPlan> plan(InterestEntry entry) async => TierPlan(TierFit.fits, entry.baseModelId);

  Future<Set<String>> _installedBases() async {
    final bases = await repository.installedEntryBases();
    return {for (final e in bases.entries) e.value ?? catalog.interestEntry(e.key).baseModelId};
  }

  @override
  Future<int> downloadBytes(InterestEntry entry) async {
    final bases = await _installedBases();
    var bytes = bases.contains(entry.baseModelId) ? 0 : catalog.baseModel(entry.baseModelId).bytes;
    if (bases.isEmpty) bytes += catalog.guardModel.bytes;
    return bytes;
  }

  Stream<InstallState> _simulate(String name, int total, Future<void> Function() finish) async* {
    final steps = total == 0 ? 1 : 40;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(step);
      yield InstallState(InstallStage.downloading, modelName: name, fraction: i / steps, receivedBytes: total * i ~/ steps, totalBytes: total);
    }
    yield InstallState(InstallStage.verifying, modelName: name, fraction: 1, receivedBytes: total, totalBytes: total);
    await Future<void>.delayed(step * 5);
    yield InstallState(InstallStage.optimizing, modelName: name, fraction: 1, receivedBytes: total, totalBytes: total);
    await Future<void>.delayed(step * 5);
    await finish();
    yield InstallState(InstallStage.done, modelName: name, fraction: 1, receivedBytes: total, totalBytes: total);
  }

  @override
  Stream<InstallState> install(InterestEntry entry, {required bool wifiOnly}) async* {
    final total = await downloadBytes(entry);
    yield* _simulate(catalog.baseModel(entry.baseModelId).name, total,
        () => repository.markEntryInstalled(entry.id, baseModelId: entry.baseModelId));
  }

  @override
  Future<bool> embedderInstalled() async => _embedder;

  @override
  Stream<InstallState> installEmbedder({required bool wifiOnly}) async* {
    final m = catalog.embeddingModel;
    yield* _simulate(m?.name ?? 'Search model', _embedder ? 0 : (m?.bytes ?? 0), () async => _embedder = true);
  }

  @override
  Future<void> uninstall(String entryId) => repository.removeEntry(entryId);

  @override
  Future<int> storageBytes() async {
    final bases = await _installedBases();
    if (bases.isEmpty) return 0;
    return bases.fold<int>(catalog.guardModel.bytes, (sum, id) => sum + catalog.baseModel(id).bytes) +
        (_embedder ? catalog.embeddingModel?.bytes ?? 0 : 0);
  }
}
