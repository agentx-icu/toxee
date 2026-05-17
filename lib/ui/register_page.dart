import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_sdk/native_im/adapter/tim_manager.dart';
import 'package:tencent_cloud_chat_sdk/enum/log_level_enum.dart';

import '../util/prefs.dart';
import '../i18n/app_localizations.dart';
import '../util/feature_flags.dart';
import '../util/responsive_layout.dart';
import '../util/app_theme_config.dart';
import '../util/logger.dart';
import '../util/account_service.dart';
import '../util/app_spacing.dart';
import 'home_page.dart';
import 'widgets/app_page_route.dart';
import 'widgets/error_banner.dart';
import 'widgets/first_run_backup_wizard.dart';

/// Standalone page for registering a new account (opened from login page).
/// Mirrors the layout of [LoginSettingsPage]: AppBar with back + title, form in body.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

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
    _nicknameController.addListener(() {
      if (mounted) setState(() {});
    });
    _statusMessageController.addListener(() {
      if (mounted) setState(() {});
    });
    _nicknameFocusNode.addListener(() {
      if (mounted) setState(() => _nicknameFocused = _nicknameFocusNode.hasFocus);
    });
    _statusFocusNode.addListener(() {
      if (mounted) setState(() => _statusFocused = _statusFocusNode.hasFocus);
    });
    _passwordFocusNode.addListener(() {
      if (mounted) setState(() => _passwordFocused = _passwordFocusNode.hasFocus);
    });
    _confirmPasswordFocusNode.addListener(() {
      if (mounted) setState(() => _confirmPasswordFocused = _confirmPasswordFocusNode.hasFocus);
    });
  }

  Future<void> _initTIMManagerSDK() async {
    try {
      if (TIMManager.instance.isInitSDK()) return;
      final result = await TIMManager.instance.initSDK(
        sdkAppID: 0,
        logLevel: LogLevelEnum.V2TIM_LOG_INFO,
        uiPlatform: 0,
      );
      if (!result) {
        throw Exception(AppLocalizations.of(context)!.failedToInitializeTIMManager);
      }
    } catch (e, stackTrace) {
      AppLogger.logError('[RegisterPage] Error initializing TIMManager SDK: $e', e, stackTrace);
      rethrow;
    }
  }

  Future<void> _register() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
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

      final result = await AccountService.registerNewAccount(
        nickname: nickname,
        statusMessage: statusMessage,
        password: _passwordController.text,
      );

      await _initTIMManagerSDK();
      await Prefs.getAccountList(); // refresh list

      if (!mounted) return;

      // First-run backup wizard: blocks navigation to HomePage until the user
      // either exports their .tox file or explicitly acknowledges the
      // data-loss consequence. Only shown for brand-new accounts (the
      // registration flow is the only caller; existing-account logins do
      // not pass through here). Gated by the feature flag so we can flip
      // the wizard off in a hotfix if a user-reported issue appears.
      if (FeatureFlags.enableFirstRunBackupWizard) {
        await FirstRunBackupWizard.show(
          context,
          toxId: result.toxId,
          nickname: nickname,
        );
        if (!mounted) return;
      }

      unawaited(HapticFeedback.lightImpact());
      Navigator.of(context).pushReplacement(AppPageRoute(
        page: HomePage(service: result.service),
      ));
    } catch (e, stackTrace) {
      AppLogger.logError('[RegisterPage] Register failed: $e', e, stackTrace);
      if (mounted) {
        unawaited(HapticFeedback.lightImpact());
        setState(() {
          _error = e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _passwordStrength(String password) {
    if (password.isEmpty) return 0;
    if (password.length < 6) return 1;
    int score = 2;
    if (password.length >= 8 && (RegExp(r'[A-Z]').hasMatch(password) || RegExp(r'\d').hasMatch(password))) score = 3;
    if (password.length >= 8 && RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'\d').hasMatch(password) && RegExp(r'[!@#$%^&*]').hasMatch(password)) score = 4;
    return score;
  }

  Widget _buildPasswordStrengthBar(BuildContext context) {
    final strength = _passwordStrength(_passwordController.text);
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Decorative semantic ramp: weak → strong. The two middle segments are
    // status colors (amber-500 / amber-300 from the design system) and are
    // intentionally kept hex — they live alongside cs.error and cs.primary
    // as a visual gradient, not a themed brand surface.
    final colors = [
      cs.error,
      AppThemeConfig.statusAwayColor, // amber-500
      const Color(0xFFFCD34D),         // amber-300 (lighter than statusAway)
      cs.primary,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.sm),
      child: Row(
        children: List.generate(4, (i) => Expanded(
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : AppDurations.medium,
            curve: AppCurves.standard,
            height: 4,
            margin: EdgeInsets.only(right: i < 3 ? AppSpacing.xs : 0),
            decoration: BoxDecoration(
              color: i < strength ? colors[i] : cs.outline.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Scaffold(
        appBar: AppBar(
          leadingWidth: 56 + ResponsiveLayout.responsiveHorizontalPadding(context),
          leading: Padding(
            padding: EdgeInsetsDirectional.only(start: ResponsiveLayout.responsiveHorizontalPadding(context)),
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
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
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  AppSpacing.verticalLg,
                  TextFormField(
                    controller: _nicknameController,
                    focusNode: _nicknameFocusNode,
                    textAlignVertical: TextAlignVertical.center,
                    keyboardType: TextInputType.name,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.nickname,
                      hintText: AppLocalizations.of(context)!.nicknameHintExample,
                      prefixIcon: Icon(Icons.person, color: _nicknameFocused ? Theme.of(context).colorScheme.primary : null),
                      errorText: calculateTextLength(_nicknameController.text) > 12
                          ? AppLocalizations.of(context)!.nicknameTooLong
                          : null,
                    ),
                    textCapitalization: TextCapitalization.words,
                    maxLength: 24,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return AppLocalizations.of(context)!.nicknameCannotBeEmpty;
                      }
                      if (calculateTextLength(value.trim()) > 12) {
                        return AppLocalizations.of(context)!.nicknameTooLong;
                      }
                      return null;
                    },
                  ),
                  AppSpacing.verticalLg,
                  TextFormField(
                    controller: _statusMessageController,
                    focusNode: _statusFocusNode,
                    textAlignVertical: TextAlignVertical.center,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.statusMessage,
                      hintText: AppLocalizations.of(context)!.statusMessage,
                      prefixIcon: Icon(Icons.info_outline, color: _statusFocused ? Theme.of(context).colorScheme.primary : null),
                      errorText: calculateTextLength(_statusMessageController.text) > 24
                          ? AppLocalizations.of(context)!.statusMessageTooLong
                          : null,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                    maxLength: 48,
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        if (calculateTextLength(value.trim()) > 24) {
                          return AppLocalizations.of(context)!.statusMessageTooLong;
                        }
                      }
                      return null;
                    },
                  ),
                  AppSpacing.verticalLg,
                  TextFormField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: _passwordObscure,
                    textAlignVertical: TextAlignVertical.center,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.password,
                      hintText: AppLocalizations.of(context)!.ircChannelPasswordHint,
                      prefixIcon: Icon(Icons.lock_outline, color: _passwordFocused ? Theme.of(context).colorScheme.primary : null),
                      suffixIcon: IconButton(
                        icon: Icon(_passwordObscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _passwordObscure = !_passwordObscure),
                        tooltip: AppLocalizations.of(context)!.passwordVisibility,
                      ),
                    ),
                    onChanged: (_) {
                      if (mounted) setState(() {});
                    },
                  ),
                  _buildPasswordStrengthBar(context),
                  AppSpacing.verticalLg,
                  TextFormField(
                    controller: _confirmPasswordController,
                    focusNode: _confirmPasswordFocusNode,
                    obscureText: _confirmPasswordObscure,
                    textAlignVertical: TextAlignVertical.center,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.confirmPassword,
                      prefixIcon: Icon(Icons.lock_outline, color: _confirmPasswordFocused ? Theme.of(context).colorScheme.primary : null),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_confirmPasswordController.text.isNotEmpty && _passwordController.text.isNotEmpty)
                            Icon(
                              _confirmPasswordController.text == _passwordController.text ? Icons.check_circle : Icons.cancel,
                              color: _confirmPasswordController.text == _passwordController.text
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                              size: 20,
                            ),
                          IconButton(
                            icon: Icon(_confirmPasswordObscure ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _confirmPasswordObscure = !_confirmPasswordObscure),
                            tooltip: AppLocalizations.of(context)!.passwordVisibility,
                          ),
                        ],
                      ),
                    ),
                    validator: (value) {
                      final pwd = _passwordController.text;
                      if (pwd.isNotEmpty) {
                        if (value == null || value != pwd) {
                          return AppLocalizations.of(context)!.passwordsDoNotMatch;
                        }
                      }
                      if (value != null && value.isNotEmpty && pwd.isEmpty) {
                        return AppLocalizations.of(context)!.passwordsDoNotMatch;
                      }
                      return null;
                    },
                    onChanged: (_) {
                      if (mounted) setState(() {});
                    },
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
                      onPressed: (_busy ||
                              calculateTextLength(_nicknameController.text) > 12 ||
                              calculateTextLength(_statusMessageController.text) > 24)
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
    );
  }
}
