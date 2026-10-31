import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../common/widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: MedhaColors.surface,
        title: const Text('Delete all chats?'),
        content: const Text('Every chat will be permanently erased from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MedhaColors.danger, foregroundColor: Colors.white, minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(chatListProvider).deleteAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All chats deleted')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        const SectionLabel('Chat history'),
        Card(
          child: ListTile(
            title: const Text('Delete all chats', style: TextStyle(color: Color(0xFFFF8A80))),
            onTap: () => _deleteAll(context, ref),
          ),
        ),
        const SectionLabel('About'),
        Card(
          child: Column(children: [
            ListTile(
              title: const Text('Open-source licences'),
              subtitle: const Text('The open models Medha uses and their licences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/licences'),
            ),
            const Divider(),
            const ListTile(
              title: Text('About AI answers'),
              subtitle: Text('Medha is an AI and can make mistakes. Check important answers.'),
            ),
            const Divider(),
            ListTile(
              title: const Text('Version'),
              trailing: Text(services.demo ? '0.1.0 · demo mode' : '0.1.0', style: const TextStyle(color: MedhaColors.muted)),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0x145FD0A5), borderRadius: BorderRadius.circular(16)),
          child: const Text(
            'Chats are stored encrypted on this phone only. Nothing is sent to a server.',
            style: TextStyle(fontSize: 13, height: 1.5, color: MedhaColors.textSoft),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
