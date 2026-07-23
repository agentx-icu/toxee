part of 'register_page.dart';

class _RegisterPageForm extends StatelessWidget {
  const _RegisterPageForm({
    required this.formKey,
    required this.nicknameController,
    required this.statusMessageController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.nicknameFocusNode,
    required this.statusFocusNode,
    required this.passwordFocusNode,
    required this.confirmPasswordFocusNode,
    required this.nicknameFocused,
    required this.statusFocused,
    required this.passwordFocused,
    required this.confirmPasswordFocused,
    required this.passwordObscure,
    required this.confirmPasswordObscure,
    required this.busy,
    required this.error,
    required this.onChanged,
    required this.onTogglePasswordObscure,
    required this.onToggleConfirmPasswordObscure,
    required this.onRegister,
    required this.onRetry,
    required this.onDismissError,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nicknameController;
  final TextEditingController statusMessageController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final FocusNode nicknameFocusNode;
  final FocusNode statusFocusNode;
  final FocusNode passwordFocusNode;
  final FocusNode confirmPasswordFocusNode;
  final bool nicknameFocused;
  final bool statusFocused;
  final bool passwordFocused;
  final bool confirmPasswordFocused;
  final bool passwordObscure;
  final bool confirmPasswordObscure;
  final bool busy;
  final String? error;
  final VoidCallback onChanged;
  final VoidCallback onTogglePasswordObscure;
  final VoidCallback onToggleConfirmPasswordObscure;
  final VoidCallback onRegister;
  final VoidCallback onRetry;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AutofillGroup(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSpacing.verticalLg,
            _nicknameField(context, l10n, theme),
            AppSpacing.verticalLg,
            _statusMessageField(context, l10n, theme),
            AppSpacing.verticalLg,
            _passwordField(context, l10n, theme),
            RegisterPasswordStrengthBar(password: passwordController.text),
            AppSpacing.verticalLg,
            _confirmPasswordField(context, l10n, theme),
            if (error != null) ...[
              AppSpacing.verticalLg,
              ErrorBanner(
                message: error!,
                onRetry: onRetry,
                onDismiss: onDismissError,
              ),
            ],
            AppSpacing.verticalXl,
            _registerButton(context, l10n, theme),
          ],
        ),
      ),
    );
  }

  Widget _nicknameField(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return TextFormField(
      key: UiKeys.registerPageNicknameField,
      controller: nicknameController,
      focusNode: nicknameFocusNode,
      textAlignVertical: TextAlignVertical.center,
      keyboardType: TextInputType.name,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.nickname],
      decoration: InputDecoration(
        labelText: l10n.nickname,
        hintText: l10n.nicknameHintExample,
        prefixIcon: Icon(
          Icons.person,
          color: nicknameFocused ? theme.colorScheme.primary : null,
        ),
        errorText: calculateTextLength(nicknameController.text) > 12
            ? l10n.nicknameTooLong
            : null,
      ),
      textCapitalization: TextCapitalization.words,
      maxLength: 24,
      onFieldSubmitted: (_) => statusFocusNode.requestFocus(),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return l10n.nicknameCannotBeEmpty;
        }
        if (calculateTextLength(value.trim()) > 12) {
          return l10n.nicknameTooLong;
        }
        return null;
      },
    );
  }

  Widget _statusMessageField(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return TextFormField(
      key: const Key('register_status_field'),
      controller: statusMessageController,
      focusNode: statusFocusNode,
      textAlignVertical: TextAlignVertical.center,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: l10n.statusMessage,
        hintText: l10n.statusMessage,
        prefixIcon: Icon(
          Icons.info_outline,
          color: statusFocused ? theme.colorScheme.primary : null,
        ),
        errorText: calculateTextLength(statusMessageController.text) > 24
            ? l10n.statusMessageTooLong
            : null,
      ),
      textCapitalization: TextCapitalization.sentences,
      maxLines: 2,
      maxLength: 48,
      onFieldSubmitted: (_) => passwordFocusNode.requestFocus(),
      validator: (value) {
        if (value != null && value.trim().isNotEmpty) {
          if (calculateTextLength(value.trim()) > 24) {
            return l10n.statusMessageTooLong;
          }
        }
        return null;
      },
    );
  }

  Widget _passwordField(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return TextFormField(
      key: UiKeys.registerPagePasswordField,
      controller: passwordController,
      focusNode: passwordFocusNode,
      obscureText: passwordObscure,
      textAlignVertical: TextAlignVertical.center,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.newPassword],
      decoration: InputDecoration(
        labelText: l10n.password,
        hintText: l10n.ircChannelPasswordHint,
        prefixIcon: Icon(
          Icons.lock_outline,
          color: passwordFocused ? theme.colorScheme.primary : null,
        ),
        suffixIcon: IconButton(
          key: const Key('register_password_visibility_toggle'),
          icon: Icon(
            key: Key(
              'register_password_visibility_icon_'
              '${passwordObscure ? 'obscured' : 'visible'}',
            ),
            passwordObscure ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: onTogglePasswordObscure,
          tooltip: l10n.passwordVisibility,
        ),
      ),
      onChanged: (_) => onChanged(),
      onFieldSubmitted: (_) => confirmPasswordFocusNode.requestFocus(),
    );
  }

  Widget _confirmPasswordField(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return TextFormField(
      key: UiKeys.registerPageConfirmPasswordField,
      controller: confirmPasswordController,
      focusNode: confirmPasswordFocusNode,
      obscureText: confirmPasswordObscure,
      textAlignVertical: TextAlignVertical.center,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newPassword],
      decoration: InputDecoration(
        labelText: l10n.confirmPassword,
        prefixIcon: Icon(
          Icons.lock_outline,
          color: confirmPasswordFocused ? theme.colorScheme.primary : null,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (confirmPasswordController.text.isNotEmpty &&
                passwordController.text.isNotEmpty)
              Icon(
                key: const Key('register_confirm_match_icon'),
                confirmPasswordController.text == passwordController.text
                    ? Icons.check_circle
                    : Icons.cancel,
                color: confirmPasswordController.text == passwordController.text
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
                size: 20,
              ),
            IconButton(
              key: const Key('register_confirm_visibility_toggle'),
              icon: Icon(
                confirmPasswordObscure
                    ? Icons.visibility_off
                    : Icons.visibility,
              ),
              onPressed: onToggleConfirmPasswordObscure,
              tooltip: l10n.passwordVisibility,
            ),
          ],
        ),
      ),
      validator: (value) {
        final pwd = passwordController.text;
        if (pwd.isNotEmpty) {
          if (value == null || value != pwd) {
            return l10n.passwordsDoNotMatch;
          }
        }
        if (value != null && value.isNotEmpty && pwd.isEmpty) {
          return l10n.passwordsDoNotMatch;
        }
        return null;
      },
      onChanged: (_) => onChanged(),
      onFieldSubmitted: (_) => onRegister(),
    );
  }

  Widget _registerButton(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final disabled =
        busy ||
        calculateTextLength(nicknameController.text) > 12 ||
        calculateTextLength(statusMessageController.text) > 24;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: UiKeys.registerPageRegisterButton,
        onPressed: disabled ? null : onRegister,
        child: busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onPrimary,
                  ),
                ),
              )
            : Text(l10n.register),
      ),
    );
  }
}
