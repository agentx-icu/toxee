import 'package:flutter/material.dart';

import '../../util/app_spacing.dart';
import '../../util/bootstrap_node_probe.dart';

/// How a [BootstrapProbeVerdict] is presented in the bootstrap settings UI.
///
/// Split out of `bootstrap_settings_section.dart` (which is at its
/// `tool/.complexity_baseline.txt` pin) along a real seam: this is the
/// verdict -> presentation mapping plus the badge that renders it, with no
/// knowledge of the settings layout around it.
class BootstrapVerdictUi {
  BootstrapVerdictUi._();

  /// Collapses a verdict to the string the section stores as its result state.
  ///
  /// `udpUnavailable` deliberately does NOT become 'failed'. The probe proved
  /// nothing about the node in that case, so rendering a negative verdict would
  /// blame a good node for a local network constraint — the same class of lie
  /// the real probe exists to remove.
  static String resultFor(BootstrapProbeVerdict v) => switch (v) {
    BootstrapProbeVerdict.reachable => 'success',
    BootstrapProbeVerdict.udpUnavailable => 'udp',
    _ => 'failed',
  };

  /// Result state for a probe that could not be *performed* at all, i.e. a
  /// caught [BootstrapProbeUnavailable].
  ///
  /// Kept distinct from 'failed' for the same reason `udpUnavailable` is: the
  /// probe instance failing to start is OUR defect, and rendering it as "node
  /// unreachable" blames the user's node for our bug (see
  /// [BootstrapProbeUnavailable]'s own doc comment).
  static const String unavailableResult = 'unavailable';

  /// Whether a result is a real negative *about the node*. Only 'failed' is —
  /// 'udp' and 'unavailable' both mean the probe never produced a verdict.
  static bool isNegative(String? result) => result == 'failed';

  /// Whether a result permits promoting the node to "current": proven
  /// reachable, or untestable here (UDP-less device / probe unavailable) —
  /// never a real negative. A TCP-only client still needs bootstrap nodes, so
  /// it must stay able to pick one.
  static bool promotable(String? result) =>
      result == 'success' || result == 'udp' || result == unavailableResult;

  /// The snackbar shown right after a manual node probe.
  ///
  /// Same verdict->presentation ownership as [pillFor]; it lived inline in the
  /// settings section as a THIRD hand-maintained copy of the same switch.
  static SnackBar snackBarFor(
    BuildContext context,
    BootstrapProbeVerdict verdict, {
    required String successLabel,
    required String udpLabel,
    required String failedLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SnackBar(
      content: Text(switch (verdict) {
        BootstrapProbeVerdict.reachable => successLabel,
        BootstrapProbeVerdict.udpUnavailable => udpLabel,
        _ => failedLabel,
      }),
      backgroundColor: switch (verdict) {
        BootstrapProbeVerdict.reachable => scheme.primary,
        BootstrapProbeVerdict.udpUnavailable => scheme.secondary,
        _ => scheme.error,
      },
    );
  }

  /// The status pill for a stored result state.
  ///
  /// Lives here rather than inline in the settings section because it IS the
  /// verdict->presentation mapping this class owns, and the section rendered
  /// two byte-identical copies of it (current node + manual node) that could
  /// drift apart — the 'udp' case had already been added to both by hand.
  ///
  /// Only 'failed' gets the error tone. 'udp' and 'unavailable' are neutral:
  /// the probe never produced a verdict about the node, so a red pill would
  /// blame the node for a local constraint or for our own defect.
  static Widget pillFor(
    BuildContext context,
    String? result, {
    required String successLabel,
    required String udpLabel,
    required String unavailableLabel,
    required String failedLabel,
    required Color successColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return StatusPill(
      label: switch (result) {
        'success' => successLabel,
        'udp' => udpLabel,
        unavailableResult => unavailableLabel,
        _ => failedLabel,
      },
      color: switch (result) {
        'success' => successColor,
        'udp' || unavailableResult => scheme.secondary,
        _ => scheme.error,
      },
    );
  }
}

/// Pill-shaped status badge used for online/offline/test-result indicators in
/// the bootstrap settings UI. Background is a 10% tint of [color]; text + dot
/// are full [color]; outer shape is a Stadium pill so it reads as a status
/// chip rather than a button or list-tile leading marker.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.10),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          AppSpacing.horizontalXs,
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
