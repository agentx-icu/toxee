import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/app_theme_config.dart';
import '../testing/ui_keys_settings.dart';
import '../widgets/safe_dialog_pop.dart';

/// EXPORT-password + confirmation prompt in front of every user-facing export
/// (Settings `.tox` and full backup, the login page's saved-account export,
/// the first-run backup wizard).
///
/// The export password protects only the exported FILE. It is deliberately
/// independent of the account password: the at-rest profile is opened with
/// the account password (live session, or a separately verified prompt on the
/// login page) and the export is then sealed with whatever the user picks
/// here. Nothing may silently reuse the account password as the export
/// password — a backup whose password changes meaning when the account
/// password is later changed is a backup the user cannot open.
///
/// Pops the password when both fields match, null when cancelled; a mismatch
/// shows a snackbar and keeps the dialog open.
///
/// [allowEmpty]: `.tox` exports may be written unencrypted (qTox-compatible
/// plaintext profile). An empty password then pops `''` and a warning line
/// ([SettingsUiKeys.exportPasswordEmptyWarning]) stays visible while the field
/// is empty, so "unencrypted" is never the silent default. Full backups are
/// always encrypted (`requireFullBackupExportPassword`): with
/// `allowEmpty: false` an empty password shows an inline error and the dialog
/// stays open.
///
/// The two [TextEditingController]s are owned by the State (the former inline
/// `SettingsPage._showConfirmPasswordDialog` never disposed them), and every
/// field and button carries a [SettingsUiKeys] anchor: on iOS the system save
/// sheet that follows cannot be driven over the VM service, so this dialog is
/// the last step automation can take.
///
/// Shared Dart: desktop and mobile render the same widget.
Future<String?> showExportPasswordDialog(
  BuildContext context, {
  required bool allowEmpty,
  String? title,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        ExportPasswordDialog(title: title, allowEmpty: allowEmpty),
  );
}

/// Maps the dialog result to the exporter's `password` argument: an empty
/// export password means "write the file unencrypted" (null).
String? exportPasswordOrNull(String password) =>
    password.isEmpty ? null : password;

class ExportPasswordDialog extends StatefulWidget {
  const ExportPasswordDialog({super.key, required this.allowEmpty, this.title});

  /// Defaults to the localized "Choose an export password".
  final String? title;
  final bool allowEmpty;

  @override
  State<ExportPasswordDialog> createState() => _ExportPasswordDialogState();
}

class _ExportPasswordDialogState extends State<ExportPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _requiredError = false;

  @override
  void initState() {
    super.initState();
    // The empty-password warning / required error track the field live.
    _password.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (!mounted) return;
    setState(() {
      if (_password.text.isNotEmpty) _requiredError = false;
    });
  }

  @override
  void dispose() {
    _password.removeListener(_onPasswordChanged);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final pwd = _password.text;
    if (pwd.isEmpty && !widget.allowEmpty) {
      setState(() => _requiredError = true);
      return;
    }
    if (pwd != _confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.passwordsDoNotMatch),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    popDialogIfCurrent(context, pwd);
  }

  InputDecoration _decoration({
    required String label,
    String? hint,
    String? error,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final showEmptyWarning = widget.allowEmpty && _password.text.isEmpty;
    return AlertDialog(
      // Landscape + keyboard leaves ~140 px for two fields: must scroll.
      scrollable: true,
      title: Text(widget.title ?? l10n.exportPasswordDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.exportPasswordExplanation,
            style: theme.textTheme.bodySmall,
          ),
          if (showEmptyWarning) ...[
            const SizedBox(height: 12),
            Row(
              key: SettingsUiKeys.exportPasswordEmptyWarning,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.exportPasswordEmptyWarning,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: SettingsUiKeys.exportPasswordField,
            controller: _password,
            obscureText: true,
            textAlignVertical: TextAlignVertical.center,
            decoration: _decoration(
              label: l10n.exportPasswordLabel,
              hint: widget.allowEmpty ? l10n.exportPasswordOptionalHint : null,
              error: _requiredError ? l10n.exportPasswordRequired : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: SettingsUiKeys.exportPasswordConfirmField,
            controller: _confirm,
            obscureText: true,
            textAlignVertical: TextAlignVertical.center,
            decoration: _decoration(label: l10n.confirmExportPasswordLabel),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: SettingsUiKeys.exportPasswordCancelButton,
          onPressed: () => popDialogIfCurrent<String>(context),
          child: Text(l10n.cancel),
        ),
        // The confirm button itself names the consequence while the password
        // is empty: actions stay pinned, so even when a landscape keyboard
        // scrolls the warning out of view the user cannot confirm a
        // plaintext export without reading "Export unencrypted".
        TextButton(
          key: SettingsUiKeys.exportPasswordOkButton,
          onPressed: _submit,
          style: showEmptyWarning
              ? TextButton.styleFrom(foregroundColor: theme.colorScheme.error)
              : null,
          child: Text(
            showEmptyWarning ? l10n.exportUnencryptedButton : l10n.ok,
          ),
        ),
      ],
    );
  }
}
