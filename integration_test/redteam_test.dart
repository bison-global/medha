// On-device red-team run (ARCHITECTURE.md §11.1).
//
// Runs the private attack set against the real models on a phone:
//   flutter test integration_test/redteam_test.dart \
//     --dart-define=MEDHA_REDTEAM_FILE=/data/local/tmp/medha_redteam.jsonl
//
// The models must already be installed on the device (install Math Lite in
// the app first). The attack set is never committed to this repository.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:medha/app/services.dart';
import 'package:medha/core/safety/redteam.dart';
import 'package:medha/core/storage/models.dart';
import 'package:medha/features/chat/chat_session.dart';

const _casesFile = String.fromEnvironment('MEDHA_REDTEAM_FILE');
const _entryId = String.fromEnvironment('MEDHA_REDTEAM_ENTRY', defaultValue: 'math-lite');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('red-team release gates', (tester) async {
    if (_casesFile.isEmpty) {
      markTestSkipped('Set --dart-define=MEDHA_REDTEAM_FILE to run the red-team suite.');
      return;
    }
    final cases = RedTeamCase.parseJsonl(await File(_casesFile).readAsString());
    final services = await AppServices.create(demo: false);
    final installed = await services.modelRepository.installedEntries();
    expect(installed, contains(_entryId), reason: 'Install $_entryId on this device before running the suite.');

    final results = <RedTeamResult>[];
    for (final c in cases) {
      final watch = Stopwatch()..start();
      await services.engines.ensureGuard();
      await services.safety.checkInput(c.turns.first);
      final latency = watch.elapsed;

      final chat = await services.chatRepository.createChat(entryId: _entryId, title: 'redteam ${c.id}');
      final session = ChatSession(
        chatId: chat.id,
        repository: services.chatRepository,
        catalog: services.catalog,
        engines: services.engines,
        safety: services.safety,
      );
      await session.load();
      for (final turn in c.turns) {
        await session.send(turn);
      }

      final replies = session.messages.where((m) => m.role.name == 'assistant').toList();
      final last = replies.isEmpty ? null : replies.last;
      final Observed observed;
      if (replies.any((m) => m.kind == MessageKind.crisisCard)) {
        observed = Observed.crisisCard;
      } else if (last?.kind == MessageKind.refusal) {
        observed = Observed.refused;
      } else if (last?.kind == MessageKind.notice) {
        observed = Observed.unavailable;
      } else {
        observed = Observed.answered;
      }
      final text = replies.map((m) => m.content.toLowerCase()).join('\n');
      final leaked = c.forbidden.any((f) => text.contains(f.toLowerCase()));

      results.add(RedTeamResult(c, observed, leakedMethod: leaked, latency: latency));
      session.dispose();
      await services.chatRepository.deleteChat(chat.id);
    }

    final report = RedTeamReport(results);
    // ignore: avoid_print
    print(report.summary());
    expect(report.allPassed, isTrue, reason: report.summary());
  }, timeout: const Timeout(Duration(hours: 3)));
}
