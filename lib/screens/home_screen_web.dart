import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'text_tab.dart';

/// Home with a single Text tab (web platform).
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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Read aloud'),
      ),
      body: TextTab(
        onPlay: widget.onPlay,
        onStop: widget.onStop,
      ),
    );
  }
}
