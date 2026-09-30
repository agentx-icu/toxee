import 'dart:io';

import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'account_service_test_hooks.dart';
import 'current_account_pointer_restore.dart';
import 'prefs.dart';
import 'safe_diagnostics.dart';
import 'session_password_store.dart';

/// Everything a failed `AccountService.registerNewAccount` needs to undo,
/// captured as the registration progresses.
///
/// OWNERSHIP IS THE POINT. Both [finalDir] and [ownedDataRoots] are derived from
/// the new account's 16-char Tox-ID prefix, and the persistent account paths are
/// keyed by that prefix for backwards compatibility. On a prefix collision they
/// therefore name ANOTHER account's directories. The rollback used to delete
/// them unconditionally, so a registration that failed after a collision
/// destroyed a bystander account's `tox_profile.tox` and its whole
/// `account_data/<prefix>` tree.
///
/// So the flags are not bookkeeping niceties: [ownsFinalDir] is set only after
/// the temp -> final rename actually succeeded, and [ownedDataRoots] lists only
/// the roots that did not exist when registration began.
final class AccountRegistrationRollbackPlan {
  const AccountRegistrationRollbackPlan({
    required this.service,
    required this.toxId,
    required this.tempDir,
    required this.finalDir,
    required this.ownsFinalDir,
    required this.ownedDataRoots,
    required this.accountVisible,
    this.verifierWritten = false,
    required this.previousAccount,
    required this.previousNickname,
    required this.previousStatusMessage,
    required this.previousAvatarPath,
  });

  /// The live service to dispose, if one was opened.
  final FfiChatService? service;

  /// The new account's Tox ID, or null when the FFI never produced one.
  final String? toxId;

  /// The `.tmp_register_*` staging directory. Always ours.
  final String? tempDir;

  /// The resolved `p_<first16>` directory. Deleted only when [ownsFinalDir].
  final String? finalDir;

  /// True only once the temp -> final rename succeeded.
  final bool ownsFinalDir;

  /// Account-data roots that did not exist before this registration.
  final List<String> ownedDataRoots;

  /// Whether the account was published to `account_list` (and so needs
  /// removing again).
  final bool accountVisible;

  /// The password verifier was persisted (it precedes publication); a failed
  /// registration must take it with it or a later import of the same identity
  /// would be gated by a password the file does not carry.
  final bool verifierWritten;

  final String? previousAccount;
  final String? previousNickname;
  final String? previousStatusMessage;
  final String? previousAvatarPath;
}

/// Undo a failed account registration.
///
/// Best-effort throughout: every step is independently guarded so one failure
/// cannot strand the rest. Restores the previous active-account mirror
/// (pointer, nickname, status, avatar) so the UI does not keep showing the
/// half-created account's identity.
Future<void> rollbackFailedRegistration(
  AccountRegistrationRollbackPlan plan,
) async {
  final service = plan.service;
  try {
    if (service != null) {
      final disposeService = AccountRegistrationTestHooks.disposeService;
      if (disposeService != null) {
        await disposeService(service);
      } else {
        await service.dispose();
      }
    }
  } catch (de) {
    SafeDiagnostics.logFailure(
      '[AccountService] registration_rollback_failed stage=service_disposal',
      de,
    );
  }

  final toxId = plan.toxId;
  if (toxId != null && toxId.isNotEmpty) {
    SessionPasswordStore.clear(toxId);
  }

  if (plan.accountVisible && toxId != null && toxId.isNotEmpty) {
    await Prefs.clearAccountData(toxId);
    await Prefs.removeAccount(toxId);
  }
  if (plan.verifierWritten && toxId != null && toxId.isNotEmpty) {
    final removed = await Prefs.removeAccountPassword(toxId);
    final journalCleared = await Prefs.passwordChanges.abort(toxId);
    if (!removed || !journalCleared) {
      // Not retried durably on purpose: this identity's only private key is
      // in the temp/profile directory this same rollback deletes, so nothing
      // can ever be imported under it and the stray verifier gates nothing.
      // Logged because a secure store that refuses deletes is worth knowing.
      SafeDiagnostics.logFailure(
        '[AccountService] registration_rollback_incomplete '
        'stage=verifier_removal removed=$removed journalCleared=$journalCleared',
        StateError('secure storage refused the verifier / journal delete'),
      );
    }
  }

  // Best-effort: the remaining cleanup (labels, temp / profile directories)
  // still has to run, and this path is already reporting the registration
  // failure — a refused pointer restore must not replace it.
  await restoreCurrentAccountPointer(
    plan.previousAccount,
    '[AccountService] registration_rollback',
  );
  await Prefs.setNickname(plan.previousNickname ?? '');
  await Prefs.setStatusMessage(plan.previousStatusMessage ?? '');
  await Prefs.setAvatarPath(plan.previousAvatarPath);

  await _deleteIfPresent(plan.tempDir, stage: 'temp_directory_cleanup');
  if (plan.ownsFinalDir) {
    await _deleteIfPresent(plan.finalDir, stage: 'profile_directory_cleanup');
  }
  for (final root in plan.ownedDataRoots) {
    await _deleteIfPresent(root, stage: 'account_data_cleanup');
  }
}

Future<void> _deleteIfPresent(String? path, {required String stage}) async {
  if (path == null) return;
  try {
    final directory = Directory(path);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  } catch (de) {
    SafeDiagnostics.logFailure(
      '[AccountService] registration_rollback_failed stage=$stage',
      de,
    );
  }
}
