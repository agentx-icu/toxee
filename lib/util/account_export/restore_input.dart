import 'dart:typed_data';

import 'package:archive/archive.dart';

// The input a full-backup restore transaction consumes, split out of
// `restore_transaction.dart` (complexity-gate pin) and re-exported from it so
// every existing importer keeps resolving it.

final class FullBackupRestoreInput {
  const FullBackupRestoreInput({
    required this.toxId,
    required this.nickname,
    required this.archive,
    required this.metadata,
    required this.toxProfile,
  });

  final String toxId;
  final String nickname;
  final Archive archive;
  final Map<String, dynamic> metadata;
  final Uint8List? toxProfile;
}
