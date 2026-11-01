import 'package:go_router/go_router.dart';

import '../core/security/app_lock.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/lock/lock_screen.dart';
import '../features/lock/secure_screen.dart';
import '../features/models/models_screen.dart';
import '../features/onboarding/install_screen.dart';
import '../features/onboarding/subjects_screen.dart';
import '../features/onboarding/tier_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/projects/project_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/settings/licences_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/voice/voice_screen.dart';

/// Routes. While the app is locked every route redirects to /lock, so no
/// screen renders before unlock (ARCHITECTURE.md §9.1).
GoRouter buildRouter({required String initialLocation, required AppLock lock}) => GoRouter(
      initialLocation: initialLocation,
      refreshListenable: lock,
      redirect: (context, state) {
        final atLock = state.matchedLocation == '/lock';
        if (lock.locked && !atLock) return '/lock?from=${Uri.encodeComponent(state.uri.toString())}';
        if (!lock.locked && atLock) return state.uri.queryParameters['from'] ?? '/chats';
        return null;
      },
      routes: [
        GoRoute(path: '/lock', builder: (_, __) => const LockScreen()),
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
        GoRoute(path: '/secure', builder: (_, s) => SecureScreen(next: s.uri.queryParameters['next'])),
        GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(chatId: s.pathParameters['id']!)),
        GoRoute(path: '/voice/:id', builder: (_, s) => VoiceScreen(chatId: s.pathParameters['id']!)),
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => HomeShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/projects',
                builder: (_, __) => const ProjectsScreen(),
                routes: [GoRoute(path: ':id', builder: (_, s) => ProjectScreen(projectId: s.pathParameters['id']!))],
              ),
            ]),
            StatefulShellBranch(routes: [GoRoute(path: '/models', builder: (_, __) => const ModelsScreen())]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
                routes: [GoRoute(path: 'licences', builder: (_, __) => const LicencesScreen())],
              ),
            ]),
          ],
        ),
      ],
    );
