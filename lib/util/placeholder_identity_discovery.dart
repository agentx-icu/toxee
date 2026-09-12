import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../adapters/bootstrap_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/shared_prefs_adapter.dart';
import 'account_export_service.dart';
import 'app_paths.dart';
import 'logger.dart';
import 'placeholder_account_migration.dart';
import 'prefs.dart';

// Resolving the real Tox ID behind a `FlutterUIKitClient`-keyed account. Split
// out of `placeholder_account_migration.dart` (complexity-gate pin).
//
// This used to open the account — `init()` + `login()` on a discovery service —
// before anything had authenticated. The migration runs at startup, AHEAD of the
// auto-login gate, so a password-protected-but-plaintext profile was unsealed
// here no matter what the gate later decided. It also could not work on an
// encrypted profile (no passphrase at this layer), so the session was opened
// precisely in the cases where it could not help.
//
// The session survives, but only for an account that is demonstrably
// unprotected — see the comment at the guard for why reading the id from the
// bytes instead is NOT a safe substitute.

Future<String?> discoverPlaceholderRealToxId([
  String? authenticatedPassword,
]) async {
  // FIRST, before any guard can return: a copy stranded by a previous kill is a
  // plaintext private key, and every early return below would otherwise walk
  // past it.
  await sweepPlaceholderDiscoveryScratch();
  final prefs = await SharedPreferences.getInstance();
  final accountPrefix = PlaceholderAccountMigration.placeholderPrefix;

  final historyDir =
      await AppPaths.getAccountChatHistoryPath(PlaceholderAccountMigration.placeholderToxId);
  final queuePath =
      await AppPaths.getAccountOfflineQueueFilePath(PlaceholderAccountMigration.placeholderToxId);
  final fileRecvPath =
      await AppPaths.getAccountFileRecvPath(PlaceholderAccountMigration.placeholderToxId);
  final avatarsPath = await AppPaths.getAccountAvatarsPath(PlaceholderAccountMigration.placeholderToxId);
  final profileDir =
      await AppPaths.getProfileDirectoryForToxId(PlaceholderAccountMigration.placeholderToxId);
  final profileFile = AppPaths.profileFileInDirectory(profileDir);

  if (!await File(profileFile).exists()) {
    AppLogger.warn(
        '[PlaceholderAccountMigration] Profile blob missing; '
        'cannot discover real Tox ID');
    return null;
  }

  // REFUSE to open a protected account.
  //
  // Discovery works by `init()` + `login()`, which OPENS the account — and this
  // runs at startup, AHEAD of the auto-login authentication gate. So a
  // password-protected-but-plaintext profile was unsealed here no matter what
  // the gate later decided. It could not succeed on an ENCRYPTED profile either
  // (no passphrase at this layer), so the session was opened precisely where it
  // could not help.
  //
  // A protected placeholder account now stays un-migrated until the user logs
  // in, which is the right place: that path has the password.
  //
  // Note what is NOT done here: reading the id from the profile bytes instead.
  // `extractToxIdFromProfile` returns the 64-char PUBLIC KEY, while a session
  // returns the 76-char full address — and `PlaceholderAccountMigration` re-keys
  // `black_list_<toxId>` to whatever this returns. The runtime writes and reads
  // that family under the 76-char address, so handing back 64 would move the
  // blocked-peer list somewhere nothing looks and silently unblock everyone. The
  // 16-char prefix that directories and scoped prefs use is identical either way,
  // which is exactly why that mistake is easy to miss.
  //
  // "Deferred to an authenticated login" has to MEAN something, which is what
  // [authenticatedPassword] is: `LoginUseCase` passes the password it has just
  // verified against the placeholder-keyed verifier. Without that continuation
  // the refusal was a dead end - a protected placeholder account logged in and
  // STAYED under `FlutterUIKitClient` forever, reading its blocked-peer list
  // under an id nothing writes, and caching its session password under the
  // placeholder while teardown looks under the real address (so even a clean
  // logout stopped re-encrypting the profile).
  final password = authenticatedPassword;
  final authenticated = password != null && password.isNotEmpty;
  if (!authenticated &&
      await Prefs.accountProtectionState(
            PlaceholderAccountMigration.placeholderToxId,
          ) !=
          AccountProtectionState.none) {
    AppLogger.warn(
        '[PlaceholderAccountMigration] refusing to open a protected account '
        'to discover its Tox ID; migration deferred to an authenticated login');
    return null;
  }
  final wasEncrypted =
      await AccountExportService.isProfileFileEncrypted(profileFile);
  if (wasEncrypted && !authenticated) {
    AppLogger.warn(
        '[PlaceholderAccountMigration] profile is encrypted; migration '
        'deferred to an authenticated login');
    return null;
  }
  await Directory(historyDir).create(recursive: true);
  await Directory(avatarsPath).create(recursive: true);

  // THE ORIGINAL IS NEVER DECRYPTED.
  //
  // Decrypting in place and re-encrypting in a `finally` looks equivalent and is
  // not: the re-encrypt can fail (a full disk, a crash, a kill), and then
  // discovery returns normally with the account's private key sitting in
  // plaintext, with no session left that owns putting it back. Discovery only
  // needs to READ an id, so it works on a throwaway copy instead and the file
  // that matters is never modified at all. The copy lives in application
  // support, beside the real profile, rather than the system temp directory -
  // it holds the same private key and must inherit the same protection.
  var discoveryProfileDir = profileDir;
  Directory? scratch;
  if (wasEncrypted && password != null) {
    try {
      // A UNIQUE directory per call. A shared, deterministic one is worse than
      // it looks: two discoveries racing would each delete the other's copy, and
      // a native init that finds no profile does not fail - it mints a FRESH
      // identity, which the migration would then use to re-key the existing
      // account's data. Wrong identity, real data.
      scratch = Directory(
        p.join(
          await AppPaths.applicationSupportPath,
          '$_scratchDirPrefix${DateTime.now().microsecondsSinceEpoch}_$pid',
        ),
      );
      await scratch.create(recursive: true);
      final copy = AppPaths.profileFileInDirectory(scratch.path);
      await File(profileFile).copy(copy);
      await AccountExportService.decryptProfileFile(copy, password);
      discoveryProfileDir = scratch.path;
    } catch (e, st) {
      AppLogger.logError(
          '[PlaceholderAccountMigration] could not open a decrypted copy of the '
          'profile with the verified password; migration skipped',
          e,
          st);
      await _deleteScratch(scratch);
      return null;
    }
  }

  try {
    return await _runDiscoverySession(
      prefs: prefs,
      accountPrefix: accountPrefix,
      historyDir: historyDir,
      queuePath: queuePath,
      fileRecvPath: fileRecvPath,
      avatarsPath: avatarsPath,
      profileDir: discoveryProfileDir,
    );
  } finally {
    await _deleteScratch(scratch);
  }
}

