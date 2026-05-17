import 'package:flutter/material.dart';
import '../i18n/app_localizations.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import 'call_state_notifier.dart';
import 'call_overlay_manager.dart';
import 'call_floating_widget.dart';
import 'incoming_call_view.dart';
import 'outgoing_call_view.dart';
import 'in_call_view.dart';

/// Full-screen call overlay that shows incoming, in-call, or ended UI on top of [child].
class CallOverlay extends StatelessWidget {
  const CallOverlay({
    super.key,
    required this.callState,
    required this.manager,
    required this.child,
  });

  final CallStateNotifier callState;
  final CallOverlayManager manager;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: callState,
      builder: (context, _) {
        if (callState.state == CallUIState.idle) return child;

        // Minimized: show floating widget, child is fully interactive
        if (callState.isMinimized &&
            (callState.state == CallUIState.ringing ||
             callState.state == CallUIState.inCall)) {
          return Stack(
            children: [
              child,
              _CallOverlayHost(
                child: _NoUnderlineScope(
                  child:
                      CallFloatingWidget(callState: callState, manager: manager),
                ),
              ),
            ],
          );
        }

        // Full-screen call views
        return Stack(
          children: [
            child,
            _CallOverlayHost(
              child: _NoUnderlineScope(
                // Asymmetric in/out timing matches Flutter's recommended
                // pattern: a slightly slower entrance feels deliberate while a
                // snappier exit keeps the next view from feeling stuck. The
                // explicit FadeTransition replaces the implicit cross-fade.
                child: Builder(
                  builder: (innerCtx) {
                    final reduceMotion =
                        MediaQuery.maybeDisableAnimationsOf(innerCtx) == true;
                    return AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      reverseDuration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: _buildCallView(),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCallView() {
    switch (callState.state) {
      case CallUIState.ringing:
        return callState.direction == CallDirection.incoming
            ? IncomingCallView(key: const ValueKey('incoming'), callState: callState, manager: manager)
            : OutgoingCallView(key: const ValueKey('outgoing'), callState: callState, manager: manager);
      case CallUIState.inCall:
        return InCallView(key: const ValueKey('inCall'), callState: callState, manager: manager);
      case CallUIState.ended:
        return _CallEndedView(key: const ValueKey('ended'), callState: callState);
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Hosts the call UI in its own [Overlay] so descendants that depend on an
/// Overlay ancestor (Tooltip, PopupMenu, SelectionToolbar) work even though
/// [CallOverlay] is mounted in the MaterialApp `builder` — above the
/// app Navigator's Overlay.
class _CallOverlayHost extends StatelessWidget {
  const _CallOverlayHost({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(builder: (_) => child),
      ],
    );
  }
}

/// Wraps call UI so inherited text style does not show underline (e.g. from theme).
class _NoUnderlineScope extends StatelessWidget {
  const _NoUnderlineScope({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.copyWith(
      decoration: TextDecoration.none,
      decorationColor: null,
      decorationStyle: null,
    );
    return DefaultTextStyle(style: style, child: child);
  }
}

/// Brief "call ended" affordance that surfaces after `endCall()` and auto-clears
/// in ~2s (see `CallStateNotifier`). Rendered as a centered toast-style card
/// over a dimmed scrim — hairline border + cardBorderRadius matches the rest
/// of the messenger refresh, errorColor accent communicates the terminal state.
class _CallEndedView extends StatelessWidget {
  const _CallEndedView({super.key, required this.callState});

  final CallStateNotifier callState;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: AppThemeConfig.darkScaffoldBackground,
              borderRadius:
                  BorderRadius.circular(AppThemeConfig.cardBorderRadius),
              border: Border.all(
                color: AppThemeConfig.errorColor.withValues(alpha: 0.4),
              ),
              boxShadow: AppThemeConfig.elevationDark,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.call_end,
                  color: AppThemeConfig.errorColor,
                  size: 20,
                ),
                AppSpacing.horizontalMd,
                Flexible(
                  child: Text(
                    l10n.callEnded,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          color: AppThemeConfig.primaryTextColorDark,
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
