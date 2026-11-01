import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/app_lock.dart';
import '../core/settings/prefs.dart';
import '../core/storage/models.dart';
import '../features/chat/chat_list_controller.dart';
import '../features/chat/chat_session.dart';
import 'services.dart';

/// Overridden in main() with the services created at startup.
final servicesProvider = Provider<AppServices>((ref) => throw UnimplementedError('servicesProvider must be overridden'));

final appLockProvider = ChangeNotifierProvider<AppLock>((ref) => ref.watch(servicesProvider).appLock);

final settingsProvider = ChangeNotifierProvider<AppSettings>((ref) => ref.watch(servicesProvider).settings);

final installedEntriesProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(servicesProvider).modelRepository.installedEntries(),
);

final chatListProvider = ChangeNotifierProvider.autoDispose<ChatListController>((ref) {
  final controller = ChatListController(ref.watch(servicesProvider).chatRepository);
  controller.refresh();
  return controller;
});

final chatSessionProvider = ChangeNotifierProvider.autoDispose.family<ChatSession, String>((ref, chatId) {
  final s = ref.watch(servicesProvider);
  final session = ChatSession(
    chatId: chatId,
    repository: s.chatRepository,
    catalog: s.catalog,
    engines: s.engines,
    safety: s.safety,
    index: s.documentIndex,
  );
  session.load();
  return session;
});

final projectsProvider = FutureProvider.autoDispose<List<Project>>((ref) => ref.watch(servicesProvider).projects.list());

final projectProvider = FutureProvider.autoDispose.family<Project?, String>(
  (ref, id) => ref.watch(servicesProvider).projects.get(id),
);

final projectFilesProvider = FutureProvider.autoDispose.family<List<DocumentRecord>, String>(
  (ref, id) => ref.watch(servicesProvider).documents.forProject(id),
);

final projectChatsProvider = FutureProvider.autoDispose.family<List<ChatSummary>, String>(
  (ref, id) => ref.watch(servicesProvider).chatRepository.listChats(projectId: id),
);
