import 'dart:async';

// ignore: directives_ordering
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../i18n/app_localizations.dart';
import '../ui/testing/ui_keys.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import '../util/responsive_layout.dart';
import 'call_audio_route_sheet.dart';
import 'call_state_notifier.dart';
import 'call_media_capabilities.dart';
import 'call_ui_shell.dart';
import 'call_ui_components.dart';
import 'in_call_manager.dart';

// ──────────────────────────────────────────────
//  Call surface palette (INTENTIONALLY hardcoded)
// ──────────────────────────────────────────────
//
// The in-call UI is dark-mode-only by industry convention — calls always render
// against a dark backdrop regardless of the system theme so users don't get
// blinded mid-call. That means we do NOT pull from `Theme.of(context)`; we keep
// a small, stable palette right here so the surface stays cohesive.
//
// Do NOT "fix" this by making it theme-aware. If you want to tweak the look,
// adjust the constants below — every call-surface tint should flow from them.

/// Pure-black video stage backdrop.
const Color _kCallStageBg = Colors.black;

/// Slate-800 placeholder when local preview hasn't bound a frame yet.
const Color _kCallLocalPreviewPlaceholder = Color(0xFF1E293B);

/// Amber-500 (quality "medium" chip accent). Shared with the design system
/// elsewhere as the away/warning hue, but the call surface keeps its own
/// constant so we don't accidentally inherit theme-aware variations.
const Color _kCallAmberAccent = Color(0xFFF59E0B);

/// Slate-400 (quality "unknown" chip accent, sheet copy de-emphasis).
const Color _kCallSlate400 = Color(0xFF94A3B8);

/// Legibility scrim color over remote video. 55% black at the top under the
/// status bar and at the bottom under the action dock keeps the overlaid
/// controls readable against bright frames.
const Color _kCallScrim = Colors.black;
const double _kCallScrimAlpha = 0.55;
const double _kCallScrimTopHeight = 88;
const double _kCallScrimBottomHeight = 120;

/// Local-preview PiP card border — white @ 18% alpha. Subtle hairline so the
/// card edge reads on bright or dark remote frames.
const Color _kCallLocalPreviewBorder = Colors.white;
const double _kCallLocalPreviewBorderAlpha = 0.18;

/// Remote-video placeholder copy color (white @ 54%).
const Color _kCallRemoteVideoFallbackText = Colors.white54;

/// Drop shadow for the floating local-preview (PiP) card on the call surface.
/// Named so other call-surface PiP-style cards can share the same elevation.
const List<BoxShadow> kCallPipShadow = [
  BoxShadow(
    color: Color(0x73000000), // Colors.black @ 0.45 alpha
    blurRadius: 16,
    offset: Offset(0, 4),
  ),
];

/// Full-screen in-call UI using shared shell: top bar, video/identity stage, action dock.
class InCallView extends StatelessWidget {
  const InCallView({super.key, required this.callState, required this.manager});

  final CallStateNotifier callState;
  final InCallManager manager;

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name =
        callState.remoteNickname ?? callState.remoteUserID ?? l10n.unknown;
    final isVideo = callState.mode == CallMode.video;
    final screenSize = MediaQuery.sizeOf(context);
    final shortSide = min(screenSize.width, screenSize.height);
    final avatarRadius = (shortSide * 0.12).clamp(36.0, 80.0);
    final avatarFontSize = avatarRadius * 0.8;

