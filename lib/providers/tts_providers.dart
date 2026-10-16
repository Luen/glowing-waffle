import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/tts_app_state.dart';

/// Provides the current TTS app state (status, error, voice, speed).
final ttsStateProvider =
    NotifierProvider<TtsStateNotifier, TtsAppState>(TtsStateNotifier.new);

class TtsStateNotifier extends Notifier<TtsAppState> {
  @override
  TtsAppState build() => const TtsAppState();

  void setStatus(AppStatus status, {String? errorMessage}) {
    state = state.copyWith(status: status, errorMessage: errorMessage);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void setVoice(String voice) {
    state = state.copyWith(voice: voice);
  }

  void setSpeed(double speed) {
    state = state.copyWith(speed: speed);
  }
}
