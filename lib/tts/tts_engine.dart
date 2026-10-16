import '../state/tts_app_state.dart';

/// Abstract TTS engine: synthesize text and play audio.
/// Platform-specific implementations are selected via conditional imports.
abstract class TtsEngine {
  /// Synthesizes [text] to audio and plays it.
  /// Updates app state (e.g. LoadingModel, GeneratingAudio, Playing) via callbacks or internally.
  Future<void> synthesizeAndPlay(String text);

  /// Stops playback if supported. No-op if not playing.
  Future<void> stop() async {}

  /// Selects the voice used for subsequent synthesis. [voice] is one of
  /// [kKokoroVoices]. No-op when an engine has a single voice.
  Future<void> setVoice(String voice) async {}

  /// Sets the playback speed multiplier (0.5 - 2.0) for subsequent synthesis.
  Future<void> setSpeed(double speed) async {}

  /// Voices this engine can speak with. Empty when not enumerable.
  Future<List<String>> voices() async => const [];
}
