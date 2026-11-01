import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech → text using the phone's own recogniser, on-device only
/// (ARCHITECTURE.md: voice). No audio leaves the phone.
abstract interface class SpeechInput {
  /// Asks for microphone permission the first time. False if unavailable.
  Future<bool> init();
  Future<void> listen({
    required String locale,
    required void Function(String words, bool isFinal) onResult,
    required void Function(String error) onError,
  });
  Future<void> stop();
}

/// Text → speech with the phone's built-in voices.
abstract interface class SpeechOutput {
  Future<void> speak(String text, {required String locale});
  Future<void> stop();
}

class DeviceSpeechInput implements SpeechInput {
  final _stt = SpeechToText();
  void Function(String error)? _onError;
  bool _ready = false;

  @override
  Future<bool> init() async {
    if (_ready) return true;
    _ready = await _stt.initialize(onError: (SpeechRecognitionError e) => _onError?.call(e.errorMsg));
    return _ready;
  }

  @override
  Future<void> listen({
    required String locale,
    required void Function(String words, bool isFinal) onResult,
    required void Function(String error) onError,
  }) async {
    _onError = onError;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) => onResult(r.recognizedWords, r.finalResult),
      localeId: locale.replaceAll('-', '_'),
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        onDevice: true,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();
}

class DeviceSpeechOutput implements SpeechOutput {
  final _tts = FlutterTts();

  @override
  Future<void> speak(String text, {required String locale}) async {
    await _tts.setLanguage(locale);
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}
