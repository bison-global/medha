import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../core/security/app_lock.dart';
import '../../core/settings/prefs.dart';
import '../common/widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: MedhaColors.surface,
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MedhaColors.danger, foregroundColor: Colors.white, minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    if (!await _confirm(context, 'Delete all chats?',
        'Every chat, including chats inside projects, will be permanently erased from this phone. Project files are kept.', 'Delete all')) {
      return;
    }
    await ref.read(servicesProvider).chatRepository.deleteAllChats();
    ref.invalidate(chatListProvider);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All chats deleted')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final lock = ref.watch(appLockProvider);
    final settings = ref.watch(settingsProvider);

    Widget seg<T>(List<(T, String)> options, T value, ValueChanged<T> onChanged) => SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [for (final o in options) ButtonSegment<T>(value: o.$1, label: Text(o.$2))],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600))),
      body: ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        const SectionLabel('Security'),
        Card(
          child: Column(children: [
            SwitchListTile(
              title: const Text('App lock'),
              subtitle: const Text('Ask for fingerprint or PIN to open Medha'),
              value: lock.enabled,
              onChanged: (on) async {
                if (on) {
                  context.push('/secure');
                } else if (await _confirm(context, 'Turn off app lock?', 'Anyone with your phone will be able to open your chats.', 'Turn off')) {
                  await lock.disable();
                }
              },
            ),
            if (lock.enabled) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Unlock with', style: TextStyle(fontSize: 13, color: MedhaColors.textSoft)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: seg<LockMethod>([(LockMethod.biometric, 'Fingerprint'), (LockMethod.pin, 'PIN only')], lock.method, lock.setMethod),
                  ),
                  const SizedBox(height: 14),
                  const Text('Lock again after leaving the app', style: TextStyle(fontSize: 13, color: MedhaColors.textSoft)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: seg<int>([(0, 'Instantly'), (60, '1 min'), (300, '5 min')], lock.autoLockSeconds, lock.setAutoLock),
                  ),
                ]),
              ),
              const Divider(),
              ListTile(leading: const Icon(Icons.pin_outlined), title: const Text('Change PIN'), onTap: () => context.push('/secure')),
              ListTile(leading: const Icon(Icons.lock_outline, color: MedhaColors.accent), title: const Text('Lock now'), onTap: lock.lockNow),
            ],
          ]),
        ),
        const SectionLabel('Chat history'),
        Card(
          child: Column(children: [
            SwitchListTile(
              title: const Text('Save chat history'),
              subtitle: Text(settings.saveHistory
                  ? 'Chats are kept on this phone until you delete them'
                  : 'Off: new chats are erased the next time Medha starts'),
              value: settings.saveHistory,
              onChanged: (v) => settings.saveHistory = v,
            ),
            const Divider(),
            ListTile(
              title: const Text('Delete all chats', style: TextStyle(color: Color(0xFFFF8A80))),
              onTap: () => _deleteAll(context, ref),
            ),
          ]),
        ),
        const SectionLabel('Voice'),
        Card(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Voice language', style: TextStyle(fontSize: 13, color: MedhaColors.textSoft)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final lang in voiceLanguages.entries)
                    ChoiceChip(
                      label: Text(lang.value),
                      selected: settings.voiceLanguage == lang.key,
                      onSelected: (_) => settings.voiceLanguage = lang.key,
                    ),
                ]),
              ]),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Read replies aloud'),
              subtitle: const Text('In voice chat, Medha speaks its answers'),
              value: settings.readAloud,
              onChanged: (v) => settings.readAloud = v,
            ),
          ]),
        ),
        const SectionLabel('Downloads'),
        Card(
          child: SwitchListTile(
            title: const Text('Download on Wi-Fi only'),
            value: settings.wifiOnly,
            onChanged: (v) => settings.wifiOnly = v,
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
              subtitle: Text('Medha is an AI and can make mistakes. Check important answers, and use Report on any reply that is harmful or wrong.'),
            ),
            const Divider(),
            ListTile(
              title: const Text('Version'),
              trailing: Text(services.demo ? '$appVersion · demo mode' : appVersion, style: const TextStyle(color: MedhaColors.muted)),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0x145FD0A5), borderRadius: BorderRadius.circular(16)),
          child: const Text(
            'Chats, projects and uploaded files are stored encrypted on this phone only. Nothing is sent to a server, except reports you choose to send.',
            style: TextStyle(fontSize: 13, height: 1.5, color: MedhaColors.textSoft),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
