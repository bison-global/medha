import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medha/core/reports/report_service.dart';
import 'package:medha/core/settings/prefs.dart';
import 'package:medha/core/storage/database.dart';
import 'package:medha/core/storage/repositories.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.inMemory());
  tearDown(() => db.close());

  group('ReportService', () {
    test('sends a queued report and then forgets its text', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('', 204);
      });
      final repo = ReportRepository(db);
      final service = ReportService(repository: repo, endpoint: Uri.parse('https://reports.test/v1'), client: client);
      await service.submit(reason: 'wrong', note: ' bad maths ', includeText: true, question: 'q?', reply: 'r.', entryId: 'math-lite');
      expect(bodies.single['reason'], 'wrong');
      expect(bodies.single['note'], 'bad maths');
      expect(bodies.single['question'], 'q?');
      expect(bodies.single.containsKey('device'), isFalse);
      expect(await repo.pending(), isEmpty);
    });

    test('leaves out the conversation when the user unticks it', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('', 200);
      });
      final service = ReportService(repository: ReportRepository(db), endpoint: Uri.parse('https://r.test'), client: client);
      await service.submit(reason: 'harmful', note: '', includeText: false, question: 'secret', reply: 'secret');
      expect(bodies.single.containsKey('question'), isFalse);
      expect(bodies.single.containsKey('reply'), isFalse);
    });

    test('keeps reports queued while offline', () async {
      final client = MockClient((_) async => throw http.ClientException('offline'));
      final repo = ReportRepository(db);
      final service = ReportService(repository: repo, endpoint: Uri.parse('https://r.test'), client: client);
      await service.submit(reason: 'other', note: 'x', includeText: false);
      expect(await repo.pending(), hasLength(1));
    });

    test('with no endpoint configured nothing is sent', () async {
      final repo = ReportRepository(db);
      await ReportService(repository: repo).submit(reason: 'other', note: '', includeText: false);
      expect(await repo.pending(), hasLength(1));
    });
  });

  group('settings', () {
    test('persist in the database', () {
      final s = SettingsRepository(db);
      final settings = AppSettings(s);
      expect(settings.saveHistory, isTrue);
      settings.saveHistory = false;
      settings.voiceLanguage = 'hi-IN';
      final again = AppSettings(SettingsRepository(db));
      expect(again.saveHistory, isFalse);
      expect(again.voiceLanguage, 'hi-IN');
    });

    test('MemoryPrefs round-trips', () {
      final p = MemoryPrefs()
        ..setBool('a', true)
        ..setInt('b', 3)
        ..setString('c', 'x');
      expect(p.getBool('a', fallback: false), isTrue);
      expect(p.getInt('b', fallback: 0), 3);
      expect(p.getString('c'), 'x');
    });
  });

  group('chats in projects', () {
    test('lists chats per project and purges ephemeral chats', () async {
      final projects = ProjectRepository(db);
      final chats = SqliteChatRepository(db);
      final p = await projects.create('Farm', 1);
      await chats.createChat(entryId: 'farming-lite', projectId: p.id);
      await chats.createChat(entryId: 'math-lite');
      await chats.createChat(entryId: 'math-lite', ephemeral: true);
      expect(await chats.listChats(projectId: p.id), hasLength(1));
      await chats.purgeEphemeral();
      expect((await chats.listChats()).where((c) => c.ephemeral), isEmpty);
    });
  });
}