/// Prefix of the throwaway directories that hold a decrypted copy.
///
/// Shared prefix + unique suffix: unique so two calls cannot delete each other's
/// copy, shared so [sweepPlaceholderDiscoveryScratch] can find one stranded by a
/// kill. That sweep is not optional - the copy is a plaintext private key, and
/// without it a process death between the decrypt and the `finally` left one on
/// disk indefinitely (the guards above return before the cleanup, and account
/// deletion knows nothing about these directories).
const _scratchDirPrefix = '.placeholder_discovery_scratch_';

/// Remove every stranded decrypted-profile copy.
///
/// Called at startup AND at the top of discovery, so a plaintext key left by a
/// kill is gone at the next opportunity rather than at the next successful
/// migration - which may never come.
Future<void> sweepPlaceholderDiscoveryScratch() async {
  try {
    final root = Directory(await AppPaths.applicationSupportPath);
    if (!await root.exists()) return;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      if (!p.basename(entry.path).startsWith(_scratchDirPrefix)) continue;
      await _deleteScratch(entry);
    }
  } catch (e, st) {
    AppLogger.logError(
        '[PlaceholderAccountMigration] could not sweep stranded decrypted '
        'profile copies',
        e,
        st);
  }
}

Future<void> _deleteScratch(Directory? scratch) async {
  if (scratch == null) return;
  try {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  } catch (e, st) {
    AppLogger.logError(
        '[PlaceholderAccountMigration] could not remove the decrypted profile '
        'copy; it is in application support and the next attempt replaces it',
        e,
        st);
  }
}

Future<String?> _runDiscoverySession({
  required SharedPreferences prefs,
  required String accountPrefix,
  required String historyDir,
  required String queuePath,
  required String fileRecvPath,
  required String avatarsPath,
  required String profileDir,
}) async {
  FfiChatService? service;
  try {
    service = FfiChatService(
      preferencesService:
          SharedPreferencesAdapter(prefs, accountPrefix: accountPrefix),
      loggerService: AppLoggerAdapter(),
      bootstrapService: BootstrapNodesAdapter(prefs),
      historyDirectory: historyDir,
      queueFilePath: queuePath,
      fileRecvPath: fileRecvPath,
      avatarsPath: avatarsPath,
    );
    await service.init(profileDirectory: profileDir);
    await service.login(
        userId: PlaceholderAccountMigration.placeholderToxId, userSig: 'dummy_sig');
    return service.getSelfToxId();
  } catch (e, st) {
    AppLogger.logError(
        '[PlaceholderAccountMigration] Discovery service init failed', e, st);
    return null;
  } finally {
    try {
      await service?.dispose();
    } catch (e, st) {
      AppLogger.logError(
          '[PlaceholderAccountMigration] Failed to dispose discovery service '
          '(non-fatal)',
          e,
          st);
    }
  }
}

/// Apply every step of the migration with a per-step rollback stack. The
/// first step that fails or precondition-rejects unwinds everything done
/// so far. Returns true only when every step succeeded and the durable
/// state (account list + pointer) was committed.
