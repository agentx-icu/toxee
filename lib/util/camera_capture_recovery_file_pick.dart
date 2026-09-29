part of 'camera_capture_recovery.dart';

// Staging of document-picker files lost to a reclaim (M9, see
// [CameraCaptureRecovery.stageFilePick]).

Future<void> _stageFilePick(
  LostFilePick lost,
  Future<void> Function(String path) ack,
  DateTime at,
) async {
  // First: a pick already recorded by a run that died before its ack
  // belongs to that record, however old it is by now.
  Directory? dir;
  RecoveredCapture? previous;
  if (lost.accountKey.isNotEmpty) {
    dir = Directory(await CameraCaptureRecovery.capturesRoot(lost.accountKey));
    await dir.create(recursive: true);
    previous = await CameraCaptureRecovery._readRecord(dir, lost.accountKey);
    if (previous?.sourcePath == lost.path) {
      await ack(lost.path);
      return;
    }
  }
  if (dir == null ||
      lost.error != null ||
      lost.userId.isEmpty ||
      at.difference(lost.pickedAt) > CameraCaptureRecovery.targetTtl) {
    AppLogger.warn('[CameraCaptureRecovery] lost file pick: ${lost.error}');
    // The native side keeps a finished copy for us to move: drop it here.
    await CameraCaptureRecovery._delete(lost.path);
    await CameraCaptureRecovery._deleteIfEmpty(File(lost.path).parent);
    await ack(lost.path);
    return;
  }
  if (!File(lost.path).existsSync()) {
    await ack(lost.path); // nothing left to record
    return;
  }
  final capture = RecoveredCapture(
    accountKey: lost.accountKey,
    userId: lost.userId,
    path: _freshItemPath(dir, at, lost.name),
    isVideo: false,
    capturedAt: at,
    sourcePath: lost.path,
    isFile: true,
    name: lost.name,
  );
  await CameraCaptureRecovery._replaceRecord(dir, previous, capture);
  await ack(lost.path);
  await CameraCaptureRecovery._dropReplaced(dir, capture);
  await CameraCaptureRecovery._finishMove(dir, capture);
}

/// `<dir>/<ms>_<n>/<name>`: a directory of its own keeps the original name.
String _freshItemPath(Directory dir, DateTime now, String name) {
  for (var n = 0; ; n++) {
    final item = p.join(dir.path, '${now.millisecondsSinceEpoch}_$n');
    if (!Directory(item).existsSync() && !File(item).existsSync()) {
      return p.join(item, name);
    }
  }
}
