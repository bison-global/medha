import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../common/widgets.dart';

/// Licence texts and notices for every model and native library
/// (ARCHITECTURE.md §9.5). Flutter package licences are one tap away.
class LicencesScreen extends ConsumerWidget {
  const LicencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(servicesProvider).catalog;
    final models = catalog.baseModels.values.toList();
    final installed = ref.watch(installedEntriesProvider).valueOrNull ?? const <String>{};
    String usedFor(String baseId) => catalog.subjects
        .where((s) => catalog.tiersFor(s.interest).any((t) => t.baseModelId == baseId))
        .map((s) => s.name)
        .join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Open-source licences')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text(
            "Medha runs on open models made by other organisations. Their licences and notices are listed here. Medha's subject add-ons are fine-tuned from these models and are marked as modified.",
            style: TextStyle(fontSize: 14, height: 1.5, color: MedhaColors.muted),
          ),
        ),
        for (final m in models)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _LicenceCard(
              title: m.name,
              licence: m.license,
              maker: m.maker,
              detail: m.id == catalog.safety.guardModelId ? 'Safety checker for every message and reply' : 'Used for: ${usedFor(m.id)}',
              onPhone: installed.isNotEmpty && (m.id == catalog.safety.guardModelId ||
                  catalog.interests.any((e) => installed.contains(e.id) && e.baseModelId == m.id)),
              text: [m.licenseText, if (m.notice != null) 'NOTICE\n${m.notice}'].join('\n\n'),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: _LicenceCard(
            title: 'llama.cpp',
            licence: 'MIT',
            maker: 'The ggml authors',
            detail: 'Runs the models on this phone',
            onPhone: true,
            text: 'MIT License. Copyright (c) 2023-2026 The ggml authors. Full text: https://github.com/ggml-org/llama.cpp/blob/master/LICENSE',
          ),
        ),
        OutlinedButton(
          onPressed: () => showLicensePage(context: context, applicationName: 'Medha'),
          child: const Text('App libraries'),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 18, 4, 0),
          child: Text(
            'Medha is not affiliated with or endorsed by these organisations. Model names are trademarks of their respective owners.',
            style: TextStyle(fontSize: 12, height: 1.5, color: MedhaColors.faint),
          ),
        ),
      ]),
    );
  }
}

class _LicenceCard extends StatelessWidget {
  const _LicenceCard({
    required this.title,
    required this.licence,
    required this.maker,
    required this.detail,
    required this.onPhone,
    required this.text,
  });
  final String title;
  final String licence;
  final String maker;
  final String detail;
  final bool onPhone;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
              Pill(licence),
            ]),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('$maker\n$detail\n${onPhone ? 'On this phone' : 'Not downloaded'}',
                  style: const TextStyle(fontSize: 12, height: 1.5, color: MedhaColors.muted)),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: MedhaColors.ink, borderRadius: BorderRadius.circular(10)),
                child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5)),
              ),
            ],
          ),
        ),
      );
}
