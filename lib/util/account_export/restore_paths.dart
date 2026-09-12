import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_paths.dart';

// The staging and final directory layout of a full-backup restore, split out of
// `restore_transaction.dart` (complexity-gate pin).
//
// Staging directories are siblings of the real ones and carry the transaction
// id, so a crash leaves them identifiable and a concurrent transaction cannot
// collide with them.

final class RestorePaths {
  const RestorePaths({
    required this.transactionId,
    required this.profileStageDir,
    required this.profileFinalDir,
    required this.accountDataStageDir,
    required this.accountDataFinalDir,
  });

  final String transactionId;
  final String profileStageDir;
  final String profileFinalDir;
  final String accountDataStageDir;
  final String accountDataFinalDir;

  static Future<RestorePaths> resolve(String toxId) async {
    final profileFinalDir = await AppPaths.getProfileDirectoryForToxId(toxId);
    final accountDataFinalDir = await AppPaths.getAccountDataRoot(toxId);
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final transactionId = DateTime.now().microsecondsSinceEpoch.toString();
    return RestorePaths(
      transactionId: transactionId,
      profileFinalDir: profileFinalDir,
      accountDataFinalDir: accountDataFinalDir,
      profileStageDir: p.join(
        p.dirname(profileFinalDir),
        '.full_backup_restore_profile_${prefix}_$transactionId',
      ),
      accountDataStageDir: p.join(
        p.dirname(accountDataFinalDir),
        '.full_backup_restore_data_${prefix}_$transactionId',
      ),
    );
  }
}

/// Remove a restore directory if it is there. Lives here with the layout it
/// operates on; both the rollback and the deletion-time discard use it.
Future<void> deleteRestoreDirectory(String path) async {
  final dir = Directory(path);
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}
