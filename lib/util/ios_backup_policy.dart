import 'app_paths.dart';
import 'logger.dart';

typedef IosBackupPathResolver =
    Future<IosBackupPathPolicy> Function(String toxId);
typedef BackupExclusionWriter = Future<void> Function(String path);
typedef DerivableExclusionFailureReporter =
    void Function(String path, Object error, StackTrace stackTrace);

/// The account paths that iOS must either exclude from or retain in backups.
///
/// The Tox profile contains the account's private key and is deliberately
/// device-local. Received files and avatars are derivable caches. Chat history
/// and the offline queue remain backup-eligible user data.
class IosBackupPathPolicy {
  const IosBackupPathPolicy({
    required this.sensitiveProfileDirectory,
    required this.derivableExcludedPaths,
    required this.backupEligiblePaths,
  });

  final String sensitiveProfileDirectory;
  final Set<String> derivableExcludedPaths;
  final Set<String> backupEligiblePaths;

  Set<String> get excludedPaths => <String>{
    sensitiveProfileDirectory,
    ...derivableExcludedPaths,
  };

  /// Resolves the live account paths. In particular, the profile directory is
  /// derived from the configurable profile storage root rather than the legacy
  /// `<appSupport>/tim2tox` directory.
  static Future<IosBackupPathPolicy> resolve(String toxId) async {
    final profileDirectory = await AppPaths.getProfileDirectoryForToxId(toxId);
    final fileRecvDirectory = await AppPaths.getAccountFileRecvPath(toxId);
    final avatarsDirectory = await AppPaths.getAccountAvatarsPath(toxId);
    final chatHistoryDirectory = await AppPaths.getAccountChatHistoryPath(
      toxId,
    );
    final offlineQueueFile = await AppPaths.getAccountOfflineQueueFilePath(
      toxId,
    );
    return IosBackupPathPolicy(
      sensitiveProfileDirectory: profileDirectory,
      derivableExcludedPaths: <String>{fileRecvDirectory, avatarsDirectory},
      backupEligiblePaths: <String>{chatHistoryDirectory, offlineQueueFile},
    );
  }
}

/// Applies [IosBackupPathPolicy] after login.
///
/// The sensitive profile exclusion is awaited and allowed to fail the session
/// boot. Derivable cache exclusions are best-effort: each failure is reported
/// independently and does not prevent the remaining cache paths from being
/// marked.
class IosPostLoginBackupExcluder {
  IosPostLoginBackupExcluder({
    required this.isIos,
    this.resolvePaths = IosBackupPathPolicy.resolve,
    this.excludeFromBackup = AppPaths.excludeFromBackupOrThrow,
    DerivableExclusionFailureReporter? reportDerivableFailure,
  }) : reportDerivableFailure =
           reportDerivableFailure ?? _reportDerivableFailure;

  final bool isIos;
  final IosBackupPathResolver resolvePaths;
  final BackupExclusionWriter excludeFromBackup;
  final DerivableExclusionFailureReporter reportDerivableFailure;

  Future<void> apply(String? toxId) async {
    if (!isIos) return;
    final normalizedToxId = toxId?.trim();
    if (normalizedToxId == null || normalizedToxId.isEmpty) {
      throw StateError(
        'Cannot apply iOS backup policy without an active account Tox ID',
      );
    }

    final paths = await resolvePaths(normalizedToxId);

    // This is the security-sensitive operation. Do not catch its failure: the
    // boot caller converts it into the existing startup/session retry path.
    await excludeFromBackup(paths.sensitiveProfileDirectory);

    for (final path in paths.derivableExcludedPaths) {
      try {
        await excludeFromBackup(path);
      } catch (error, stackTrace) {
        reportDerivableFailure(path, error, stackTrace);
      }
    }
  }

  static void _reportDerivableFailure(
    String path,
    Object error,
    StackTrace stackTrace,
  ) {
    AppLogger.logError(
      '[IosPostLoginBackupExcluder] Could not exclude derivable path $path '
      'from backup; continuing',
      error,
      stackTrace,
    );
  }
}
