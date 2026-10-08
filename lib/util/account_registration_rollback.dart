import 'dart:io';

import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'account_service_test_hooks.dart';
import 'current_account_pointer_restore.dart';
import 'logger.dart';
import 'native_quarantine.dart';
import 'prefs.dart';
import 'safe_diagnostics.dart';
import 'session_password_store.dart';
import 'stranded_verifier_cleanup.dart';

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
    this.bootstrapStopped = true,
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

  /// A password verifier write was ATTEMPTED (it precedes publication); a
  /// failed registration must take it — or the partial pair a refused write
  /// can leave behind — with it, or a later import of the same identity would
  /// be gated by a password the file does not carry. A refused delete is
  /// recorded for `StrandedVerifierCleanup` to retry at startup.
  final bool verifierWritten;

  /// False when a bootstrap instance of this registration was disposed but
  /// not proven stopped (see [disposeRegistrationBootstrap]). The rollback
  /// then deletes no directory (a late native save could still land there)
  /// and, when the account was already published, keeps it registered with
  /// its verifier rather than stranding a protected profile.
  final bool bootstrapStopped;

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
  // The service in the plan may be a replacement opened after an earlier
  // bootstrap instance was quarantined, so it is always disposed; the
  // historical outcome is combined afterwards (disposing again cannot stop
  // an instance an earlier dispose quarantined — Tim2Tox is single-flight).
  final disposed =
      service == null ||
      await disposeRegistrationBootstrap(service, 'rollback');
  final stopped = plan.bootstrapStopped && disposed;
  final toxId = plan.toxId;
  // Whatever is kept below must not be deleted later in this process
  // either (Login's service-less deletion resumes on the same registry).
  if (!stopped && toxId != null && toxId.isNotEmpty) {
    NativeQuarantine.mark(toxId);
  }

  if (toxId != null && toxId.isNotEmpty) {
    SessionPasswordStore.clear(toxId);
  }

  // A published account whose instance may still write stays REGISTERED:
  // its profile, prefs and password verifier are left together, so the user
  // can open it later (startup reconciliation skips encrypted orphans, so a
  // row-less protected profile would be unreachable). Only the active-account
  // mirror is restored below.
  final keepPublished = plan.accountVisible && !stopped;
  if (keepPublished) {
    SafeDiagnostics.logFailure(
      '[AccountService] registration_rollback_incomplete '
      'stage=account_removal reason=native_instance_not_stopped',
      StateError('the account stays registered; open it after a restart'),
    );
  }
  if (plan.accountVisible && toxId != null && toxId.isNotEmpty && !keepPublished) {
    await Prefs.clearAccountData(toxId);
    await Prefs.removeAccount(toxId);
  }
  if (plan.verifierWritten &&
      toxId != null &&
      toxId.isNotEmpty &&
      !keepPublished) {
    final removed = await Prefs.removeAccountPassword(toxId);
    final journalCleared = await Prefs.passwordChanges.abort(toxId);
    if (!removed || !journalCleared) {
      // The stray verifier gates nothing (this identity's only private key is
      // in the temp/profile directory this same rollback deletes), but it
      // must not sit in the Keychain / Keystore forever: record it so
      // `StrandedVerifierCleanup.retryPending` removes it on a later start.
      await StrandedVerifierCleanup.record(toxId);
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

  if (!stopped) {
    // An unpublished tree is junk the next start cannot adopt when it is
    // encrypted (no verifier, never used); a published one is the account
    // kept above. Either way nothing may be deleted under a late save.
    SafeDiagnostics.logFailure(
      '[AccountService] registration_rollback_incomplete '
      'stage=directory_cleanup reason=native_instance_not_stopped',
      StateError('the bootstrap Tox instance may still write; left in place'),
    );
    return;
  }
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

/// Disposes a registration's bootstrap instance (`AccountService.registerNewAccount`) and reports whether native
/// provably stopped (the test hook, like teardown's, is the test's own
/// statement that it did). Never throws: registration decides what a
/// quarantined instance means for the step it is on.
Future<bool> disposeRegistrationBootstrap(
  FfiChatService service,
  String stage,
) async {
  final hook = AccountRegistrationTestHooks.disposeService;
  // Captured before the instance goes away: a dispose that throws may no
  // longer answer, and every false outcome below must be recorded.
  final toxId = service.getSelfToxId() ?? '';
  try {
    if (hook != null) {
      await hook(service);
      return true;
    }
    await service.dispose();
  } catch (e) {
    SafeDiagnostics.logFailure(
      '[AccountService] registration_bootstrap_dispose_failed stage=$stage',
      e,
    );
    NativeQuarantine.mark(toxId);
    return false;
  }
  if (service.nativeInstanceStopped == true) return true;
  // A registration that still succeeds (reopen is the documented recovery)
  // leaves an account whose directory no deletion in this process may touch.
  NativeQuarantine.mark(toxId);
  AppLogger.warn(
    '[AccountService] registration stage=$stage: the bootstrap Tox instance '
    'was quarantined rather than stopped; its directory is left for the '
    'next start instead of being deleted under a possible late save',
  );
  return false;
}
