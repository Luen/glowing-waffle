import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';
import 'providers/tts_providers.dart';
import 'state/tts_app_state.dart';
import 'tts/tts_engine.dart';
import 'tts/tts_engine_impl.dart';

class GlowingWaffleApp extends ConsumerStatefulWidget {
  const GlowingWaffleApp({super.key, this.engine});

  /// Override the platform TTS engine (used by tests).
  final TtsEngine? engine;

  @override
  ConsumerState<GlowingWaffleApp> createState() => _GlowingWaffleAppState();
}

class _GlowingWaffleAppState extends ConsumerState<GlowingWaffleApp> {
  late final TtsEngine _engine = widget.engine ?? getTtsEngine();

  Future<void> _handlePlay(String text) async {
    if (text.trim().isEmpty) return;
    final notifier = ref.read(ttsStateProvider.notifier);
    notifier.clearError();
    final settings = ref.read(ttsStateProvider);
    // synthesizeAndPlay resolves once playback has finished.
    notifier.setStatus(AppStatus.playing);
    try {
      await _engine.setVoice(settings.voice);
      await _engine.setSpeed(settings.speed);
      await _engine.synthesizeAndPlay(text);
      notifier.setStatus(AppStatus.idle);
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: HomeScreen(
        onPlay: _handlePlay,
        onStop: _handleStop,
      ),
    );
  }
}
