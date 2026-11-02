import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/catalog/catalog.dart';
import '../../core/documents/document_index.dart';
import '../../core/inference/inference_engine.dart';
import '../../core/storage/models.dart';
import '../common/file_pick.dart';
import '../common/widgets.dart';
import 'chat_session.dart';
import 'report_sheet.dart';
import 'rich_reply.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId});
  final String chatId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  PickedFile? _pending;

  @override
  void dispose() {
    _input.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  /// Back from a chat always lands on the chat list, even when the chat was
  /// opened directly (after a download or unlock).
  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/chats');
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _send(ChatSession session, [String? text]) {
    final value = text ?? _input.text;
    if ((value.trim().isEmpty && _pending == null) || session.busy) return;
    final attachment = _pending;
    _input.clear();
    setState(() => _pending = null);
    session.send(value, attachment: attachment);
  }

  Future<void> _attach() async {
    final file = await pickDocument(ref);
    if (file == null || !mounted) return;
    final problem = DocumentIndex.validate(file, attachment: true);
    if (problem != null) {
      _toast(problem);
      return;
    }
    setState(() => _pending = file);
  }

  Future<void> _report(ChatSession session, ChatMessage reply) async {
    final i = session.messages.indexOf(reply);
    final question = session.messages.take(i < 0 ? 0 : i).lastWhere((m) => m.role == ChatRole.user, orElse: () => reply).content;
    final sent = await showReportSheet(context, ref, question: question, reply: reply.content, entryId: session.chat?.entryId);
    if (sent && mounted) _toast('Thanks. Your report is saved and will be sent when you are online.');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(chatSessionProvider(widget.chatId));
    final services = ref.watch(servicesProvider);
    // Keep the screen on while a reply is being written, so the phone
    // doesn't sleep in the middle of it.
    ref.listen(chatSessionProvider(widget.chatId).select((s) => s.busy), (_, busy) {
      busy ? WakelockPlus.enable() : WakelockPlus.disable();
    });
    final installed = ref.watch(installedEntriesProvider).valueOrNull;
    final entry = session.entry;

    if (session.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (session.loadError != null || entry == null) {
      return Scaffold(appBar: AppBar(leading: BackButton(onPressed: _back)), body: Center(child: Text(session.loadError ?? 'This subject is no longer available.')));
    }
    final modelMissing = installed != null && !installed.contains(entry.id);
    final projectId = session.chat?.projectId;
    final messages = session.messages.reversed.toList();

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/chats');
      },
      child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(session.chat?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Row(children: [
            CircleAvatar(radius: 4, backgroundColor: Color(entry.color)),
            const SizedBox(width: 6),
            Flexible(child: Text(entry.displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: MedhaColors.muted))),
          ]),
        ]),
        actions: [
          if (!modelMissing)
            IconButton(tooltip: 'Voice chat', icon: const Icon(Icons.graphic_eq), onPressed: () => context.push('/voice/${widget.chatId}')),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Pill('Offline', icon: Icons.lock_outline, color: MedhaColors.success, background: Color(0x1F5FD0A5)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          if (projectId != null) _ProjectBanner(projectId: projectId),
          if (session.chat?.ephemeral ?? false)
            const _Banner(icon: Icons.history_toggle_off, text: 'History is off. This chat is erased the next time Medha starts.'),
          Expanded(
            child: messages.isEmpty
                ? _Suggestions(entry: entry, onPick: modelMissing ? null : (p) => _send(session, p))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MessageView(
                        message: messages[i],
                        safety: services.catalog.safety,
                        attachment: session.attachments[messages[i].documentId],
                        onReport: () => _report(session, messages[i]),
                      ),
                    ),
                  ),
          ),
          if (session.status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(session.status!, style: const TextStyle(fontSize: 12, color: MedhaColors.muted)),
            ),
          if (modelMissing)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text('This model was removed from your phone. Download it again to keep chatting.',
                    textAlign: TextAlign.center, style: TextStyle(color: MedhaColors.textSoft)),
                const SizedBox(height: 10),
                FilledButton(onPressed: () => context.push('/subjects/${entry.interest}'), child: const Text('Download again')),
              ]),
            )
          else ...[
            if (_pending != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: InputChip(
                  avatar: const Icon(Icons.description_outlined, size: 16),
                  label: Text('${_pending!.name} · ${formatBytes(_pending!.bytes)}'),
                  onDeleted: () => setState(() => _pending = null),
                ),
              ),
            _Composer(
              controller: _input,
              busy: session.busy,
              hint: 'Ask ${entry.displayName}…',
              onSend: () => _send(session),
              onStop: session.stop,
              onAttach: session.busy ? null : _attach,
              onVoice: () => context.push('/voice/${widget.chatId}'),
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(aiDisclosure, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: MedhaColors.faint)),
          ),
        ]),
      ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.color = MedhaColors.muted});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: MedhaColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: MedhaColors.textSoft))),
        ]),
      );
}

