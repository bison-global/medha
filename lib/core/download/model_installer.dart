import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../catalog/catalog.dart';
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

abstract interface class Installer {
  /// Bytes still to download for [entry] (0 when every file is on the phone).
  Future<int> downloadBytes(InterestEntry entry);
  Stream<InstallState> install(InterestEntry entry, {required bool wifiOnly});
}

/// Downloads, verifies and registers everything one interest needs:
/// its base model, plus the safety guard model if it isn't installed yet
/// (ARCHITECTURE.md §6, §9.4). Files already on the phone are reused.
class ModelInstaller implements Installer {
  ModelInstaller({
    required this.catalog,
    required this.repository,
    required this.downloader,
    required this.modelsDirectory,
    required this.warmUp,
    Future<String> Function(String path)? hashFile,
  }) : _hash = hashFile ?? sha256OfFile;

  final Catalog catalog;
  final ModelRepository repository;
  final ModelDownloader downloader;
  final Directory modelsDirectory;

  /// Test-loads a model after download ("Optimizing for this phone").
  final Future<void> Function(BaseModel model, String path) warmUp;
  final Future<String> Function(String path) _hash;

  String pathFor(BaseModel m) => p.join(modelsDirectory.path, m.fileName);

  /// Models the entry needs that are not installed (or whose file is gone).
  Future<List<BaseModel>> missingModels(InterestEntry entry) async {
    final installed = await repository.installedModels();
    final needed = <BaseModel>[catalog.guardModel, catalog.baseModel(entry.baseModelId)];
    final missing = <BaseModel>[];
    for (final m in needed) {
      final rec = installed[m.id];
      final ok = rec != null && rec.sha256 == m.sha256.toLowerCase() && await File(rec.path).exists();
      if (!ok && !missing.any((x) => x.id == m.id)) missing.add(m);
    }
    return missing;
  }

  @override
  Future<int> downloadBytes(InterestEntry entry) async =>
      (await missingModels(entry)).fold<int>(0, (sum, m) => sum + m.bytes);

  @override
  Stream<InstallState> install(InterestEntry entry, {required bool wifiOnly}) {
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
        final missing = await missingModels(entry);
        final total = missing.fold<int>(0, (sum, m) => sum + m.bytes);
        var done = 0;
        final partial = Directory(p.join(modelsDirectory.path, 'partial'));

        for (final m in missing) {
          if (m.sha256.isEmpty || m.url.isEmpty) {
            throw IntegrityException(
                'The catalog has no download or checksum for ${m.name}. Build one with tool/make_catalog.dart.');
          }
          if (cancelled) return;
          currentFile = m.fileName;
          final file = await downloader.download(
            url: Uri.parse(m.url),
            directory: partial,
            fileName: m.fileName,
            wifiOnly: wifiOnly,
            onProgress: (f) {
              final received = done + (m.bytes * f).round();
              out.add(InstallState(InstallStage.downloading,
                  modelName: m.name, fraction: total == 0 ? 1 : received / total, receivedBytes: received, totalBytes: total));
            },
          );
          currentFile = null;
          if (cancelled) return;

          out.add(InstallState(InstallStage.verifying,
              modelName: m.name, fraction: total == 0 ? 1 : (done + m.bytes) / total, receivedBytes: done + m.bytes, totalBytes: total));
          final hash = await _hash(file.path);
          if (hash.toLowerCase() != m.sha256.toLowerCase()) {
            await file.delete();
            throw IntegrityException('${m.name} did not pass its integrity check. Please try again.');
          }

          await modelsDirectory.create(recursive: true);
          final target = pathFor(m);
          await file.rename(target);
          await repository.markModelInstalled(InstalledModel(
            baseModelId: m.id,
            path: target,
            bytes: m.bytes,
            sha256: m.sha256.toLowerCase(),
            installedAt: DateTime.now(),
          ));
          done += m.bytes;
        }

        final base = catalog.baseModel(entry.baseModelId);
        out.add(InstallState(InstallStage.optimizing, modelName: base.name, fraction: 1, receivedBytes: total, totalBytes: total));
        await warmUp(base, pathFor(base));
        await repository.markEntryInstalled(entry.id);
        out.add(InstallState(InstallStage.done, modelName: base.name, fraction: 1, receivedBytes: total, totalBytes: total));
      } on Object catch (e) {
        out.add(InstallState(InstallStage.failed, error: e.toString()));
      } finally {
        await out.close();
      }
    }();
    return out.stream;
  }
}

/// Demo mode: pretends to download so the UI can be developed without
/// model files (`--dart-define=MEDHA_FAKE_ENGINE=true`).
class DemoInstaller implements Installer {
  DemoInstaller({required this.catalog, required this.repository, this.step = const Duration(milliseconds: 60)});

  final Catalog catalog;
  final ModelRepository repository;
  final Duration step;

  @override
  Future<int> downloadBytes(InterestEntry entry) async {
    final installed = await repository.installedEntries();
    return installed.contains(entry.id) ? 0 : catalog.baseModel(entry.baseModelId).bytes + catalog.guardModel.bytes;
  }

  @override
  Stream<InstallState> install(InterestEntry entry, {required bool wifiOnly}) async* {
    final total = await downloadBytes(entry);
    final name = catalog.baseModel(entry.baseModelId).name;
    for (var i = 1; i <= 40; i++) {
      await Future<void>.delayed(step);
      yield InstallState(InstallStage.downloading,
          modelName: name, fraction: i / 40, receivedBytes: total * i ~/ 40, totalBytes: total);
    }
    yield InstallState(InstallStage.verifying, modelName: name, fraction: 1, receivedBytes: total, totalBytes: total);
    await Future<void>.delayed(step * 5);
    yield InstallState(InstallStage.optimizing, modelName: name, fraction: 1, receivedBytes: total, totalBytes: total);
    await Future<void>.delayed(step * 5);
    await repository.markEntryInstalled(entry.id);
    yield InstallState(InstallStage.done, modelName: name, fraction: 1, receivedBytes: total, totalBytes: total);
  }
}
