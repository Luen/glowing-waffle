import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tts_providers.dart';
import '../state/tts_app_state.dart';

/// Tab for manual text input and Play/Stop.
class TextTab extends ConsumerStatefulWidget {
  const TextTab({
    super.key,
    required this.onPlay,
    required this.onStop,
  });

  /// Called with the current text when Play is pressed.
  final void Function(String text) onPlay;
  final VoidCallback onStop;

  @override
  ConsumerState<TextTab> createState() => _TextTabState();
}

class _TextTabState extends ConsumerState<TextTab> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ttsStateProvider);
    final isBusy = state.status != AppStatus.idle && state.status != AppStatus.error;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'Enter or paste text to read aloud...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              state.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: isBusy ? null : () => widget.onPlay(_controller.text),
                icon: const Icon(Icons.play_arrow),
                label: Text(_buttonLabel(state.status)),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: state.status == AppStatus.playing ? widget.onStop : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buttonLabel(AppStatus status) {
    switch (status) {
      case AppStatus.loadingModel:
        return 'Loading…';
      case AppStatus.generatingAudio:
        return 'Generating…';
      case AppStatus.playing:
        return 'Playing';
      default:
        return 'Play';
    }
  }

}
