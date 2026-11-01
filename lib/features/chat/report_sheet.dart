import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/reports/report_service.dart';

/// "Report this reply": reason, optional note, and whether to include the
/// question and reply. Nothing is sent until the user taps Send.
Future<bool> showReportSheet(BuildContext context, WidgetRef ref, {required String question, required String reply, String? entryId}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MedhaColors.surface,
    builder: (_) => _ReportSheet(question: question, reply: reply, entryId: entryId),
  );
  return sent ?? false;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.question, required this.reply, this.entryId});
  final String question;
  final String reply;
  final String? entryId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  String _reason = 'harmful';
  bool _include = true;
  bool _sending = false;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    await ref.read(servicesProvider).reports.submit(
          reason: _reason,
          note: _note.text,
          includeText: _include,
          question: widget.question,
          reply: widget.reply,
          entryId: widget.entryId,
        );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Report this reply', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text("What's wrong with it?", style: TextStyle(color: MedhaColors.textSoft)),
              const SizedBox(height: 8),
              for (final r in ReportService.reasons.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_reason == r.key ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: _reason == r.key ? MedhaColors.accent : MedhaColors.faint),
                  title: Text(r.value),
                  selected: _reason == r.key,
                  onTap: () => setState(() => _reason = r.key),
                ),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Add details (optional)', hintText: 'What should it have said?'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _include,
                onChanged: (v) => setState(() => _include = v),
                title: const Text('Include my question and this reply'),
                subtitle: const Text('Helps the team see what went wrong'),
              ),
              const Text(
                'Reports are the only thing Medha ever sends. Nothing leaves your phone until you tap Send, and it waits until you are online.',
                style: TextStyle(fontSize: 12, height: 1.5, color: MedhaColors.muted),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: _sending ? null : _send, child: const Text('Send report'))),
              ]),
            ]),
          ),
        ),
      );
}
