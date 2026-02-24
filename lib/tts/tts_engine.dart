/// Abstract TTS engine: synthesize text and play audio.
/// Platform-specific implementations are selected via conditional imports.
abstract class TtsEngine {
  /// Synthesizes [text] to audio and plays it.
  /// Updates app state (e.g. LoadingModel, GeneratingAudio, Playing) via callbacks or internally.
  Future<void> synthesizeAndPlay(String text);

  /// Stops playback if supported. No-op if not playing.
  Future<void> stop() async {}
}
