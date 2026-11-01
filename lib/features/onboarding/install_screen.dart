import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/download/model_installer.dart';
import '../common/widgets.dart';

/// Downloads, verifies and test-loads the models, then opens a new chat.
class InstallScreen extends ConsumerStatefulWidget {
  const InstallScreen({super.key, required this.entryId, required this.wifiOnly});
  final String entryId;
  final bool wifiOnly;

  @override
  ConsumerState<InstallScreen> createState() => _InstallScreenState();
}

class _InstallScreenState extends ConsumerState<InstallScreen> {
  StreamSubscription<InstallState>? _sub;
  InstallState _state = const InstallState(InstallStage.preparing);

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final services = ref.read(servicesProvider);
    final entry = services.catalog.interestEntry(widget.entryId);
    setState(() => _state = const InstallState(InstallStage.preparing));
    _sub?.cancel();
    _sub = services.installer.install(entry, wifiOnly: widget.wifiOnly).listen((s) async {
      if (!mounted) return;
      setState(() => _state = s);
      if (s.stage == InstallStage.done) {
        ref.invalidate(installedEntriesProvider);
        final chat = await services.chatRepository.createChat(entryId: entry.id);
        if (mounted) context.go('/chat/${chat.id}');
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final entry = services.catalog.interestEntry(widget.entryId);
    final s = _state;
    final pct = (s.fraction * 100).clamp(0, 100).round();
    final failed = s.stage == InstallStage.failed;

    return PopScope(
      canPop: failed || s.stage == InstallStage.preparing || s.stage == InstallStage.downloading,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Setting up your model', style: TextStyle(color: MedhaColors.muted)),
              const SizedBox(height: 16),
              Text(entry.displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              Text('${entry.tier} · ${services.catalog.baseModel(entry.baseModelId).name}',
                  style: const TextStyle(color: MedhaColors.muted)),
              const SizedBox(height: 48),
              if (failed) ...[
                const Text("The download didn't finish", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(s.error ?? 'Something went wrong.', style: const TextStyle(color: MedhaColors.textSoft, height: 1.5)),
              ] else ...[
                Text('$pct%', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w600, height: 1)),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: s.stage == InstallStage.preparing ? null : s.fraction,
                    minHeight: 10,
                    backgroundColor: MedhaColors.lineSoft,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  s.totalBytes > 0
                      ? '${formatBytes(s.receivedBytes)} of ${formatBytes(s.totalBytes)} · ${widget.wifiOnly ? 'Wi-Fi only' : 'Wi-Fi or mobile data'}'
                      : 'Model already on this phone · setting up',
                  style: const TextStyle(color: MedhaColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 32),
                _Step('Downloading model files', _stepState(s, InstallStage.downloading)),
                _Step('Verifying file integrity', _stepState(s, InstallStage.verifying)),
                _Step('Optimizing for this phone', _stepState(s, InstallStage.optimizing)),
              ],
              const Spacer(),
              if (failed) ...[
                FilledButton(onPressed: _start, child: const Text('Try again')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
              ] else ...[
                const Text('One-time download. After this, Medha works with no internet at all.',
                    textAlign: TextAlign.center, style: TextStyle(color: MedhaColors.muted, fontSize: 13)),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: s.stage == InstallStage.optimizing || s.stage == InstallStage.verifying ? null : () => context.pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  static _StepState _stepState(InstallState s, InstallStage step) {
    const order = [InstallStage.preparing, InstallStage.downloading, InstallStage.verifying, InstallStage.optimizing, InstallStage.done];
    final current = order.indexOf(s.stage);
    final mine = order.indexOf(step);
    if (current > mine) return _StepState.done;
    if (current == mine) return _StepState.active;
    return _StepState.pending;
  }
}

enum _StepState { pending, active, done }

class _Step extends StatelessWidget {
  const _Step(this.label, this.state);
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          switch (state) {
            _StepState.done => const Icon(Icons.check_circle, color: MedhaColors.success, size: 24),
            _StepState.active => const Icon(Icons.radio_button_checked, color: MedhaColors.accent, size: 24),
            _StepState.pending => const Icon(Icons.radio_button_unchecked, color: MedhaColors.line, size: 24),
          },
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 15, color: state == _StepState.pending ? MedhaColors.faint : MedhaColors.text)),
        ]),
      );
}
