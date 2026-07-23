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

part 'register_page_form.dart';

/// Standalone page for registering a new account (opened from login page).
/// Mirrors the layout of [LoginSettingsPage]: AppBar with back + title, form in body.
///
/// Mobile parity: this is shared Dart with no platform-conditional code — the
/// same fields, validators, password-strength bar, match/mismatch icon, busy
/// spinner, error banner, and the injectable callbacks run identically on iOS,
/// Android, and desktop. The hermetic real-UI gates in
/// `test/ui/register/*_real_ui_test.dart` therefore cover all targets at once.
typedef RegisterAccountFn =
    Future<RegisterResult> Function({
      required String nickname,
      required String statusMessage,
      required String password,
    });

typedef RegisterBootSessionFn = Future<void> Function(FfiChatService service);

typedef RegisterTeardownSessionFn =
    Future<void> Function({
      required FfiChatService service,
      bool reEncryptProfile,
    });

typedef ShowFirstRunBackupWizardFn =
    Future<void> Function({
      required BuildContext context,
      required String toxId,
      required String nickname,
    });

typedef NavigateToHomeFn =
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

  final RegisterAccountFn? registerAccount;
  final RegisterBootSessionFn? bootSession;
  final RegisterTeardownSessionFn? teardownSession;
  final ShowFirstRunBackupWizardFn? showFirstRunBackupWizard;
  final NavigateToHomeFn? navigateToHome;

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
  late final RegisterAccountFn _registerAccount;
  late final RegisterBootSessionFn _bootSession;
  late final RegisterTeardownSessionFn _teardownSession;
  late final ShowFirstRunBackupWizardFn _showFirstRunBackupWizard;
  late final NavigateToHomeFn _navigateToHome;

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
      if (mounted) {
        setState(() => _nicknameFocused = _nicknameFocusNode.hasFocus);
      }
    });
    _statusFocusNode.addListener(() {
      if (mounted) setState(() => _statusFocused = _statusFocusNode.hasFocus);
    });
    _passwordFocusNode.addListener(() {
      if (mounted) {
        setState(() => _passwordFocused = _passwordFocusNode.hasFocus);
      }
    });
    _confirmPasswordFocusNode.addListener(() {
      if (mounted) {
        setState(
          () => _confirmPasswordFocused = _confirmPasswordFocusNode.hasFocus,
        );
      }
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
                child: _RegisterPageForm(
                  formKey: _formKey,
                  nicknameController: _nicknameController,
                  statusMessageController: _statusMessageController,
                  passwordController: _passwordController,
                  confirmPasswordController: _confirmPasswordController,
                  nicknameFocusNode: _nicknameFocusNode,
                  statusFocusNode: _statusFocusNode,
                  passwordFocusNode: _passwordFocusNode,
                  confirmPasswordFocusNode: _confirmPasswordFocusNode,
                  nicknameFocused: _nicknameFocused,
                  statusFocused: _statusFocused,
                  passwordFocused: _passwordFocused,
                  confirmPasswordFocused: _confirmPasswordFocused,
                  passwordObscure: _passwordObscure,
                  confirmPasswordObscure: _confirmPasswordObscure,
                  busy: _busy,
                  error: _error,
                  onChanged: () {
                    if (mounted) setState(() {});
                  },
                  onTogglePasswordObscure: () =>
                      setState(() => _passwordObscure = !_passwordObscure),
                  onToggleConfirmPasswordObscure: () => setState(
                    () => _confirmPasswordObscure = !_confirmPasswordObscure,
                  ),
                  onRegister: _register,
                  onRetry: () {
                    setState(() => _error = null);
                    _register();
                  },
                  onDismissError: () => setState(() => _error = null),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
