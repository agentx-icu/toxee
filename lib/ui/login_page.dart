// Mobile parity: this file is shared Dart with no platform split — the same
// saved-account picker, quick-login/password dialogs, restore/import actions,
// account-management bottom sheet (long-press on mobile, right-click on
// desktop), and settings entry render identically on iOS/Android and desktop.
// The widget-test gates in test/ui/login/*_real_ui_test.dart therefore cover
// every target; no mobile-specific twin exists for these handlers.
import 'dart:async';
import 'dart:io';

// ignore: directives_ordering
import 'widgets/safe_dialog_pop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../util/app_spacing.dart';

import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'home_page.dart';
import 'login_settings_page.dart';
import 'register_page.dart';
import 'widgets/app_page_route.dart';
import 'widgets/app_snackbar.dart';
import 'widgets/bottom_sheet_handle.dart';
import 'widgets/error_banner.dart';
import 'widgets/stagger_list_item.dart';
import '../util/prefs.dart';
import '../i18n/app_localizations.dart';
import '../util/responsive_layout.dart';
import '../util/app_theme_config.dart';
import '../util/account_export_service.dart';
import 'testing/ui_keys.dart';

import '../util/account_service.dart';
import '../util/app_bootstrap_coordinator.dart';
import '../util/feature_flags.dart';
import '../util/logger.dart';
import '../auth/login_use_case.dart';
import 'login/login_page_controller.dart';
import 'pairing/pairing_client_page.dart';

typedef _BootSessionFn = Future<void> Function(FfiChatService service);
typedef _TeardownSessionFn =
    Future<void> Function({
      required FfiChatService service,
      bool reEncryptProfile,
    });

/// Exports a non-active account's profile and returns the written file path.
/// Production binds this to [AccountExportService.exportAccountData]; tests
/// inject a recording stub so the export handler can be driven without the
/// Tox FFI / on-disk profile.
typedef _ExportAccountFn =
    Future<String> Function({required String toxId, String? password});

