import 'dart:async';

// ignore: directives_ordering
import 'widgets/safe_dialog_pop.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../util/prefs.dart';
import '../i18n/app_localizations.dart';
import '../util/feature_flags.dart';
import '../util/responsive_layout.dart';
import '../util/logger.dart';
import '../util/account_service.dart';
import '../util/app_bootstrap_coordinator.dart';
import '../util/app_spacing.dart';
import 'home_page.dart';
import 'widgets/app_page_route.dart';
import 'widgets/error_banner.dart';
import 'widgets/first_run_backup_wizard.dart';
import 'widgets/register_password_strength_bar.dart';
import 'testing/ui_keys.dart';

/// Standalone page for registering a new account (opened from login page).
/// Mirrors the layout of [LoginSettingsPage]: AppBar with back + title, form in body.
///
/// Mobile parity: this is shared Dart with no platform-conditional code — the
/// same fields, validators, password-strength bar, match/mismatch icon, busy
/// spinner, error banner, and the injectable callbacks run identically on iOS,
/// Android, and desktop. The hermetic real-UI gates in
/// `test/ui/register/*_real_ui_test.dart` therefore cover all targets at once.
typedef _RegisterAccountFn =
    Future<RegisterResult> Function({
      required String nickname,
      required String statusMessage,
      required String password,
    });

typedef _RegisterBootSessionFn = Future<void> Function(FfiChatService service);

typedef _RegisterTeardownSessionFn =
    Future<void> Function({
      required FfiChatService service,
      bool reEncryptProfile,
    });

typedef _ShowFirstRunBackupWizardFn =
    Future<void> Function({
      required BuildContext context,
      required String toxId,
      required String nickname,
    });

