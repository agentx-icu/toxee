import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../widgets/safe_dialog_pop.dart';

/// Password prompt used by the login page's quick-login, restore and import
/// flows. Pops the entered text, or null when cancelled.
///
/// A [StatefulWidget] rather than an inline `StatefulBuilder`, for the same
/// reason as [DeleteAccountConfirmDialog]: the previous version created its
/// [TextEditingController] in the enclosing method and never disposed it, so
/// every password prompt leaked one. Owning it in a State ties its lifetime to
/// the dialog.
class PasswordPromptDialog extends StatefulWidget {
  const PasswordPromptDialog({super.key, required this.title});

  final String title;

  @override
  State<PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<PasswordPromptDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: TextField(
        // Stable automation anchor for the saved-account quick-login / re-login
        // password prompt (the dialog has no other distinguishing key). Lets
        // real-UI automation type the password deterministically.
        // Automation-only, shared Dart.
        key: const Key('login_quick_password_field'),
        controller: _controller,
        autofocus: true,
        obscureText: _obscure,
        textAlignVertical: TextAlignVertical.center,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        decoration: InputDecoration(
          labelText: l10n.password,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
            tooltip: l10n.passwordVisibility,
          ),
        ),
        onSubmitted: (value) => popDialogIfCurrent(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => popDialogIfCurrent<String>(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => popDialogIfCurrent(context, _controller.text),
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}
