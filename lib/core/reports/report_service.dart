import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/models.dart';
import '../storage/repositories.dart';

/// "Report this reply" (ARCHITECTURE.md §9.5). Reports are the only data Medha
/// ever sends. They are queued encrypted on the phone and posted only after
/// the user taps Send, once the phone is online. No account or device id.
class ReportService {
  ReportService({required this.repository, this.endpoint, http.Client? client}) : _client = client ?? http.Client();

  final ReportRepository repository;

  /// Where reports go; null keeps them queued on the phone.
  final Uri? endpoint;
  final http.Client _client;

  static const reasons = <String, String>{
    'harmful': 'Harmful or unsafe',
    'wrong': 'Wrong or misleading',
    'offensive': 'Offensive or biased',
    'other': 'Something else',
  };

  Future<void> submit({
    required String reason,
    required String note,
    required bool includeText,
    String? question,
    String? reply,
    String? entryId,
  }) async {
    await repository.add(ReportRecord(
      id: newId(),
      createdAt: DateTime.now(),
      reason: reason,
      note: note.trim(),
      question: includeText ? question : null,
      reply: includeText ? reply : null,
      entryId: entryId,
    ));
    await flush();
  }

  /// Sends queued reports; failures stay queued for next time.
  Future<int> flush() async {
    final url = endpoint;
    if (url == null) return 0;
    var sent = 0;
    for (final r in await repository.pending()) {
      try {
        final res = await _client
            .post(url, headers: {'content-type': 'application/json'}, body: jsonEncode(r.toJson()))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          await repository.markSent(r.id);
          sent++;
        }
      } on Object {
        break; // offline: try again later
      }
    }
    return sent;
  }
}
