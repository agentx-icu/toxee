import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../adapters/bootstrap_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/shared_prefs_adapter.dart';
import 'account_scratch_storage.dart';
import 'account_service.dart';
import 'app_paths.dart';
import 'safe_diagnostics.dart';

// Constructs an `FfiChatService` wired to an account's scoped paths. Split out of
// `account_service.dart` (complexity-gate pin); it is plumbing, not lifecycle
// policy, and pairs with `account_registration_rollback.dart`.

/// Creates an [FfiChatService] with account-scoped paths (history, queue,
/// fileRecv, avatars). Caller must call [FfiChatService.startPolling] if needed.
Future<FfiChatService> createAccountScopedService({
  required SharedPreferences prefs,
  required String toxId,
  required String profileDirectory,
}) async {
  final paths = await _prepareAccountStoragePaths(toxId);
  final historyDirectory = paths.historyDirectory;
  final queueFilePath = paths.queueFilePath;
  final fileRecvPath = paths.fileRecvPath;
  final avatarsPath = paths.avatarsPath;
  final scratchStorage = await AccountService.createScratchStorageForAccount(toxId);

  final accountPrefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
  final svc = FfiChatService(
    preferencesService: SharedPreferencesAdapter(
      prefs,
      accountPrefix: accountPrefix,
    ),
    loggerService: AppLoggerAdapter(),
    bootstrapService: BootstrapNodesAdapter(prefs),
    historyDirectory: historyDirectory,
    queueFilePath: queueFilePath,
    fileRecvPath: fileRecvPath,
    avatarsPath: avatarsPath,
    scratchFileService: scratchStorage,
  );
  try {
    await svc.init(profileDirectory: profileDirectory);
    await svc.login(userId: 'FlutterUIKitClient', userSig: 'dummy_sig');
    return svc;
  } catch (_) {
    try {
      await svc.dispose();
    } catch (disposeError) {
      SafeDiagnostics.logFailure(
        '[AccountService] registration_rollback_failed '
        'stage=scoped_service_disposal',
        disposeError,
      );
    }
    rethrow;
  }
}

/// Adopt any legacy global data this account is entitled to, resolve its
/// per-account storage paths and create the directories the service does not
/// create for itself.
Future<
  ({
    String historyDirectory,
    String queueFilePath,
    String fileRecvPath,
    String avatarsPath,
  })
>
_prepareAccountStoragePaths(String toxId) async {
  await AppPaths.migrateAccountDataFromLegacy(toxId);
  final historyDirectory = await AppPaths.getAccountChatHistoryPath(toxId);
  final queueFilePath = await AppPaths.getAccountOfflineQueueFilePath(toxId);
  final fileRecvPath = await AppPaths.getAccountFileRecvPath(toxId);
  final avatarsPath = await AppPaths.getAccountAvatarsPath(toxId);

  await Directory(historyDirectory).create(recursive: true);
  await Directory(avatarsPath).create(recursive: true);

  return (
    historyDirectory: historyDirectory,
    queueFilePath: queueFilePath,
    fileRecvPath: fileRecvPath,
    avatarsPath: avatarsPath,
  );
}

/// Late-bind account-scoped storage onto a service that HAD to be created
/// before its Tox ID was known.
///
/// The legacy login paths (`LoginUseCase._executeLegacy`,
/// `StartupSessionUseCase`'s legacy fallback) open an account row that carries
/// no Tox ID, so they cannot use [createAccountScopedService]: the identity
/// only exists once `init()` + `login()` have run. Without this the service
/// keeps tim2tox's shared `<AppSupport>/chat_history` +
/// `offline_message_queue.json` + `file_recv` + `avatars`, which EVERY account
/// on the device would share — the same defect the prefs prefix and the
/// scratch storage avoid by being injected late.
///
/// Call it in the same place those two are injected: right after
/// `getSelfToxId()` has produced the real 76-char address, before the session
/// is booted (`startPolling`). Throws (and persists nothing durable) on
/// failure, so the caller's existing catch can dispose the service.
Future<void> installAccountScopedStorage({
  required FfiChatService service,
  required String toxId,
}) async {
  // Land everything still owed to the SHARED location before the adoption
  // copy reads it. `installAccountStorage` flushes too, but that happens
  // after the copy: a row `init()`/`login()` had queued but not yet written
  // would be flushed to the shared directory the copy had already walked,
  // and the per-file `if (!dest.exists())` guard means it is never adopted.
  await service.messageHistoryPersistence.flushPendingSaves();
  final paths = await _prepareAccountStoragePaths(toxId);
  await service.installAccountStorage(
    historyDirectory: paths.historyDirectory,
    queueFilePath: paths.queueFilePath,
    fileRecvPath: paths.fileRecvPath,
    avatarsPath: paths.avatarsPath,
  );
}

/// Sub-directory of the registration temp directory that holds the
/// bootstrap-only service's storage. Dot-prefixed so it is inert to every
/// profile-directory scan.
const String _registerBootstrapStorageDirName = '.register_bootstrap';

/// Storage root for the bootstrap-only registration service living under
/// [directory] (the temp profile directory, or the final one after the
/// temp -> final rename).
String bootstrapStorageRootIn(String directory) =>
    p.join(directory, _registerBootstrapStorageDirName);

/// The bootstrap-only service `AccountService.register` uses to mint an
/// identity, with storage under its own temp directory.
///
/// It has no Tox ID yet and is disposed before any message flow, but it still
/// opens history / offline-queue / file_recv / avatars stores during `init()`.
/// Left on the defaults those were the SHARED `<AppSupport>` ones, so a
/// registration touched (and could create) the dataset that belongs to
/// whichever account owns the legacy global data. Scoping them to [tempDir]
/// keeps the shared default untouched, and the whole tree is removed with the
/// temp directory (see [deleteBootstrapStorageQuietly]).
FfiChatService createRegistrationBootstrapService({
  required SharedPreferences prefs,
  required String tempDir,
}) {
  final storageRoot = bootstrapStorageRootIn(tempDir);
  return FfiChatService(
    preferencesService: SharedPreferencesAdapter(prefs),
    loggerService: AppLoggerAdapter(),
    bootstrapService: BootstrapNodesAdapter(prefs),
    historyDirectory: p.join(storageRoot, 'chat_history'),
    queueFilePath: p.join(storageRoot, 'offline_message_queue.json'),
    fileRecvPath: p.join(storageRoot, 'file_recv'),
    avatarsPath: p.join(storageRoot, 'avatars'),
    scratchFileService: AccountScratchStorage.unavailableUntilAccountKnown(),
  );
}

/// Remove a [createRegistrationBootstrapService] storage tree once its service
/// is disposed. Never throws: the tree is scratch, and a leftover would only
/// be clutter inside the account's own profile directory.
Future<void> deleteBootstrapStorageQuietly(String storageRoot) async {
  try {
    final dir = Directory(storageRoot);
    if (await dir.exists()) await dir.delete(recursive: true);
  } catch (e) {
    SafeDiagnostics.logFailure(
      '[AccountService] registration_cleanup_failed '
      'stage=bootstrap_storage_removal',
      e,
    );
  }
}
