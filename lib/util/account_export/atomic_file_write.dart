import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

const int _maxReservationAttempts = 1024;
int _nextInvocationId = 0;

/// Writes [bytes] through a same-directory temporary file and atomically renames
/// it into [target].
Future<void> writeBytesAtomically(
  File target,
  List<int> bytes, {
  String tempSuffix = '.tmp',
  @visibleForTesting
  Future<void> Function(File stage, File destination)? publishForTesting,
  @visibleForTesting int? reservationIdForTesting,
}) async {
  final invocationId = reservationIdForTesting ?? _allocateInvocationId();
  final parent = target.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }

  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final temp = await _reserveTemporaryFile(target, tempSuffix, invocationId);
  try {
    final handle = await temp.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(data);
      await handle.flush();
    } finally {
      await handle.close();
    }

    await (publishForTesting ?? _publishByRename)(temp, target);
  } finally {
    await _deleteStageBestEffort(temp);
  }
}

int _allocateInvocationId() {
  final invocationId = _nextInvocationId;
  _nextInvocationId += 1;
  return invocationId;
}

Future<File> _reserveTemporaryFile(
  File target,
  String tempSuffix,
  int invocationId,
) async {
  for (var attempt = 0; attempt < _maxReservationAttempts; attempt++) {
    final candidate = File(
      '${target.path}$tempSuffix.$pid.$invocationId.$attempt',
    );
    try {
      await candidate.create(exclusive: true);
      return candidate;
    } on PathExistsException {
      continue;
    }
  }
  throw const FileSystemException(
    'Unable to reserve a temporary file for atomic write',
  );
}

Future<void> _publishByRename(File stage, File destination) async {
  await stage.rename(destination.path);
}

Future<void> _deleteStageBestEffort(File stage) async {
  try {
    if (await stage.exists()) {
      await stage.delete();
    }
  } catch (_) {
    // Preserve the original write or publish failure.
  }
}
