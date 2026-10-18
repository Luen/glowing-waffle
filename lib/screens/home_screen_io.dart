import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/model_setup_card.dart';
import 'text_tab.dart';
import 'web_reader_tab.dart';

/// Home with Text and Web Reader tabs (mobile/macOS).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onPlay,
    required this.onStop,
    required this.onDownloadModel,
  });

  final void Function(String text) onPlay;
  final VoidCallback onStop;

  /// Starts the first-run voice model download (see [ModelSetupCard]).
  final VoidCallback onDownloadModel;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Read aloud'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Text', icon: Icon(Icons.text_fields)),
            Tab(text: 'Web Reader', icon: Icon(Icons.language)),
          ],
        ),
      ),
      body: Column(
        children: [
          ModelSetupCard(onDownload: widget.onDownloadModel),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                TextTab(
                  onPlay: widget.onPlay,
                  onStop: widget.onStop,
                  // Native builds choose between Kokoro and Kitten (see #6).
                  showModelPicker: true,
                ),
                WebReaderTab(
                  onExtractAndPlay: widget.onPlay,
                  onStop: widget.onStop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