    // Back-button handling: the outer PopScope in `call_overlay.dart` owns
    // the back gesture for every call-state surface (single source of truth)
    // and routes back into minimize() for inCall + reconnecting. Hang-up
    // remains an explicit user action via the call_end button in the dock.
    // Video floats the bars over an edge-to-edge stage; audio uses the Column
    // shell so the identity block can never sit under the dock (see shell).
    // On phones the five video actions (5×80 + 4×16 = 464 px) wrap to two
    // rows over the remote frame, so the dock drops its labels there.
    final compactDock = isVideo && ResponsiveLayout.isMobile(context);
    return CallSceneShell(
      overlayBars: isVideo,
      topBar: CallTopStatusBar(
        key: const ValueKey('call-top-bar'),
        title: name,
        subtitle: _formatDuration(callState.callDuration),
        qualityIndicator: _buildQualityIndicator(context, l10n),
        trailingIcon: Icons.picture_in_picture_alt,
        onTrailingPressed: () => callState.minimize(),
      ),
      bottomBar: CallActionDock(
        key: const ValueKey('call-action-dock'),
        actions: _buildDockActions(context, l10n, isVideo),
        showLabels: !compactDock,
      ),
      child: isVideo
          ? CallVideoStage(
              remoteContent: _buildRemoteContent(l10n),
              localPreviewCard: _buildLocalPreviewCard(l10n, shortSide),
            )
          : CallIdentityStage(
              avatar: _buildAvatar(name, avatarRadius, avatarFontSize),
              title: name,
              subtitle: _formatDuration(callState.callDuration),
            ),
    );
  }

  Widget? _buildQualityIndicator(BuildContext context, AppLocalizations l10n) {
    final quality = callState.callQuality;
    if (quality == CallQuality.unknown) return null;
    final label = switch (quality) {
      CallQuality.good => l10n.callQualityGood,
      CallQuality.medium => l10n.callQualityMedium,
      CallQuality.poor => l10n.callQualityPoor,
      CallQuality.unknown => null,
    };
    if (label == null) return null;
    // Semantic colors: emerald success / amber medium / red poor. Sits on the
    // dark slate-900 call surface so we tint @ 0.16 for the chip background.
    final Color accent = switch (quality) {
      CallQuality.good => AppThemeConfig.successColor,
      CallQuality.medium => _kCallAmberAccent,
      CallQuality.poor => AppThemeConfig.errorColor,
      CallQuality.unknown => _kCallSlate400,
    };
    return Semantics(
      label: l10n.callQualityLabel,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(
              AppThemeConfig.badgeBorderRadius,
            ),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  List<CallDockAction> _buildDockActions(
    BuildContext context,
    AppLocalizations l10n,
    bool isVideo,
  ) {
    final showSpeakerToggle = CallMediaCapabilities.supportsSpeakerToggle();
    final supportsRouteSelection =
        CallMediaCapabilities.supportsAudioRouteSelection();
    final actions = <CallDockAction>[
      CallDockAction(
        key: UiKeys.callMicMuteButton,
        icon: callState.isMuted ? Icons.mic_off : Icons.mic,
        label: callState.isMuted ? l10n.callUnmute : l10n.callMute,
        selected: callState.isMuted,
        onPressed: () async => manager.toggleMute(),
      ),
      if (isVideo)
        CallDockAction(
          key: UiKeys.callCameraToggleButton,
          icon: callState.isVideoEnabled ? Icons.videocam : Icons.videocam_off,
          label: callState.isVideoEnabled
              ? l10n.callVideoOff
              : l10n.callVideoOn,
          selected: !callState.isVideoEnabled,
          onPressed: () async => manager.toggleVideo(),
        ),
      if (isVideo &&
          callState.isVideoEnabled &&
          CallMediaCapabilities.supportsCameraSwitch())
        CallDockAction(
          key: UiKeys.callCameraSwitchButton,
          icon: Icons.cameraswitch,
          label: l10n.callSwitchCamera,
          onPressed: () async => manager.switchCamera(),
        ),
      if (!showSpeakerToggle && supportsRouteSelection)
        CallDockAction(
          key: UiKeys.callAudioRouteButton,
          icon: Icons.route,
          label: l10n.routeSelection,
          onPressed: () => showCallAudioRouteSheet(
            context,
            manager,
            l10n,
            callState: callState,
          ),
        )
      else if (!showSpeakerToggle && !supportsRouteSelection)
        // Desktop (and other platforms where the OS owns the audio route):
        // surface the affordance as *disabled* with a tooltip explaining that
        // routing is managed by the system, so users aren't left wondering
        // whether the app is missing a feature.
        CallDockAction(
          key: UiKeys.callAudioRouteButton,
          icon: Icons.route,
          label: l10n.routeSelection,
          enabled: false,
          tooltip: l10n.callAudioRouteSystem,
        ),
      CallDockAction(
        key: UiKeys.callHangupButton,
        icon: Icons.call_end,
        label: l10n.callHangUp,
        destructive: true,
        onPressed: () async {
          unawaited(HapticFeedback.lightImpact());
          await manager.hangUp();
        },
      ),
    ];
    return actions;
  }

  Widget _buildRemoteContent(AppLocalizations l10n) {
    return ValueListenableBuilder<ui.Image?>(
      valueListenable: manager.remoteVideo,
      builder: (context, image, _) {
        final Widget content = image != null
            ? RawImage(image: image, fit: BoxFit.contain)
            : Center(
                child: Text(
                  l10n.callRemoteVideo,
                  style: const TextStyle(color: _kCallRemoteVideoFallbackText),
                ),
              );
        // Pure-black video pane with top + bottom legibility gradients so the
        // overlaid controls stay readable against bright frames. The stage is
        // edge-to-edge, so each scrim also spans the system inset behind the
        // floating bar it backs.
        final insets = MediaQuery.paddingOf(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _kCallStageBg),
            content,
            // Top scrim under the status bar.
            IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: _kCallScrimTopHeight + insets.top,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _kCallScrim.withValues(alpha: _kCallScrimAlpha),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Bottom scrim under the action dock.
            IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: _kCallScrimBottomHeight + insets.bottom,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        _kCallScrim.withValues(alpha: _kCallScrimAlpha),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget? _buildLocalPreviewCard(AppLocalizations l10n, double shortSide) {
    final previewWidth = (shortSide * 0.35).clamp(120.0, 280.0);
    final previewHeight = previewWidth * 4 / 3;
    return ListenableBuilder(
      listenable: manager.previewListenable,
      builder: (context, _) {
        final preview = manager.localPreview;
        // The video stage is edge-to-edge (overlayBars), so clear BOTH the
        // system inset and the floating top bar here — exactly once.
        final topInset = MediaQuery.paddingOf(context).top +
            CallSceneShell.topBarHeight(context);
        return Positioned(
          top: AppSpacing.lg + topInset,
          // Edge-to-edge stage: keep clear of a landscape notch on the right.
          right: AppSpacing.lg + MediaQuery.paddingOf(context).right,
          child: KeyedSubtree(
            key: const ValueKey('call-local-preview-card'),
            child: Container(
              width: previewWidth,
              height: previewHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(
                  color: _kCallLocalPreviewBorder.withValues(
                    alpha: _kCallLocalPreviewBorderAlpha,
                  ),
                ),
                boxShadow: kCallPipShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child:
                  preview ??
                  const ColoredBox(color: _kCallLocalPreviewPlaceholder),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(String name, double radius, double fontSize) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          // Subtle primary-tinted halo — replaces the generic blue glow with the
          // brand blue-500 token at the same low intensity.
          BoxShadow(
            color: AppThemeConfig.primaryColorDark.withValues(alpha: 0.18),
            blurRadius: 32,
            spreadRadius: 6,
          ),
        ],
      ),
      child: CallUserAvatar(
        userId: callState.remoteUserID,
        name: name,
        radius: radius,
        fontSize: fontSize,
      ),
    );
  }
}
