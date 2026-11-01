import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';

const projectColors = [0xFF7AA7FF, 0xFFF5B04C, 0xFF5FD0A5, 0xFFB892FF, 0xFFFF8FB1];

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MedhaColors.surface,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('New project', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Project name', hintText: 'e.g. Exam revision'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Create'))),
          ]),
        ]),
      ),
    );
    controller.dispose();
    if (name == null) return;
    final services = ref.read(servicesProvider);
    final count = (await services.projects.list()).length;
    final p = await services.projects.create(name.trim().isEmpty ? 'Untitled project' : name.trim(), projectColors[count % projectColors.length]);
    ref.invalidate(projectsProvider);
    if (context.mounted) context.go('/projects/${p.id}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Projects', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-project',
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New project'),
      ),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
            child: Text('Group chats and documents together. Chats in a project can answer from its files.',
                style: TextStyle(fontSize: 14, height: 1.5, color: MedhaColors.muted)),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: Column(children: [
                Text('No projects yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                SizedBox(height: 8),
                Text('Create one for a subject or goal, like exam revision, and keep its notes and chats together.',
                    textAlign: TextAlign.center, style: TextStyle(color: MedhaColors.muted, height: 1.5)),
              ]),
            ),
          for (final p in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ProjectTile(projectId: p.id, name: p.name, color: p.color),
            ),
        ]),
      ),
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  const _ProjectTile({required this.projectId, required this.name, required this.color});
  final String projectId;
  final String name;
  final int color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(projectFilesProvider(projectId)).valueOrNull?.length ?? 0;
    final chats = ref.watch(projectChatsProvider(projectId)).valueOrNull?.length ?? 0;
    return Material(
      color: MedhaColors.surfaceLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go('/projects/$projectId'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: MedhaColors.ink, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.folder_outlined, color: Color(color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('$chats chat${chats == 1 ? '' : 's'} · $files file${files == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 13, color: MedhaColors.muted)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: MedhaColors.muted),
          ]),
        ),
      ),
    );
  }
}
