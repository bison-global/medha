import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/catalog/catalog.dart';

/// Starts a new chat (in [projectId] if given), asking which subject to use
/// when more than one is installed. Opens voice mode when [voice] is set.
Future<void> startNewChat(BuildContext context, WidgetRef ref, {String? projectId, bool voice = false}) async {
  final services = ref.read(servicesProvider);
  final installed = await ref.read(installedEntriesProvider.future);
  final entries = services.catalog.interests.where((e) => installed.contains(e.id)).toList();
  if (!context.mounted) return;

  if (entries.isEmpty) {
    context.push('/subjects');
    return;
  }
  InterestEntry? entry = entries.length == 1 ? entries.single : null;
  entry ??= await showModalBottomSheet<InterestEntry>(
    context: context,
    backgroundColor: MedhaColors.surface,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Chat with', style: TextStyle(fontWeight: FontWeight.w600))),
          for (final e in entries)
            ListTile(
              leading: CircleAvatar(radius: 6, backgroundColor: Color(e.color)),
              title: Text(e.displayName),
              onTap: () => Navigator.of(sheet).pop(e),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add a subject'),
            onTap: () {
              Navigator.of(sheet).pop();
              context.push('/subjects');
            },
          ),
        ]),
      ),
    ),
  );
  if (entry == null) return;

  final chat = await services.chatRepository.createChat(
    entryId: entry.id,
    projectId: projectId,
    ephemeral: !services.settings.saveHistory,
  );
  if (projectId != null) {
    await services.projects.touch(projectId);
    ref.invalidate(projectChatsProvider(projectId));
  }
  if (!context.mounted) return;
  await context.push(voice ? '/voice/${chat.id}' : '/chat/${chat.id}');
  ref.invalidate(chatListProvider);
  if (projectId != null) ref.invalidate(projectChatsProvider(projectId));
}
