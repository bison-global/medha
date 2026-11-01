import 'dart:io';
import 'dart:isolate';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class DownloadException implements Exception {
  DownloadException(this.message);
  final String message;
  @override
  String toString() => 'DownloadException: $message';
}

/// Downloads large model files. Implementations must resume after network
/// drops and keep going while the app is in the background.
abstract interface class ModelDownloader {
  Future<File> download({
    required Uri url,
    required Directory directory,
    required String fileName,
    required bool wifiOnly,
    required void Function(double fraction) onProgress,
  });

  Future<void> cancel(String fileName);
}

/// [ModelDownloader] backed by WorkManager (Android) / URLSession (iOS).
class BackgroundModelDownloader implements ModelDownloader {
  BackgroundModelDownloader({required this.supportDirectory});

  /// The app-support directory; tasks are addressed relative to it.
  final Directory supportDirectory;
  final Map<String, String> _taskIds = {};

  @override
  Future<File> download({
    required Uri url,
    required Directory directory,
    required String fileName,
    required bool wifiOnly,
    required void Function(double fraction) onProgress,
  }) async {
    final relative = p.relative(directory.path, from: supportDirectory.path);
    if (relative.startsWith('..')) throw ArgumentError('Download directory must be inside app support');
    await directory.create(recursive: true);

    final task = DownloadTask(
      url: url.toString(),
      filename: fileName,
      directory: relative,
      baseDirectory: BaseDirectory.applicationSupport,
      updates: Updates.statusAndProgress,
      requiresWiFi: wifiOnly,
      retries: 3,
      allowPause: true,
    );
    _taskIds[fileName] = task.taskId;
    try {
      final result = await FileDownloader().download(
        task,
        onProgress: (fraction) {
          if (fraction >= 0) onProgress(fraction);
        },
      );
      if (result.status != TaskStatus.complete) {
        throw DownloadException('Download ${result.status.name} (${result.exception?.description ?? 'no details'})');
      }
      return File(p.join(directory.path, fileName));
    } finally {
      _taskIds.remove(fileName);
    }
  }

  @override
  Future<void> cancel(String fileName) async {
    final id = _taskIds[fileName];
    if (id != null) await FileDownloader().cancelTaskWithId(id);
  }
}

/// SHA-256 of a file, computed off the UI isolate.
Future<String> sha256OfFile(String path) =>
    Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());
