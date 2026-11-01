import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'theme.dart';

class MedhaApp extends StatefulWidget {
  const MedhaApp({super.key, required this.initialLocation});
  final String initialLocation;

  @override
  State<MedhaApp> createState() => _MedhaAppState();
}

class _MedhaAppState extends State<MedhaApp> {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Medha',
        debugShowCheckedModeBanner: false,
        theme: buildMedhaTheme(),
        darkTheme: buildMedhaTheme(),
        themeMode: ThemeMode.dark,
        routerConfig: _router,
      );
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
