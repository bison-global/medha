import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/catalog/catalog.dart';
import '../chat/new_chat.dart';
import '../common/widgets.dart';

final _storageProvider = FutureProvider.autoDispose<int>((ref) => ref.watch(servicesProvider).installer.storageBytes());
final _entryBasesProvider =
    FutureProvider.autoDispose<Map<String, String?>>((ref) => ref.watch(servicesProvider).modelRepository.installedEntryBases());

/// Installed subjects, storage use, details, delete; and subjects to add.
class ModelsScreen extends ConsumerWidget {
  const ModelsScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(installedEntriesProvider);
    ref.invalidate(_storageProvider);
    ref.invalidate(_entryBasesProvider);
  }

  Future<void> _details(BuildContext context, WidgetRef ref, InterestEntry e, String baseId, Map<String, String?> bases) async {
    final catalog = ref.read(servicesProvider).catalog;
    final b = catalog.baseModel(baseId);
    final shared = bases.entries
        .where((x) => x.key != e.id && (x.value ?? catalog.interestEntry(x.key).baseModelId) == baseId)
        .map((x) => catalog.interestEntry(x.key).name)
        .toSet()
        .join(', ');
    final rows = <(String, String)>[
      ('Runs on', b.name),
      ('Made by', b.maker),
      ('Licence', b.license),
      ('File', 'GGUF · ${formatBytes(b.bytes)}'),
      ('Memory needed', '~${(b.minRamMb / 1024).toStringAsFixed(1)} GB'),
      ('Subject add-on', e.adapter == null ? 'None · built-in instructions' : 'Fine-tuned by Medha'),
      ('Shared with', shared.isEmpty ? 'No other subjects' : shared),
      ('Safety checker', catalog.guardModel.name),
      if (baseId != e.baseModelId) ('Note', 'Using a smaller model because this phone has less memory'),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: MedhaColors.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.displayName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 130, child: Text(r.$1, style: const TextStyle(color: MedhaColors.muted, fontSize: 13))),
                  Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 13))),
                ]),
              ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(sheet);
                    context.go('/settings/licences');
                  },
                  child: const Text('View licence'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(sheet), child: const Text('Done'))),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, InterestEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MedhaColors.surface,
        title: Text('Remove ${e.displayName}?'),
        content: const Text('Its model file is deleted unless another subject uses it. Your chats stay, and you can download it again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MedhaColors.danger, foregroundColor: Colors.white, minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final services = ref.read(servicesProvider);
    await services.engines.chat.unload();
    await services.installer.uninstall(e.id);
    _refresh(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(servicesProvider).catalog;
    final installed = ref.watch(installedEntriesProvider).valueOrNull ?? const <String>{};
    final bases = ref.watch(_entryBasesProvider).valueOrNull ?? const <String, String?>{};
    final storage = ref.watch(_storageProvider).valueOrNull ?? 0;
    final entries = catalog.interests.where((e) => installed.contains(e.id)).toList();
    final available = catalog.subjects.where((s) => !catalog.tiersFor(s.interest).any((t) => installed.contains(t.id))).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Models', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text('Everything here runs on this phone. Subjects that share a model only download it once.',
              style: TextStyle(color: MedhaColors.muted, height: 1.5)),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: MedhaColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Icon(Icons.sd_storage_outlined, color: MedhaColors.accent),
            const SizedBox(width: 12),
            const Expanded(child: Text('Storage used by Medha', style: TextStyle(color: MedhaColors.textSoft))),
            Text(formatBytes(storage), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
        const SectionLabel('Installed'),
        if (entries.isEmpty) const Text('No models yet. Add one below.', style: TextStyle(color: MedhaColors.muted)),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: MedhaColors.surfaceLow,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _details(context, ref, e, bases[e.id] ?? e.baseModelId, bases),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  child: Row(children: [
                    CircleAvatar(radius: 7, backgroundColor: Color(e.color)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.displayName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('${catalog.baseModel(bases[e.id] ?? e.baseModelId).name} · ${e.tier} · Details',
                            style: const TextStyle(fontSize: 12, color: MedhaColors.muted)),
                      ]),
                    ),
                    TextButton(onPressed: () => startNewChat(context, ref), child: const Text('Chat')),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline, color: MedhaColors.muted),
                      onPressed: () => _remove(context, ref, e),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        if (available.isNotEmpty) const SectionLabel('Add a subject'),
        for (final s in available)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: MedhaColors.surfaceLow,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                leading: CircleAvatar(radius: 7, backgroundColor: Color(s.color)),
                title: Text('Medha ${s.name}'),
                subtitle: Text(s.blurb, style: const TextStyle(fontSize: 12, color: MedhaColors.muted)),
                trailing: catalog.tiersFor(s.interest).any((t) => t.available)
                    ? OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 36)),
                        onPressed: () async {
                          await context.push('/subjects/${s.interest}');
                          _refresh(ref);
                        },
                        child: const Text('Get'),
                      )
                    : const Pill('Coming soon'),
              ),
            ),
          ),
      ]),
    );
  }
}
