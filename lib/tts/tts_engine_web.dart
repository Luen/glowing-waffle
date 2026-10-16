import 'dart:js_interop';

import '../state/tts_app_state.dart';
import 'tts_engine.dart';

/// JS bridge exposed by `web/tts_bridge.js` as `window.glowingWaffleTts`.
extension type _TtsBridge._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> synthesize(JSString text);
  external void stop();
  external JSString getEngineName();
  external JSArray<JSString> getVoices();
  external JSString getVoice();
  external void setVoice(JSString voice);
  external JSNumber getSpeed();
  external void setSpeed(JSNumber speed);
  external void setBackend(JSString backend);
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
    _bridge?.stop();
  }

  @override
  Future<void> setVoice(String voice) async {
    _bridge?.setVoice(voice.toJS);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _bridge?.setSpeed(speed.toJS);
  }

  @override
  Future<void> setBackend(TtsBackend backend) async {
    _bridge?.setBackend(backend.wireName.toJS);
  }

  @override
  Future<List<String>> voices() async {
    final list = _bridge?.getVoices();
    if (list == null) return const [];
    return [for (final voice in list.toDart) voice.toDart];
  }
}

TtsEngine getTtsEngineImpl() => TtsEngineWeb();
