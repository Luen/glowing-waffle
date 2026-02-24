import 'dart:js_util';

import 'tts_engine.dart';

/// Web implementation (Kokoro primary + Kitten fallback via tts_bridge.js).
class TtsEngineWeb implements TtsEngine {
  Object? _ttsBridge;

  Object? get _bridge {
    _ttsBridge ??= _getGlobal('glowingWaffleTts');
    return _ttsBridge;
  }

  dynamic _getGlobal(String name) {
    return _getProperty(globalThis, name);
  }

  dynamic _getProperty(Object o, String name) {
    return getProperty<Object?>(o, name);
  }

  @override
  Future<void> synthesizeAndPlay(String text) async {
    if (text.trim().isEmpty) return;
    final bridge = _bridge;
    if (bridge == null) {
      throw StateError('TTS bridge (glowingWaffleTts) not loaded. Ensure tts_bridge.js is loaded.');
    }
    final promise = callMethod<Object?>(bridge, 'synthesize', [text]);
    await promiseToFuture(promise);
  }

  @override
  Future<void> stop() async {
    // Web Audio playback cannot be stopped mid-buffer easily; no-op.
  }
}

TtsEngine getTtsEngineImpl() => TtsEngineWeb();
