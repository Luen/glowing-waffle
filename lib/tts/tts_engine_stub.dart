import 'tts_engine.dart';

/// Stub implementation for tests or when no platform implementation is used.
class TtsEngineStub implements TtsEngine {
  @override
  Future<void> synthesizeAndPlay(String text) async {
    if (text.trim().isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> stop() async {}
}

TtsEngine getTtsEngineImpl() => TtsEngineStub();
