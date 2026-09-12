import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/app_spacing.dart';
import '../../util/prefs.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/safe_dialog_pop.dart';

/// Confirmation body for deleting a saved account from the login page.
///
/// A [StatefulWidget] on purpose, and split out of `login_page.dart` for the
/// same reason `SettingsPage` did it: the previous inline version created its
/// [TextEditingController] INSIDE `showDialog`'s builder. That builder re-runs
/// whenever the dialog route rebuilds — which the soft keyboard's inset change
/// makes routine on iOS and Android — so each rebuild produced a fresh
/// controller and silently discarded whatever the user had typed. The
/// controller was also never disposed.
///
/// Pops `true` only after the confirmation actually passes, so the caller can
/// treat a `true` result as authorized.
class DeleteAccountConfirmDialog extends StatefulWidget {
  const DeleteAccountConfirmDialog({
    super.key,
    required this.toxId,
    required this.hasPassword,
  });

  final String toxId;

  /// Whether the account is password-protected. Resolved by the caller before
  /// the dialog opens (the builder cannot await), and fail-closed: an
  /// unreadable secure store reports `true`, so an outage demands the password
  /// rather than falling back to the weaker type-a-word confirmation.
  final bool hasPassword;

  @override
  State<DeleteAccountConfirmDialog> createState() =>
      _DeleteAccountConfirmDialogState();
}

class _DeleteAccountConfirmDialogState
    extends State<DeleteAccountConfirmDialog> {
  final TextEditingController _inputController = TextEditingController();

  /// The word a passwordless account must type. Fixed rather than random so the
  /// prompt and the check cannot disagree across a rebuild.
  static const String _confirmWord = 'delete';

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    if (widget.hasPassword) {
      final ok = await Prefs.verifyAccountPassword(
        widget.toxId,
        _inputController.text,
      );
      if (!ok) {
        if (mounted) {
          AppSnackBar.showError(
            context,
            AppLocalizations.of(context)!.invalidPassword,
          );
        }
        return;
      }
    } else if (_inputController.text.trim().toLowerCase() != _confirmWord) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.deleteAccountWrongWord,
        );
      }
      return;
    }
    if (!mounted) return;
    popDialogIfCurrent(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      // Keyboard + landscape leave <300 px; the Column must scroll.
      scrollable: true,
      title: Text(l10n.deleteAccount),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.deleteAccountConfirmMessage),
          AppSpacing.verticalMd,
          if (widget.hasPassword) ...[
            Text(l10n.deleteAccountEnterPasswordToConfirm),
            AppSpacing.verticalSm,
            TextField(
              // Automation anchor for the delete-confirm password input.
              key: const Key('login_delete_account_confirm_input'),
              controller: _inputController,
              obscureText: true,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: l10n.password,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
          ] else ...[
            Text(l10n.deleteAccountTypeWordToConfirm),
            AppSpacing.verticalSm,
            Text(
              l10n.deleteAccountConfirmWordPrompt(_confirmWord),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            AppSpacing.verticalSm,
            TextField(
              // Same automation anchor as the password branch: tests target the
              // single delete-confirm input regardless of which branch the
              // account triggers.
              key: const Key('login_delete_account_confirm_input'),
              controller: _inputController,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => popDialogIfCurrent(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          // Automation anchor for the delete-confirm action button.
          key: const Key('login_delete_account_confirm_button'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _onConfirm,
          child: Text(l10n.deleteAccount),
        ),
      ],
    );
  }
}
