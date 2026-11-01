import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/catalog/catalog.dart';
import '../../core/storage/models.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final services = ref.read(servicesProvider);
    final installed = await ref.read(installedEntriesProvider.future);
    final entries = services.catalog.interests.where((e) => installed.contains(e.id)).toList();
    if (!context.mounted) return;

    InterestEntry? entry;
    if (entries.isEmpty) {
      context.push('/subjects');
      return;
    } else if (entries.length == 1) {
      entry = entries.single;
    } else {
      entry = await showModalBottomSheet<InterestEntry>(
        context: context,
        backgroundColor: MedhaColors.surface,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Chat with', style: TextStyle(fontWeight: FontWeight.w600))),
            for (final e in entries)
              ListTile(
                leading: CircleAvatar(radius: 6, backgroundColor: Color(e.color)),
                title: Text(e.displayName),
                onTap: () => Navigator.of(context).pop(e),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add a subject'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/subjects');
              },
            ),
          ]),
        ),
      );
    }
    if (entry == null) return;
    final chat = await services.chatRepository.createChat(entryId: entry.id);
    if (context.mounted) {
      await context.push('/chat/${chat.id}');
      ref.read(chatListProvider).refresh();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(chatListProvider);
    final catalog = ref.watch(servicesProvider).catalog;
    final chats = list.chats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await context.push('/settings');
              list.refresh();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newChat(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New chat'),
      ),
      body: list.loading
          ? const Center(child: CircularProgressIndicator())
          : chats.isEmpty
              ? const _Empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: chats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = chats[i];
                    InterestEntry? entry;
                    try {
                      entry = catalog.interestEntry(c.entryId);
                    } on StateError {
                      entry = null;
                    }
                    return _ChatTile(
                      chat: c,
                      entry: entry,
                      onOpen: () async {
                        await context.push('/chat/${c.id}');
                        list.refresh();
                      },
                      onDelete: () {
                        list.delete(c.id);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                            content: const Text('Chat deleted'),
                            duration: list.undoWindow,
                            action: SnackBarAction(label: 'Undo', onPressed: () => list.undo(c.id)),
                          ));
                      },
                    );
                  },
                ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.entry, required this.onOpen, required this.onDelete});
  final ChatSummary chat;
  final InterestEntry? entry;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  String _when(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (diff == 1) return 'Yesterday';
    return '${t.day}/${t.month}';
  }

  @override
  Widget build(BuildContext context) => Material(
        color: MedhaColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(children: [
                    CircleAvatar(radius: 4, backgroundColor: entry == null ? MedhaColors.faint : Color(entry!.color)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(entry?.displayName ?? 'Model removed',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: MedhaColors.muted)),
                    ),
                    Text('  ·  ${_when(chat.updatedAt)}', style: const TextStyle(fontSize: 12, color: MedhaColors.muted)),
                  ]),
                ]),
              ),
              IconButton(tooltip: 'Delete chat', icon: const Icon(Icons.delete_outline, color: MedhaColors.muted), onPressed: onDelete),
            ]),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('No chats yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('Start a new chat with one of your models.', textAlign: TextAlign.center, style: TextStyle(color: MedhaColors.muted)),
          ]),
        ),
      );
}
