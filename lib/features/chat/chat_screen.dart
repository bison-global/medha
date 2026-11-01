import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/catalog/catalog.dart';
import '../../core/inference/inference_engine.dart';
import '../../core/storage/models.dart';
import '../common/widgets.dart';
import 'chat_session.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId});
  final String chatId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send(ChatSession session, [String? text]) {
    final value = text ?? _input.text;
    if (value.trim().isEmpty || session.busy) return;
    _input.clear();
    session.send(value);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(chatSessionProvider(widget.chatId));
    final safety = ref.watch(servicesProvider).catalog.safety;
    final entry = session.entry;

    if (session.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (session.loadError != null || entry == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(session.loadError ?? 'This model is no longer installed.')));
    }

    final messages = session.messages.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(session.chat?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Row(children: [
            CircleAvatar(radius: 4, backgroundColor: Color(entry.color)),
            const SizedBox(width: 6),
            Text(entry.displayName, style: const TextStyle(fontSize: 12, color: MedhaColors.muted)),
          ]),
        ]),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Pill('Offline', icon: Icons.lock_outline, color: MedhaColors.success, background: Color(0x1F5FD0A5)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: messages.isEmpty
                ? _Suggestions(entry: entry, onPick: (p) => _send(session, p))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MessageView(message: messages[i], safety: safety),
                    ),
                  ),
          ),
          _Composer(
            controller: _input,
            busy: session.busy,
            hint: 'Ask ${entry.displayName}…',
            onSend: () => _send(session),
            onStop: session.stop,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(aiDisclosure, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: MedhaColors.faint)),
          ),
        ]),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.entry, required this.onPick});
  final InterestEntry entry;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),
          Text('Hi! I am ${entry.displayName}, running fully on this phone.',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.35)),
          const SizedBox(height: 6),
          const Text('Ask me anything. No internet needed.', style: TextStyle(color: MedhaColors.muted)),
          if (entry.prompts.isNotEmpty) const SectionLabel('Try asking'),
          for (final p in entry.prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size.fromHeight(48)),
                onPressed: () => onPick(p),
                child: Text(p, style: const TextStyle(color: MedhaColors.textSoft)),
              ),
            ),
        ],
      );
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.safety});
  final ChatMessage message;
  final SafetyConfig safety;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.kind == MessageKind.crisisCard) return _CrisisCard(safety: safety);

    if (m.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          child: Container(
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
        ),
      );
    }

    final isRefusal = m.kind == MessageKind.refusal;
    final isNotice = m.kind == MessageKind.notice;
    final streaming = m.status == MessageStatus.streaming;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        child: Container(
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
              SelectableText(m.content, style: const TextStyle(fontSize: 15, height: 1.5)),
            if (m.status == MessageStatus.cancelled)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Stopped', style: TextStyle(fontSize: 12, color: MedhaColors.faint)),
              ),
          ]),
        ),
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
  const _Composer({required this.controller, required this.busy, required this.hint, required this.onSend, required this.onStop});
  final TextEditingController controller;
  final bool busy;
  final String hint;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: MedhaColors.lineSoft))),
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
        child: Row(children: [
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
          const SizedBox(width: 8),
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
