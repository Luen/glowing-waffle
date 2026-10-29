import 'package:flutter/material.dart';

import '../app_version.dart';
import '../theme/waffle_mark.dart';

/// The app bar title: the mark, the app's name, and the ship version.
class AppTitle extends StatelessWidget {
  const AppTitle({super.key});

  /// The app's display name, as on every platform (docs/branding.md).
  static const String name = 'Waffle';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const WaffleMark(size: 30),
        const SizedBox(width: 12),
        Text(name),
        const SizedBox(width: 8),
        Text(
          'v$kAppVersion',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
