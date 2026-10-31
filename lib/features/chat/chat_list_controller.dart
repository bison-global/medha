import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/storage/models.dart';
import '../../core/storage/repositories.dart';

/// Chat history with delayed delete: a deleted chat disappears at once but is
/// only removed from storage after [undoWindow], so Undo can bring it back.
class ChatListController extends ChangeNotifier {
  ChatListController(this.repository, {this.undoWindow = const Duration(seconds: 4)});

  final ChatRepository repository;
  final Duration undoWindow;

  List<ChatSummary> _all = const [];
  final Map<String, Timer> _pending = {};
  bool _loading = true;
  bool _disposed = false;

  bool get loading => _loading;
  List<ChatSummary> get chats => _all.where((c) => !_pending.containsKey(c.id)).toList();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    _all = await repository.listChats();
    _loading = false;
    _notify();
  }

  void delete(String id) {
    _pending[id]?.cancel();
    _pending[id] = Timer(undoWindow, () => unawaited(_commit(id)));
    _notify();
  }

  void undo(String id) {
    _pending.remove(id)?.cancel();
    _notify();
  }

  Future<void> _commit(String id) async {
    _pending.remove(id)?.cancel();
    await repository.deleteChat(id);
    _all = _all.where((c) => c.id != id).toList();
    _notify();
  }

  /// Commits every pending delete now (e.g. when leaving the screen).
  Future<void> flush() async {
    for (final id in _pending.keys.toList()) {
      await _commit(id);
    }
  }

  Future<void> deleteAll() async {
    for (final t in _pending.values) {
      t.cancel();
    }
    _pending.clear();
    await repository.deleteAllChats();
    _all = const [];
    _notify();
  }

  @override
  void dispose() {
    unawaited(flush());
    _disposed = true;
    super.dispose();
  }
}
