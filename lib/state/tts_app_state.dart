/// App status for TTS pipeline.
enum AppStatus {
  idle,
  loadingModel,
  generatingAudio,
  playing,
  error,
}

/// State held by the TTS app (status + optional error message).
class TtsAppState {
  const TtsAppState({
    this.status = AppStatus.idle,
    this.errorMessage,
  });

  final AppStatus status;
  final String? errorMessage;

  TtsAppState copyWith({
    AppStatus? status,
    String? errorMessage,
  }) {
    return TtsAppState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
