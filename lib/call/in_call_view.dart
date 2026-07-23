import 'dart:async';

// ignore: directives_ordering
import '../ui/widgets/safe_dialog_pop.dart';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../i18n/app_localizations.dart';
import '../ui/testing/ui_keys.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import 'call_audio_platform.dart';
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

/// Slate-700 (bottom-sheet drag handle in dark — matches the global sheet
/// handle but locked to dark since call sheets are dark-only).
const Color _kCallSheetHandleDark = Color(0xFF334155);

/// Slate-300 (bottom-sheet drag handle in light — only reachable from the
/// system-light theme variant of audio-route picker).
const Color _kCallSheetHandleLight = Color(0xFFCBD5E1);

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
    return CallSceneShell(
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
          icon: Icons.route,
          label: l10n.routeSelection,
          onPressed: () => _showAudioRouteSheet(context, l10n),
        )
      else if (!showSpeakerToggle && !supportsRouteSelection)
        // Desktop (and other platforms where the OS owns the audio route):
        // surface the affordance as *disabled* with a tooltip explaining that
        // routing is managed by the system, so users aren't left wondering
        // whether the app is missing a feature.
        CallDockAction(
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

  void _showAudioRouteSheet(BuildContext context, AppLocalizations l10n) {
    final state = manager.audioState.value;
    if (!state.canSelectRoutes) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _CallSheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.routeSelection,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              for (final route in state.routes)
                ListTile(
                  leading: Icon(
                    _iconForRoute(route.kind),
                    color: route.selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  title: Text(
                    route.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: route.selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                      fontWeight: route.selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: route.selected
                      ? Icon(
                          Icons.check,
                          size: 20,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  onTap: () async {
                    popDialogIfCurrent(ctx);
                    await manager.selectAudioRoute(route.id);
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForRoute(CallAudioRouteKind? kind) {
    switch (kind) {
      case CallAudioRouteKind.speaker:
        return Icons.speaker_phone;
      case CallAudioRouteKind.bluetooth:
        return Icons.bluetooth_audio;
      case CallAudioRouteKind.wired:
        return Icons.headset;
      case CallAudioRouteKind.earpiece:
        return Icons.phone_in_talk;
      case CallAudioRouteKind.unknown:
      case null:
        return Icons.route;
    }
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
        // overlaid controls stay readable against bright frames.
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
                  height: _kCallScrimTopHeight,
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
                  height: _kCallScrimBottomHeight,
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
        // Offset by the system safe-area top so the preview card clears
        // notch / Dynamic Island when an ancestor hasn't already absorbed it.
        final topInset = MediaQuery.paddingOf(context).top;
        return Positioned(
          top: AppSpacing.lg + topInset,
          right: AppSpacing.lg,
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

/// 32×4 drag handle for call-screen bottom sheets. Matches the global
/// `_BottomSheetHandle` used in `login_page.dart`.
class _CallSheetHandle extends StatelessWidget {
  const _CallSheetHandle();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 32,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? _kCallSheetHandleDark : _kCallSheetHandleLight,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
