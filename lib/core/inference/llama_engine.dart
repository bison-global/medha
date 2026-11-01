import 'dart:convert';
import 'dart:isolate';

import 'package:medha_llama/medha_llama.dart';

import 'inference_engine.dart';
import 'prompt_format.dart';

class InferenceException implements Exception {
  InferenceException(this.message);
  final String message;
  @override
  String toString() => 'InferenceException: $message';
}

/// Runs a llama.cpp model in its own long-lived isolate so token generation
/// never blocks the UI. One instance holds at most one loaded model.
class LlamaEngine implements InferenceEngine {
  LlamaEngine({this.debugName = 'medha-llama'});

  final String debugName;
  Isolate? _isolate;
  SendPort? _commands;
  String? _loadedId;
  String? _adapter;
  String _template = 'native';
  int _nextGenerationId = 0;
  int? _activeGeneration;

  @override
  String? get loadedModelId => _loadedId;

  Future<SendPort> _ensureIsolate() async {
    final existing = _commands;
    if (existing != null) return existing;
    final ready = ReceivePort();
    _isolate = await Isolate.spawn(_llamaWorkerMain, ready.sendPort, debugName: debugName);
    final port = await ready.first as SendPort;
    ready.close();
    _commands = port;
    return port;
  }

  Future<Map<Object?, Object?>> _call(Map<String, Object?> msg) async {
    final commands = await _ensureIsolate();
    final reply = ReceivePort();
    commands.send({...msg, 'reply': reply.sendPort});
    final res = await reply.first as Map<Object?, Object?>;
    reply.close();
    final error = res['error'];
    if (error != null) throw InferenceException(error as String);
    return res;
  }

  @override
  Future<void> load(ModelHandle model) async {
    if (_loadedId == model.id) {
      if (_adapter != model.adapterPath) {
        await _call({'op': 'lora', 'path': model.adapterPath, 'scale': model.adapterScale});
        _adapter = model.adapterPath;
      }
      return;
    }
    if (_loadedId != null) await unload();
    await _call({
      'op': 'load',
      'path': model.path,
      'contextTokens': model.contextTokens,
      'threads': model.threads,
      'gpuLayers': model.gpuLayers,
    });
    _loadedId = model.id;
    _template = model.promptTemplate;
    _adapter = null;
    if (model.adapterPath != null) {
      await _call({'op': 'lora', 'path': model.adapterPath, 'scale': model.adapterScale});
      _adapter = model.adapterPath;
    }
  }

  @override
  Stream<String> generate(List<ChatTurn> turns, GenerationParams params, {String assistantPrefix = ''}) async* {
    String? prompt;
    if (_template == 'native') {
      final res = await _call({
        'op': 'format',
        'roles': [for (final t in turns) t.role.wire],
        'contents': [for (final t in turns) t.content],
      });
      prompt = res['prompt'] as String?;
    }
    prompt ??= formatPrompt(_template == 'native' ? 'chatml' : _template, turns);
    yield* generateRaw(prompt + assistantPrefix, params);
  }

  @override
  Stream<String> generateRaw(String prompt, GenerationParams params) async* {
    if (_loadedId == null) throw InferenceException('No model loaded');
    final commands = await _ensureIsolate();
    final id = ++_nextGenerationId;
    _activeGeneration = id;
    final port = ReceivePort();
    var finished = false;
    final s = params.sampling;
    commands.send({
      'op': 'generate',
      'id': id,
      'prompt': prompt,
      'temperature': s.temperature,
      'topP': s.topP,
      'topK': s.topK,
      'minP': s.minP,
      'presencePenalty': s.presencePenalty,
      'seed': params.seed,
      'maxTokens': params.maxTokens,
      'reply': port.sendPort,
    });
    try {
      await for (final raw in port) {
        final msg = raw as Map<Object?, Object?>;
        switch (msg['t']) {
          case 'tok':
            yield msg['s'] as String;
          case 'done':
            finished = true;
            port.close();
          case 'err':
            finished = true;
            port.close();
            throw InferenceException(msg['m'] as String);
        }
      }
    } finally {
      // The listener stopped early (user pressed Stop or left the screen).
      if (!finished) commands.send({'op': 'cancel', 'id': id});
      port.close();
      if (_activeGeneration == id) _activeGeneration = null;
    }
  }

  @override
  Future<void> cancel() async {
    final id = _activeGeneration;
    if (id != null) _commands?.send({'op': 'cancel', 'id': id});
  }

  @override
  Future<void> unload() async {
    if (_loadedId == null) return;
    await _call({'op': 'unload'});
    _loadedId = null;
    _adapter = null;
  }

  Future<void> dispose() async {
    await unload();
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _commands = null;
  }
}

class _PortSink implements Sink<String> {
  _PortSink(this._port);
  final SendPort _port;

  @override
  void add(String data) {
    if (data.isNotEmpty) _port.send({'t': 'tok', 's': data});
  }

  @override
  void close() {}
}

