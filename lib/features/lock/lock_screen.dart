import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/security/app_lock.dart';
import '../common/widgets.dart';
import 'pin_pad.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _wrong = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Offer the fingerprint prompt straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(appLockProvider).lockoutRemaining != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _biometric() async {
    final lock = ref.read(appLockProvider);
    if (lock.method == LockMethod.biometric) await lock.unlockWithBiometrics();
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final lockout = lock.lockoutRemaining;
    final message = lockout != null
        ? 'Too many tries. Try again in ${lockout.inSeconds + 1} s'
        : _wrong
            ? 'Wrong PIN. Try again.'
            : 'Enter your PIN';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const MedhaLogo(size: 44),
              const SizedBox(height: 18),
              const Text('Medha is locked', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('Your chats and projects are protected on this phone.',
                  textAlign: TextAlign.center, style: TextStyle(color: MedhaColors.muted)),
              const SizedBox(height: 32),
              PinPad(
                message: message,
                error: _wrong || lockout != null,
                enabled: lockout == null,
                onBiometric: lock.method == LockMethod.biometric ? _biometric : null,
                onComplete: (pin) async {
                  final ok = await lock.unlockWithPin(pin);
                  if (mounted) setState(() => _wrong = !ok);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
