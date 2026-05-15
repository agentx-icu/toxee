import 'package:flutter/material.dart';
import '../i18n/app_localizations.dart';
import '../util/app_theme_config.dart';
import '../util/responsive_layout.dart';
import 'call_state_notifier.dart';
import 'ringing_call_manager.dart';
import 'call_ui_components.dart';

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

class _CallFloatingWidgetState extends State<CallFloatingWidget> {
  late Offset _position;

  @override
  void initState() {
    super.initState();
    _position = widget.callState.floatingPosition;
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screenSize = MediaQuery.sizeOf(context);
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

    final clampedX = _position.dx.clamp(0.0, screenSize.width - widgetWidth);
    final clampedY = _position.dy.clamp(0.0, screenSize.height - widgetHeight);

    return Positioned(
      left: clampedX,
      top: clampedY,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx)
                  .clamp(0.0, screenSize.width - widgetWidth),
              (_position.dy + details.delta.dy)
                  .clamp(0.0, screenSize.height - widgetHeight),
            );
          });
        },
        onPanEnd: (_) => widget.callState.updateFloatingPosition(_position),
        onTap: () => widget.callState.restore(),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          color: AppThemeConfig.darkGradientEnd,
          child: SizedBox(
            width: widgetWidth,
            height: widgetHeight,
            child: CallCompactCard(
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
          ),
        ),
      ),
    );
  }
}
