import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/inference/inference_engine.dart';
import '../../core/settings/prefs.dart';
import '../../core/storage/models.dart';
import '../../core/voice/voice_io.dart';

final speechInputProvider = Provider<SpeechInput>((ref) => DeviceSpeechInput());
final speechOutputProvider = Provider<SpeechOutput>((ref) => DeviceSpeechOutput());

enum _Phase { idle, listening, thinking, speaking }

/// Full-screen voice chat on top of an existing chat. What you say goes
/// through the same safety checks as typed messages.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key, required this.chatId});
  final String chatId;

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.idle;
  String _heard = '';
  String? _error;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final SpeechInput _input = ref.read(speechInputProvider);
  late final SpeechOutput _output = ref.read(speechOutputProvider);

  @override
  void initState() {
    super.initState();
    _input;
    _output;
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void dispose() {
    _pulse.dispose();
    unawaited(_input.stop());
    unawaited(_output.stop());
    super.dispose();
  }

  String get _locale => ref.read(settingsProvider).voiceLanguage;

  Future<void> _listen() async {
    final input = _input;
    final ok = await ref.read(appLockProvider).whileExternal(input.init);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Speech recognition is not available on this phone. Check the microphone permission in Settings.');
      return;
    }
    setState(() {
      _phase = _Phase.listening;
      _heard = '';
      _error = null;
    });
    await input.listen(
      locale: _locale,
      onResult: (words, isFinal) {
        if (!mounted) return;
        setState(() => _heard = words);
        if (isFinal) _sendHeard();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.idle;
          _error = e.contains('language') || e.contains('network')
              ? 'Offline speech for ${voiceLanguages[_locale] ?? _locale} is not installed on this phone. You can add it in your phone\'s speech settings.'
              : "Didn't catch that. Tap the mic to try again.";
        });
      },
    );
  }

  Future<void> _sendHeard() async {
    await _input.stop();
    final text = _heard.trim();
    if (text.isEmpty) {
      setState(() => _phase = _Phase.idle);
      return;
    }
    setState(() => _phase = _Phase.thinking);
    final session = ref.read(chatSessionProvider(widget.chatId));
    await session.send(text, voice: true);
    if (!mounted) return;
    final reply = session.messages.lastWhere((m) => m.role == ChatRole.assistant, orElse: () => ChatMessage.create(chatId: '', role: ChatRole.assistant, content: ''));
    if (ref.read(settingsProvider).readAloud && reply.content.isNotEmpty) {
      setState(() => _phase = _Phase.speaking);
      await _output.speak(reply.content, locale: _locale);
    }
    if (mounted && _phase != _Phase.idle) setState(() => _phase = _Phase.idle);
  }

  Future<void> _micTap() async {
    switch (_phase) {
      case _Phase.idle:
        await _listen();
      case _Phase.listening:
        await _sendHeard();
      case _Phase.speaking:
        await _output.stop();
        setState(() => _phase = _Phase.idle);
      case _Phase.thinking:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(chatSessionProvider(widget.chatId));
    final entry = session.entry;
    final lastUser = session.messages.lastWhere((m) => m.role == ChatRole.user, orElse: () => ChatMessage.create(chatId: '', role: ChatRole.user, content: ''));
    final lastReply = session.messages.isNotEmpty && session.messages.last.role == ChatRole.assistant ? session.messages.last : null;
    final crisisShown = session.messages.reversed.take(3).any((m) => m.kind == MessageKind.crisisCard);
    final shownUser = _phase == _Phase.listening ? _heard : lastUser.content;

    final phaseText = switch (_phase) {
      _Phase.idle => 'Tap the mic to talk',
      _Phase.listening => 'Listening… tap to send',
      _Phase.thinking => 'Thinking on-device…',
      _Phase.speaking => 'Speaking · tap to interrupt',
    };

    return Scaffold(
      backgroundColor: MedhaColors.inkDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(children: [
            Row(children: [
              if (entry != null) CircleAvatar(radius: 5, backgroundColor: Color(entry.color)),
              const SizedBox(width: 8),
              Expanded(child: Text(entry?.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${voiceLanguages[_locale] ?? _locale} · On-device', style: const TextStyle(fontSize: 12, color: MedhaColors.success)),
            ]),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (shownUser.isEmpty && lastReply == null)
                      Text('Talk to ${entry?.displayName ?? 'Medha'}.\nYour voice is turned into text on this phone. No audio leaves it.',
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5, color: MedhaColors.muted)),
                    if (shownUser.isNotEmpty)
                      Text(shownUser, textAlign: TextAlign.right, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, height: 1.35)),
                    if (crisisShown)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0x145FD0A5), borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          'You don\'t have to go through this alone. ${ref.read(servicesProvider).catalog.safety.crisisResources.map((r) => '${r.label}: ${r.number}').join(' · ')}',
                          style: const TextStyle(color: MedhaColors.textSoft, height: 1.5),
                        ),
                      ),
                    if (lastReply != null && lastReply.content.isNotEmpty && _phase != _Phase.listening)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(lastReply.content, style: const TextStyle(fontSize: 16, height: 1.55, color: MedhaColors.textSoft)),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF8A80))),
                      ),
                  ]),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 7; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3.5),
                      width: 7,
                      height: 8 +
                          (_phase == _Phase.idle ? 0 : (_phase == _Phase.thinking ? 10 : 50)) *
                              (0.4 + 0.6 * ((i.isEven ? _pulse.value : 1 - _pulse.value))) *
                              (1 - (i - 3).abs() / 5),
                      decoration: BoxDecoration(
                        color: _phase == _Phase.speaking ? MedhaColors.success : MedhaColors.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(phaseText, style: const TextStyle(color: MedhaColors.textSoft)),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(
                tooltip: 'Switch to typing',
                iconSize: 24,
                style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
                onPressed: () => context.pop(),
                icon: const Icon(Icons.keyboard_alt_outlined),
              ),
              const SizedBox(width: 32),
              IconButton.filled(
                tooltip: switch (_phase) {
                  _Phase.idle => 'Start talking',
                  _Phase.listening => 'Stop and send',
                  _Phase.thinking => 'Thinking',
                  _Phase.speaking => 'Interrupt',
                },
                iconSize: 36,
                style: IconButton.styleFrom(
                  minimumSize: const Size(84, 84),
                  backgroundColor: _phase == _Phase.listening ? MedhaColors.accent : MedhaColors.lineSoft,
                  foregroundColor: _phase == _Phase.listening ? MedhaColors.onAccent : MedhaColors.text,
                ),
                onPressed: _phase == _Phase.thinking ? null : _micTap,
                icon: const Icon(Icons.mic),
              ),
              const SizedBox(width: 32),
              IconButton.filled(
                tooltip: 'End voice chat',
                iconSize: 24,
                style: IconButton.styleFrom(minimumSize: const Size(56, 56), backgroundColor: MedhaColors.danger, foregroundColor: Colors.white),
                onPressed: () => context.pop(),
                icon: const Icon(Icons.close),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
