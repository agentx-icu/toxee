import 'package:flutter/material.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../models/account_summary.dart';
import '../ui/home_page.dart';
import '../ui/login_page.dart';
import '../ui/widgets/app_page_route.dart';
import '../i18n/app_localizations.dart';
import 'account_service.dart';
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
      final targetAccount = AccountSummary.fromMap(targetAccountMap);

      // 1. Check if target account has a password
      String? password;
      final hasPassword = await Prefs.hasAccountPassword(targetToxId);
      if (hasPassword && context.mounted) {
        password = await _showPasswordDialog(context, targetAccount.nickname);
        if (password == null) {
          return;
        }
        final isValid = await Prefs.verifyAccountPassword(targetToxId, password);
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
      );

      // 4. Only now update lastLoginTime (after successful init)
      await Prefs.addAccount(
        toxId: targetToxId,
        nickname: targetAccount.nickname,
        statusMessage: targetAccount.statusMessage,
      );

      // 5. Verify toxId
      final actualToxId = newService.selfId;
      if (!compareToxIds(actualToxId, targetToxId)) {
        // Log warning but continue
      }

      // 6. Navigate to HomePage
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
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
            content: Text(AppLocalizations.of(context)!.failedToSwitchAccount(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        if (currentSessionDisposed) {
          Navigator.of(context).pushAndRemoveUntil(
            AppPageRoute(page: const LoginPage()),
            (route) => false,
          );
        }
      }
      rethrow;
    }
  }

  static Future<String?> _showPasswordDialog(BuildContext context, String nickname) async {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.enterPasswordForAccount(nickname)),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.password,
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(passwordController.text),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
  }
}
