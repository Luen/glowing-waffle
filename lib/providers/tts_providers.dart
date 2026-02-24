import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/tts_app_state.dart';

/// Provides the current TTS app state (status, error).
final ttsStateProvider =
    StateNotifierProvider<TtsStateNotifier, TtsAppState>((ref) {
  return TtsStateNotifier();
});

class TtsStateNotifier extends StateNotifier<TtsAppState> {
  TtsStateNotifier() : super(const TtsAppState());

  void setStatus(AppStatus status, {String? errorMessage}) {
    state = state.copyWith(status: status, errorMessage: errorMessage);
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}
