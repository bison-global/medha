import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/security/app_lock.dart';
import 'pin_pad.dart';

/// Turns on the app lock: choose fingerprint or PIN, then set a PIN (always
/// required, as the fallback). Shown after the first install and from Settings.
class SecureScreen extends ConsumerStatefulWidget {
  const SecureScreen({super.key, this.next});

  /// Where to go afterwards; null pops back.
  final String? next;

  @override
  ConsumerState<SecureScreen> createState() => _SecureScreenState();
}

enum _Step { choose, pin, confirm }

class _SecureScreenState extends ConsumerState<SecureScreen> {
  _Step _step = _Step.choose;
  LockMethod _method = LockMethod.biometric;
  bool _biometricsAvailable = false;
  String _first = '';
  bool _mismatch = false;

  @override
  void initState() {
    super.initState();
    ref.read(appLockProvider).biometrics.available().then((ok) {
      if (!mounted) return;
      setState(() {
        _biometricsAvailable = ok;
        if (!ok) _method = LockMethod.pin;
      });
    });
  }

  void _done() {
    final next = widget.next;
    if (next != null) {
      // Keep the chat list underneath so Back leads somewhere.
      context.go('/chats');
      context.push(next);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/chats');
    }
  }

  void _skip() {
    ref.read(appLockProvider).markAsked();
    _done();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: switch (_step) {
              _Step.choose => _choose(context),
              _Step.pin => _pinStep('Set a 4-digit PIN', 'You can use it whenever the fingerprint is not available.', (pin) async {
                  setState(() {
                    _first = pin;
                    _mismatch = false;
                    _step = _Step.confirm;
                  });
                }),
              _Step.confirm => _pinStep('Enter the PIN again', _mismatch ? 'PINs did not match. Try again.' : '', (pin) async {
                  if (pin != _first) {
                    setState(() {
                      _mismatch = true;
                      _step = _Step.pin;
                    });
                    return;
                  }
                  await ref.read(appLockProvider).enable(method: _method, pin: pin);
                  if (mounted) _done();
                }),
            },
          ),
        ),
      );

  Widget _choose(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.verified_user_outlined, color: MedhaColors.accent, size: 40),
        const SizedBox(height: 20),
        Text('Lock your chats', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Add an app lock so only you can open your chats, projects and files.',
            style: TextStyle(fontSize: 15, height: 1.5, color: MedhaColors.muted)),
        const SizedBox(height: 24),
        if (_biometricsAvailable)
          _MethodTile(
            icon: Icons.fingerprint,
            title: 'Fingerprint or face',
            subtitle: 'Unlock with your phone\'s biometrics, with a PIN as backup',
            selected: _method == LockMethod.biometric,
            onTap: () => setState(() => _method = LockMethod.biometric),
          ),
        const SizedBox(height: 12),
        _MethodTile(
          icon: Icons.pin_outlined,
          title: '4-digit PIN',
          subtitle: 'Works on any phone',
          selected: _method == LockMethod.pin,
          onTap: () => setState(() => _method = LockMethod.pin),
        ),
        const Spacer(),
        FilledButton(onPressed: () => setState(() => _step = _Step.pin), child: const Text('Turn on app lock')),
        const SizedBox(height: 8),
        TextButton(onPressed: _skip, child: const Text('Not now')),
      ]);

  Widget _pinStep(String title, String message, Future<void> Function(String) onComplete) => Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 28),
            PinPad(key: ValueKey(_step), message: message, error: _mismatch, onComplete: onComplete),
          ]),
        ),
      );
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? const Color(0xFF1B2338) : MedhaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? MedhaColors.accent : MedhaColors.line, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(icon, color: MedhaColors.accent, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: MedhaColors.muted)),
                ]),
              ),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? MedhaColors.accent : MedhaColors.faint),
            ]),
          ),
        ),
      );
}
