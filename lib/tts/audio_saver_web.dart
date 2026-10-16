import 'dart:js_interop';
import 'dart:typed_data';

import 'audio_saver.dart';

/// Download helper exposed by `web/tts_bridge.js` as `window.glowingWaffleTts`.
extension type _TtsBridge._(JSObject _) implements JSObject {
  external void downloadWav(JSUint8Array bytes, JSString fileName);
}

@JS('glowingWaffleTts')
external _TtsBridge? get _bridge;

/// Web saver: hands the WAV to the browser as a download.
///
/// There is no filesystem to write to, so the bytes are turned into a Blob and
/// offered to the user as a download named after the text.
class WebAudioSaver implements AudioSaver {
  @override
  Future<String> save(Uint8List bytes, String fileName) async {
    final bridge = _bridge;
    if (bridge == null) {
      throw StateError(
        'TTS bridge (glowingWaffleTts) not loaded. Ensure tts_bridge.js is loaded.',
      );
    }
    bridge.downloadWav(bytes.toJS, fileName.toJS);
    // The browser owns where downloads land, so there is no path to report.
    return "your browser's downloads";
  }
}

AudioSaver getAudioSaverImpl() => WebAudioSaver();
