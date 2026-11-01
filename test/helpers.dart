import 'dart:convert';
import 'dart:io';

import 'package:medha/core/catalog/catalog.dart';
import 'package:medha/core/inference/engine_manager.dart';
import 'package:medha/core/inference/fake_engine.dart';
import 'package:medha/core/inference/inference_engine.dart';
import 'package:medha/core/safety/guard_classifier.dart';

/// The development catalog shipped in assets/.
Map<String, dynamic> devCatalogJson() =>
    jsonDecode(File('assets/catalog/catalog.dev.json').readAsStringSync()) as Map<String, dynamic>;

Catalog devCatalog() => Catalog.fromJson(devCatalogJson());

/// A guard that answers from a lookup; anything unknown is Safe.
class FakeGuard implements GuardClassifier {
  FakeGuard({this.prompt = const {}, this.response = const {}, this.fail = false});

  final Map<String, GuardResult> prompt;
  final Map<String, GuardResult> response;
  bool fail;
  final List<String> promptCalls = [];
  final List<String> responseCalls = [];

  @override
  Future<GuardResult> checkPrompt(String userText) async {
    promptCalls.add(userText);
    if (fail) throw GuardUnavailableException('test');
    return prompt[userText] ?? const GuardResult(GuardVerdict.safe);
  }

  @override
  Future<GuardResult> checkResponse(String userText, String assistantText) async {
    responseCalls.add(assistantText);
    if (fail) throw GuardUnavailableException('test');
    for (final e in response.entries) {
      if (assistantText.contains(e.key)) return e.value;
    }
    return const GuardResult(GuardVerdict.safe);
  }
}

class FakeEngines implements ChatEngines {
  FakeEngines({FakeInferenceEngine? chat, FakeInferenceEngine? guard})
      : chat = chat ?? FakeInferenceEngine(delay: Duration.zero),
        guard = guard ?? FakeInferenceEngine(delay: Duration.zero);

  @override
  final FakeInferenceEngine chat;
  @override
  final FakeInferenceEngine guard;
  int chatLoads = 0;

  @override
  Future<void> ensureChat(InterestEntry entry) async {
    chatLoads++;
    await chat.load(ModelHandle(id: entry.baseModelId, path: '', contextTokens: entry.contextTokens, promptTemplate: 'chatml'));
  }

  @override
  Future<void> ensureGuard() => guard.load(const ModelHandle(id: 'guard', path: '', contextTokens: 2048, promptTemplate: 'chatml'));
}
