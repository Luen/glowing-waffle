import 'dart:typed_data';

import '../state/tts_app_state.dart';
import 'wav.dart';

/// Mono PCM audio rendered by an engine, before it is played or encoded.
class RenderedAudio {
  const RenderedAudio(this.samples, {this.sampleRate = kKokoroSampleRate});

  /// Samples in -1.0..1.0.
  final Float32List samples;

  /// Samples per second.
  final int sampleRate;

  /// True when nothing was rendered (empty input, or an engine that produced
  /// no audio for this text).
  bool get isEmpty => samples.isEmpty;
}

/// Abstract TTS engine: synthesize text and play audio.
/// Platform-specific implementations are selected via conditional imports.
abstract class TtsEngine {
  /// Synthesizes [text] to audio and plays it.
  /// Updates app state (e.g. LoadingModel, GeneratingAudio, Playing) via callbacks or internally.
  Future<void> synthesizeAndPlay(String text);

  /// Renders [text] to audio with the selected voice, speed and backend,
  /// *without* playing it, so the app can save it to a file.
  ///
  /// Engines that cannot render without playing throw [UnsupportedError]; the
  /// app reports that like any other engine error.
  Future<RenderedAudio> renderSamples(String text) async {
    throw UnsupportedError('This engine cannot export audio.');
  }

  /// Stops playback if supported. No-op if not playing.
  Future<void> stop() async {}

  /// Selects the voice used for subsequent synthesis. [voice] is one of
  /// [kKokoroVoices]. No-op when an engine has a single voice.
  Future<void> setVoice(String voice) async {}

  /// Sets the playback speed multiplier (0.5 - 2.0) for subsequent synthesis.
  Future<void> setSpeed(double speed) async {}

  /// Selects the execution backend used for subsequent synthesis. An engine
  /// with a single backend (the native engines) ignores this.
  Future<void> setBackend(TtsBackend backend) async {}

  /// Voices this engine can speak with. Empty when not enumerable.
  Future<List<String>> voices() async => const [];
}
