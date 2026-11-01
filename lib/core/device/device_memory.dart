import 'dart:io';

/// Total RAM of this phone in MB, or null when unknown.
///
/// Android exposes it in /proc/meminfo with no permission. iOS has no Dart
/// API for it; returning null there means "don't gate", which is safe on the
/// iPhones that can install Medha (iOS 15+, mostly 4 GB or more).
abstract interface class DeviceMemory {
  Future<int?> totalRamMb();
}

class SystemDeviceMemory implements DeviceMemory {
  const SystemDeviceMemory();

  @override
  Future<int?> totalRamMb() async {
    if (!Platform.isAndroid && !Platform.isLinux) return null;
    try {
      final info = await File('/proc/meminfo').readAsString();
      return parseMemTotalMb(info);
    } on FileSystemException {
      return null;
    }
  }
}

/// Parses the `MemTotal:` line of /proc/meminfo (kB) into MB.
int? parseMemTotalMb(String meminfo) {
  final m = RegExp(r'^MemTotal:\s+(\d+)\s*kB', multiLine: true).firstMatch(meminfo);
  if (m == null) return null;
  return int.parse(m.group(1)!) ~/ 1024;
}

class FixedDeviceMemory implements DeviceMemory {
  const FixedDeviceMemory(this.mb);
  final int? mb;
  @override
  Future<int?> totalRamMb() async => mb;
}
