import 'package:flutter/material.dart';
import '../i18n/app_localizations.dart';
import '../util/app_theme_config.dart';
import '../util/responsive_layout.dart';
import 'call_state_notifier.dart';
import 'ringing_call_manager.dart';
import 'call_ui_components.dart';

// ──────────────────────────────────────────────
//  Floating-widget palette (INTENTIONALLY dark)
// ──────────────────────────────────────────────
//
// The floating call PiP sits on top of every other surface in the app and
// follows the dark-mode-only call surface convention (see `in_call_view.dart`
// for the same rationale). Tokens live here so the look stays consistent and
// future changes have a single dial.

/// Card background — slate-800. Matches `AppThemeConfig.darkGradientEnd`, which
/// is the in-call surface elevation-1 color, so the PiP visually belongs to the
/// call subsystem and not to the app's general dark theme.
const Color _kFloatingCallBg = AppThemeConfig.darkGradientEnd;

/// Drag-handle pip color — slate-400. Affordance hint; intentionally low
/// contrast so it doesn't compete with the avatar + name + duration.
const Color _kFloatingDragPipColor = Color(0xFF94A3B8);

/// Small draggable floating card showing active call info.
/// Tap to restore full-screen, drag to reposition, red button to hang up.
class CallFloatingWidget extends StatefulWidget {
  const CallFloatingWidget({
    super.key,
    required this.callState,
    required this.manager,
  });

  final CallStateNotifier callState;
  final RingingCallManager manager;

  @override
  State<CallFloatingWidget> createState() => _CallFloatingWidgetState();
}

class _CallFloatingWidgetState extends State<CallFloatingWidget>
    with SingleTickerProviderStateMixin {
  late Offset _position;
  AnimationController? _snapController;

  @override
  void initState() {
    super.initState();
    _position = widget.callState.floatingPosition;
  }

  @override
  void dispose() {
    _snapController?.dispose();
    super.dispose();
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  /// Snap the widget to the nearest horizontal edge (left or right of the safe
  /// area) using a 250ms ease-out tween. When motion is disabled, jump
  /// directly to the snapped position.
  void _snapToNearestEdge({
    required Size screenSize,
    required EdgeInsets safePadding,
    required double widgetWidth,
    required double widgetHeight,
    required bool disableAnimations,
  }) {
    final minX = safePadding.left;
    final maxX = screenSize.width - safePadding.right - widgetWidth;
    final centerX = _position.dx + widgetWidth / 2;
    final screenCenter = screenSize.width / 2;
    final targetX = centerX < screenCenter ? minX : maxX;
    final clampedY = _position.dy.clamp(
      safePadding.top,
      screenSize.height - safePadding.bottom - widgetHeight,
    );
    final target = Offset(targetX, clampedY);

    if (disableAnimations) {
      setState(() => _position = target);
      widget.callState.updateFloatingPosition(target);
      return;
    }

    _snapController?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: AppDurations.medium,
    );
    final animation = Tween<Offset>(begin: _position, end: target).animate(
      CurvedAnimation(parent: controller, curve: AppCurves.exit),
    );
    animation.addListener(() {
      setState(() => _position = animation.value);
    });
    _snapController = controller;
    controller.forward().whenComplete(() {
      widget.callState.updateFloatingPosition(_position);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screenSize = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final cs = widget.callState;
    final name = cs.remoteNickname ?? cs.remoteUserID ?? l10n.unknown;
    final subtitle = cs.state == CallUIState.inCall
        ? _formatDuration(cs.callDuration)
        : l10n.callCalling;

    final widgetWidth = ResponsiveLayout.responsiveValue<double>(
      context,
      mobile: 180,
      tablet: 200,
      desktop: 240,
    );
    final widgetHeight = ResponsiveLayout.responsiveValue<double>(
      context,
      mobile: 56,
      tablet: 60,
      desktop: 64,
    );

    // Tighten the drag clamp by MediaQuery.paddingOf(context) so the widget
    // can't slide under notch / Dynamic Island / home-indicator / status bar.
    final minX = safePadding.left;
    final maxX = screenSize.width - safePadding.right - widgetWidth;
    final minY = safePadding.top;
    final maxY = screenSize.height - safePadding.bottom - widgetHeight;
    // Guard against degenerate viewports where padding exceeds screen size.
    final safeMaxX = maxX < minX ? minX : maxX;
    final safeMaxY = maxY < minY ? minY : maxY;

    final clampedX = _position.dx.clamp(minX, safeMaxX);
    final clampedY = _position.dy.clamp(minY, safeMaxY);

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: GestureDetector(
        onPanStart: (_) {
          // Cancel any in-flight snap animation when user grabs the widget.
          _snapController?.stop();
        },
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(minX, safeMaxX),
              (_position.dy + details.delta.dy).clamp(minY, safeMaxY),
            );
          });
        },
        onPanEnd: (_) {
          _snapToNearestEdge(
            screenSize: screenSize,
            safePadding: safePadding,
            widgetWidth: widgetWidth,
            widgetHeight: widgetHeight,
            disableAnimations: disableAnimations,
          );
        },
        onTap: () => widget.callState.restore(),
        child: MouseRegion(
          // Desktop affordance: tapping the floating widget restores full-screen
          // call. Show the click cursor so the interaction reads as a button.
          cursor: SystemMouseCursors.click,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(AppRadii.card),
            color: _kFloatingCallBg,
            child: SizedBox(
              width: widgetWidth,
              height: widgetHeight,
              child: Stack(
                children: [
                  CallCompactCard(
                    key: const ValueKey('floating-call-card'),
                    title: name,
                    subtitle: subtitle,
                    leading: CallUserAvatar(
                      userId: cs.remoteUserID,
                      name: name,
                      radius: widgetHeight * 0.3,
                      fontSize: widgetHeight * 0.25,
                    ),
                    onHangUp: widget.manager.hangUp,
                  ),
                  // Drag-handle pip: small slate-400 bar at top-center signals
                  // "this is draggable" without competing with the content.
                  const Positioned(
                    top: 4,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(child: _FloatingDragPip()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 24×3 slate-400 bar centered above the floating-call card content. Pure
/// affordance — never receives pointer events (parent wraps in IgnorePointer).
class _FloatingDragPip extends StatelessWidget {
  const _FloatingDragPip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 3,
      decoration: BoxDecoration(
        color: _kFloatingDragPipColor,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}
