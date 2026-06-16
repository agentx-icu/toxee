import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../../util/responsive_layout.dart';

/// On a macOS frameless window the native traffic lights overlay the top-left
/// corner. Full-window pages / dialogs that carry a top bar place this at the
/// very top so their controls (back button, title) sit clear of the lights.
/// Zero height on every other platform.
class MacTitleBarInset extends StatelessWidget {
  const MacTitleBarInset({super.key});

  @override
  Widget build(BuildContext context) => Platform.isMacOS
      ? const SizedBox(height: ResponsiveLayout.macTitleBarReservedHeight)
      : const SizedBox.shrink();
}
