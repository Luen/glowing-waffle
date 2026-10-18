import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/tts_app_state.dart';
import '../tts/tts_models.dart';

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

  void setModel(TtsModel model) {
    state = state.copyWith(model: model);
  }

  /// Remembers [voice] for the selected model. Ids of another model are
  /// ignored, so a stale selection can never reach the engine.
  void setVoice(String voice) {
    if (!state.model.voices.contains(voice)) return;
    state = state.copyWith(
      voicePicks: {...state.voicePicks, state.model: voice},
    );
  }

  void setSpeed(double speed) {
    state = state.copyWith(speed: speed);
  }

  void setBackend(TtsBackend backend) {
    state = state.copyWith(backend: backend);
  }

  void setModelReady(bool ready) {
    state = state.copyWith(modelReady: ready);
  }
}
