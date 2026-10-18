import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tts_providers.dart';
import '../state/tts_app_state.dart';
import '../tts/model_progress.dart';

/// First-run setup card shown while the voice model is not installed.
///
/// The Kokoro model is ~350 MB and is no longer bundled with the app, so native
/// builds fetch it on first run instead of shipping it (issue #7). The card
/// stays hidden once the model is there; the download is explicit because of
/// its size.
class ModelSetupCard extends ConsumerWidget {
  const ModelSetupCard({super.key, required this.onDownload});

  /// Starts the model download. The engine lives in the app, not here.
  final VoidCallback onDownload;

  /// Rough size of the download, shown to explain the wait.
  static const String downloadSize = '~350 MB';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ttsStateProvider);
    if (state.modelReady) return const SizedBox.shrink();
    final downloading = state.status == AppStatus.loadingModel;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_download_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Voice model needed',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'The voice model ($downloadSize, one time) is downloaded and '
              'kept on this device. That keeps the app itself small.',
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<double?>(
              valueListenable: modelDownloadProgress,
              builder: (context, progress, _) {
                if (!downloading) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 4),
                    Text(
                      _progressLabel(progress),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: downloading ? null : onDownload,
                icon: const Icon(Icons.download),
                label: Text(downloading ? 'Downloading…' : 'Download model'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _progressLabel(double? progress) {
    if (progress == null) return 'Starting…';
    if (progress >= 1.0) return 'Finishing up…';
    // The last 20% of the bar is unpacking the archive, which is slower per
    // percent than the download, so call it out instead of pretending.
    if (progress > 0.8) return 'Unpacking…';
    return 'Downloading ${(progress * 100).round()}%';
  }
}
