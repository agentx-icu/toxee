import 'dart:io';

import 'package:path/path.dart' as p;

import '../../util/logger.dart';

/// Best-effort cleanup of older `group_<id>_*` avatar files in [avatarsDir]
/// so they don't pile up every time the user re-picks. Tolerates locked
/// files and a directory that cannot be listed.
Future<void> deleteStaleGroupAvatars(Directory avatarsDir, String groupId) async {
  try {
    final prefix = 'group_${groupId}_';
    await for (final entity in avatarsDir.list()) {
      if (entity is File && p.basename(entity.path).startsWith(prefix)) {
        try {
          await entity.delete();
        } catch (e) {
          AppLogger.warn('[GroupAvatar] delete stale ${entity.path} failed: $e');
        }
      }
    }
  } catch (e) {
    AppLogger.warn('[GroupAvatar] stale cleanup scan failed: $e');
  }
}
