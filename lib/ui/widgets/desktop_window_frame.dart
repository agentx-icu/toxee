import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../util/platform_utils.dart';

/// Height of the transparent draggable strip at the top of the frameless window.
const double kDesktopTitleBarDragHeight = 38.0;

/// Frameless desktop window chrome, matching the reference design.
///
/// There is NO separate title-bar strip and NO app-name/icon label — the app
/// content (nav rail, conversation list, chat) fills to the very top edge. On
/// macOS the native traffic lights overlay the top-left of the nav rail (which
/// reserves vertical space for them so the avatar sits clear), and a
/// transparent drag strip across the top lets the window be moved while taps
/// fall through to the header content below. On Windows/Linux the
/// native-styled caption buttons sit at the top-right.
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

    final isMac = Platform.isMacOS;
    // Width occupied by the Windows/Linux caption buttons (3 × 46).
    const captionWidth = 46.0 * 3;

    return Stack(
      children: [
        // Content fills the whole window — no title-bar strip pushing it down.
        Positioned.fill(child: widget.child),

        // Transparent window-drag strip. `HitTestBehavior.translucent` + a
        // pan-only recognizer means taps fall through to the header content
        // (search box, chat header, action buttons) while a drag moves the
        // window. Kept clear of the native macOS traffic lights (left) and of
        // the caption buttons (right, Windows/Linux).
        Positioned(
          top: 0,
          left: isMac ? 78 : 0,
          right: isMac ? 0 : captionWidth,
          height: kDesktopTitleBarDragHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => unawaited(windowManager.startDragging()),
            child: const SizedBox.expand(),
          ),
        ),

        // Windows / Linux caption buttons at the top-right. macOS uses its
        // native traffic lights, so nothing is drawn there.
        if (!isMac)
          Positioned(
            top: 0,
            right: 0,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
              ),
            ),
          ),
      ],
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
            height: kDesktopTitleBarDragHeight,
            color: backgroundColor,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 17, color: iconColor),
          ),
        ),
      ),
    );
  }
}
