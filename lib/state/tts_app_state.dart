/// App status for TTS pipeline.
enum AppStatus {
  idle,
  loadingModel,
  generatingAudio,
  playing,
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

/// State held by the TTS app (status, error, playback settings).
class TtsAppState {
  const TtsAppState({
    this.status = AppStatus.idle,
    this.errorMessage,
    this.voice = kDefaultVoice,
    this.speed = 1.0,
  });

  final AppStatus status;
  final String? errorMessage;

  /// Selected voice id (see [kKokoroVoices]).
  final String voice;

  /// Playback speed multiplier (0.5 - 2.0).
  final double speed;

  /// Returns a copy. Pass [clearError] to drop the current error message.
  TtsAppState copyWith({
    AppStatus? status,
    String? errorMessage,
    bool clearError = false,
    String? voice,
    double? speed,
  }) {
    return TtsAppState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      voice: voice ?? this.voice,
      speed: speed ?? this.speed,
    );
  }
}
