import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tts_providers.dart';
import '../state/tts_app_state.dart';
import '../tts/model_progress.dart';
import 'content_width.dart';

/// First-run setup card shown while the selected voice model is not installed.
///
/// Models are no longer bundled with the app, so native builds fetch the
/// selected one on first run instead of shipping it (issues #6, #7). The card
/// stays hidden once the model is there; the download is explicit because of
/// its size.
class ModelSetupCard extends ConsumerWidget {
  const ModelSetupCard({super.key, required this.onDownload});

  /// Starts the model download. The engine lives in the app, not here.
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ttsStateProvider);
    if (state.modelReady) return const SizedBox.shrink();
    final downloading = state.status == AppStatus.loadingModel;
    final model = state.model;

    final scheme = Theme.of(context).colorScheme;

    return ContentWidth(
      child: Card(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        color: scheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_download_outlined,
                    color: scheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Voice model needed',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'The ${model.label} voice model (${model.size}, one time) is '
                'downloaded and kept on this device. That keeps the app itself '
                'small.',
                style: TextStyle(color: scheme.onPrimaryContainer),
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
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onPrimaryContainer),
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
