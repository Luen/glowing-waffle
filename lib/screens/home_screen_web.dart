import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/model_setup_card.dart';
import 'text_tab.dart';

/// Home with a single Text tab (web platform).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onPlay,
    required this.onStop,
    required this.onDownloadModel,
    required this.onSave,
  });

  final void Function(String text) onPlay;
  final VoidCallback onStop;

  /// Unused on web: the model is fetched by kokoro-js in the browser, so
  /// [ModelSetupCard] never appears here. Kept for a constructor shared with
  /// the native home screen.
  final VoidCallback onDownloadModel;

  /// Called with the text to export when Save is pressed.
  final void Function(String text) onSave;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Read aloud'),
      ),
      body: Column(
        children: [
          ModelSetupCard(onDownload: widget.onDownloadModel),
          Expanded(
            child: TextTab(
              onPlay: widget.onPlay,
              onStop: widget.onStop,
              onSave: widget.onSave,
              // The web engine can run on WebGPU or WASM, so let the user override.
              showBackend: true,
            ),
          ),
        ],
      ),
    );
  }
}
