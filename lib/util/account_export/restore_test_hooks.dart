// Crash-injection points for the full-backup restore transaction, split out of
// `restore_transaction.dart` (complexity-gate pin) and re-exported from it, so
// every existing importer keeps resolving them.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

enum FullBackupRestoreFailurePoint {
  afterStaging,
  afterProfileCommit,
  afterAccountDataCommit,
  afterScopedPrefsApply,
  afterAccountRegistryVisible,
}

abstract final class FullBackupRestoreTestHooks {
  FullBackupRestoreTestHooks._();

  @visibleForTesting
  static FullBackupRestoreFailurePoint? crashAt;

  static String Function(Uint8List profileBytes)? profileIdentityExtractor;

  @visibleForTesting
  static void reset() {
    crashAt = null;
    profileIdentityExtractor = null;
  }

  static void maybeCrash(FullBackupRestoreFailurePoint point) {
    if (crashAt == point) {
      throw FullBackupRestoreCrashSimulation(point);
    }
  }
}

final class FullBackupRestoreCrashSimulation implements Exception {
  const FullBackupRestoreCrashSimulation(this.point);

  final FullBackupRestoreFailurePoint point;

  @override
  String toString() => 'FullBackupRestoreCrashSimulation: ${point.name}';
}
