import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/documents/document_index.dart';
import '../../core/documents/extractor.dart';
import '../../core/storage/models.dart';
import '../chat/new_chat.dart';
import '../common/file_pick.dart';
import '../common/widgets.dart';
import 'search_model_dialog.dart';

class ProjectScreen extends ConsumerStatefulWidget {
  const ProjectScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> {
  String? _uploading;

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _refresh() {
    ref.invalidate(projectFilesProvider(widget.projectId));
    ref.invalidate(projectChatsProvider(widget.projectId));
    ref.invalidate(projectsProvider);
  }

  Future<void> _upload(int existing) async {
    if (existing >= UploadLimits.projectFiles) {
      _toast('A project can hold up to ${UploadLimits.projectFiles} files. Remove one to add another.');
      return;
    }
    final file = await pickDocument(ref);
    if (file == null || !mounted) return;
    final problem = DocumentIndex.validate(file, attachment: false, existingProjectFiles: existing);
    if (problem != null) {
      _toast(problem);
      return;
    }
    await offerSearchModel(context, ref);
    setState(() => _uploading = file.name);
    try {
      final (record, _) = await ref.read(servicesProvider).documentIndex.add(file, projectId: widget.projectId);
      if (!mounted) return;
      _toast(switch (record.status) {
        DocumentStatus.noText => 'No readable text found in "${file.name}". Scanned PDFs are not supported yet.',
        _ when record.truncated => 'Added "${file.name}". It is very long, so only the first part can be searched.',
        _ => 'Added "${file.name}"',
      });
    } on UploadRejected catch (e) {
      if (mounted) _toast(e.message);
    } on Object {
      if (mounted) _toast('Medha couldn\'t read "${file.name}". Try a different file.');
    } finally {
      if (mounted) setState(() => _uploading = null);
      await ref.read(servicesProvider).projects.touch(widget.projectId);
      _refresh();
    }
  }

  Future<void> _delete(Project p, int files) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MedhaColors.surface,
        title: Text('Delete "${p.name}"?'),
        content: Text('Its $files uploaded file${files == 1 ? '' : 's'} will be removed from this phone. Its chats will move to Chats.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MedhaColors.danger, foregroundColor: Colors.white, minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(servicesProvider).projects.delete(p.id);
    ref.invalidate(projectsProvider);
    ref.invalidate(chatListProvider);
    if (mounted) context.go('/projects');
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider(widget.projectId)).valueOrNull;
    final files = ref.watch(projectFilesProvider(widget.projectId)).valueOrNull ?? const <DocumentRecord>[];
    final chats = ref.watch(projectChatsProvider(widget.projectId)).valueOrNull ?? const <ChatSummary>[];
    final catalog = ref.watch(servicesProvider).catalog;
    if (project == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final totalBytes = files.fold<int>(0, (n, f) => n + f.bytes);

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(project, files.length);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete project'))],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Row(children: [
          const Expanded(child: SectionLabel('Files')),
          Padding(
            padding: const EdgeInsets.only(top: 14, right: 4),
            child: Text('${files.length} of ${UploadLimits.projectFiles} files · ${formatBytes(totalBytes)}',
                style: const TextStyle(fontSize: 12, color: MedhaColors.muted)),
          ),
        ]),
        for (final f in files)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: MedhaColors.surfaceLow,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: MedhaColors.ink, borderRadius: BorderRadius.circular(10)),
                  child: Text(f.ext.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MedhaColors.textSoft)),
                ),
                title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${formatBytes(f.bytes)} · ${switch (f.status) {
                    DocumentStatus.ready => f.truncated ? 'Ready (first part only)' : 'Ready',
                    DocumentStatus.indexing => 'Reading…',
                    DocumentStatus.noText => 'No readable text',
                    DocumentStatus.failed => 'Could not read',
                  }}',
                  style: const TextStyle(fontSize: 12, color: MedhaColors.muted),
                ),
                trailing: IconButton(
                  tooltip: 'Remove file',
                  icon: const Icon(Icons.close, color: MedhaColors.muted),
                  onPressed: () async {
                    await ref.read(servicesProvider).documentIndex.remove(f.id);
                    _refresh();
                  },
                ),
              ),
            ),
          ),
        if (_uploading != null)
          ListTile(
            leading: const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            title: Text('Reading $_uploading…'),
          )
        else if (files.length < UploadLimits.projectFiles)
          OutlinedButton.icon(
            onPressed: () => _upload(files.length),
            icon: const Icon(Icons.upload_file, color: MedhaColors.accent),
            label: const Text('Upload a document · PDF, DOCX, TXT or MD, up to 10 MB'),
          )
        else
          const Padding(
            padding: EdgeInsets.all(4),
            child: Text('This project has the maximum of 5 files. Remove one to add another.', style: TextStyle(color: MedhaColors.muted)),
          ),
        const SectionLabel('Chats in this project'),
        for (final c in chats)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: MedhaColors.surfaceLow,
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(catalog.interests.where((e) => e.id == c.entryId).firstOrNull?.displayName ?? 'Model removed',
                    style: const TextStyle(fontSize: 12, color: MedhaColors.muted)),
                onTap: () async {
                  await context.push('/chat/${c.id}');
                  _refresh();
                },
                trailing: IconButton(
                  tooltip: 'Delete chat',
                  icon: const Icon(Icons.delete_outline, color: MedhaColors.muted),
                  onPressed: () async {
                    await ref.read(servicesProvider).chatRepository.deleteChat(c.id);
                    _refresh();
                  },
                ),
              ),
            ),
          ),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => startNewChat(context, ref, projectId: widget.projectId),
          icon: const Icon(Icons.add),
          label: const Text('New chat in this project'),
        ),
      ]),
    );
  }
}
