import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tts_providers.dart';
import '../state/tts_app_state.dart';

/// Voice, speed and (on web) acceleration controls shared by the Text and Web
/// Reader tabs.
///
/// The selected values are read by the app when Play is pressed; the engines
/// apply them (kokoro-js `voice`/`speed`/`device`, sherpa-onnx `sid`/`speed`).
class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({super.key, this.showBackend = false});

  /// Shows the execution-backend picker. Only web has more than one backend,
  /// so only the web home screen passes true.
  final bool showBackend;

  static const double _minSpeed = 0.5;
  static const double _maxSpeed = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ttsStateProvider);
    final notifier = ref.read(ttsStateProvider.notifier);
    final selectedVoice =
        kKokoroVoices.contains(state.voice) ? state.voice : kKokoroVoices.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.record_voice_over, size: 20),
            const SizedBox(width: 12),
            const Text('Voice'),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                value: selectedVoice,
                isExpanded: true,
                items: [
                  for (final voice in kKokoroVoices)
                    DropdownMenuItem<String>(
                      value: voice,
                      child: Text(voice),
                    ),
                ],
                onChanged: (voice) {
                  if (voice != null) notifier.setVoice(voice);
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.speed, size: 20),
            const SizedBox(width: 12),
            SizedBox(
              width: 48,
              child: Text('${state.speed.toStringAsFixed(2)}x'),
            ),
            Expanded(
              child: Slider(
                value: state.speed.clamp(_minSpeed, _maxSpeed),
                min: _minSpeed,
                max: _maxSpeed,
                divisions: 15,
                label: '${state.speed.toStringAsFixed(2)}x',
                onChanged: notifier.setSpeed,
              ),
            ),
          ],
        ),
        if (showBackend)
          Row(
            children: [
              const Icon(Icons.memory, size: 20),
              const SizedBox(width: 12),
              const Tooltip(
                message: 'Choose CPU if playback sounds garbled.',
                child: Text('Acceleration'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<TtsBackend>(
                  value: state.backend,
                  isExpanded: true,
                  items: [
                    for (final backend in TtsBackend.values)
                      DropdownMenuItem<TtsBackend>(
                        value: backend,
                        child: Text(backend.label),
                      ),
                  ],
                  onChanged: (backend) {
                    if (backend != null) notifier.setBackend(backend);
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }
}
