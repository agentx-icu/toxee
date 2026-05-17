import 'package:flutter/material.dart';

import '../../util/app_theme_config.dart';

/// Discrete states the pairing UI can be in. Drives the icon + color of
/// [PairingStatusIndicator] and the [AnimatedSwitcher] keys upstream so the
/// transitions feel intentional rather than incidental.
enum PairingState {
  /// Idle / awaiting peer. Outline ring, neutral.
  waiting,

  /// Actively scanning / discovering / generating QR. Animated rotation
  /// (replaced with a static ring when MediaQuery.disableAnimations is on).
  scanning,

  /// Handshake in progress — gentle pulse on a primary-color dot.
  connecting,

  /// Successfully completed.
  connected,

  /// Error / failure path. Caller surfaces a retry CTA next to this.
  error,
}

/// Compact visual indicator for the pairing pipeline state.
///
/// Honors reduced-motion: when [MediaQuery.disableAnimationsOf] is true we
/// fall back to a static representation instead of looping animations.
class PairingStatusIndicator extends StatefulWidget {
  const PairingStatusIndicator({
    super.key,
    required this.state,
    this.size = 24,
  });

  final PairingState state;
  final double size;

  @override
  State<PairingStatusIndicator> createState() => _PairingStatusIndicatorState();
}

class _PairingStatusIndicatorState extends State<PairingStatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PairingStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final wantsAnim = !reduceMotion &&
        (widget.state == PairingState.scanning ||
            widget.state == PairingState.connecting);
    if (wantsAnim) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final size = widget.size;
    switch (widget.state) {
      case PairingState.waiting:
        return Icon(
          Icons.radio_button_unchecked,
          size: size,
          color: cs.outline,
        );
      case PairingState.scanning:
        if (reduceMotion) {
          return Icon(Icons.qr_code_scanner, size: size, color: cs.primary);
        }
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: size > 32 ? 3.2 : 2.4,
            color: cs.primary,
          ),
        );
      case PairingState.connecting:
        if (reduceMotion) {
          return Icon(Icons.sync, size: size, color: cs.primary);
        }
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            // Soft pulse 0.55 → 1.0
            final scale = 0.85 + 0.15 * (0.5 - (0.5 - _controller.value).abs()) * 2;
            return Transform.scale(
              scale: scale,
              child: Icon(
                Icons.cell_tower,
                size: size,
                color: cs.primary,
              ),
            );
          },
        );
      case PairingState.connected:
        return Icon(
          Icons.check_circle,
          size: size,
          color: AppThemeConfig.successColor,
        );
      case PairingState.error:
        return Icon(
          Icons.error_outline,
          size: size,
          color: cs.error,
        );
    }
  }
}