/// Worker isolate: owns the native model. Commands other than `cancel` run
/// one at a time; generation yields between tokens so `cancel` is seen.
void _llamaWorkerMain(SendPort ready) {
  final commands = ReceivePort();
  ready.send(commands.sendPort);

  MedhaLlama? model;
  final cancelled = <int>{};
  var queue = Future<void>.value();

  Future<void> handle(Map<Object?, Object?> msg) async {
    final reply = msg['reply'] as SendPort;
    switch (msg['op']) {
      case 'load':
        try {
          model?.close();
          model = MedhaLlama.load(
            msg['path'] as String,
            contextTokens: msg['contextTokens'] as int,
            threads: msg['threads'] as int,
            gpuLayers: msg['gpuLayers'] as int,
          );
          reply.send(<String, Object?>{'ok': true});
        } on Object catch (e) {
          model = null;
          reply.send(<String, Object?>{'error': '$e'});
        }

      case 'format':
        final m = model;
        if (m == null) {
          reply.send(<String, Object?>{'error': 'No model loaded'});
          return;
        }
        final roles = (msg['roles'] as List).cast<String>();
        final contents = (msg['contents'] as List).cast<String>();
        reply.send(<String, Object?>{
          'prompt': m.formatChat([for (var i = 0; i < roles.length; i++) (roles[i], contents[i])]),
        });

      case 'generate':
        final id = msg['id'] as int;
        final m = model;
        if (m == null) {
          reply.send(<String, Object?>{'t': 'err', 'm': 'No model loaded'});
          return;
        }
        try {
          m.begin(
            msg['prompt'] as String,
            temperature: msg['temperature'] as double,
            topP: msg['topP'] as double,
            topK: msg['topK'] as int,
            minP: msg['minP'] as double,
            presencePenalty: msg['presencePenalty'] as double,
            seed: msg['seed'] as int,
          );
          final decoder = const Utf8Decoder(allowMalformed: true).startChunkedConversion(_PortSink(reply));
          final maxTokens = msg['maxTokens'] as int;
          var n = 0;
          while (n < maxTokens && !cancelled.contains(id)) {
            final bytes = m.next();
            if (bytes == null) break;
            decoder.add(bytes);
            n++;
            // Let the isolate see a pending cancel before the next token.
            await Future<void>.delayed(Duration.zero);
          }
          decoder.close();
          reply.send(<String, Object?>{'t': 'done', 'tokens': n, 'promptTokens': m.promptTokens});
        } on Object catch (e) {
          reply.send(<String, Object?>{'t': 'err', 'm': '$e'});
        } finally {
          cancelled.remove(id);
        }

      case 'lora':
        final m = model;
        if (m == null) {
          reply.send(<String, Object?>{'error': 'No model loaded'});
          return;
        }
        try {
          m.setLora(msg['path'] as String?, scale: msg['scale'] as double);
          reply.send(<String, Object?>{'ok': true});
        } on Object catch (e) {
          reply.send(<String, Object?>{'error': '$e'});
        }

      case 'unload':
        model?.close();
        model = null;
        reply.send(<String, Object?>{'ok': true});
    }
  }

  commands.listen((raw) {
    final msg = raw as Map<Object?, Object?>;
    if (msg['op'] == 'cancel') {
      cancelled.add(msg['id'] as int);
      return;
    }
    queue = queue.then((_) => handle(msg));
  });
}

/// Runs an embedding model in its own isolate.
class LlamaEmbeddingEngine implements EmbeddingEngine {
  Isolate? _isolate;
  SendPort? _commands;
  String? _path;

  @override
  bool get isLoaded => _path != null;

  Future<Map<Object?, Object?>> _call(Map<String, Object?> msg) async {
    var commands = _commands;
    if (commands == null) {
      final ready = ReceivePort();
      _isolate = await Isolate.spawn(_embedWorkerMain, ready.sendPort, debugName: 'medha-embed');
      commands = await ready.first as SendPort;
      ready.close();
      _commands = commands;
    }
    final reply = ReceivePort();
    commands.send({...msg, 'reply': reply.sendPort});
    final res = await reply.first as Map<Object?, Object?>;
    reply.close();
    final error = res['error'];
    if (error != null) throw InferenceException(error as String);
    return res;
  }

  @override
  Future<void> load(String path) async {
    if (_path == path) return;
    await _call({'op': 'load', 'path': path});
    _path = path;
  }

  @override
  Future<List<double>> embed(String text) async {
    if (_path == null) throw InferenceException('No embedding model loaded');
    final res = await _call({'op': 'embed', 'text': text});
    return (res['v'] as List).cast<double>();
  }

  @override
  Future<void> unload() async {
    if (_path == null) return;
    await _call({'op': 'unload'});
    _path = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _commands = null;
  }
}

void _embedWorkerMain(SendPort ready) {
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  MedhaLlama? model;
  commands.listen((raw) {
    final msg = raw as Map<Object?, Object?>;
    final reply = msg['reply'] as SendPort;
    try {
      switch (msg['op']) {
        case 'load':
          model?.close();
          model = MedhaLlama.loadEmbedder(msg['path'] as String, contextTokens: 1024, threads: 2);
          reply.send(<String, Object?>{'ok': true});
        case 'embed':
          final m = model;
          if (m == null) throw StateError('No embedding model loaded');
          reply.send(<String, Object?>{'v': m.embed(msg['text'] as String)});
        case 'unload':
          model?.close();
          model = null;
          reply.send(<String, Object?>{'ok': true});
      }
    } on Object catch (e) {
      reply.send(<String, Object?>{'error': '$e'});
    }
  });
}
