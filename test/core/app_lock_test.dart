import 'package:flutter_test/flutter_test.dart';
import 'package:medha/core/security/app_lock.dart';
import 'package:medha/core/settings/prefs.dart';

class FakeBiometrics implements BiometricAuth {
  FakeBiometrics({this.isAvailable = true, this.succeed = true});
  bool isAvailable;
  bool succeed;
  int prompts = 0;
  @override
  Future<bool> available() async => isAvailable;
  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeed;
  }
}

void main() {
  late DateTime now;
  late MemoryPrefs prefs;
  late MemorySecretStore secrets;
  late FakeBiometrics bio;

  AppLock make() => AppLock(prefs: prefs, secrets: secrets, biometrics: bio, pbkdf2Iterations: 1000, clock: () => now);

  setUp(() {
    now = DateTime(2026, 11, 1, 12);
    prefs = MemoryPrefs();
    secrets = MemorySecretStore();
    bio = FakeBiometrics();
  });

  test('is off and unlocked by default', () {
    final lock = make();
    expect(lock.enabled, isFalse);
    expect(lock.locked, isFalse);
  });

  test('stores only a salted hash of the PIN, never the PIN', () async {
    final lock = make();
    await lock.enable(method: LockMethod.pin, pin: '4821');
    final stored = secrets.values[appLockPinKey]!;
    expect(stored, isNot(contains('4821')));
    expect(stored, contains('salt'));
    expect(lock.enabled, isTrue);
    expect(lock.asked, isTrue);
  });

  test('rejects PINs that are not 4–6 digits', () {
    expect(AppLock.validPin('123'), isFalse);
    expect(AppLock.validPin('12a4'), isFalse);
    expect(AppLock.validPin('1234'), isTrue);
    expect(AppLock.validPin('123456'), isTrue);
  });

  test('starts locked when enabled, and unlocks with the right PIN', () async {
    await make().enable(method: LockMethod.pin, pin: '4821');
    final lock = make();
    expect(lock.locked, isTrue);
    expect(await lock.unlockWithPin('0000'), isFalse);
    expect(lock.locked, isTrue);
    expect(await lock.unlockWithPin('4821'), isTrue);
    expect(lock.locked, isFalse);
  });

  test('five wrong PINs lock out for 30 seconds, then the lockout grows', () async {
    await make().enable(method: LockMethod.pin, pin: '4821');
    final lock = make();
    for (var i = 0; i < 5; i++) {
      await lock.unlockWithPin('0000');
    }
    expect(lock.lockoutRemaining, isNotNull);
    expect(await lock.unlockWithPin('4821'), isFalse, reason: 'even the right PIN is refused during lockout');
    now = now.add(const Duration(seconds: 31));
    expect(lock.lockoutRemaining, isNull);
    await lock.unlockWithPin('0000');
    expect(lock.lockoutRemaining!.inSeconds, greaterThan(50), reason: 'sixth miss doubles the lockout');
  });

  test('biometric unlock when chosen and available', () async {
    await make().enable(method: LockMethod.biometric, pin: '4821');
    final lock = make();
    expect(await lock.unlockWithBiometrics(), isTrue);
    expect(lock.locked, isFalse);
  });

  test('biometrics are not used when PIN-only is chosen', () async {
    await make().enable(method: LockMethod.pin, pin: '4821');
    final lock = make();
    expect(await lock.unlockWithBiometrics(), isFalse);
    expect(bio.prompts, 0);
  });

  test('auto-lock: instantly, or after the chosen time in the background', () async {
    final lock = make();
    await lock.enable(method: LockMethod.pin, pin: '4821');
    await lock.unlockWithPin('4821');

    lock.onBackground();
    lock.onForeground();
    expect(lock.locked, isTrue, reason: 'instant by default');
    await lock.unlockWithPin('4821');

    lock.setAutoLock(60);
    lock.onBackground();
    now = now.add(const Duration(seconds: 30));
    lock.onForeground();
    expect(lock.locked, isFalse);
    lock.onBackground();
    now = now.add(const Duration(seconds: 61));
    lock.onForeground();
    expect(lock.locked, isTrue);
  });

  test('a file picker or permission prompt does not lock the app', () async {
    final lock = make();
    await lock.enable(method: LockMethod.pin, pin: '4821');
    await lock.unlockWithPin('4821');
    await lock.whileExternal(() async {
      lock.onBackground();
      now = now.add(const Duration(minutes: 5));
      lock.onForeground();
    });
    expect(lock.locked, isFalse);
  });

  test('turning the lock off removes the PIN', () async {
    final lock = make();
    await lock.enable(method: LockMethod.pin, pin: '4821');
    await lock.disable();
    expect(lock.enabled, isFalse);
    expect(await lock.hasPin(), isFalse);
  });
}
