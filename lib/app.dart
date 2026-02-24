import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';
import 'providers/tts_providers.dart';
import 'state/tts_app_state.dart';
import 'tts/tts_engine.dart';
import 'tts/tts_engine_impl.dart';

class GlowingWaffleApp extends ConsumerStatefulWidget {
  const GlowingWaffleApp({super.key});

  @override
  ConsumerState<GlowingWaffleApp> createState() => _GlowingWaffleAppState();
}

class _GlowingWaffleAppState extends ConsumerState<GlowingWaffleApp> {
  late final TtsEngine _engine = getTtsEngine();

  Future<void> _handlePlay(String text) async {
    if (text.trim().isEmpty) return;
    final notifier = ref.read(ttsStateProvider.notifier);
    notifier.setStatus(AppStatus.generatingAudio);
    try {
      await _engine.synthesizeAndPlay(text);
      notifier.setStatus(AppStatus.playing);
      // Engine may play async; assume playing until we add completion callback.
      await Future<void>.delayed(const Duration(seconds: 1));
    } catch (e, st) {
      notifier.setStatus(AppStatus.error, errorMessage: e.toString());
    } finally {
      notifier.setStatus(AppStatus.idle);
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
