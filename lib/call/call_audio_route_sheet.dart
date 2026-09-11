import 'package:flutter/material.dart';
import '../i18n/app_localizations.dart';
import '../ui/testing/ui_keys.dart';
import '../ui/widgets/safe_dialog_pop.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import 'call_audio_platform.dart';
import 'call_state_notifier.dart';
import 'in_call_manager.dart';

/// Slate-700 / slate-300 drag handle colours for the route picker sheet.
const Color _kCallSheetHandleDark = Color(0xFF334155);
const Color _kCallSheetHandleLight = Color(0xFFCBD5E1);

/// Scrim behind the in-overlay sheet (same weight as the modal barrier).
const Color _kCallSheetBarrier = Colors.black54;

/// Opens the audio-route picker for the active call.
///
/// The in-call view is mounted from `MaterialApp.builder`, ABOVE the app
/// Navigator, so there is no Navigator ancestor to push a bottom-sheet route
/// on — and a route pushed through the app navigator would paint BEHIND the
/// opaque call surface. So when no Navigator is available the sheet is hosted
/// as an entry in the call's own [Overlay] (entries inserted later paint on
/// top of the call view). With a Navigator (tests that pump the view under
/// `MaterialApp(home:)`) the standard modal sheet is used.
///
/// The overlay-hosted sheet is not a route, so back/minimize would not pop
/// it: pass [callState] and it closes itself as soon as the call is
/// minimized or leaves the in-call states.
void showCallAudioRouteSheet(
  BuildContext context,
  InCallManager manager,
  AppLocalizations l10n, {
  CallStateNotifier? callState,
}) {
  final state = manager.audioState.value;
  if (!state.canSelectRoutes) return;

  if (Navigator.maybeOf(context) != null) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
      ),
      builder: (ctx) => _RouteSheetBody(
        state: state,
        manager: manager,
        l10n: l10n,
        close: () => popDialogIfCurrent(ctx),
      ),
    );
    return;
  }

  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  var closed = false;
  void close() {
    if (closed) return;
    closed = true;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (ctx) => _CallOverlaySheet(
      onDismiss: close,
      callState: callState,
      child: _RouteSheetBody(
        state: state,
        manager: manager,
        l10n: l10n,
        close: close,
      ),
    ),
  );
  overlay.insert(entry);
}

/// Modal-sheet chrome for an [Overlay]-hosted sheet: dismissible scrim plus a
/// bottom-anchored surface with the same shape as the Navigator-backed sheet.
class _CallOverlaySheet extends StatefulWidget {
  const _CallOverlaySheet({
    required this.onDismiss,
    required this.child,
    this.callState,
  });

  final VoidCallback onDismiss;
  final Widget child;
  final CallStateNotifier? callState;

  @override
  State<_CallOverlaySheet> createState() => _CallOverlaySheetState();
}

class _CallOverlaySheetState extends State<_CallOverlaySheet> {
  @override
  void initState() {
    super.initState();
    widget.callState?.addListener(_onCallStateChanged);
  }

  @override
  void dispose() {
    widget.callState?.removeListener(_onCallStateChanged);
    super.dispose();
  }

  void _onCallStateChanged() {
    final s = widget.callState;
    if (s == null) return;
    final live = s.state == CallUIState.inCall ||
        s.state == CallUIState.reconnecting;
    if (s.isMinimized || !live) {
      // Deferred: the notifier may fire mid-build, and removing an overlay
      // entry during build is not allowed.
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDismiss());
    }
  }

  @override
  Widget build(BuildContext context) {
    final onDismiss = widget.onDismiss;
    final child = widget.child;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('call-audio-route-barrier'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: _kCallSheetBarrier),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(top: false, child: child),
          ),
        ),
      ],
    );
  }
}

class _RouteSheetBody extends StatelessWidget {
  const _RouteSheetBody({
    required this.state,
    required this.manager,
    required this.l10n,
    required this.close,
  });

  final CallAudioState state;
  final InCallManager manager;
  final AppLocalizations l10n;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
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
          // Many Bluetooth devices or large text can exceed a landscape
          // phone's height; the route list scrolls inside the sheet.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              children: [
                for (final route in state.routes)
                  ListTile(
                    // toxee automation anchor: lets a case pick a SPECIFIC
                    // route deterministically instead of tapping by label.
                    key: UiKeys.callAudioRouteOption(route.id),
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
                      close();
                      await manager.selectAudioRoute(route.id);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
