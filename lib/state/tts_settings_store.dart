import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tts/tts_models.dart';
import 'tts_app_state.dart';

/// The playback settings that survive a restart (issue #23).
class TtsSettings {
  const TtsSettings({
    required this.model,
    required this.voicePicks,
    required this.speed,
    required this.backend,
  });

  /// The selected model, or null when nothing has been stored yet.
  final TtsModel? model;

  /// Voice picked per model. Entries that no longer belong to their model are
  /// ignored when [TtsAppState.voice] reads them.
  final Map<TtsModel, String> voicePicks;

  /// Playback speed multiplier.
  final double speed;

  /// Execution backend preference.
  final TtsBackend backend;
}

/// Where [TtsSettings] are kept.
///
/// A seam so tests do not need the platform plugin; [PrefsTtsSettingsStore] is
/// the implementation the app uses.
abstract class TtsSettingsStore {
  /// The stored settings, or null when nothing has been saved yet.
  Future<TtsSettings?> load();

  /// Replaces the stored settings. Failures are the store's problem: the app
  /// keeps working when persistence is unavailable.
  Future<void> save(TtsSettings settings);
}

/// Keeps the settings in the platform's key-value store: SharedPreferences on
/// Android, NSUserDefaults on iOS/macOS and the browser's localStorage on web.
///
/// Errors are swallowed (and logged): a missing plugin, a corrupt value or a
/// read-only store must not stop the app from starting, it only means the
/// settings are not remembered.
class PrefsTtsSettingsStore implements TtsSettingsStore {
  static const String _modelKey = 'tts.model';
  static const String _speedKey = 'tts.speed';
  static const String _backendKey = 'tts.backend';

  static String _voiceKey(TtsModel model) => 'tts.voice.${model.wireName}';

  @override
  Future<TtsSettings?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final picks = <TtsModel, String>{};
      for (final model in TtsModel.values) {
        final voice = prefs.getString(_voiceKey(model));
        if (voice != null) picks[model] = voice;
      }
      final hasModel = prefs.containsKey(_modelKey);
      final hasSpeed = prefs.containsKey(_speedKey);
      final hasBackend = prefs.containsKey(_backendKey);
      if (!hasModel && !hasSpeed && !hasBackend && picks.isEmpty) return null;

      return TtsSettings(
        model: _byName(TtsModel.values, prefs.getString(_modelKey),
            (model) => model.wireName),
        voicePicks: picks,
        speed: prefs.getDouble(_speedKey) ?? 1.0,
        backend: _byName(TtsBackend.values, prefs.getString(_backendKey),
                (backend) => backend.wireName) ??
            TtsBackend.auto,
      );
    } catch (error) {
      debugPrint('Could not restore TTS settings: $error');
      return null;
    }
  }

  @override
  Future<void> save(TtsSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final model = settings.model;
      if (model != null) await prefs.setString(_modelKey, model.wireName);
      for (final model in TtsModel.values) {
        final voice = settings.voicePicks[model];
        if (voice != null) await prefs.setString(_voiceKey(model), voice);
      }
      await prefs.setDouble(_speedKey, settings.speed);
      await prefs.setString(_backendKey, settings.backend.wireName);
    } catch (error) {
      debugPrint('Could not save TTS settings: $error');
    }
  }

  /// The value whose [name] matches, ignoring names this build no longer knows
  /// (a removed model or backend must not break startup).
  static T? _byName<T>(
      List<T> values, String? name, String Function(T) nameOf) {
    if (name == null) return null;
    for (final value in values) {
      if (nameOf(value) == name) return value;
    }
    return null;
  }
}

/// In-memory store for tests.
class MemoryTtsSettingsStore implements TtsSettingsStore {
  MemoryTtsSettingsStore([this.settings]);

  /// Current contents; tests may seed it before the state reads it.
  TtsSettings? settings;

  /// How many times [save] ran, for tests that check write-through.
  int saves = 0;

  @override
  Future<TtsSettings?> load() async => settings;

  @override
  Future<void> save(TtsSettings value) async {
    settings = value;
    saves++;
  }
}