class _ProjectBanner extends ConsumerWidget {
  const _ProjectBanner({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider(projectId)).valueOrNull;
    final files = ref.watch(projectFilesProvider(projectId)).valueOrNull?.length ?? 0;
    if (project == null) return const SizedBox.shrink();
    return _Banner(
      icon: Icons.folder_outlined,
      color: Color(project.color),
      text: 'Answers can use $files file${files == 1 ? '' : 's'} from ${project.name}',
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.entry, required this.onPick});
  final InterestEntry entry;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),
          Text('Hi! I am ${entry.displayName}, running fully on this phone.',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.35)),
          const SizedBox(height: 6),
          const Text('Ask me anything. No internet needed.', style: TextStyle(color: MedhaColors.muted)),
          if (entry.prompts.isNotEmpty && onPick != null) const SectionLabel('Try asking'),
          if (onPick != null)
            for (final p in entry.prompts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size.fromHeight(48)),
                  onPressed: () => onPick!(p),
                  child: Text(p, style: const TextStyle(color: MedhaColors.textSoft)),
                ),
              ),
        ],
      );
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.safety, required this.onReport, this.attachment});
  final ChatMessage message;
  final SafetyConfig safety;
  final DocumentRecord? attachment;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.kind == MessageKind.crisisCard) return _CrisisCard(safety: safety);
    final width = MediaQuery.sizeOf(context).width;

    if (m.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width * 0.8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (attachment != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Pill('${attachment!.name} · ${formatBytes(attachment!.bytes)}', icon: Icons.description_outlined, background: MedhaColors.lineSoft),
              ),
            if (m.voice)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mic_none, size: 12, color: MedhaColors.muted),
                  SizedBox(width: 4),
                  Text('Voice', style: TextStyle(fontSize: 11, color: MedhaColors.muted)),
                ]),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: const BoxDecoration(
                color: MedhaColors.accent,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: SelectableText(m.content, style: const TextStyle(color: MedhaColors.onAccent, fontSize: 15, height: 1.45)),
            ),
          ]),
        ),
      );
    }

    final isRefusal = m.kind == MessageKind.refusal;
    final isNotice = m.kind == MessageKind.notice;
    final streaming = m.status == MessageStatus.streaming;
    final reportable = m.kind == MessageKind.text && m.status == MessageStatus.done && m.content.isNotEmpty;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width * 0.86),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isNotice ? MedhaColors.surfaceLow : MedhaColors.bubble,
              border: isRefusal ? Border.all(color: MedhaColors.line) : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (m.reasoning.isNotEmpty) _Reasoning(text: m.reasoning, thinking: streaming && m.content.isEmpty),
              if (isRefusal)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.shield_outlined, size: 14, color: MedhaColors.muted),
                    SizedBox(width: 6),
                    Text('Safety', style: TextStyle(fontSize: 12, color: MedhaColors.muted, fontWeight: FontWeight.w600)),
                  ]),
                ),
              if (streaming && m.content.isEmpty && m.reasoning.isEmpty)
                const Text('Thinking on-device…', style: TextStyle(color: MedhaColors.muted))
              else if (m.content.isNotEmpty)
                if (m.kind == MessageKind.text)
                  RichReply(m.content)
                else
                  SelectableText(m.content, style: const TextStyle(fontSize: 15, height: 1.5)),
              if (m.sources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Sources: ${m.sources.join(', ')}', style: const TextStyle(fontSize: 12, color: MedhaColors.muted)),
                ),
              if (m.status == MessageStatus.cancelled)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Stopped', style: TextStyle(fontSize: 12, color: MedhaColors.faint)),
                ),
            ]),
          ),
          if (reportable)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: MedhaColors.faint, minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: onReport,
              icon: const Icon(Icons.flag_outlined, size: 14),
              label: const Text('Report', style: TextStyle(fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

class _Reasoning extends StatelessWidget {
  const _Reasoning({required this.text, required this.thinking});
  final String text;
  final bool thinking;

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          dense: true,
          title: Text(thinking ? 'Working it out…' : 'Show steps',
              style: const TextStyle(fontSize: 13, color: MedhaColors.accent, fontWeight: FontWeight.w600)),
          children: [Text(text, style: const TextStyle(fontSize: 13, height: 1.5, color: MedhaColors.textSoft))],
        ),
      );
}

class _CrisisCard extends StatelessWidget {
  const _CrisisCard({required this.safety});
  final SafetyConfig safety;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x145FD0A5),
          border: Border.all(color: const Color(0x665FD0A5)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(safety.crisisTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(safety.crisisBody, style: const TextStyle(fontSize: 14, height: 1.5, color: MedhaColors.textSoft)),
          const SizedBox(height: 12),
          for (final r in safety.crisisResources)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size.fromHeight(52)),
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: r.number)),
                icon: const Icon(Icons.call, color: MedhaColors.success),
                label: Text('${r.label} · ${r.number}\n${r.description}', style: const TextStyle(fontSize: 13, height: 1.35)),
              ),
            ),
        ]),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.hint,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
    required this.onVoice,
  });
  final TextEditingController controller;
  final bool busy;
  final String hint;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback? onAttach;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: MedhaColors.lineSoft))),
        padding: const EdgeInsets.fromLTRB(4, 10, 12, 8),
        child: Row(children: [
          IconButton(tooltip: 'Attach a file (up to 5 MB)', icon: const Icon(Icons.attach_file), onPressed: onAttach),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(hintText: hint),
            ),
          ),
          IconButton(tooltip: 'Talk to Medha', icon: const Icon(Icons.mic_none), onPressed: busy ? null : onVoice),
          IconButton.filled(
            tooltip: busy ? 'Stop' : 'Send',
            iconSize: 22,
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: busy ? onStop : onSend,
            icon: Icon(busy ? Icons.stop_rounded : Icons.arrow_upward_rounded),
          ),
        ]),
      );
}
