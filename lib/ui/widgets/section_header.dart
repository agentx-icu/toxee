import 'package:flutter/material.dart';

/// Reusable grouped-list section header — a small, muted label that sits above
/// a rounded settings card (the reference enterprise-chat pattern). Rendered as
/// secondary-text, 13px, medium weight, with a little positive tracking so it
/// reads as a quiet group label rather than a page title.
///
/// Shared Dart → identical on desktop and mobile.
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      title,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            height: 1.3,
          ),
    );
  }
}
