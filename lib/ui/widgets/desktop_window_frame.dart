import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../util/platform_utils.dart';

const double kDesktopWindowFrameHeight = 48.0;

/// Width reserved at the leading edge of the title bar on macOS so the custom
/// title content never sits under the native traffic-light buttons (which are
/// shown by `window_manager` with `windowButtonVisibility: true`).
const double _kMacTrafficLightReserve = 72.0;

/// Shared desktop-only custom title bar used after the native system title bar
/// is hidden via `window_manager`.
///
/// Window controls follow each platform's convention, like the reference
/// design: on macOS the native traffic lights stay at the top-left and we draw
/// no buttons; on Windows/Linux we draw native-styled min/max/close at the
/// top-right.
class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!PlatformUtils.isDesktop) return;
    windowManager.addListener(this);
    unawaited(_refreshMaximizedState());
  }

  @override
  void dispose() {
    if (PlatformUtils.isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _refreshMaximizedState() async {
    final isMaximized = await windowManager.isMaximized();
    if (!mounted) return;
    setState(() => _isMaximized = isMaximized);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _isMaximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _isMaximized = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils.isDesktop) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isMac = Platform.isMacOS;
    final titleColor = scheme.onSurface;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          Material(
            color: scheme.surface,
            child: Container(
              height: kDesktopWindowFrameHeight,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  // macOS: keep clear of the native traffic-light cluster.
                  if (isMac) const SizedBox(width: _kMacTrafficLightReserve),
                  Expanded(
                    child: DragToMoveArea(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: _toggleMaximize,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMac ? 4 : 14,
                          ),
                          child: Row(
                            children: [
                              Image.asset(
                                isDark
                                    ? 'assets/app_icon_white.png'
                                    : 'assets/app_icon.png',
                                width: 18,
                                height: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Toxee',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: titleColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Windows / Linux: native-styled caption buttons at top-right.
                  // macOS uses its native traffic lights, so no buttons here.
                  if (!isMac) ...[
                    _WindowControlButton(
                      icon: Icons.remove_rounded,
                      onPressed: () => windowManager.minimize(),
                    ),
                    _WindowControlButton(
                      icon: _isMaximized
                          ? Icons.filter_none_rounded
                          : Icons.crop_square_rounded,
                      onPressed: _toggleMaximize,
                    ),
                    _WindowControlButton(
                      icon: Icons.close_rounded,
                      danger: true,
                      onPressed: () => windowManager.close(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  const _WindowControlButton({
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final Future<void> Function() onPressed;
  final bool danger;

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  // Windows 11 close-button hover red.
  static const Color _closeHover = Color(0xFFE81123);

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundColor = widget.danger
        ? _closeHover.withValues(alpha: _hovered ? 1 : 0)
        : scheme.onSurface.withValues(alpha: _hovered ? 0.08 : 0);
    final iconColor = widget.danger && _hovered
        ? Colors.white
        : scheme.onSurface.withValues(alpha: 0.78);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => unawaited(widget.onPressed()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: 46,
            height: kDesktopWindowFrameHeight,
            color: backgroundColor,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 17, color: iconColor),
          ),
        ),
      ),
    );
  }
}
