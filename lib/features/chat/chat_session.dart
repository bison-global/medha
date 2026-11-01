import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/catalog/catalog.dart';
import '../../core/documents/document_index.dart';
import '../../core/inference/context_builder.dart';
import '../../core/inference/engine_manager.dart';
import '../../core/inference/inference_engine.dart';
import '../../core/inference/thinking.dart';
import '../../core/safety/safety_service.dart';
import '../../core/storage/models.dart';
import '../../core/storage/repositories.dart';

/// One open chat: loads its history, runs the safety pipeline on each
/// message, streams the model's reply and saves everything.
class ChatSession extends ChangeNotifier {
  ChatSession({
    required this.chatId,
    required this.repository,
    required this.catalog,
    required this.engines,
    required this.safety,
    this.contextBuilder = const ContextBuilder(),
    this.outputCheckEvery = 300,
    this.index,
  });

  final String chatId;
  final ChatRepository repository;
  final Catalog catalog;
  final ChatEngines engines;
  final SafetyService safety;
  final ContextBuilder contextBuilder;

  /// Re-check the streaming reply with the guard model every N chunks.
  final int outputCheckEvery;

  /// Document search for project files and attachments (null in tests that
  /// don't need it).
  final DocumentIndex? index;

  ChatSummary? _chat;
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _busy = false;
  bool _stopRequested = false;
  bool _disposed = false;
  String? _loadError;
  String? _status;
  Map<String, DocumentRecord> _attachments = const {};

  ChatSummary? get chat => _chat;

  /// A short progress note while working, e.g. "Reading notes.pdf…".
  String? get status => _status;

  /// Files attached in this chat, by id.
  Map<String, DocumentRecord> get attachments => _attachments;
  List<ChatMessage> get messages => _messages;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get loadError => _loadError;

  InterestEntry? get entry {
    final c = _chat;
    if (c == null) return null;
    try {
      return catalog.interestEntry(c.entryId);
    } on StateError {
      return null;
    }
  }

