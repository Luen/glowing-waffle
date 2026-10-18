import '../state/tts_app_state.dart';
import 'tts_models.dart';

/// Abstract TTS engine: synthesize text and play audio.
/// Platform-specific implementations are selected via conditional imports.
abstract class TtsEngine {
  /// Synthesizes [text] to audio and plays it.
  /// Updates app state (e.g. LoadingModel, GeneratingAudio, Playing) via callbacks or internally.
  Future<void> synthesizeAndPlay(String text);

  /// Stops playback if supported. No-op if not playing.
  Future<void> stop() async {}

  /// Selects the speech model used for subsequent synthesis (see [TtsModel]).
  ///
  /// No-op for engines with a single model: the web engine always uses Kokoro
  /// through kokoro-js, so only native builds offer a choice (issue #6).
  Future<void> setModel(TtsModel model) async {}

  /// Selects the voice used for subsequent synthesis. [voice] is one of
  /// [TtsModel.voices] for the model selected with [setModel]. No-op when an
  /// engine has a single voice.
  Future<void> setVoice(String voice) async {}

  /// Sets the playback speed multiplier (0.5 - 2.0) for subsequent synthesis.
  Future<void> setSpeed(double speed) async {}

  /// Selects the execution backend used for subsequent synthesis. An engine
  /// with a single backend (the native engines) ignores this.
  Future<void> setBackend(TtsBackend backend) async {}

  /// Voices this engine can speak with. Empty when not enumerable.
  Future<List<String>> voices() async => const [];

  /// Whether the engine can synthesize with the selected model without
  /// fetching anything first.
  ///
  /// Engines whose model ships with the app, or is fetched by the browser, are
  /// always ready. The native engine downloads its model on first run (issue
  /// #7) and reports false until the selected model has been installed.
  Future<bool> isModelReady() async => true;

  /// Fetches whatever [isModelReady] last reported as missing, for the model
  /// selected with [setModel].
  ///
  /// No-op for engines that are always ready. Progress is reported through
  /// [modelDownloadProgress] by the engine that implements this.
  Future<void> downloadModel() async {}
}