typedef _NavigateToHomeFn =
    Future<void> Function(BuildContext context, FfiChatService service);

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    this.registerAccount,
    this.bootSession,
    this.teardownSession,
    this.showFirstRunBackupWizard,
    this.navigateToHome,
  });

  final _RegisterAccountFn? registerAccount;
  final _RegisterBootSessionFn? bootSession;
  final _RegisterTeardownSessionFn? teardownSession;
  final _ShowFirstRunBackupWizardFn? showFirstRunBackupWizard;
  final _NavigateToHomeFn? navigateToHome;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nicknameController = TextEditingController();
  final _statusMessageController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  final _nicknameFocusNode = FocusNode();
  final _statusFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();
  bool _nicknameFocused = false;
  bool _statusFocused = false;
  bool _passwordFocused = false;
  bool _confirmPasswordFocused = false;
  bool _passwordObscure = true;
  bool _confirmPasswordObscure = true;
  late final _RegisterAccountFn _registerAccount;
  late final _RegisterBootSessionFn _bootSession;
  late final _RegisterTeardownSessionFn _teardownSession;
  late final _ShowFirstRunBackupWizardFn _showFirstRunBackupWizard;
  late final _NavigateToHomeFn _navigateToHome;

  @override
  void dispose() {
    _nicknameController.dispose();
    _statusMessageController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameFocusNode.dispose();
    _statusFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _registerAccount =
        widget.registerAccount ??
        ({
          required String nickname,
          required String statusMessage,
          required String password,
        }) => AccountService.registerNewAccount(
          nickname: nickname,
          statusMessage: statusMessage,
          password: password,
        );
    _bootSession = widget.bootSession ?? AppBootstrapCoordinator.boot;
    _teardownSession =
        widget.teardownSession ??
        ({required FfiChatService service, bool reEncryptProfile = true}) =>
            AccountService.teardownCurrentSession(
              service: service,
              reEncryptProfile: reEncryptProfile,
            );
    _showFirstRunBackupWizard =
        widget.showFirstRunBackupWizard ??
        ({
          required BuildContext context,
          required String toxId,
          required String nickname,
        }) => FirstRunBackupWizard.show(
          context,
          toxId: toxId,
          nickname: nickname,
        ).then((_) {});
    _navigateToHome =
        widget.navigateToHome ??
        (BuildContext context, FfiChatService service) {
          return Navigator.of(
            context,
          ).pushReplacement(AppPageRoute(page: HomePage(service: service)));
        };
    _nicknameController.addListener(() {
      if (mounted) setState(() {});
    });
    _statusMessageController.addListener(() {
      if (mounted) setState(() {});
    });
    _nicknameFocusNode.addListener(() {
      if (mounted)
        setState(() => _nicknameFocused = _nicknameFocusNode.hasFocus);
    });
    _statusFocusNode.addListener(() {
      if (mounted) setState(() => _statusFocused = _statusFocusNode.hasFocus);
    });
    _passwordFocusNode.addListener(() {
      if (mounted)
        setState(() => _passwordFocused = _passwordFocusNode.hasFocus);
    });
    _confirmPasswordFocusNode.addListener(() {
      if (mounted)
        setState(
          () => _confirmPasswordFocused = _confirmPasswordFocusNode.hasFocus,
        );
    });
  }

  Future<void> _register() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    RegisterResult? result;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nickname = _nicknameController.text.trim();
      final statusMessage = _statusMessageController.text.trim();
      if (nickname.isEmpty) {
        throw Exception(l10n.nicknameCannotBeEmpty);
      }

      result = await _registerAccount(
        nickname: nickname,
        statusMessage: statusMessage,
        password: _passwordController.text,
      );

      await _bootSession(result.service);
      await Prefs.getAccountList(); // refresh list

      if (!mounted) {
        await _teardownSession(service: result.service);
        return;
      }

      // First-run backup wizard: blocks navigation to HomePage until the user
      // either exports their .tox file or explicitly acknowledges the
      // data-loss consequence. Only shown for brand-new accounts (the
      // registration flow is the only caller; existing-account logins do
      // not pass through here). Gated by the feature flag so we can flip
      // the wizard off in a hotfix if a user-reported issue appears.
      if (FeatureFlags.enableFirstRunBackupWizard) {
        await _showFirstRunBackupWizard(
          context: context,
          toxId: result.toxId,
          nickname: nickname,
        );
        if (!mounted) {
          await _teardownSession(service: result.service);
          return;
        }
      }

      unawaited(HapticFeedback.lightImpact());
      await _navigateToHome(context, result.service);
    } catch (e, stackTrace) {
      if (result != null) {
        await _teardownSession(service: result.service);
      }
      AppLogger.logError('[RegisterPage] Register failed: $e', e, stackTrace);
      if (mounted) {
        unawaited(HapticFeedback.lightImpact());
        setState(() {
          _error = e is Exception
              ? e.toString().replaceFirst('Exception: ', '')
              : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Scaffold(
        appBar: AppBar(
          leadingWidth:
              56 + ResponsiveLayout.responsiveHorizontalPadding(context),
          leading: Padding(
            padding: EdgeInsetsDirectional.only(
              start: ResponsiveLayout.responsiveHorizontalPadding(context),
            ),
            child: IconButton(
              // Stable test key for the AppBar back button (real-UI pop assertion).
              key: const Key('register_back_button'),
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => popDialogIfCurrent(context),
            ),
          ),
          title: Text(AppLocalizations.of(context)!.registerNewAccount),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveLayout.isMobile(context)
                    ? double.infinity
                    : 440.0,
              ),
              child: SingleChildScrollView(
                padding: ResponsiveLayout.responsivePadding(context),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppSpacing.verticalLg,
                        TextFormField(
                          key: UiKeys.registerPageNicknameField,
                          controller: _nicknameController,
                          focusNode: _nicknameFocusNode,
                          textAlignVertical: TextAlignVertical.center,
                          keyboardType: TextInputType.name,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.nickname],
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!.nickname,
                            hintText: AppLocalizations.of(
                              context,
                            )!.nicknameHintExample,
                            prefixIcon: Icon(
                              Icons.person,
                              color: _nicknameFocused
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            errorText:
                                calculateTextLength(_nicknameController.text) >
                                    12
                                ? AppLocalizations.of(context)!.nicknameTooLong
                                : null,
                          ),
                          textCapitalization: TextCapitalization.words,
                          maxLength: 24,
                          onFieldSubmitted: (_) =>
                              _statusFocusNode.requestFocus(),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return AppLocalizations.of(
                                context,
                              )!.nicknameCannotBeEmpty;
                            }
                            if (calculateTextLength(value.trim()) > 12) {
                              return AppLocalizations.of(
                                context,
                              )!.nicknameTooLong;
                            }
                            return null;
                          },
                        ),
                        AppSpacing.verticalLg,
                        TextFormField(
                          // Stable test key for the status-message field (real-UI gate).
                          key: const Key('register_status_field'),
                          controller: _statusMessageController,
                          focusNode: _statusFocusNode,
                          textAlignVertical: TextAlignVertical.center,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(
                              context,
                            )!.statusMessage,
                            hintText: AppLocalizations.of(
                              context,
                            )!.statusMessage,
                            prefixIcon: Icon(
                              Icons.info_outline,
                              color: _statusFocused
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            errorText:
                                calculateTextLength(
                                      _statusMessageController.text,
                                    ) >
                                    24
                                ? AppLocalizations.of(
                                    context,
                                  )!.statusMessageTooLong
                                : null,
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 2,
                          maxLength: 48,
                          onFieldSubmitted: (_) =>
                              _passwordFocusNode.requestFocus(),
                          validator: (value) {
                            if (value != null && value.trim().isNotEmpty) {
                              if (calculateTextLength(value.trim()) > 24) {
                                return AppLocalizations.of(
                                  context,
                                )!.statusMessageTooLong;
                              }
                            }
                            return null;
                          },
                        ),
                        AppSpacing.verticalLg,
                        TextFormField(
                          key: UiKeys.registerPagePasswordField,
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: _passwordObscure,
                          textAlignVertical: TextAlignVertical.center,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!.password,
                            hintText: AppLocalizations.of(
                              context,
                            )!.ircChannelPasswordHint,
                            prefixIcon: Icon(
                              Icons.lock_outline,
                              color: _passwordFocused
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            suffixIcon: IconButton(
                              // Stable test key for the password visibility toggle.
                              key: const Key(
                                'register_password_visibility_toggle',
                              ),
                              icon: Icon(
                                // State-suffixed key so a real-UI driver can OBSERVE the
                                // obscure flip (the IconButton key above stays stable for
                                // tapping). Same "encode state in the key" pattern as the
                                // conversation online-dot. Shared Dart → covers mobile too.
                                key: Key(
                                  'register_password_visibility_icon_'
                                  '${_passwordObscure ? 'obscured' : 'visible'}',
                                ),
                                _passwordObscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _passwordObscure = !_passwordObscure,
                              ),
                              tooltip: AppLocalizations.of(
                                context,
                              )!.passwordVisibility,
                            ),
                          ),
                          onChanged: (_) {
                            if (mounted) setState(() {});
                          },
                          onFieldSubmitted: (_) =>
                              _confirmPasswordFocusNode.requestFocus(),
                        ),
                        RegisterPasswordStrengthBar(
                          password: _passwordController.text,
                        ),
                        AppSpacing.verticalLg,
                        TextFormField(
                          key: UiKeys.registerPageConfirmPasswordField,
                          controller: _confirmPasswordController,
                          focusNode: _confirmPasswordFocusNode,
                          obscureText: _confirmPasswordObscure,
                          textAlignVertical: TextAlignVertical.center,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(
                              context,
                            )!.confirmPassword,
                            prefixIcon: Icon(
                              Icons.lock_outline,
                              color: _confirmPasswordFocused
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_confirmPasswordController
                                        .text
                                        .isNotEmpty &&
                                    _passwordController.text.isNotEmpty)
                                  Icon(
                                    // Stable test key for the confirm-password match/mismatch
                                    // indicator (check_circle when matching, cancel otherwise).
                                    key: const Key(
                                      'register_confirm_match_icon',
                                    ),
                                    _confirmPasswordController.text ==
                                            _passwordController.text
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    color:
                                        _confirmPasswordController.text ==
                                            _passwordController.text
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.error,
                                    size: 20,
                                  ),
                                IconButton(
                                  // Stable test key for the confirm-password visibility toggle.
                                  key: const Key(
                                    'register_confirm_visibility_toggle',
                                  ),
                                  icon: Icon(
                                    _confirmPasswordObscure
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () => setState(
                                    () => _confirmPasswordObscure =
                                        !_confirmPasswordObscure,
                                  ),
                                  tooltip: AppLocalizations.of(
                                    context,
                                  )!.passwordVisibility,
                                ),
                              ],
                            ),
                          ),
                          validator: (value) {
                            final pwd = _passwordController.text;
                            if (pwd.isNotEmpty) {
                              if (value == null || value != pwd) {
                                return AppLocalizations.of(
                                  context,
                                )!.passwordsDoNotMatch;
                              }
                            }
                            if (value != null &&
                                value.isNotEmpty &&
                                pwd.isEmpty) {
                              return AppLocalizations.of(
                                context,
                              )!.passwordsDoNotMatch;
                            }
                            return null;
                          },
                          onChanged: (_) {
                            if (mounted) setState(() {});
                          },
                          onFieldSubmitted: (_) => _register(),
                        ),
                        if (_error != null) ...[
                          AppSpacing.verticalLg,
                          ErrorBanner(
                            message: _error!,
                            onRetry: () {
                              setState(() => _error = null);
                              _register();
                            },
                            onDismiss: () => setState(() => _error = null),
                          ),
                        ],
                        AppSpacing.verticalXl,
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            key: UiKeys.registerPageRegisterButton,
                            onPressed:
                                (_busy ||
                                    calculateTextLength(
                                          _nicknameController.text,
                                        ) >
                                        12 ||
                                    calculateTextLength(
                                          _statusMessageController.text,
                                        ) >
                                        24)
                                ? null
                                : _register,
                            child: _busy
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Theme.of(context).colorScheme.onPrimary,
                                      ),
                                    ),
                                  )
                                : Text(AppLocalizations.of(context)!.register),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
