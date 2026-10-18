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

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  /// Native builds download the model on first run (issue #7), so find out
  /// whether it is installed before the user presses Play.
  Future<void> _checkModel() async {
    bool ready;
    try {
      ready = await _engine.isModelReady();
    } catch (e) {
      // Best effort: if the check fails, leave the UI usable and let Play
      // report the real error.
      debugPrint('Could not check whether the voice model is installed: $e');
      return;
    }
    if (!mounted) return;
    ref.read(ttsStateProvider.notifier).setModelReady(ready);
  }

  Future<void> _handleDownloadModel() async {
    final notifier = ref.read(ttsStateProvider.notifier);
    notifier.clearError();
    notifier.setStatus(AppStatus.loadingModel);
    try {
      await _engine.downloadModel();
      notifier.setModelReady(true);
      notifier.setStatus(AppStatus.idle);
    } catch (e) {
      notifier.setStatus(AppStatus.error, errorMessage: e.toString());
    }
  }

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
      await _engine.setBackend(settings.backend);
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
        onDownloadModel: _handleDownloadModel,
      ),
    );
  }
}
