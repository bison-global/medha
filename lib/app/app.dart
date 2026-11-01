import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/common/widgets.dart';
import '../features/lock/lock_screen.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class MedhaApp extends ConsumerStatefulWidget {
  const MedhaApp({super.key, required this.initialLocation});
  final String initialLocation;

  @override
  ConsumerState<MedhaApp> createState() => _MedhaAppState();
}

class _MedhaAppState extends ConsumerState<MedhaApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);
  final _lockNavigator = GlobalKey<NavigatorState>();
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(servicesProvider).reports.flush());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider);
    final services = ref.read(servicesProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        lock.onForeground();
        unawaited(services.reports.flush());
        setState(() => _covered = false);
      case AppLifecycleState.inactive:
        // Hide chats from the app switcher snapshot.
        if (lock.enabled) setState(() => _covered = true);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        lock.onBackground();
        if (lock.enabled) setState(() => _covered = true);
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider.select((l) => l.locked));
    return MaterialApp.router(
        title: 'Medha',
        debugShowCheckedModeBanner: false,
        theme: buildMedhaTheme(),
        darkTheme: buildMedhaTheme(),
        themeMode: ThemeMode.dark,
        routerConfig: _router,
        builder: (context, child) => Stack(children: [
          // While locked the app stays alive but is not painted, can't be
          // touched and is hidden from screen readers.
          if (child != null) Offstage(offstage: locked, child: child),
          if (locked)
            Positioned.fill(
              child: Navigator(
                key: _lockNavigator,
                onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const LockScreen()),
              ),
            ),
          if (_covered)
            const Positioned.fill(
              child: ColoredBox(color: MedhaColors.ink, child: Center(child: MedhaLogo(size: 72))),
            ),
        ]),
      );
  }
}

/// Shown when the app cannot start (e.g. untrusted catalog, storage error).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildMedhaTheme(),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 48),
                  const Text("Medha couldn't start", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  const Text(
                    'Your chats are safe on this phone. Please update the app or try again later.',
                    style: TextStyle(color: MedhaColors.muted, fontSize: 15, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SelectableText('$error', style: const TextStyle(color: MedhaColors.faint, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
}
