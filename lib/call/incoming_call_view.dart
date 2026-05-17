import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../i18n/app_localizations.dart';
import 'call_state_notifier.dart';
import 'ringing_call_manager.dart';
import 'call_ui_components.dart';

/// Full-screen incoming call UI using shared shell: identity stage and reject/accept actions.
class IncomingCallView extends StatelessWidget {
  const IncomingCallView({
    super.key,
    required this.callState,
    required this.manager,
  });

  final CallStateNotifier callState;
  final RingingCallManager manager;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name =
        callState.remoteNickname ?? callState.remoteUserID ?? l10n.unknown;
    final isVideo = callState.mode == CallMode.video;
    final screenSize = MediaQuery.sizeOf(context);
    final shortSide = min(screenSize.width, screenSize.height);
    final avatarRadius = (shortSide * 0.11).clamp(36.0, 72.0);
    final avatarFontSize = avatarRadius * 0.8;
    final callTypeSubtitle = isVideo ? l10n.callVideoCall : l10n.callAudioCall;

    return RingingCallScene(
      userId: callState.remoteUserID,
      name: name,
      primarySubtitle: callTypeSubtitle,
      onMinimize: callState.minimize,
      avatarRadius: avatarRadius,
      avatarFontSize: avatarFontSize,
      bottomBar: CallActionDock(
        key: const ValueKey('incoming-call-actions'),
        actions: [
          CallDockAction(
            icon: Icons.call_end,
            label: l10n.callReject,
            destructive: true,
            onPressed: () {
              unawaited(HapticFeedback.lightImpact());
              manager.rejectCall();
            },
          ),
          CallDockAction(
            icon: Icons.call,
            label: l10n.callAccept,
            affirmative: true,
            onPressed: () {
              unawaited(HapticFeedback.mediumImpact());
              manager.acceptCall();
            },
          ),
        ],
      ),
    );
  }
}
