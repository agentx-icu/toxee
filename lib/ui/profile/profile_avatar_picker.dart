import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../util/app_paths.dart';
import '../../util/prefs.dart';

/// Result of [pickAndPersistAvatar] when the user actually chose a file.
class PickedAvatar {
  const PickedAvatar(this.destPath);
  final String destPath;
}

/// Show the system file picker, copy the chosen image into the per-account
/// avatars directory, and persist the new path in [Prefs]. Returns null if
/// the user cancelled the picker.
///
/// Pure I/O — no Flutter `setState` here, the caller owns UI state.
Future<PickedAvatar?> pickAndPersistAvatar({
  required bool isEditable,
  required String userId,
}) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  final pickedPath = result?.files.single.path;
  if (pickedPath == null) return null;
  final currentToxId = await Prefs.getCurrentAccountToxId();
  final avatarsDirPath = (currentToxId != null && currentToxId.isNotEmpty)
      ? await AppPaths.getAccountAvatarsPath(currentToxId)
      : (await AppPaths.avatars).path;
  final avatarsDir = Directory(avatarsDirPath);
  if (!await avatarsDir.exists()) {
    await avatarsDir.create(recursive: true);
  }
  final ext = p.extension(pickedPath);
  final ts = DateTime.now().millisecondsSinceEpoch;
  final baseName = isEditable && userId.isNotEmpty
      ? 'avatar_$userId'
      : 'self_avatar';
  final fileName = '${baseName}_$ts$ext';
  final destPath = p.join(avatarsDirPath, fileName);

  // Remove previous self-avatar files so stale versions don't accumulate.
  try {
    final dir = Directory(avatarsDirPath);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && p.basename(entity.path).startsWith(baseName)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
  } catch (_) {}

  await File(pickedPath).copy(destPath);
  await Prefs.setAvatarPath(destPath);
  if (isEditable && userId.isNotEmpty) {
    await Prefs.setAccountAvatarPath(userId, destPath);
  }
  return PickedAvatar(destPath);
}
