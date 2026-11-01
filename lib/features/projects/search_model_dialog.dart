import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/download/model_installer.dart';
import '../common/widgets.dart';

/// Before the first upload, offers the small search model that lets Medha
/// find the relevant part of a document. Without it, search uses keywords.
/// Returns when the user has chosen (and any download has finished).
Future<void> offerSearchModel(BuildContext context, WidgetRef ref) async {
  final services = ref.read(servicesProvider);
  if (services.catalog.embeddingModel == null || await services.installer.embedderInstalled()) return;
  if (!context.mounted) return;
  await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const _SearchModelDialog());
}

class _SearchModelDialog extends ConsumerStatefulWidget {
  const _SearchModelDialog();

  @override
  ConsumerState<_SearchModelDialog> createState() => _SearchModelDialogState();
}

class _SearchModelDialogState extends ConsumerState<_SearchModelDialog> {
  StreamSubscription<InstallState>? _sub;
  InstallState? _state;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _download() {
    final services = ref.read(servicesProvider);
    _sub = services.installer.installEmbedder(wifiOnly: services.settings.wifiOnly).listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
      if (s.stage == InstallStage.done) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(servicesProvider).catalog.embeddingModel!;
    final s = _state;
    return AlertDialog(
      backgroundColor: MedhaColors.surface,
      title: const Text('Add document search?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'A small search model (${formatBytes(model.bytes)}) helps Medha find the right part of your files. '
          'It runs on this phone. Without it, Medha searches by keywords only.',
          style: const TextStyle(height: 1.5, color: MedhaColors.textSoft),
        ),
        if (s != null) ...[
          const SizedBox(height: 16),
          if (s.stage == InstallStage.failed)
            Text(s.error ?? 'Download failed', style: const TextStyle(color: Color(0xFFFF8A80)))
          else ...[
            LinearProgressIndicator(value: s.stage == InstallStage.preparing ? null : s.fraction),
            const SizedBox(height: 6),
            Text('${(s.fraction * 100).round()}%', style: const TextStyle(color: MedhaColors.muted, fontSize: 12)),
          ],
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now')),
        if (s == null || s.stage == InstallStage.failed)
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: _download,
            child: const Text('Download'),
          ),
      ],
    );
  }
}
