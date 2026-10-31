import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final services = await AppServices.create(demo: BuildFlags.demo);
    final installed = await services.modelRepository.installedEntries();
    runApp(ProviderScope(
      overrides: [servicesProvider.overrideWithValue(services)],
      child: MedhaApp(initialLocation: installed.isEmpty ? '/welcome' : '/chats'),
    ));
  } on Object catch (e) {
    runApp(StartupErrorApp(error: e));
  }
}
