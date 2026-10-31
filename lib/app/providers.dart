import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/chat/chat_list_controller.dart';
import '../features/chat/chat_session.dart';
import 'services.dart';

/// Overridden in main() with the services created at startup.
final servicesProvider = Provider<AppServices>((ref) => throw UnimplementedError('servicesProvider must be overridden'));

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
  );
  session.load();
  return session;
});