  /// Suggested first questions, shown while the chat is empty.
  List<String> get suggestions => _messages.isEmpty ? (entry?.prompts ?? const []) : const [];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      _chat = await repository.getChat(chatId);
      if (_chat == null) {
        _loadError = 'This chat no longer exists.';
      } else {
        _messages = await repository.messages(chatId);
        await _loadAttachments();
        // A reply interrupted by the app closing is shown as stopped.
        for (final m in _messages.where((m) => m.status == MessageStatus.streaming).toList()) {
          await _put(m.copyWith(status: MessageStatus.cancelled));
        }
      }
    } on Object catch (e) {
      _loadError = 'Could not open this chat ($e).';
    }
    _loading = false;
    _notify();
  }

  Future<void> _loadAttachments() async {
    final idx = index;
    if (idx == null) return;
    _attachments = {for (final d in await idx.documents.forChat(chatId)) d.id: d};
  }

  Future<void> _put(ChatMessage m) async {
    final i = _messages.indexWhere((x) => x.id == m.id);
    _messages = i < 0 ? [..._messages, m] : ([..._messages]..[i] = m);
    _notify();
    await repository.saveMessage(m);
  }

  /// Updates the in-memory copy only (used for every streamed chunk).
  void _show(ChatMessage m) {
    final i = _messages.indexWhere((x) => x.id == m.id);
    if (i < 0) return;
    _messages = [..._messages]..[i] = m;
    _notify();
  }

  Future<void> stop() async {
    if (!_busy) return;
    _stopRequested = true;
    await engines.chat.cancel();
  }

  /// Sends a message, optionally with a file attached ([attachment]) or
  /// spoken in voice mode ([voice]).
  Future<void> send(String raw, {bool voice = false, PickedFile? attachment}) async {
    var text = raw.trim();
    final chat = _chat;
    final entry = this.entry;
    if ((text.isEmpty && attachment == null) || _busy || chat == null || entry == null) return;

    _busy = true;
    _stopRequested = false;
    _notify();
    try {
      String? attachmentText;
      String? documentId;
      if (attachment != null) {
        final idx = index;
        if (idx == null) return;
        _status = 'Reading ${attachment.name}…';
        _notify();
        try {
          final (record, extracted) = await idx.add(attachment, chatId: chatId);
          documentId = record.id;
          attachmentText = extracted;
          await _loadAttachments();
        } on UploadRejected catch (e) {
          await _assistantNote(e.message, MessageKind.notice);
          return;
        } on Object {
          await _assistantNote("Medha couldn't read ${attachment.name}. Try a different file.", MessageKind.notice);
          return;
        } finally {
          _status = null;
        }
        if (text.isEmpty) text = 'Please look at the attached file.';
      }

      final userMessage = ChatMessage.create(chatId: chatId, role: ChatRole.user, content: text, voice: voice, documentId: documentId);
      await _put(userMessage);
      if (chat.title == 'New chat') {
        final title = text.length <= 40 ? text : '${text.substring(0, 39)}…';
        await repository.renameChat(chatId, title);
        _chat = chat.copyWith(title: title);
      }

      InputDecision decision;
      try {
        await engines.ensureGuard();
        decision = await safety.checkInput(text, attachmentText: attachmentText);
      } on Object {
        decision = UnavailableInput(catalog.safety.refusalFor('unavailable'));
      }

      // Refused messages stay visible but are kept out of the model's history.
      Future<void> withhold() => _put(userMessage.copyWith(kind: MessageKind.withheld));

      switch (decision) {
        case BlockInput(:final message):
          await withhold();
          await _assistantNote(message, MessageKind.refusal);
        case CooldownInput(:final message):
          await withhold();
          await _assistantNote(message, MessageKind.notice);
        case UnavailableInput(:final message):
          await withhold();
          await _assistantNote(message, MessageKind.notice);
        case CrisisInput():
          await _assistantNote('', MessageKind.crisisCard);
          await _reply(entry, text, crisis: true);
        case AllowInput():
          await _reply(entry, text, crisis: false);
      }
    } finally {
      _busy = false;
      _stopRequested = false;
      _notify();
    }
  }

  Future<void> _assistantNote(String text, MessageKind kind) =>
      _put(ChatMessage.create(chatId: chatId, role: ChatRole.assistant, content: text, kind: kind));

  List<ChatTurn> _history() => [
        for (final m in _messages)
          if (m.isConversational) ChatTurn(m.role, m.content),
      ];

  Future<(String, List<String>)> _reference(InterestEntry entry, String query, {required bool crisis}) async {
    final idx = index;
    final chat = _chat;
    if (idx == null || chat == null) return ('', const <String>[]);
    if (chat.projectId == null && _attachments.isEmpty) return ('', const <String>[]);
    try {
      final hits = await idx.search(query, projectId: chat.projectId, chatId: _attachments.isEmpty ? null : chatId);
      if (hits.isEmpty) return ('', const <String>[]);
      final budget = contextBuilder.referenceBudgetChars(catalog.safety, entry, crisis: crisis);
      final names = {for (final h in hits) h.documentName}.toList();
      return (formatReference(hits, maxChars: budget), names);
    } on Object {
      return ('', const <String>[]);
    }
  }

  Future<void> _reply(InterestEntry entry, String userText, {required bool crisis}) async {
    var reply = ChatMessage.create(chatId: chatId, role: ChatRole.assistant, content: '', status: MessageStatus.streaming);
    await _put(reply);
    final (reference, sources) = await _reference(entry, userText, crisis: crisis);
    final history = _history()..removeWhere((t) => t.role == ChatRole.assistant && t.content.isEmpty);
    final turns = contextBuilder.build(safety: catalog.safety, entry: entry, history: history, crisis: crisis, reference: reference);

    final splitter = ThinkingSplitter();
    BlockOutput? blocked;
    var failed = false;

    try {
      await engines.ensureChat(entry);
      final thinkingCap = entry.thinking.enabled ? entry.thinking.maxTokens : 0;
      final params = GenerationParams(sampling: entry.sampling, maxTokens: entry.maxNewTokens + thinkingCap);

      var chunks = 0;
      var reasoningChunks = 0;
      var lastChecked = 0;
      var hitThinkingCap = false;

      Future<bool> consume(Stream<String> stream) async {
        await for (final chunk in stream) {
          splitter.add(chunk);
          chunks++;
          if (splitter.inReasoning) reasoningChunks++;
          reply = reply.copyWith(content: splitter.answer, reasoning: splitter.reasoning);
          _show(reply);

          if (_stopRequested) return false;
          if (thinkingCap > 0 && splitter.inReasoning && reasoningChunks >= thinkingCap) {
            hitThinkingCap = true;
            return false;
          }
          if (chunks - lastChecked >= outputCheckEvery && splitter.answer.isNotEmpty) {
            lastChecked = chunks;
            final d = await safety.checkOutput(userText, splitter.answer);
            if (d is BlockOutput) {
              blocked = d;
              return false;
            }
          }
        }
        return true;
      }

      await consume(engines.chat.generate(turns, params));

      // Reasoning ran past its budget: close the block and ask for the answer.
      if (hitThinkingCap && blocked == null && !_stopRequested) {
        final prefix = '<think>\n${splitter.reasoning}\n</think>\n\n';
        splitter.add('\n</think>\n\n');
        await consume(engines.chat.generate(
          turns,
          GenerationParams(sampling: entry.sampling, maxTokens: entry.maxNewTokens),
          assistantPrefix: prefix,
        ));
      }

      if (blocked == null && splitter.answer.trim().isNotEmpty) {
        final d = await safety.checkOutput(userText, splitter.answer);
        if (d is BlockOutput) blocked = d;
      }
    } on Object {
      failed = true;
    }

    final b = blocked;
    if (b != null) {
      reply = reply.copyWith(content: b.message, reasoning: '', kind: MessageKind.refusal, status: MessageStatus.done);
    } else if (failed) {
      reply = reply.copyWith(
        content: splitter.answer.isEmpty ? 'Something went wrong running the model on this phone. Please try again.' : splitter.answer,
        status: MessageStatus.error,
      );
    } else if (_stopRequested) {
      reply = reply.copyWith(content: splitter.answer, status: MessageStatus.cancelled);
    } else if (splitter.answer.trim().isEmpty) {
      reply = reply.copyWith(content: "I couldn't come up with an answer. Please try rephrasing.", status: MessageStatus.error);
    } else {
      reply = reply.copyWith(content: splitter.answer.trim(), status: MessageStatus.done, sources: sources);
    }
    await _put(reply);
  }

  @override
  void dispose() {
    _disposed = true;
    if (_busy) unawaited(engines.chat.cancel());
    super.dispose();
  }
}
