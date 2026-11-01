import 'package:go_router/go_router.dart';

import '../features/chat/chat_list_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/onboarding/install_screen.dart';
import '../features/onboarding/subjects_screen.dart';
import '../features/onboarding/tier_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/settings/licences_screen.dart';
import '../features/settings/settings_screen.dart';

GoRouter buildRouter({required String initialLocation}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
        GoRoute(
          path: '/subjects',
          builder: (_, __) => const SubjectsScreen(),
          routes: [
            GoRoute(path: ':interest', builder: (_, s) => TierScreen(interest: s.pathParameters['interest']!)),
          ],
        ),
        GoRoute(
          path: '/install/:entryId',
          builder: (_, s) => InstallScreen(
            entryId: s.pathParameters['entryId']!,
            wifiOnly: s.uri.queryParameters['wifi'] != '0',
          ),
        ),
        GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
        GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(chatId: s.pathParameters['id']!)),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
          routes: [GoRoute(path: 'licences', builder: (_, __) => const LicencesScreen())],
        ),
      ],
    );
