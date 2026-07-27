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
import 'tox_utils.dart';

/// Account switcher service for switching between multiple accounts
class AccountSwitcher {
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
  }) async {
    bool currentSessionDisposed = false;
    FfiChatService? newService;
    try {
      final targetAccountMap = await Prefs.getAccountByToxId(targetToxId);
      if (targetAccountMap == null) {
        throw Exception('Target account not found');
      }
      await AccountService.throwIfAccountDeleting(targetToxId);
      final targetAccount = AccountSummary.fromMap(targetAccountMap);

      // 1. Check if target account has a password
      String? password;
      final hasPassword = await Prefs.hasAccountPassword(targetToxId);
      if (hasPassword && context.mounted) {
        password = await _showPasswordDialog(context, targetAccount.nickname);
        if (password == null) {
          return;
        }
        final isValid = await Prefs.verifyAccountPassword(
          targetToxId,
          password,
        );
        if (!isValid) {
          throw Exception('Invalid password');
        }
      }

      // 2. Teardown current session (re-encrypts profile if needed)
      await AccountService.teardownCurrentSession(service: currentService);
      currentSessionDisposed = true;

      // 3. Initialize service for target account
      newService = await AccountService.initializeServiceForAccount(
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
      await AppBootstrapCoordinator.boot(newService);
      try {
        // `selfId` is the V2TIM placeholder (`FlutterUIKitClient`); the
        // `account_list` row is keyed by the real Tox address. We know the
        // expected real ID here (`targetToxId`), so prefer the FFI's
        // resolved value and fall back to `targetToxId` rather than the
        // placeholder.
        final touchId = newService.getSelfToxId() ?? targetToxId;
        await Prefs.touchAccountLoginTime(touchId);
      } catch (_) {}

      // 6. Verify the FFI-reported Tox ID matches what we asked for. The
      // V2TIM `selfId` is always the same placeholder string, so comparing
      // it with `targetToxId` would always mismatch — use the real address.
      final actualToxId = newService.getSelfToxId() ?? '';
      if (actualToxId.isNotEmpty && !compareToxIds(actualToxId, targetToxId)) {
        // Log warning but continue
      }

      // 7. Navigate to HomePage
      if (context.mounted) {
        await Navigator.of(context).pushAndRemoveUntil(
          AppPageRoute(page: HomePage(service: newService)),
          (route) => false,
        );
      }
    } catch (e) {
      if (newService != null) {
        await AccountService.teardownCurrentSession(service: newService);
      }
      // Show error and optionally navigate back to login page
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.failedToSwitchAccount(e.toString()),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        if (currentSessionDisposed) {
          await Navigator.of(context).pushAndRemoveUntil(
            AppPageRoute(page: const LoginPage()),
            (route) => false,
          );
        }
      }
      rethrow;
    }
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
