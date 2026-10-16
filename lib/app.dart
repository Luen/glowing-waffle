import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';
import 'providers/tts_providers.dart';
import 'state/tts_app_state.dart';
import 'tts/audio_saver.dart';
import 'tts/tts_engine.dart';
import 'tts/tts_engine_impl.dart';
import 'tts/wav.dart';

class GlowingWaffleApp extends ConsumerStatefulWidget {
  const GlowingWaffleApp({super.key, this.engine, this.audioSaver});

  /// Override the platform TTS engine (used by tests).
  final TtsEngine? engine;

  /// Override where exported audio is written (used by tests).
  final AudioSaver? audioSaver;

  @override
  ConsumerState<GlowingWaffleApp> createState() => _GlowingWaffleAppState();
}

class _GlowingWaffleAppState extends ConsumerState<GlowingWaffleApp> {
  late final TtsEngine _engine = widget.engine ?? getTtsEngine();
  late final AudioSaver _audioSaver = widget.audioSaver ?? getAudioSaver();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Pushes the current voice/speed/backend into the engine. Play and Save both
  /// do this so a saved file matches what playback would sound like.
  Future<void> _applySettings(TtsAppState settings) async {
    await _engine.setVoice(settings.voice);
    await _engine.setSpeed(settings.speed);
    await _engine.setBackend(settings.backend);
  }

  Future<void> _handlePlay(String text) async {
    if (text.trim().isEmpty) return;
    final notifier = ref.read(ttsStateProvider.notifier);
    notifier.clearError();
    final settings = ref.read(ttsStateProvider);
    // synthesizeAndPlay resolves once playback has finished.
    notifier.setStatus(AppStatus.playing);
    try {
      await _applySettings(settings);
      await _engine.synthesizeAndPlay(text);
      notifier.setStatus(AppStatus.idle);
    } catch (e) {
      notifier.setStatus(AppStatus.error, errorMessage: e.toString());
    }
  }

  /// Renders [text] and writes it to a file the user can keep.
  ///
  /// The audio is rendered again for the export (whole text, current voice and
  /// speed) instead of being captured during playback, so a save works whether
  /// or not the text was played, and always yields one complete file.
  Future<void> _handleSave(String text) async {
    if (text.trim().isEmpty) return;
    final notifier = ref.read(ttsStateProvider.notifier);
    notifier.clearError();
    final settings = ref.read(ttsStateProvider);
    notifier.setStatus(AppStatus.exportingAudio);
    try {
      await _applySettings(settings);
      final audio = await _engine.renderSamples(text);
      if (audio.isEmpty) {
        throw StateError('No audio was produced for this text.');
      }
      final fileName = suggestedAudioFileName(text, voice: settings.voice);
      final where = await _audioSaver.save(
        encodeWavPcm16(audio.samples, sampleRate: audio.sampleRate),
        fileName,
      );
      notifier.setStatus(AppStatus.idle);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Saved $fileName to $where')),
      );
    } catch (e) {
      notifier.setStatus(AppStatus.error, errorMessage: e.toString());
    }
  }

  void _handleStop() {
    _engine.stop();
    ref.read(ttsStateProvider.notifier).setStatus(AppStatus.idle);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Read aloud',
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: HomeScreen(
        onPlay: _handlePlay,
        onStop: _handleStop,
        onSave: _handleSave,
      ),
    );
  }
}
