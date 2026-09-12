import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../adapters/bootstrap_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/shared_prefs_adapter.dart';
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
  await AppPaths.migrateAccountDataFromLegacy(toxId);
  final historyDirectory = await AppPaths.getAccountChatHistoryPath(toxId);
  final queueFilePath = await AppPaths.getAccountOfflineQueueFilePath(toxId);
  final fileRecvPath = await AppPaths.getAccountFileRecvPath(toxId);
  final avatarsPath = await AppPaths.getAccountAvatarsPath(toxId);
  final scratchStorage = await AccountService.createScratchStorageForAccount(toxId);

  await Directory(historyDirectory).create(recursive: true);
  await Directory(avatarsPath).create(recursive: true);

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
