import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medha/core/catalog/catalog.dart';
import 'package:medha/core/device/device_memory.dart';
import 'package:medha/core/download/model_downloader.dart';
import 'package:medha/core/download/model_installer.dart';
import 'package:medha/core/storage/repositories.dart';
import 'package:path/path.dart' as p;

import '../helpers.dart';

/// Writes [content] for each URL instead of downloading.
class FakeDownloader implements ModelDownloader {
  FakeDownloader(this.content);
  final Map<String, List<int>> content;
  final List<String> downloaded = [];

  @override
  Future<File> download({
    required Uri url,
    required Directory directory,
    required String fileName,
    required bool wifiOnly,
    required void Function(double fraction) onProgress,
  }) async {
    downloaded.add(url.toString());
    onProgress(0.5);
    await directory.create(recursive: true);
    final f = File(p.join(directory.path, fileName));
    await f.writeAsBytes(content[url.toString()]!);
    onProgress(1);
    return f;
  }

  @override
  Future<void> cancel(String fileName) async {}
}

void main() {
  late Directory tmp;
  late Catalog catalog;
  late Map<String, List<int>> files;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('medha_install_');
    files = {
      'https://test/minicpm.gguf': utf8.encode('minicpm weights'),
      'https://test/guard.gguf': utf8.encode('guard weights'),
    };
    final j = devCatalogJson();
    for (final b in (j['baseModels'] as List).cast<Map<String, dynamic>>()) {
      final url = switch (b['id']) {
        'minicpm5-2b-q4km' => 'https://test/minicpm.gguf',
        'qwen3guard-gen-0_6b-q4km' => 'https://test/guard.gguf',
        _ => null,
      };
      if (url == null) continue;
      b['file'] = {'url': url, 'bytes': files[url]!.length, 'sha256': sha256.convert(files[url]!).toString()};
    }
    catalog = Catalog.fromJson(j);
  });

  tearDown(() => tmp.delete(recursive: true));

  ModelInstaller installer(InMemoryModelRepository repo, ModelDownloader d, {List<String>? warmed, int? ramMb = 8192}) =>
      ModelInstaller(
        catalog: catalog,
        memory: FixedDeviceMemory(ramMb),
        repository: repo,
        downloader: d,
        modelsDirectory: Directory(p.join(tmp.path, 'models')),
        warmUp: (m, path) async => warmed?.add(m.id),
        hashFile: (path) async => sha256.convert(await File(path).readAsBytes()).toString(),
      );

  test('downloads the base model and the guard, verifies and registers them', () async {
    final repo = InMemoryModelRepository();
    final d = FakeDownloader(files);
    final warmed = <String>[];
    final entry = catalog.interestEntry('math-lite');
    final states = await installer(repo, d, warmed: warmed).install(entry, wifiOnly: true).toList();

    expect(states.last.stage, InstallStage.done);
    expect(d.downloaded.toSet(), {'https://test/minicpm.gguf', 'https://test/guard.gguf'});
    expect(repo.models.keys.toSet(), {'minicpm5-2b-q4km', 'qwen3guard-gen-0_6b-q4km'});
    expect(repo.entries, {'math-lite'});
    expect(warmed, ['minicpm5-2b-q4km']);
    expect(File(p.join(tmp.path, 'models', 'minicpm5-2b-q4km.gguf')).existsSync(), isTrue);
    expect(states.map((s) => s.fraction), everyElement(inInclusiveRange(0, 1)));
  });

  test('reuses files already on the phone', () async {
    final repo = InMemoryModelRepository();
    final entry = catalog.interestEntry('math-lite');
    await installer(repo, FakeDownloader(files)).install(entry, wifiOnly: true).drain<void>();

    final second = FakeDownloader(files);
    final inst = installer(repo, second);
    expect(await inst.downloadBytes(entry), 0);
    final states = await inst.install(entry, wifiOnly: true).toList();
    expect(states.last.stage, InstallStage.done);
    expect(second.downloaded, isEmpty);
  });

  test('rejects a file whose checksum does not match', () async {
    final repo = InMemoryModelRepository();
    final bad = Map.of(files)..['https://test/minicpm.gguf'] = utf8.encode('tampered');
    final states = await installer(repo, FakeDownloader(bad)).install(catalog.interestEntry('math-lite'), wifiOnly: true).toList();
    expect(states.last.stage, InstallStage.failed);
    expect(states.last.error, contains('integrity'));
    expect(repo.entries, isEmpty);
    expect(repo.models.containsKey('minicpm5-2b-q4km'), isFalse);
  });

  test('refuses models with no checksum in the catalog', () async {
    final j = devCatalogJson();
    final c = Catalog.fromJson(j);
    final inst = ModelInstaller(
      catalog: c,
      repository: InMemoryModelRepository(),
      downloader: FakeDownloader(files),
      modelsDirectory: Directory(p.join(tmp.path, 'models')),
      warmUp: (_, __) async {},
    );
    final states = await inst.install(c.interestEntry('math-lite'), wifiOnly: true).toList();
    expect(states.last.stage, InstallStage.failed);
    expect(states.last.error, contains('make_catalog'));
  });

  group('memory plan', () {
    test('fits when the phone has enough RAM, or RAM is unknown', () async {
      final repo = InMemoryModelRepository();
      final entry = catalog.interestEntry('general-lite');
      expect((await installer(repo, FakeDownloader(files)).plan(entry)).fit, TierFit.fits);
      expect((await installer(repo, FakeDownloader(files), ramMb: null).plan(entry)).fit, TierFit.fits);
    });

    test('uses the smaller fallback model on a low-RAM phone', () async {
      final plan = await installer(InMemoryModelRepository(), FakeDownloader(files), ramMb: 3000).plan(catalog.interestEntry('general-lite'));
      expect(plan.fit, TierFit.fallback);
      expect(plan.baseModelId, 'qwen3_5-2b-q4km');
    });

    test('says Pro is too big when there is no fallback', () async {
      final plan = await installer(InMemoryModelRepository(), FakeDownloader(files), ramMb: 4096).plan(catalog.interestEntry('math-pro'));
      expect(plan.fit, TierFit.tooBig);
    });
  });

  test('parseMemTotalMb reads /proc/meminfo', () {
    expect(parseMemTotalMb('MemTotal:        7864320 kB\nMemFree: 1 kB'), 7680);
    expect(parseMemTotalMb('nothing'), isNull);
  });
}
