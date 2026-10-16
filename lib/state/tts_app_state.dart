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

/// Voice ids shared by the web (kokoro-js) and native (sherpa-onnx) engines.
///
/// Both back ends use the same Kokoro v1.0 speaker names, so the same id can be
/// selected on every platform. The list is in sherpa-onnx speaker-id order, so
/// the native engine can use the list index as the `sid`.
/// See https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html
const List<String> kKokoroVoices = [
  'af_alloy', // 0
  'af_aoede', // 1
  'af_bella', // 2
  'af_heart', // 3
  'af_jessica', // 4
  'af_kore', // 5
  'af_nicole', // 6
  'af_nova', // 7
  'af_river', // 8
  'af_sarah', // 9
  'af_sky', // 10
  'am_adam', // 11
  'am_echo', // 12
  'am_eric', // 13
  'am_fenrir', // 14
  'am_liam', // 15
  'am_michael', // 16
  'am_onyx', // 17
  'am_puck', // 18
  'am_santa', // 19
];

/// Default voice used when nothing else is selected.
const String kDefaultVoice = 'af_heart';

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
    this.voice = kDefaultVoice,
    this.speed = 1.0,
    this.backend = TtsBackend.auto,
  });

  final AppStatus status;
  final String? errorMessage;

  /// Selected voice id (see [kKokoroVoices]).
  final String voice;

  /// Playback speed multiplier (0.5 - 2.0).
  final double speed;

  /// Execution backend preference (see [TtsBackend]).
  final TtsBackend backend;

  /// Returns a copy. Pass [clearError] to drop the current error message.
  TtsAppState copyWith({
    AppStatus? status,
    String? errorMessage,
    bool clearError = false,
    String? voice,
    double? speed,
    TtsBackend? backend,
  }) {
    return TtsAppState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      voice: voice ?? this.voice,
      speed: speed ?? this.speed,
      backend: backend ?? this.backend,
    );
  }
}
