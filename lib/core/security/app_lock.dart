import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../settings/prefs.dart';

enum LockMethod {
  biometric,
  pin;

  static LockMethod parse(String? s) => s == 'pin' ? LockMethod.pin : LockMethod.biometric;
}

/// Where the PIN hash lives: the Android Keystore / iOS Keychain.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

abstract interface class BiometricAuth {
  Future<bool> available();
  Future<bool> authenticate(String reason);
}

class LocalBiometricAuth implements BiometricAuth {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on Object {
      return false;
    }
  }
}

/// App lock (ARCHITECTURE.md §9.1): fingerprint/face or a PIN, which is
/// always set as the fallback. The PIN is never stored, only a salted
/// PBKDF2-SHA256 hash. Wrong PINs trigger an increasing lockout.
class AppLock extends ChangeNotifier {
  AppLock({
    required this.prefs,
    required this.secrets,
    required this.biometrics,
    this.pbkdf2Iterations = 60000,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    _enabled = prefs.getBool(_kEnabled, fallback: false);
    _method = LockMethod.parse(prefs.getString(_kMethod));
    _autoLockSeconds = prefs.getInt(_kAutoLock, fallback: 0);
    _locked = _enabled;
  }

  final Prefs prefs;
  final SecretStore secrets;
  final BiometricAuth biometrics;
  final int pbkdf2Iterations;
  final DateTime Function() _now;

  static const _kEnabled = 'lock.enabled';
  static const _kMethod = 'lock.method';
  static const _kAutoLock = 'lock.autoLockSeconds';
  static const _kAsked = 'lock.asked';
  static const _kPin = 'medha.pin.v1';

  static const lockoutAfter = 5;
  static const baseLockout = Duration(seconds: 30);

  late bool _enabled;
  late LockMethod _method;
  late int _autoLockSeconds;
  late bool _locked;
  int _failures = 0;
  DateTime? _lockoutUntil;
  DateTime? _backgroundedAt;
  int _external = 0;

  bool get enabled => _enabled;
  bool get locked => _locked;
  LockMethod get method => _method;
  int get autoLockSeconds => _autoLockSeconds;

  /// Whether the user has been offered the lock during onboarding.
  bool get asked => prefs.getBool(_kAsked, fallback: false);
  void markAsked() => prefs.setBool(_kAsked, true);

  Duration? get lockoutRemaining {
    final until = _lockoutUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    return left.isNegative ? null : left;
  }

  Future<bool> hasPin() async => await secrets.read(_kPin) != null;

  static bool validPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  Future<List<int>> _derive(String pin, List<int> salt, int iterations) async {
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
        .deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  Future<void> setPin(String pin) async {
    if (!validPin(pin)) throw ArgumentError('PIN must be 4 to 6 digits');
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final hash = await _derive(pin, salt, pbkdf2Iterations);
    await secrets.write(
      _kPin,
      jsonEncode({'v': 1, 'iter': pbkdf2Iterations, 'salt': base64Encode(salt), 'hash': base64Encode(hash)}),
    );
  }

  /// Turns the lock on with [method]; a PIN is required as the fallback.
  Future<void> enable({required LockMethod method, required String pin}) async {
    await setPin(pin);
    _method = method;
    _enabled = true;
    prefs
      ..setString(_kMethod, method.name)
      ..setBool(_kEnabled, true)
      ..setBool(_kAsked, true);
    notifyListeners();
  }

  Future<void> disable() async {
    _enabled = false;
    _locked = false;
    prefs.setBool(_kEnabled, false);
    await secrets.delete(_kPin);
    notifyListeners();
  }

  void setMethod(LockMethod m) {
    _method = m;
    prefs.setString(_kMethod, m.name);
    notifyListeners();
  }

  void setAutoLock(int seconds) {
    _autoLockSeconds = seconds;
    prefs.setInt(_kAutoLock, seconds);
    notifyListeners();
  }

  void lockNow() {
    if (!_enabled) return;
    _locked = true;
    notifyListeners();
  }

  void _unlock() {
    _locked = false;
    _failures = 0;
    _lockoutUntil = null;
    notifyListeners();
  }

  /// Returns true if [pin] is correct. Wrong PINs count towards a lockout.
  Future<bool> unlockWithPin(String pin) async {
    if (lockoutRemaining != null) return false;
    final raw = await secrets.read(_kPin);
    if (raw == null) return false;
    final rec = jsonDecode(raw) as Map<String, dynamic>;
    final expected = base64Decode(rec['hash'] as String);
    final actual = await _derive(pin, base64Decode(rec['salt'] as String), rec['iter'] as int);
    var diff = expected.length ^ actual.length;
    for (var i = 0; i < min(expected.length, actual.length); i++) {
      diff |= expected[i] ^ actual[i];
    }
    if (diff == 0) {
      _unlock();
      return true;
    }
    _failures++;
    if (_failures >= lockoutAfter) {
      _lockoutUntil = _now().add(baseLockout * (1 << (_failures - lockoutAfter)).clamp(1, 32));
    }
    notifyListeners();
    return false;
  }

  Future<bool> unlockWithBiometrics() async {
    if (_method != LockMethod.biometric || !await biometrics.available()) return false;
    _external++;
    try {
      final ok = await biometrics.authenticate('Unlock Medha');
      if (ok) _unlock();
      return ok;
    } finally {
      _external--;
    }
  }

  /// Runs [action] (a file picker, permission prompt, system dialog) without
  /// the app locking itself when it briefly goes to the background.
  Future<T> whileExternal<T>(Future<T> Function() action) async {
    _external++;
    try {
      return await action();
    } finally {
      _external--;
      _backgroundedAt = null;
    }
  }

  /// Call when the app goes to the background.
  void onBackground() {
    if (_external > 0) return;
    _backgroundedAt = _now();
  }

  /// Call when the app comes back; locks if the auto-lock time has passed.
  void onForeground() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (!_enabled || _locked || _external > 0 || since == null) return;
    if (_now().difference(since).inSeconds >= _autoLockSeconds) {
      _locked = true;
      notifyListeners();
    }
  }
}

/// Exposed for tests.
@visibleForTesting
const appLockPinKey = AppLock._kPin;
