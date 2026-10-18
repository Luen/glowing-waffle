import 'dart:js_interop';
import 'dart:typed_data';

import '../state/tts_app_state.dart';
import 'tts_engine.dart';
import 'tts_models.dart';

/// JS bridge exposed by `web/tts_bridge.js` as `window.glowingWaffleTts`.
extension type _TtsBridge._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> synthesize(JSString text);
  external JSPromise<JSFloat32Array> renderSamples(JSString text);
  external JSString downloadWav(JSUint8Array bytes, JSString fileName);
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

  /// Renders [text] through the bridge without playing it, so it can be saved
  /// as a WAV. The bridge joins every sentence chunk into one buffer.
  @override
  Future<RenderedAudio> renderSamples(String text) async {
    if (text.trim().isEmpty) return RenderedAudio(Float32List(0));
    final bridge = _bridge;
    if (bridge == null) {
      throw StateError(
        'TTS bridge (glowingWaffleTts) not loaded. Ensure tts_bridge.js is loaded.',
      );
    }
    final samples = await bridge.renderSamples(text.toJS).toDart;
    return RenderedAudio(samples.toDart);
  }

  @override
  Future<void> stop() async {
    _bridge?.stop();
  }

  /// No-op: the web engine always speaks with Kokoro through kokoro-js, so the
  /// picker that offers Kitten is only shown by the native home screen (#6).
  @override
  Future<void> setModel(TtsModel model) async {}

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

  /// Always ready: kokoro-js fetches its own model in the browser, so nothing
  /// is installed on this device (unlike the native engine, see issues #6,
  /// #7).
  @override
  Future<bool> isModelReady() async => true;

  /// No-op on web; the browser fetches the model when it first synthesizes.
  @override
  Future<void> downloadModel() async {}
}

TtsEngine getTtsEngineImpl() => TtsEngineWeb();
