import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tts_providers.dart';
import '../state/tts_app_state.dart';
import '../tts/tts_models.dart';

/// Model, voice, speed and (on web) acceleration controls shared by the Text
/// and Web Reader tabs.
///
/// The selected values are read by the app when Play is pressed; the engines
/// apply them (kokoro-js `voice`/`speed`/`device`, sherpa-onnx
/// `model`/`sid`/`speed`).
class PlaybackControls extends ConsumerWidget {
  const PlaybackControls({
    super.key,
    this.showBackend = false,
    this.showModelPicker = false,
  });

  /// Shows the execution-backend picker. Only web has more than one backend,
  /// so only the web home screen passes true.
  final bool showBackend;

  /// Shows the speech-model picker. Only native builds can choose: the web
  /// engine always speaks with Kokoro through kokoro-js, so the web home screen
  /// hides the option instead of offering something that does nothing (#6).
  final bool showModelPicker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ttsStateProvider);
    final notifier = ref.read(ttsStateProvider.notifier);
    // state.voice is already valid for the selected model; the guard keeps a
    // dropdown from being handed a value outside its items.
    final voices = state.model.voices;
    final selectedVoice =
        voices.contains(state.voice) ? state.voice : voices.first;
    final accent = Theme.of(context).colorScheme.primary;

    // The controls sit on a card in the Text tab, where underlines are noise.
    return DropdownButtonHideUnderline(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showModelPicker)
            Row(
              children: [
                Icon(Icons.graphic_eq, size: 20, color: accent),
                const SizedBox(width: 12),
                const Tooltip(
                  message: 'Kitten is the small model (~25 MB), '
                      'Kokoro the original 82M one (~350 MB).',
                  child: Text('Model'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<TtsModel>(
                    value: state.model,
                    isExpanded: true,
                    items: [
                      for (final model in TtsModel.values)
                        DropdownMenuItem<TtsModel>(
                          value: model,
                          child: Text('${model.label} (${model.size})'),
                        ),
                    ],
                    onChanged: (model) {
                      if (model != null) notifier.setModel(model);
                    },
                  ),
                ),
              ],
            ),
          Row(
            children: [
              Icon(Icons.record_voice_over, size: 20, color: accent),
              const SizedBox(width: 12),
              const Text('Voice'),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  value: selectedVoice,
                  isExpanded: true,
                  items: [
                    for (final voice in voices)
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
              Icon(Icons.speed, size: 20, color: accent),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                child: Text('${state.speed.toStringAsFixed(2)}x'),
              ),
              Expanded(
                child: Slider(
                  value: state.speed.clamp(kMinSpeed, kMaxSpeed),
                  min: kMinSpeed,
                  max: kMaxSpeed,
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
                Icon(Icons.memory, size: 20, color: accent),
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
      ),
    );
  }
}
