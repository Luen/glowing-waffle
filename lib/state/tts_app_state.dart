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

  /// Returns a copy. Pass [clearError] to drop the current error message.
  TtsAppState copyWith({
    AppStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TtsAppState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
