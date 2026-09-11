import 'package:flutter/material.dart';

import '../../util/app_spacing.dart';
import 'pairing_status_indicator.dart';

/// Centred status/error block shared by the pairing host and client pages:
/// indicator, message, optional action.
///
/// The Column sits in a shrink-wrapping scroll view so a short message stays
/// vertically centred while a long one (e.g. `lanUnreachable` plus the OS
/// error text, 5–7 lines on a phone) scrolls instead of overflowing a
/// landscape phone's ~340 px.
class PairingCenteredMessage extends StatelessWidget {
  const PairingCenteredMessage({
    super.key,
    required this.state,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final PairingState state;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PairingStatusIndicator(state: state, size: 56),
            AppSpacing.verticalLg,
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (actionLabel != null && onAction != null) ...[
              AppSpacing.verticalLg,
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
