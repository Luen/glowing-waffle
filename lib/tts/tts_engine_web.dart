import 'dart:js_interop';

import 'tts_engine.dart';

/// JS bridge exposed by `web/tts_bridge.js` as `window.glowingWaffleTts`.
extension type _TtsBridge._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> synthesize(JSString text);
  external JSString getEngineName();
}

@JS('glowingWaffleTts')
external _TtsBridge? get _bridge;

/// Web implementation (Kokoro via WebGPU, falling back to Kokoro on WASM)
/// through tts_bridge.js.
class TtsEngineWeb implements TtsEngine {
  @override
  Future<void> synthesizeAndPlay(String text) async {
    if (text.trim().isEmpty) return;
    final bridge = _bridge;
    if (bridge == null) {
      throw StateError(
        'TTS bridge (glowingWaffleTts) not loaded. Ensure tts_bridge.js is loaded.',
      );
    }
    await bridge.synthesize(text.toJS).toDart;
  }

  @override
  Future<void> stop() async {
    // Web Audio playback cannot be stopped mid-buffer easily; no-op.
  }
}

TtsEngine getTtsEngineImpl() => TtsEngineWeb();
