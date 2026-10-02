import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/app_theme_config.dart';
import '../testing/ui_keys_settings.dart';
import '../widgets/safe_dialog_pop.dart';

/// Password + confirmation prompt in front of the settings exports (`.tox`
/// and full backup). Pops the password when both fields match, null when
/// cancelled; a mismatch shows a snackbar and keeps the dialog open.
///
/// Extracted from `SettingsPage._showConfirmPasswordDialog` so that
///   * the two [TextEditingController]s are owned by a State whose lifetime
///     is the dialog's (the inline version created them in the enclosing
///     method and never disposed them — the leak `PasswordPromptDialog`
///     already fixed on the login page), and
///   * its fields and buttons carry [SettingsUiKeys] anchors. On iOS the
///     system save sheet that follows this dialog cannot be driven over the
///     VM service, so the dialog is the last step automation can take — and
///     it had no anchors at all.
///
/// Shared Dart: desktop and mobile render the same widget.
Future<String?> showExportPasswordDialog(BuildContext context, String title) {
  return showDialog<String>(
    context: context,
    builder: (context) => ExportPasswordDialog(title: title),
  );
}

class ExportPasswordDialog extends StatefulWidget {
  const ExportPasswordDialog({super.key, required this.title});

  final String title;

  @override
  State<ExportPasswordDialog> createState() => _ExportPasswordDialogState();
}

class _ExportPasswordDialogState extends State<ExportPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final pwd = _password.text;
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

  InputDecoration _decoration({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      // Landscape + keyboard leaves ~140 px for two fields: must scroll.
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: SettingsUiKeys.exportPasswordField,
            controller: _password,
            obscureText: true,
            textAlignVertical: TextAlignVertical.center,
            decoration: _decoration(
              label: l10n.password,
              hint: l10n.ircChannelPasswordHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: SettingsUiKeys.exportPasswordConfirmField,
            controller: _confirm,
            obscureText: true,
            textAlignVertical: TextAlignVertical.center,
            decoration: _decoration(label: l10n.confirmPassword),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: SettingsUiKeys.exportPasswordCancelButton,
          onPressed: () => popDialogIfCurrent<String>(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: SettingsUiKeys.exportPasswordOkButton,
          onPressed: _submit,
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}
