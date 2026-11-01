import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the database key in the Android Keystore / iOS Keychain.
class SecureKeys {
  SecureKeys([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _storage;
  static const _dbKey = 'medha.db_key.v1';

  /// Returns the database key, generating a random 256-bit key on first use.
  Future<String> databaseKey() async {
    final existing = await _storage.read(key: _dbKey);
    if (existing != null) return existing;
    final key = randomHex(32);
    await _storage.write(key: _dbKey, value: key);
    return key;
  }
}

String randomHex(int bytes) {
  final r = Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    b.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}
