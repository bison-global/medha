/// Dart FFI bindings for Medha's llama.cpp shim (`src/medha_llama.h`).
///
/// These calls block. Call them only from a background isolate; the app's
/// `LlamaEngine` owns one isolate per loaded model.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _LoadNative = Pointer<Void> Function(Pointer<Utf8>, Int32, Int32, Int32);
typedef _LoadDart = Pointer<Void> Function(Pointer<Utf8>, int, int, int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);
typedef _FormatNative = Int32 Function(
    Pointer<Void>, Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>, Int32, Int32, Pointer<Utf8>, Int32);
typedef _FormatDart = int Function(
    Pointer<Void>, Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>, int, int, Pointer<Utf8>, int);
typedef _BeginNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Float, Float, Int32, Float, Float, Uint32);
typedef _BeginDart = int Function(Pointer<Void>, Pointer<Utf8>, double, double, int, double, double, int);
typedef _NextNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32);
typedef _NextDart = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _IntOfCtxNative = Int32 Function(Pointer<Void>);
typedef _IntOfCtxDart = int Function(Pointer<Void>);
typedef _ErrorNative = Pointer<Utf8> Function();

DynamicLibrary _open() {
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
  if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('libmedha_llama.so');
  if (Platform.isWindows) return DynamicLibrary.open('medha_llama.dll');
  throw UnsupportedError('medha_llama is not available on ${Platform.operatingSystem}');
}

/// Thrown when the native library reports an error.
class MedhaLlamaException implements Exception {
  MedhaLlamaException(this.message, [this.code]);
  final String message;
  final int? code;
  @override
  String toString() => code == null ? 'MedhaLlamaException: $message' : 'MedhaLlamaException($code): $message';
}

/// A loaded model plus its inference context.
class MedhaLlama {
  MedhaLlama._(this._ctx);

  static final DynamicLibrary _lib = _open();
  static final _load = _lib.lookupFunction<_LoadNative, _LoadDart>('medha_load');
  static final _free = _lib.lookupFunction<_FreeNative, _FreeDart>('medha_free');
  static final _format = _lib.lookupFunction<_FormatNative, _FormatDart>('medha_format_chat');
  static final _begin = _lib.lookupFunction<_BeginNative, _BeginDart>('medha_begin');
  static final _next = _lib.lookupFunction<_NextNative, _NextDart>('medha_next');
  static final _promptTokens = _lib.lookupFunction<_IntOfCtxNative, _IntOfCtxDart>('medha_prompt_tokens');
  static final _lastError = _lib.lookupFunction<_ErrorNative, _ErrorNative>('medha_last_error');

  static const int _pieceBufferSize = 256;

  Pointer<Void> _ctx;
  final Pointer<Uint8> _piece = calloc<Uint8>(_pieceBufferSize);

  static String lastError() => _lastError().toDartString();

  /// Loads a GGUF file. Throws [MedhaLlamaException] on failure.
  static MedhaLlama load(String path, {required int contextTokens, int threads = 4, int gpuLayers = 0}) {
    final p = path.toNativeUtf8();
    try {
      final ctx = _load(p, contextTokens, threads, gpuLayers);
      if (ctx == nullptr) throw MedhaLlamaException(lastError());
      return MedhaLlama._(ctx);
    } finally {
      calloc.free(p);
    }
  }

  bool get isOpen => _ctx != nullptr;

  void _ensureOpen() {
    if (!isOpen) throw StateError('model is closed');
  }

  /// Applies the model's built-in chat template, or returns null if the model
  /// has none that llama.cpp can apply natively.
  String? formatChat(List<(String role, String content)> messages, {bool addAssistant = true}) {
    _ensureOpen();
    if (messages.isEmpty) return null;
    final roles = calloc<Pointer<Utf8>>(messages.length);
    final contents = calloc<Pointer<Utf8>>(messages.length);
    try {
      var total = 0;
      for (var i = 0; i < messages.length; i++) {
        roles[i] = messages[i].$1.toNativeUtf8();
        contents[i] = messages[i].$2.toNativeUtf8();
        total += messages[i].$2.length + messages[i].$1.length;
      }
      var cap = total * 2 + 256;
      for (var attempt = 0; attempt < 2; attempt++) {
        final buf = calloc<Uint8>(cap);
        try {
          final n = _format(_ctx, roles, contents, messages.length, addAssistant ? 1 : 0, buf.cast(), cap);
          if (n < 0) return null;
          if (n <= cap) return buf.cast<Utf8>().toDartString(length: n);
          cap = n + 1;
        } finally {
          calloc.free(buf);
        }
      }
      return null;
    } finally {
      for (var i = 0; i < messages.length; i++) {
        if (roles[i] != nullptr) calloc.free(roles[i]);
        if (contents[i] != nullptr) calloc.free(contents[i]);
      }
      calloc.free(roles);
      calloc.free(contents);
    }
  }

  /// Reads the prompt into the model and prepares sampling.
  void begin(
    String prompt, {
    required double temperature,
    required double topP,
    required int topK,
    double minP = 0,
    double presencePenalty = 0,
    int seed = 0xC0FFEE,
  }) {
    _ensureOpen();
    final p = prompt.toNativeUtf8();
    try {
      final rc = _begin(_ctx, p, temperature, topP, topK, minP, presencePenalty, seed);
      if (rc != 0) throw MedhaLlamaException(lastError(), rc);
    } finally {
      calloc.free(p);
    }
  }

  /// Returns the next token's bytes, or null when generation has finished.
  List<int>? next() {
    _ensureOpen();
    final n = _next(_ctx, _piece, _pieceBufferSize);
    if (n == 0) return null;
    if (n < 0) throw MedhaLlamaException(lastError(), n);
    return List<int>.of(_piece.asTypedList(n));
  }

  int get promptTokens => isOpen ? _promptTokens(_ctx) : 0;

  void close() {
    if (!isOpen) return;
    _free(_ctx);
    _ctx = nullptr;
    calloc.free(_piece);
  }
}
