import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';
import 'providers/tts_providers.dart';
import 'state/tts_app_state.dart';
import 'theme/brand_theme.dart';
import 'tts/audio_saver.dart';
import 'tts/tts_engine.dart';
import 'tts/tts_engine_impl.dart';
import 'tts/tts_models.dart';
import 'tts/wav.dart';
import 'widgets/app_title.dart';

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

  /// Pushes the current model/voice/speed/backend into the engine. Play and Save
  /// both do this so a saved file matches what playback would sound like.
  Future<void> _applySettings(TtsAppState settings) async {
    await _engine.setModel(settings.model);
    await _engine.setVoice(settings.voice);
    await _engine.setSpeed(settings.speed);
    await _engine.setBackend(settings.backend);
  }

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
      final message = await _audioSaver.save(
        encodeWavPcm16(audio.samples, sampleRate: audio.sampleRate),
        fileName,
      );
      notifier.setStatus(AppStatus.idle);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      notifier.setStatus(AppStatus.error, errorMessage: e.toString());
    }
  }

  void _handleStop() {
    _engine.stop();
    ref.read(ttsStateProvider.notifier).setStatus(AppStatus.idle);
  }

  /// Keeps the engine on the model the UI selected.
  ///
  /// Readiness, the download and the voice list all refer to the selected
  /// model, so the engine has to follow the picker, not just Play (#6).
  Future<void> _applyModel(TtsModel model) async {
    try {
      await _engine.setModel(model);
    } catch (e) {
      debugPrint('Could not switch the speech model: $e');
    }
    await _checkModel();
  }

  @override
  Widget build(BuildContext context) {
    // Each model has its own files, so a switch has to be re-checked: the
    // setup card appears or disappears and Play follows (issue #6).
    ref.listen(ttsStateProvider.select((state) => state.model),
        (_, model) => _applyModel(model));
    return MaterialApp(
      title: AppTitle.name,
      scaffoldMessengerKey: _messengerKey,
      theme: buildBrandTheme(Brightness.light),
      darkTheme: buildBrandTheme(Brightness.dark),
      home: HomeScreen(
        onPlay: _handlePlay,
        onStop: _handleStop,
        onDownloadModel: _handleDownloadModel,
        onSave: _handleSave,
      ),
    );
  }
}
