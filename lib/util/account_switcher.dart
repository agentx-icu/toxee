import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/widgets/safe_dialog_pop.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../models/account_summary.dart';
import '../ui/home_page.dart';
import '../ui/login_page.dart';
import '../ui/widgets/app_page_route.dart';
import '../i18n/app_localizations.dart';
import 'account_service.dart';
import 'app_bootstrap_coordinator.dart';
import 'prefs.dart';
import 'safe_diagnostics.dart';
import 'tox_utils.dart';

final class InvalidAccountSwitchPasswordException implements Exception {
  const InvalidAccountSwitchPasswordException();
}

final class AccountSwitchContextUnavailable implements Exception {
  const AccountSwitchContextUnavailable();
}

final class AccountSwitchFailure implements Exception {
  const AccountSwitchFailure();
}

typedef AccountSwitchInitializeServiceFn =
    Future<FfiChatService> Function({
      required String toxId,
      String? nickname,
      String? statusMessage,
      String? password,
      required bool startPolling,
    });
typedef AccountSwitchTeardownSessionFn =
    Future<void> Function({
      FfiChatService? service,
      required bool reEncryptProfile,
    });
typedef AccountSwitchBootSessionFn =
    Future<void> Function(FfiChatService service);
typedef AccountSwitchNavigateHomeFn =
    Future<void> Function(BuildContext context, FfiChatService service);

/// Account switcher service for switching between multiple accounts
class AccountSwitcher {
  static Future<void>? _switchInProgress;

  /// Switch to a different account
  ///
  /// This will:
  /// 1. Teardown current session (dispose SDK, re-encrypt profile)
  /// 2. Initialize service for target account
  /// 3. Update account's lastLoginTime
  /// 4. Navigate to HomePage
  static Future<void> switchAccount({
    required BuildContext context,
    required String targetToxId,
    FfiChatService? currentService,
    AccountSwitchInitializeServiceFn? initializeService,
    AccountSwitchTeardownSessionFn? teardownSession,
    AccountSwitchBootSessionFn? bootSession,
    Future<void> Function(String toxId)? ensureNotDeleting,
    Future<bool> Function(String toxId)? hasPasswordFn,
    Future<bool> Function(String toxId, String password)? verifyPasswordFn,
    Future<String?> Function(BuildContext context, String nickname)?
    requestPasswordFn,
    AccountSwitchNavigateHomeFn? navigateHome,
  }) {
    final inFlight = _switchInProgress;
    if (inFlight != null) return inFlight;

    late final Future<void> shared;
    shared =
        _performSwitchAccount(
          context: context,
          targetToxId: targetToxId,
          currentService: currentService,
          initializeService: initializeService,
          teardownSession: teardownSession,
          bootSession: bootSession,
          ensureNotDeleting: ensureNotDeleting,
          hasPasswordFn: hasPasswordFn,
          verifyPasswordFn: verifyPasswordFn,
          requestPasswordFn: requestPasswordFn,
          navigateHome: navigateHome,
        ).whenComplete(() {
          if (identical(_switchInProgress, shared)) {
            _switchInProgress = null;
          }
        });
    _switchInProgress = shared;
    return shared;
  }

