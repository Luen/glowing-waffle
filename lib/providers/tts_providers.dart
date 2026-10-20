import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/tts_app_state.dart';
import '../state/tts_settings_store.dart';
import '../tts/tts_models.dart';

/// Provides the current TTS app state (status, error, voice, speed).
final ttsStateProvider =
    NotifierProvider<TtsStateNotifier, TtsAppState>(TtsStateNotifier.new);

class TtsStateNotifier extends Notifier<TtsAppState> {
  TtsStateNotifier({TtsSettingsStore? store})
      : _store = store ?? PrefsTtsSettingsStore();

  /// Where the settings are remembered between runs (#23).
  final TtsSettingsStore _store;

  /// Set once the user changes something, so a slow restore cannot overwrite a
  /// choice made while the store was still loading.
  bool _touched = false;

  bool _disposed = false;

  @override
  TtsAppState build() {
    _touched = false;
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // The first frame uses the defaults; restored values arrive asynchronously
    // and go through copyWith, so nothing blocks startup.
    unawaited(_restore());
    return const TtsAppState();
  }

  Future<void> _restore() async {
    final stored = await _store.load();
    if (stored == null || _disposed || _touched) return;
    state = state.copyWith(
      model: stored.model ?? state.model,
      voicePicks: stored.voicePicks,
      speed: stored.speed.clamp(kMinSpeed, kMaxSpeed).toDouble(),
      backend: stored.backend,
    );
  }

  /// Writes the settings through after a change.
  void _changed() {
    _touched = true;
    unawaited(_store.save(TtsSettings(
      model: state.model,
      voicePicks: state.voicePicks,
      speed: state.speed,
      backend: state.backend,
    )));
  }

  void setStatus(AppStatus status, {String? errorMessage}) {
    state = state.copyWith(status: status, errorMessage: errorMessage);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void setModel(TtsModel model) {
    if (model == state.model) return;
    state = state.copyWith(model: model);
    _changed();
  }

  /// Remembers [voice] for the selected model. Ids of another model are
  /// ignored, so a stale selection can never reach the engine.
  void setVoice(String voice) {
    if (!state.model.voices.contains(voice)) return;
    if (state.voice == voice) return;
    state = state.copyWith(
      voicePicks: {...state.voicePicks, state.model: voice},
    );
    _changed();
  }

  void setSpeed(double speed) {
    state = state.copyWith(
      speed: speed.clamp(kMinSpeed, kMaxSpeed).toDouble(),
    );
    _changed();
  }

  void setBackend(TtsBackend backend) {
    if (backend == state.backend) return;
    state = state.copyWith(backend: backend);
    _changed();
  }

  void setModelReady(bool ready) {
    state = state.copyWith(modelReady: ready);
  }
}
