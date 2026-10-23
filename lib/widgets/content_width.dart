import 'package:flutter/material.dart';

/// Centres [child] and caps its width, so forms stay readable in wide windows
/// (web, macOS, tablets) instead of stretching edge to edge.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  static const double maxWidth = 720;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
