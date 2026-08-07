import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../ui/testing/ui_keys.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import '../util/responsive_layout.dart';
import 'av_conference_session_controller.dart';
import 'call_ui_components.dart';
import 'call_ui_shell.dart';

const Color _kCallForeground = Color(0xFFE2E8F0);
const Color _kCallMutedForeground = Color(0xFF94A3B8);
const Color _kCallAmberAccent = Color(0xFFF59E0B);

class AvConferenceHeaderAction extends StatelessWidget {
  const AvConferenceHeaderAction({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.enabled = true,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: UiKeys.avConferenceJoinButton,
      tooltip: tooltip,
      icon: const Icon(Icons.headset_mic_outlined),
      onPressed: enabled ? onPressed : null,
    );
  }
}

class AvConferenceSessionPage extends StatefulWidget {
  const AvConferenceSessionPage({super.key, required this.controller});

  final AvConferenceSessionController controller;

  @override
  State<AvConferenceSessionPage> createState() =>
      _AvConferenceSessionPageState();
}

class _AvConferenceSessionPageState extends State<AvConferenceSessionPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.join());
  }

  @override
  void dispose() {
    unawaited(widget.controller.disposeSession());
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: kCallBackgroundBase,
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final session = widget.controller.session;
          final status = _statusForSession(l10n, session);
          return CallSceneShell(
            topBar: CallTopStatusBar(
              title: session.displayName,
              subtitle: session.groupId,
              trailingIcon: Icons.close,
              trailingActionTooltip: l10n.callHangUp,
              onTrailingPressed: () {
                unawaited(_leaveAndPop());
              },
            ),
            bottomBar: CallActionDock(
              actions: <CallDockAction>[
                CallDockAction(
                  key: UiKeys.avConferenceMuteButton,
                  icon: session.isMuted ? Icons.mic_off : Icons.mic,
                  label: session.isMuted ? l10n.callUnmute : l10n.callMute,
                  selected: session.isMuted,
                  enabled:
                      session.lifecycle == AvConferenceSessionLifecycle.active,
                  onPressed: () async {
                    await widget.controller.toggleMuted();
                  },
                ),
                _audioActionForSession(l10n, session),
                CallDockAction(
                  key: UiKeys.avConferenceLeaveButton,
                  icon: Icons.call_end,
                  label: l10n.callHangUp,
                  destructive: true,
                  enabled: !_isTerminal(session.lifecycle),
                  onPressed: () async {
                    await _leaveAndPop();
                  },
                ),
              ],
            ),
            child: _SessionStage(
              session: session,
              status: status,
              frameCountLabel: l10n.callReceivedFrames(
                session.receivedFrameCount,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _leaveAndPop() async {
    await widget.controller.leave();
    if (mounted) {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  CallDockAction _audioActionForSession(
    AppLocalizations l10n,
    AvConferenceSession session,
  ) {
    final lifecycle = session.lifecycle;
    if (lifecycle == AvConferenceSessionLifecycle.failed) {
      return CallDockAction(
        key: UiKeys.avConferenceEnableButton,
        icon: Icons.refresh_rounded,
        label: l10n.retry,
        affirmative: true,
        onPressed: () async {
          await widget.controller.join();
        },
      );
    }
    if (lifecycle == AvConferenceSessionLifecycle.active) {
      return CallDockAction(
        key: UiKeys.avConferenceEnableButton,
        icon: Icons.hearing_disabled,
        label: l10n.disable,
        onPressed: () async {
          await widget.controller.setEnabled(false);
        },
      );
    }
    final canJoin =
        lifecycle == AvConferenceSessionLifecycle.idle ||
        lifecycle == AvConferenceSessionLifecycle.disabled;
    return CallDockAction(
      key: UiKeys.avConferenceEnableButton,
      icon: canJoin ? Icons.hearing : Icons.hearing_disabled,
      label: canJoin ? l10n.join : l10n.audio,
      enabled: canJoin,
      onPressed: canJoin
          ? () async {
              await widget.controller.join();
            }
          : null,
    );
  }

  _SessionStatus _statusForSession(
    AppLocalizations l10n,
    AvConferenceSession session,
  ) {
    switch (session.lifecycle) {
      case AvConferenceSessionLifecycle.joining:
        return _SessionStatus(
          label: l10n.callCalling,
          icon: Icons.hourglass_top_rounded,
          accent: AppThemeConfig.statusConnectingColor,
        );
      case AvConferenceSessionLifecycle.active:
        return _SessionStatus(
          label: session.isMuted ? l10n.callMute : l10n.audio,
          icon: session.isMuted ? Icons.mic_off : Icons.graphic_eq_rounded,
          accent: session.isMuted
              ? _kCallAmberAccent
              : AppThemeConfig.successColor,
        );
      case AvConferenceSessionLifecycle.disabled:
        return _SessionStatus(
          label: l10n.disable,
          icon: Icons.hearing_disabled_rounded,
          accent: _kCallAmberAccent,
        );
      case AvConferenceSessionLifecycle.failed:
        return _SessionStatus(
          label: l10n.failed,
          detail: switch (session.failure) {
            AvConferenceSessionFailure.join => l10n.joinFailed,
            AvConferenceSessionFailure.mute ||
            AvConferenceSessionFailure.disable => l10n.callFailedSignaling,
            null => l10n.failed,
          },
          icon: Icons.error_outline_rounded,
          accent: AppThemeConfig.errorColor,
        );
      case AvConferenceSessionLifecycle.closing:
        return _SessionStatus(
          label: l10n.callLeaving,
          icon: Icons.logout_rounded,
          accent: _kCallAmberAccent,
        );
      case AvConferenceSessionLifecycle.left:
      case AvConferenceSessionLifecycle.disposed:
        return _SessionStatus(
          label: l10n.callEnded,
          icon: Icons.call_end_rounded,
          accent: _kCallMutedForeground,
        );
      case AvConferenceSessionLifecycle.idle:
        return _SessionStatus(
          label: l10n.audio,
          icon: Icons.headset_mic_outlined,
          accent: _kCallMutedForeground,
        );
    }
  }

  bool _isTerminal(AvConferenceSessionLifecycle lifecycle) {
    return lifecycle == AvConferenceSessionLifecycle.closing ||
        lifecycle == AvConferenceSessionLifecycle.left ||
        lifecycle == AvConferenceSessionLifecycle.disposed;
  }
}

class _SessionStage extends StatelessWidget {
  const _SessionStage({
    required this.session,
    required this.status,
    required this.frameCountLabel,
  });

  final AvConferenceSession session;
  final _SessionStatus status;
  final String frameCountLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final horizontalPadding = ResponsiveLayout.responsiveHorizontalPadding(
      context,
    );

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CallUserAvatar(
              name: session.displayName,
              radius: ResponsiveLayout.responsiveValue<double>(
                context,
                mobile: 56,
                tablet: 64,
                desktop: 72,
              ),
              fontSize: ResponsiveLayout.responsiveValue<double>(
                context,
                mobile: 28,
                tablet: 32,
                desktop: 36,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SessionStatusBadge(status: status),
            const SizedBox(height: AppSpacing.lg),
            Text(
              session.displayName,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                color: _kCallForeground,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            if (status.detail != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                status.detail!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: _kCallMutedForeground,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Semantics(
              label: frameCountLabel,
              child: ExcludeSemantics(
                child: Text(
                  frameCountLabel,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: _kCallMutedForeground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionStatusBadge extends StatelessWidget {
  const _SessionStatusBadge({required this.status});

  final _SessionStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: status.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppThemeConfig.badgeBorderRadius),
        border: Border.all(color: status.accent.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, color: status.accent, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: status.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionStatus {
  const _SessionStatus({
    required this.label,
    required this.icon,
    required this.accent,
    this.detail,
  });

  final String label;
  final String? detail;
  final IconData icon;
  final Color accent;
}