  static Future<void> _performSwitchAccount({
    required BuildContext context,
    required String targetToxId,
    FfiChatService? currentService,
    AccountSwitchInitializeServiceFn? initializeService,
    AccountSwitchTeardownSessionFn? teardownSession,
    AccountSwitchBootSessionFn? bootSession,
    Future<void> Function(String toxId)? ensureNotDeleting,
    Future<bool> Function(String toxId)? hasPasswordFn,
    Future<bool> Function(String toxId, String password)? verifyPasswordFn,
    Future<String?> Function(BuildContext context, String nickname)?
    requestPasswordFn,
    AccountSwitchNavigateHomeFn? navigateHome,
  }) async {
    bool currentSessionDisposed = false;
    FfiChatService? newService;
    AccountActivationTransaction? activation;
    final initialize =
        initializeService ?? AccountService.initializeServiceForAccount;
    final teardown = teardownSession ?? AccountService.teardownCurrentSession;
    final boot = bootSession ?? AppBootstrapCoordinator.boot;
    final checkDeleting =
        ensureNotDeleting ?? AccountService.throwIfAccountDeleting;
    final hasPassword = hasPasswordFn ?? Prefs.hasAccountPassword;
    final verifyPassword = verifyPasswordFn ?? Prefs.verifyAccountPassword;
    final requestPassword = requestPasswordFn ?? _showPasswordDialog;
    final navigate = navigateHome ?? _navigateHome;
    try {
      final targetAccountMap = await Prefs.getAccountByToxId(targetToxId);
      if (targetAccountMap == null) {
        throw Exception('Target account not found');
      }
      await checkDeleting(targetToxId);
      final targetAccount = AccountSummary.fromMap(targetAccountMap);

      // 1. Check if target account has a password
      String? password;
      final passwordRequired = await hasPassword(targetToxId);
      if (passwordRequired) {
        if (!context.mounted) {
          throw const AccountSwitchContextUnavailable();
        }
        password = await requestPassword(context, targetAccount.nickname);
        if (password == null) {
          return;
        }
        if (!context.mounted) {
          throw const AccountSwitchContextUnavailable();
        }
        final isValid = await verifyPassword(targetToxId, password);
        if (!isValid) {
          throw const InvalidAccountSwitchPasswordException();
        }
      }
      if (!context.mounted) {
        throw const AccountSwitchContextUnavailable();
      }

      // 2. Teardown current session (re-encrypts profile if needed)
      activation = await AccountActivationTransaction.begin();
      if (!context.mounted) {
        throw const AccountSwitchContextUnavailable();
      }
      try {
        await teardown(service: currentService, reEncryptProfile: true);
      } finally {
        // Teardown is destructive before its fail-closed final checks run. If
        // one of those checks throws, the old Home session is still unusable.
        currentSessionDisposed = true;
      }

      // 3. Initialize service for target account
      newService = await initialize(
        toxId: targetToxId,
        nickname: targetAccount.nickname,
        statusMessage: targetAccount.statusMessage,
        password: password,
        startPolling: false,
      );

      // 4. Refresh stored profile fields, but defer the lastLoginTime bump
      // until boot succeeds — otherwise a failed boot would still surface
      // this account as "recently logged in".
      await Prefs.addAccount(
        toxId: targetToxId,
        nickname: targetAccount.nickname,
        statusMessage: targetAccount.statusMessage,
        updateLastLogin: false,
      );

      // 5. Boot the app coordinator (installs platform, starts polling, etc.)
      // before navigating, then stamp lastLoginTime.
      await boot(newService);
      if (!context.mounted) {
        throw const AccountSwitchContextUnavailable();
      }

      // 6. Verify the FFI-reported Tox ID matches what we asked for. The
      // V2TIM `selfId` is always the same placeholder string, so comparing
      // it with `targetToxId` would always mismatch — use the real address.
      final actualToxId = newService.getSelfToxId() ?? '';
      if (actualToxId.isNotEmpty && !compareToxIds(actualToxId, targetToxId)) {
        // Log warning but continue
      }

      // 7. Schedule navigation before committing the durable activation. The
      // route Future represents Home's lifetime and must not hold this
      // transaction open; synchronous Navigator failures remain rollbackable.
      unawaited(navigate(context, newService));
      activation.commit();
      try {
        final touchId = newService.getSelfToxId() ?? targetToxId;
        await Prefs.touchAccountLoginTime(touchId);
      } catch (_) {}
    } catch (e, stackTrace) {
      if (newService != null) {
        try {
          await teardown(service: newService, reEncryptProfile: true);
        } catch (cleanupError) {
          SafeDiagnostics.logFailure(
            '[AccountSwitcher] cleanup after switch failure failed',
            cleanupError,
          );
        }
      }
      final pendingActivation = activation;
      if (pendingActivation != null) {
        try {
          await pendingActivation.rollback();
        } catch (rollbackError) {
          SafeDiagnostics.logFailure(
            '[AccountSwitcher] current-account rollback after switch failure failed',
            rollbackError,
          );
        }
      }
      SafeDiagnostics.logFailure('[AccountSwitcher] Account switch failed', e);
      // UI callers own error presentation so one failure produces one message.
      // The service retains only the recovery navigation required after the
      // previous session has already been torn down.
      if (context.mounted && currentSessionDisposed) {
        try {
          unawaited(
            Navigator.of(context).pushAndRemoveUntil(
              AppPageRoute(page: const LoginPage()),
              (route) => false,
            ),
          );
        } catch (navigationError) {
          SafeDiagnostics.logFailure(
            '[AccountSwitcher] login fallback navigation failed',
            navigationError,
          );
        }
      }
      final outwardError = switch (e) {
        InvalidAccountSwitchPasswordException() => e,
        AccountSwitchContextUnavailable() => e,
        AccountTeardownFailure() => e,
        _ => const AccountSwitchFailure(),
      };
      Error.throwWithStackTrace(outwardError, stackTrace);
    }
  }

  static Future<void> _navigateHome(
    BuildContext context,
    FfiChatService service,
  ) {
    return Navigator.of(context)
        .pushAndRemoveUntil(
          AppPageRoute(page: HomePage(service: service)),
          (route) => false,
        )
        .then<void>((_) {});
  }

  static Future<String?> _showPasswordDialog(
    BuildContext context,
    String nickname,
  ) async {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.enterPasswordForAccount(nickname),
        ),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.password,
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
    );
  }
}
