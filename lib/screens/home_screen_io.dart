import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'text_tab.dart';
import 'web_reader_tab.dart';

/// Home with Text and Web Reader tabs (mobile/macOS).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onPlay,
    required this.onStop,
  });

  final void Function(String text) onPlay;
  final VoidCallback onStop;

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
      body: TabBarView(
        controller: _tabController,
        children: [
          TextTab(
            onPlay: widget.onPlay,
            onStop: widget.onStop,
          ),
          WebReaderTab(
            onExtractAndPlay: widget.onPlay,
            onStop: widget.onStop,
          ),
        ],
      ),
    );
  }
}
