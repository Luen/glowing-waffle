import 'package:flutter/material.dart';

import '../theme/waffle_mark.dart';

/// The app bar title: the mark and the app's name.
class AppTitle extends StatelessWidget {
  const AppTitle({super.key});

  /// The app's display name, as on every platform (docs/branding.md).
  static const String name = 'Waffle';

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WaffleMark(size: 30),
        SizedBox(width: 12),
        Text(name),
      ],
    );
  }
}
