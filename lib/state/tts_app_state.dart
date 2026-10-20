import '../tts/tts_models.dart';

/// Speed slider bounds, shared by the UI and the stored settings.
const double kMinSpeed = 0.5;
const double kMaxSpeed = 2.0;

/// App status for TTS pipeline.
enum AppStatus {
  idle,
  loadingModel,
  generatingAudio,
  playing,

  /// Rendering audio to save as a file (no playback).
  exportingAudio,
  error,
}

/// Execution backend preference for TTS synthesis.
///
/// Only the web engine has more than one backend today: kokoro-js runs on
/// WebGPU ("gpu") or on WASM ("cpu"). Engines with a single backend (the native
/// sherpa-onnx engines) ignore this setting.
enum TtsBackend {
  /// Use the best accelerator available on this device.
  auto('Auto', 'auto'),

  /// Force the GPU path (WebGPU on web).
  gpu('GPU (WebGPU)', 'gpu'),

  /// Force the CPU path (WASM on web).
  cpu('CPU (WASM)', 'cpu');

  const TtsBackend(this.label, this.wireName);

  /// Label shown in the UI.
  final String label;

  /// Value understood by `web/tts_bridge.js`.
  final String wireName;
}

/// State held by the TTS app (status, error, playback settings).
class TtsAppState {
  const TtsAppState({
    this.status = AppStatus.idle,
    this.errorMessage,
    this.model = TtsModel.kokoro,
    this.voicePicks = const {},
    this.speed = 1.0,
    this.backend = TtsBackend.auto,
    this.modelReady = true,
  });

  final AppStatus status;
  final String? errorMessage;

  /// Speech model to synthesize with (see [TtsModel]). Native only: the web
  /// engine always uses Kokoro via kokoro-js.
  final TtsModel model;

  /// Voice picked per model, so switching model and back remembers the choice.
  /// Values are only trusted for their own model (see [voice]).
  final Map<TtsModel, String> voicePicks;

  /// Voice to synthesize with for the selected [model]: the remembered pick
  /// when it is still a voice of that model, otherwise its default. Switching
  /// model therefore never leaves an id behind that the new model cannot use.
  String get voice {
    final picked = voicePicks[model];
    return picked != null && model.voices.contains(picked)
        ? picked
        : model.defaultVoice;
  }

  /// Playback speed multiplier (0.5 - 2.0).
  final double speed;

  /// Execution backend preference (see [TtsBackend]).
  final TtsBackend backend;

  /// Whether the engine has everything it needs to synthesize.
  ///
  /// Starts out true so nothing flashes on launch; `app.dart` asks the engine
  /// on startup and flips this to false when the native model still has to be
  /// downloaded. Engines that need nothing (web) always report true.
  final bool modelReady;

  /// Returns a copy. Pass [clearError] to drop the current error message.
  TtsAppState copyWith({
    AppStatus? status,
    String? errorMessage,
    bool clearError = false,
    TtsModel? model,
    Map<TtsModel, String>? voicePicks,
    double? speed,
    TtsBackend? backend,
    bool? modelReady,
  }) {
    return TtsAppState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      model: model ?? this.model,
      voicePicks: voicePicks ?? this.voicePicks,
      speed: speed ?? this.speed,
      backend: backend ?? this.backend,
      modelReady: modelReady ?? this.modelReady,
    );
  }
}