/// Returns the appropriate trailing chevron for the current text direction.
/// In LTR locales this is `chevron_right`; in RTL locales it flips to
/// `chevron_left` so the affordance always points "forward" in reading order.
IconData _trailingChevron(BuildContext context) {
  return Directionality.of(context) == TextDirection.rtl
      ? Icons.chevron_left
      : Icons.chevron_right;
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.loginUseCase,
    this.loginPageController,
    this.bootSession,
    this.teardownSession,
    this.exportAccount,
  });

  final LoginUseCase? loginUseCase;
  final LoginPageController? loginPageController;
  final _BootSessionFn? bootSession;
  final _TeardownSessionFn? teardownSession;

  /// Test seam for the saved-account "Export" action. Defaults to the real
  /// [AccountExportService.exportAccountData]; injected in widget tests so the
  /// export handler is observable without FFI / disk profile state.
  final _ExportAccountFn? exportAccount;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _nicknameController = TextEditingController();
  final _statusMessageController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  // Re-entrancy guard for _quickLogin: a fast double-tap (or an automation
  // double-fire) on a saved-account card would otherwise call _quickLogin twice
  // and, on a password-protected account, stack TWO password prompts. The second
  // call returns immediately while the first is still in flight.
  bool _quickLoginInProgress = false;
  String? _error;
  FfiChatService? _service;
  List<Map<String, String>> _accountList = [];
  String?
  _verifiedPassword; // Password already verified by _quickLogin, avoids re-prompting in _login
  String? _verifiedPasswordToxId;
  late final LoginPageController _loginController;
  late final _BootSessionFn _bootSession;
  late final _TeardownSessionFn _teardownSession;
  late final _ExportAccountFn _exportAccount;
  final TextEditingController _manualHostController = TextEditingController();
  final TextEditingController _manualPortController = TextEditingController();
  final TextEditingController _manualPubkeyController = TextEditingController();
  final FocusNode _nicknameFocusNode = FocusNode();
  final ScrollController _savedAccountsScrollController = ScrollController();

  @override
  void dispose() {
    _nicknameController.dispose();
    _statusMessageController.dispose();
    _manualHostController.dispose();
    _manualPortController.dispose();
    _manualPubkeyController.dispose();
    _nicknameFocusNode.dispose();
    _savedAccountsScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loginController =
        widget.loginPageController ??
        LoginPageController(loginUseCase: widget.loginUseCase);
    _bootSession = widget.bootSession ?? AppBootstrapCoordinator.boot;
    _teardownSession =
        widget.teardownSession ??
        ({required FfiChatService service, bool reEncryptProfile = true}) =>
            AccountService.teardownCurrentSession(
              service: service,
              reEncryptProfile: reEncryptProfile,
            );
    _exportAccount =
        widget.exportAccount ??
        ({required String toxId, String? password}) =>
            AccountExportService.exportAccountData(
              toxId: toxId,
              password: password,
            );
    // Listen to text changes to update UI
    _nicknameController.addListener(() {
      if (mounted) setState(() {});
    });
    _statusMessageController.addListener(() {
      if (mounted) setState(() {});
    });
    // Load account list
    _loadAccountList();
    // Load settings
    _loadSettings();
    // Load saved nickname and status message if available (for backward compatibility)
    Prefs.getNickname().then((v) {
      if (v != null && mounted) {
        _nicknameController.text = v;
        setState(() {});
      }
    });
    Prefs.getStatusMessage().then((v) {
      if (v != null && mounted) {
        _statusMessageController.text = v;
      }
    });
  }

  Future<void> _loadAccountList() async {
    final accounts = await Prefs.getAccountList();
    if (mounted) {
      setState(() {
        _accountList = accounts;
      });
    }
  }

  Widget _buildAccountAvatar(
    Map<String, String> account,
    String nickname,
    dynamic colorTheme,
  ) {
    final avatarPath = account['avatarPath'];
    final hasAvatar =
        avatarPath != null &&
        avatarPath.isNotEmpty &&
        File(avatarPath).existsSync();
    if (hasAvatar) {
      return CircleAvatar(
        backgroundImage: FileImage(File(avatarPath)),
        radius: 24,
      );
    }
    return CircleAvatar(
      backgroundColor: colorTheme.primaryColor,
      radius: 24,
      child: Text(
        nickname.isNotEmpty ? nickname[0].toUpperCase() : 'A',
        style: TextStyle(
          color: colorTheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<String?> _showPasswordDialog(String title) async {
    final passwordController = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: TextField(
            // Stable automation anchor for the saved-account quick-login /
            // re-login password prompt (the dialog has no other distinguishing
            // key; the field is not autofocused). Lets real-UI automation type
            // the password deterministically. Automation-only, shared Dart.
            key: const Key('login_quick_password_field'),
            controller: passwordController,
            autofocus: true,
            obscureText: obscure,
            textAlignVertical: TextAlignVertical.center,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.password,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setLocal(() => obscure = !obscure),
                tooltip: AppLocalizations.of(context)!.passwordVisibility,
              ),
            ),
            onSubmitted: (value) => popDialogIfCurrent(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => popDialogIfCurrent<String>(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () =>
                  popDialogIfCurrent(context, passwordController.text),
              child: Text(AppLocalizations.of(context)!.ok),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog with password + confirm password; returns password if both match, null on cancel or mismatch.
  Future<String?> _showConfirmPasswordDialog(String title) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              textAlignVertical: TextAlignVertical.center,
              keyboardType: TextInputType.visiblePassword,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.password,
                hintText: AppLocalizations.of(context)!.ircChannelPasswordHint,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
            AppSpacing.verticalMd,
            TextField(
              controller: confirmController,
              obscureText: true,
              textAlignVertical: TextAlignVertical.center,
              keyboardType: TextInputType.visiblePassword,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.confirmPassword,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => popDialogIfCurrent<String>(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              final pwd = passwordController.text;
              if (pwd != confirmController.text) {
                AppSnackBar.showError(
                  context,
                  AppLocalizations.of(context)!.passwordsDoNotMatch,
                );
                return;
              }
              popDialogIfCurrent(context, pwd);
            },
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _quickLogin(Map<String, String> account) async {
    final toxId = account['toxId'];
    if (toxId == null || toxId.isEmpty) return;
    // Drop a re-entrant call (double-tap / double-fire) so we never stack two
    // password prompts or kick off two concurrent logins.
    if (_quickLoginInProgress) return;
    _quickLoginInProgress = true;
    try {
      await _quickLoginInner(account, toxId);
    } finally {
      _quickLoginInProgress = false;
    }
  }

  Future<void> _quickLoginInner(
    Map<String, String> account,
    String toxId,
  ) async {
    final cachedVerifiedPassword = _verifiedPasswordToxId == toxId
        ? _verifiedPassword
        : null;
    // Check if account has password
    final hasPassword =
        (cachedVerifiedPassword != null && cachedVerifiedPassword.isNotEmpty)
        ? true
        : await Prefs.hasAccountPassword(toxId);
    if (hasPassword) {
      String? password = cachedVerifiedPassword;
      final usedCachedVerifiedPassword =
          password != null && password.isNotEmpty;
      if (!usedCachedVerifiedPassword) {
        password = await _showPasswordDialog(
          AppLocalizations.of(
            context,
          )!.enterPasswordForAccount(account['nickname'] ?? ''),
        );
        if (password == null) return; // User cancelled
        final isValid = await Prefs.verifyAccountPassword(toxId, password);
        if (!isValid) {
          _verifiedPassword = null;
          _verifiedPasswordToxId = null;
          if (mounted) {
            setState(() {
              _error = AppLocalizations.of(context)!.invalidPassword;
            });
            AppSnackBar.showError(
              context,
              AppLocalizations.of(context)!.invalidPassword,
            );
          }
          return;
        }
      }
      // Store verified password so _login() won't prompt again
      _verifiedPassword = password;
      _verifiedPasswordToxId = toxId;
    }

    // Fill controllers for _login() without expanding the nickname/signature form
    _nicknameController.text = account['nickname'] ?? '';
    _statusMessageController.text = account['statusMessage'] ?? '';
    await _login();
  }

  @visibleForTesting
  Future<void> debugQuickLoginForTest(Map<String, String> account) =>
      _quickLogin(account);

  @visibleForTesting
  void debugPrimeVerifiedPasswordForTest({
    required String toxId,
    required String password,
  }) {
    _verifiedPasswordToxId = toxId;
    _verifiedPassword = password;
  }

  Future<void> _loadSettings() async {
    await _loadCurrentBootstrapNode();
    if (_manualPortController.text.isEmpty) {
      _manualPortController.text = '33445';
    }
  }

  Future<void> _loadCurrentBootstrapNode() async {
    final node = await Prefs.getCurrentBootstrapNode();
    if (mounted && node != null) {
      setState(() {
        _manualHostController.text = node.host;
        _manualPortController.text = node.port.toString();
        _manualPubkeyController.text = node.pubkey;
      });
    }
  }

  Future<void> _login() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
    });

    final nickname = _nicknameController.text.trim();
    final statusMessage = _statusMessageController.text.trim();
    if (nickname.isEmpty) {
      if (mounted) {
        setState(() {
          _error = '${l10n.nickname} cannot be empty';
          _busy = false;
        });
        AppSnackBar.showError(context, _error!);
        FocusScope.of(context).requestFocus(_nicknameFocusNode);
      }
      return;
    }

    String? password;
    final account = await Prefs.getUniqueAccountByNickname(nickname);
    final toxIdForLogin = account?['toxId'];
    if (toxIdForLogin != null && toxIdForLogin.isNotEmpty) {
      final cachedVerifiedPassword = _verifiedPasswordToxId == toxIdForLogin
          ? _verifiedPassword
          : null;
      final hasPassword =
          (cachedVerifiedPassword != null && cachedVerifiedPassword.isNotEmpty)
          ? true
          : await Prefs.hasAccountPassword(toxIdForLogin);
      if (hasPassword) {
        password = cachedVerifiedPassword;
        _verifiedPassword = null;
        _verifiedPasswordToxId = null;
        if (password == null || password.isEmpty) {
          if (!mounted) {
            return;
          }
          password = await _showPasswordDialog(
            l10n.enterPasswordForAccount(account?['nickname'] ?? nickname),
          );
          if (password == null || password.isEmpty) {
            if (mounted) {
              setState(() {
                _error = l10n.invalidPassword;
                _busy = false;
              });
              AppSnackBar.showError(context, l10n.invalidPassword);
            }
            return;
          }
          final ok = await Prefs.verifyAccountPassword(toxIdForLogin, password);
          if (!ok) {
            if (mounted) {
              setState(() {
                _error = l10n.invalidPassword;
                _busy = false;
              });
              AppSnackBar.showError(context, l10n.invalidPassword);
            }
            return;
          }
        }
      }
    }

    final result = await _loginController.login(
      nickname: nickname,
      statusMessage: statusMessage,
      password: password,
    );

    if (!mounted) {
      if (result is LoginControllerSuccess) {
        await _teardownSession(service: result.service);
      }
      return;
    }

    // CR-09: keep _busy held through boot + navigation so a second tap can't
    // re-enter login/boot concurrently. It is cleared only on the failure
    // branches below; on success this State is replaced by HomePage.
    switch (result) {
      case LoginControllerSuccess(:final service):
        try {
          await _loadAccountList();
          if (!mounted) {
            await _teardownSession(service: service);
            return;
          }
          _service = service;
          await _bootSession(service);
          // Boot succeeded — only now mark this account as "recently logged in"
          // so a failed boot earlier doesn't leave a misleading timestamp.
          // `selfId` is the V2TIM login placeholder (`FlutterUIKitClient`);
          // account_list is keyed by the real Tox address, so use
          // `getSelfToxId()` here or the touch silently misses the record.
          try {
            final touchId = service.getSelfToxId() ?? service.selfId;
            await Prefs.touchAccountLoginTime(touchId);
          } catch (_) {}
          if (!mounted) {
            await _teardownSession(service: service);
            return;
          }
          unawaited(HapticFeedback.lightImpact());
          Navigator.of(
            context,
          ).pushReplacement(AppPageRoute(page: HomePage(service: service)));
        } catch (e, stackTrace) {
          await _teardownSession(service: service);
          AppLogger.logError('[LoginPage] Login boot failed', e, stackTrace);
          if (!mounted) return;
          unawaited(HapticFeedback.lightImpact());
          final message = e is Exception
              ? e.toString().replaceFirst('Exception: ', '')
              : e.toString();
          setState(() {
            _error = message;
            _busy = false;
          });
          AppSnackBar.showError(context, message);
        }
        break;
      case LoginControllerFailure(:final message):
        unawaited(HapticFeedback.lightImpact());
        setState(() {
          _error = message;
          _busy = false;
        });
        AppSnackBar.showError(context, message);
        FocusScope.of(context).requestFocus(_nicknameFocusNode);
        break;
    }
  }

  /// First-class "Restore from .tox file" action. Mirrors the Login affordance
  /// in prominence — peer to the saved-accounts picker and to "Register new
  /// account" — so a user who has lost their previous device finds the
  /// recovery path immediately. On success, the imported account is added to
  /// the saved-accounts list (and the user can tap it to log in); on
  /// invalid-password the user can retry without dismissing the action.
  Future<void> _restoreFromToxFile() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    while (true) {
      final result = await _loginController.restoreFromToxFile(
        requestPassword: () => _showPasswordDialog(l10n.enterPasswordToImport),
        importedAccountDefaultName: l10n.importedAccountDefaultName,
      );
      if (!mounted) return;
      switch (result) {
        case RestoreSuccess(:final nickname, :final password, :final toxId):
          await _loadAccountList();
          if (!mounted) return;
          setState(() {
            _error = null;
            _nicknameController.text = nickname;
            _verifiedPassword = password;
            _verifiedPasswordToxId = toxId;
          });
          AppSnackBar.showSuccess(
            context,
            l10n.restoreFromToxFileSuccess(nickname),
          );
          return;
        case RestoreFailure(:final kind, :final detail):
          final message = switch (kind) {
            RestoreFailureKind.noFileSelected => l10n.importNoFileSelected,
            RestoreFailureKind.cancelled => l10n.importCancelled,
            RestoreFailureKind.invalidPassword => l10n.invalidPassword,
            RestoreFailureKind.accountAlreadyExists =>
              l10n.accountAlreadyExists,
            RestoreFailureKind.notAToxProfile =>
              l10n.restoreFromToxFileInvalidFile,
            RestoreFailureKind.generalError => l10n.failedToImport(
              detail ?? '',
            ),
          };
          if (kind == RestoreFailureKind.invalidPassword) {
            // Allow the user to retry the password without dismissing.
            AppSnackBar.showError(context, message);
            continue;
          }
          setState(() => _error = message);
          if (kind != RestoreFailureKind.noFileSelected &&
              kind != RestoreFailureKind.cancelled) {
            AppSnackBar.showError(context, message);
          }
          return;
      }
    }
  }

  /// Import a tox_profile.tox or .zip file via [LoginPageController].
  Future<void> _importToxProfile() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await _loginController.importAccount(
      requestPassword: () =>
          _showConfirmPasswordDialog(l10n.enterPasswordToImport),
      importedAccountDefaultName: l10n.importedAccountDefaultName,
    );
    if (!mounted) return;
    switch (result) {
      case ImportSuccess():
        await _loadAccountList();
        if (!mounted) return;
        setState(() => _error = null);
        AppSnackBar.showSuccess(
          context,
          AppLocalizations.of(context)!.accountImportedSuccessfully,
        );
        break;
      case ImportFailure(:final kind, :final detail):
        final localized = AppLocalizations.of(context)!;
        final message = switch (kind) {
          ImportFailureKind.noFileSelected => localized.importNoFileSelected,
          ImportFailureKind.cancelled => localized.importCancelled,
          ImportFailureKind.accountAlreadyExists =>
            localized.accountAlreadyExists,
          ImportFailureKind.generalError => localized.failedToImport(
            detail ?? '',
          ),
        };
        setState(() => _error = message);
        // Suppress the toast for user-initiated cancellation paths; surface
        // it for genuine failures.
        if (kind != ImportFailureKind.noFileSelected &&
            kind != ImportFailureKind.cancelled) {
          AppSnackBar.showError(context, message);
        }
        break;
    }
  }

  /// Show bottom sheet menu for account management (long-press on account card
  /// on mobile, right-click on desktop). [position] is currently ignored — the
  /// modal bottom sheet anchors to the bottom edge regardless of pointer pos.
  void _showAccountManagementMenu(
    Map<String, String> account, {
    Offset? position,
  }) {
    final toxId = account['toxId'] ?? '';
    final nickname = account['nickname'] ?? '';
    if (toxId.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BottomSheetHandle(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                nickname.isNotEmpty
                    ? nickname
                    : AppLocalizations.of(context)!.unnamedAccount,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              // Automation anchor for the saved-account "Export" action.
              key: const Key('login_account_management_export_option'),
              leading: const Icon(Icons.upload_file),
              title: Text(AppLocalizations.of(context)!.exportAccount),
              onTap: () {
                popDialogIfCurrent(ctx);
                _exportAccountFromLoginPage(toxId, nickname);
              },
            ),
            ListTile(
              // Automation anchor for the saved-account "Delete" action.
              key: const Key('login_account_management_delete_option'),
              leading: Icon(
                Icons.delete_forever,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                AppLocalizations.of(context)!.deleteAccount,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                popDialogIfCurrent(ctx);
                _confirmDeleteAccountFromLoginPage(toxId, nickname);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  /// Export a non-active account's profile from the login page.
  Future<void> _exportAccountFromLoginPage(
    String toxId,
    String nickname,
  ) async {
    try {
      final filePath = await _exportAccount(toxId: toxId);
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          AppLocalizations.of(context)!.accountExportedSuccessfully(filePath),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          AppLocalizations.of(context)!.failedToExportAccount(e.toString()),
        );
      }
    }
  }

  /// Confirm and delete an account from the login page (no running service).
  Future<void> _confirmDeleteAccountFromLoginPage(
    String toxId,
    String nickname,
  ) async {
    // Check if account has password — require password for verification
    final hasPassword = await Prefs.hasAccountPassword(toxId);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final inputController = TextEditingController();
        return AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.deleteAccount),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppLocalizations.of(ctx)!.deleteAccountConfirmMessage),
              AppSpacing.verticalMd,
              if (hasPassword) ...[
                Text(
                  AppLocalizations.of(ctx)!.deleteAccountEnterPasswordToConfirm,
                ),
                AppSpacing.verticalSm,
                TextField(
                  // Automation anchor for the delete-confirm password input.
                  key: const Key('login_delete_account_confirm_input'),
                  controller: inputController,
                  obscureText: true,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx)!.password,
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
              ] else ...[
                Text(AppLocalizations.of(ctx)!.deleteAccountTypeWordToConfirm),
                AppSpacing.verticalSm,
                Text(
                  AppLocalizations.of(
                    ctx,
                  )!.deleteAccountConfirmWordPrompt('delete'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                AppSpacing.verticalSm,
                TextField(
                  // Same automation anchor as the password branch: tests target
                  // the single delete-confirm input regardless of which branch
                  // (password vs confirm-word) the account triggers.
                  key: const Key('login_delete_account_confirm_input'),
                  controller: inputController,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => popDialogIfCurrent(ctx, false),
              child: Text(AppLocalizations.of(ctx)!.cancel),
            ),
            TextButton(
              // Automation anchor for the delete-confirm action button.
              key: const Key('login_delete_account_confirm_button'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () async {
                if (hasPassword) {
                  final ok = await Prefs.verifyAccountPassword(
                    toxId,
                    inputController.text,
                  );
                  if (!ok) {
                    if (ctx.mounted) {
                      AppSnackBar.showError(
                        ctx,
                        AppLocalizations.of(ctx)!.invalidPassword,
                      );
                    }
                    return;
                  }
                } else {
                  if (inputController.text.trim().toLowerCase() != 'delete') {
                    if (ctx.mounted) {
                      AppSnackBar.showError(
                        ctx,
                        AppLocalizations.of(ctx)!.deleteAccountWrongWord,
                      );
                    }
                    return;
                  }
                }
                popDialogIfCurrent(ctx, true);
              },
              child: Text(AppLocalizations.of(ctx)!.deleteAccount),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await AccountService.deleteAccountWithoutService(toxId: toxId);
        await _loadAccountList();
        if (mounted) {
          AppSnackBar.showSuccess(
            context,
            '${AppLocalizations.of(context)!.deleteAccount}: $nickname',
          );
        }
      } catch (e) {
        if (mounted) {
          AppSnackBar.showError(context, e.toString());
        }
      }
    }
  }

  /// Launch the QR pairing client page. On successful pair, the receiving
  /// device materialized a new account on disk via [AccountExportService]; we
  /// refresh the account list so the new entry shows up immediately and the
  /// user can tap-to-login. Gated on [FeatureFlags.enableQRPairing].
  Future<void> _startPairingAsClient() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(AppPageRoute(page: const PairingClientPage()));
    if (!mounted) return;
    if (result == true) {
      await _loadAccountList();
      if (!mounted) return;
      AppSnackBar.showSuccess(
        context,
        AppLocalizations.of(context)!.pairingClientCompleted,
      );
    }
  }

  void _openSettings() async {
    await Navigator.of(
      context,
    ).push<void>(AppPageRoute(page: const LoginSettingsPage()));
    if (mounted) _loadSettings();
  }

  Widget _buildFloatingSettingsButton(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Glass chip rides the themed surface (white in light, near-black in
        // dark) at ~78% so the gradient shows through — no hardcoded white.
        color: scheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: UiKeys.loginPageSettingsButton,
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          onTap: _openSettings,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Icon(
              Icons.settings_rounded,
              color: scheme.onSurface.withValues(alpha: 0.86),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final maxSavedAccountsHeight = (viewportHeight * 0.38).clamp(220.0, 420.0);
    const estimatedSavedAccountCardHeight = 108.0;
    final estimatedSavedAccountsHeight =
        _accountList.length * estimatedSavedAccountCardHeight;
    final savedAccountsHeight =
        estimatedSavedAccountsHeight > maxSavedAccountsHeight
        ? maxSavedAccountsHeight
        : estimatedSavedAccountsHeight;
    final savedAccountsNeedsScroll =
        estimatedSavedAccountsHeight > maxSavedAccountsHeight;
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Scaffold(
        body: SafeArea(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        AppThemeConfig.darkGradientStart,
                        AppThemeConfig.darkGradientEnd,
                      ]
                    : [
                        AppThemeConfig.lightGradientStart,
                        AppThemeConfig.lightGradientEnd,
                      ],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: AppSpacing.md,
                  right: ResponsiveLayout.responsiveHorizontalPadding(context),
                  child: Tooltip(
                    message: AppLocalizations.of(context)!.settings,
                    child: _buildFloatingSettingsButton(context),
                  ),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      // Mobile uses full width (500 cap above mobile breakpoint
                      // is effectively a no-op); tablet/desktop tighten to 440 so
                      // the form reads like a focused card rather than stretching
                      // edge-to-edge on wide screens.
                      maxWidth: ResponsiveLayout.isMobile(context)
                          ? double.infinity
                          : 440.0,
                    ),
                    child: Padding(
                      padding: ResponsiveLayout.isMobile(context)
                          ? const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.sm,
                            )
                          : ResponsiveLayout.responsivePadding(context),
                      child: Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Saved accounts list (main content)
                              if (_accountList.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                    AppSpacing.xs,
                                    0,
                                    0,
                                    AppSpacing.md,
                                  ),
                                  child: Text(
                                    AppLocalizations.of(context)!.savedAccounts,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.6),
                                          letterSpacing: 0.4,
                                        ),
                                  ),
                                ),
                                SizedBox(
                                  height: savedAccountsHeight,
                                  child: Scrollbar(
                                    controller: _savedAccountsScrollController,
                                    thumbVisibility: savedAccountsNeedsScroll,
                                    child: ListView.builder(
                                      controller:
                                          _savedAccountsScrollController,
                                      primary: false,
                                      padding: EdgeInsets.zero,
                                      itemCount: _accountList.length,
                                      itemBuilder: (context, index) {
                                        final entry = MapEntry(
                                          index,
                                          _accountList[index],
                                        );
                                        final i = entry.key;
                                        final account = entry.value;
                                        final nickname =
                                            account['nickname'] ?? '';
                                        final statusMsg =
                                            account['statusMessage'] ?? '';
                                        final lastLogin =
                                            account['lastLoginTime'];
                                        final toxId = account['toxId'] ?? '';
                                        final toxIdPrefix = toxId.length >= 8
                                            ? toxId.substring(0, 8)
                                            : toxId;

                                        String formatLastLogin(
                                          String? isoString,
                                        ) {
                                          if (isoString == null ||
                                              isoString.isEmpty)
                                            return AppLocalizations.of(
                                              context,
                                            )!.never;
                                          try {
                                            final dateTime = DateTime.parse(
                                              isoString,
                                            );
                                            final now = DateTime.now();
                                            final difference = now.difference(
                                              dateTime,
                                            );

                                            // TODO(i18n): replace daysAgo/hoursAgo/minutesAgo with
                                            // ICU {count, plural, ...} forms in next round. Passing
                                            // an empty string for the {plural} placeholder so RTL/Arabic
                                            // doesn't render a stray ASCII "s" inside the localized
                                            // string. English degrades to "1 day ago / 2 day ago"
                                            // (the singular "day" baked into the en string) until ICU
                                            // plural support is wired up.
                                            if (difference.inDays > 0) {
                                              return AppLocalizations.of(
                                                context,
                                              )!.daysAgo(difference.inDays, '');
                                            } else if (difference.inHours > 0) {
                                              return AppLocalizations.of(
                                                context,
                                              )!.hoursAgo(
                                                difference.inHours,
                                                '',
                                              );
                                            } else if (difference.inMinutes >
                                                0) {
                                              return AppLocalizations.of(
                                                context,
                                              )!.minutesAgo(
                                                difference.inMinutes,
                                                '',
                                              );
                                            } else {
                                              return AppLocalizations.of(
                                                context,
                                              )!.justNow;
                                            }
                                          } catch (e) {
                                            return AppLocalizations.of(
                                              context,
                                            )!.unknown;
                                          }
                                        }

                                        return StaggeredListItem(
                                          index: i,
                                          child: _PressableScale(
                                            child: Card(
                                              margin: const EdgeInsets.only(
                                                bottom: AppSpacing.sm,
                                              ),
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                side: BorderSide(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.outlineVariant,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      AppThemeConfig
                                                          .cardBorderRadius,
                                                    ),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.click,
                                                child: InkWell(
                                                  key:
                                                      UiKeys.loginPageAccountCard(
                                                        toxId,
                                                      ),
                                                  onTap: () =>
                                                      _quickLogin(account),
                                                  onLongPress: () =>
                                                      _showAccountManagementMenu(
                                                        account,
                                                      ),
                                                  onSecondaryTapUp: (details) =>
                                                      _showAccountManagementMenu(
                                                        account,
                                                        position: details
                                                            .globalPosition,
                                                      ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          AppSpacing.lg,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        _buildAccountAvatar(
                                                          account,
                                                          nickname,
                                                          colorTheme,
                                                        ),
                                                        AppSpacing.horizontalMd,
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                nickname.isNotEmpty
                                                                    ? nickname
                                                                    : AppLocalizations.of(
                                                                        context,
                                                                      )!.unnamedAccount,
                                                                style: Theme.of(
                                                                  context,
                                                                ).textTheme.titleSmall,
                                                              ),
                                                              if (statusMsg
                                                                  .isNotEmpty) ...[
                                                                AppSpacing
                                                                    .verticalXs,
                                                                Text(
                                                                  statusMsg,
                                                                  style: Theme.of(context)
                                                                      .textTheme
                                                                      .bodySmall
                                                                      ?.copyWith(
                                                                        color:
                                                                            Theme.of(
                                                                              context,
                                                                            ).colorScheme.onSurface.withValues(
                                                                              alpha: 0.7,
                                                                            ),
                                                                      ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ],
                                                              AppSpacing
                                                                  .verticalXs,
                                                              Row(
                                                                children: [
                                                                  Text(
                                                                    '${AppLocalizations.of(context)!.userId}: $toxIdPrefix…',
                                                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                                      fontFamily:
                                                                          'monospace',
                                                                      color: Theme.of(context)
                                                                          .colorScheme
                                                                          .onSurface
                                                                          .withValues(
                                                                            alpha:
                                                                                0.5,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                  AppSpacing
                                                                      .horizontalSm,
                                                                  Text(
                                                                    '• ${formatLastLogin(lastLogin)}',
                                                                    style: Theme.of(context)
                                                                        .textTheme
                                                                        .labelSmall
                                                                        ?.copyWith(
                                                                          color:
                                                                              Theme.of(
                                                                                context,
                                                                              ).colorScheme.onSurface.withValues(
                                                                                alpha: 0.5,
                                                                              ),
                                                                        ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Icon(
                                                          _trailingChevron(
                                                            context,
                                                          ),
                                                          size: 20,
                                                          color:
                                                              Theme.of(context)
                                                                  .iconTheme
                                                                  .color
                                                                  ?.withValues(
                                                                    alpha: 0.4,
                                                                  ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                AppSpacing.verticalMd,
                              ],
                              if (_accountList.isEmpty) ...[
                                // First-run welcome: only shown to brand-new users
                                // (no saved accounts). Returning users with cached
                                // accounts skip this and go straight to the picker.
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 360,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.shield_outlined,
                                          size: 56,
                                          color: colorTheme.primaryColor,
                                        ),
                                        AppSpacing.verticalLg,
                                        Text(
                                          AppLocalizations.of(
                                                context,
                                              )?.appTitle ??
                                              'toxee',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                        AppSpacing.verticalLg,
                                        Text(
                                          // TODO(l10n): key=appTagline
                                          'A private, peer-to-peer messenger',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.7),
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                AppSpacing.verticalLg,
                              ],
                              // Restore-from-.tox is a top-level, peer-prominence
                              // action with Register: a user who has just lost a
                              // device must find this entry without digging into
                              // "Import account…" or settings.
                              _LoginActionCard(
                                key: UiKeys.loginPageRestoreFromToxFile,
                                icon: Icons.restore_outlined,
                                label: AppLocalizations.of(
                                  context,
                                )!.restoreFromToxFile,
                                color: colorTheme.primaryColor,
                                isPrimary: true,
                                onTap: _busy ? null : _restoreFromToxFile,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _LoginActionCard(
                                // Automation anchor for the "Import account" action.
                                key: const Key(
                                  'login_page_import_account_card',
                                ),
                                icon: Icons.download_outlined,
                                label: AppLocalizations.of(
                                  context,
                                )!.importAccount,
                                color: colorTheme.primaryColor,
                                onTap: _busy ? null : _importToxProfile,
                              ),
                              if (FeatureFlags.enableQRPairing) ...[
                                const SizedBox(height: AppSpacing.sm),
                                _LoginActionCard(
                                  icon: Icons.qr_code_scanner_outlined,
                                  label: AppLocalizations.of(
                                    context,
                                  )!.pairWithAnotherDevice,
                                  color: colorTheme.primaryColor,
                                  onTap: _busy ? null : _startPairingAsClient,
                                ),
                              ],
                              const SizedBox(height: AppSpacing.sm),
                              _LoginActionCard(
                                icon: Icons.person_add_outlined,
                                label: AppLocalizations.of(
                                  context,
                                )!.registerNewAccount,
                                color: colorTheme.primaryColor,
                                isPrimary: true,
                                onTap: _busy
                                    ? null
                                    : () async {
                                        await Navigator.of(context).push<void>(
                                          AppPageRoute(
                                            page: const RegisterPage(),
                                          ),
                                        );
                                        if (mounted) {
                                          await _loadAccountList();
                                        }
                                      },
                              ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.md,
                                  ),
                                  child: ErrorBanner(
                                    key: UiKeys.loginPageErrorBanner,
                                    message: _error!,
                                    onRetry: () {
                                      setState(() => _error = null);
                                      _login();
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Card-shaped action used on the login screen for "Import account" and
/// "Register new account". Elevation-0 + hairline border for a modern
/// messenger look; primary variant uses a tinted background to emphasize the
/// canonical create-account path.
class _LoginActionCard extends StatelessWidget {
  const _LoginActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _PressableScale(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: isPrimary ? AppThemeConfig.tintedPrimaryCardColor(color) : null,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: isPrimary
                ? AppThemeConfig.tintedPrimaryCardBorderColor(color)
                : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                AppSpacing.horizontalMd,
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: isPrimary ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                AppSpacing.horizontalSm,
                Icon(
                  _trailingChevron(context),
                  size: 20,
                  color: Theme.of(
                    context,
                  ).iconTheme.color?.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle scale-down on press for tappable Cards/InkWell rows.
/// Scales to [pressedScale] (default 0.97) when pressed and back to 1.0 over
/// 120ms. Respects `MediaQuery.disableAnimations` (no-op when reduced motion
/// is enabled).
class _PressableScale extends StatefulWidget {
  const _PressableScale({
    required this.child,
    this.pressedScale = 0.97,
    this.duration = const Duration(milliseconds: 120),
  });

  final Widget child;
  final double pressedScale;
  final Duration duration;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
