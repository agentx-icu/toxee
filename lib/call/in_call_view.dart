import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import '../i18n/app_localizations.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import 'call_audio_platform.dart';
import 'call_state_notifier.dart';
import 'call_media_capabilities.dart';
import 'call_ui_shell.dart';
import 'call_ui_components.dart';
import 'in_call_manager.dart';

/// Full-screen in-call UI using shared shell: top bar, video/identity stage, action dock.
class InCallView extends StatelessWidget {
  const InCallView({
    super.key,
    required this.callState,
    required this.manager,
  });

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
      CallQuality.medium => const Color(0xFFF59E0B), // amber-500
      CallQuality.poor => AppThemeConfig.errorColor,
      CallQuality.unknown => const Color(0xFF94A3B8),
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
            borderRadius:
                BorderRadius.circular(AppThemeConfig.badgeBorderRadius),
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
      BuildContext context, AppLocalizations l10n, bool isVideo) {
    final showSpeakerToggle = CallMediaCapabilities.supportsSpeakerToggle();
    final actions = <CallDockAction>[
      CallDockAction(
        icon: callState.isMuted ? Icons.mic_off : Icons.mic,
        label: callState.isMuted ? l10n.callUnmute : l10n.callMute,
        selected: callState.isMuted,
        onPressed: () => manager.toggleMute(),
      ),
      if (isVideo)
        CallDockAction(
          icon: callState.isVideoEnabled ? Icons.videocam : Icons.videocam_off,
          label:
              callState.isVideoEnabled ? l10n.callVideoOff : l10n.callVideoOn,
          selected: !callState.isVideoEnabled,
          onPressed: () => manager.toggleVideo(),
        ),
      if (!showSpeakerToggle &&
          CallMediaCapabilities.supportsAudioRouteSelection())
        CallDockAction(
          icon: Icons.route,
          label: l10n.routeSelection,
          onPressed: () => _showAudioRouteSheet(context, l10n),
        ),
      CallDockAction(
        icon: Icons.call_end,
        label: l10n.callHangUp,
        destructive: true,
        onPressed: () => manager.hangUp(),
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
          top: Radius.circular(AppThemeConfig.formCardBorderRadius),
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
                        : theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                  ),
                  title: Text(
                    route.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: route.selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                      fontWeight:
                          route.selected ? FontWeight.w600 : FontWeight.w400,
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
                    Navigator.of(ctx).pop();
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
                  style: const TextStyle(color: Colors.white54),
                ),
              );
        // Pure-black video pane with top + bottom legibility gradients so the
        // overlaid controls stay readable against bright frames.
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            content,
            // Top scrim under the status bar.
            IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
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
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
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
        return Positioned(
          top: AppSpacing.lg,
          right: AppSpacing.lg,
          child: KeyedSubtree(
            key: const ValueKey('call-local-preview-card'),
            child: Container(
              width: previewWidth,
              height: previewHeight,
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(AppThemeConfig.cardBorderRadius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: preview ??
                  const ColoredBox(
                    color: Color(0xFF1E293B), // slate-800 placeholder
                  ),
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
        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
