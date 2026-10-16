import 'dart:ffi' show Int8;

import 'package:ffi/ffi.dart' show Utf8, Utf8Pointer, malloc;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../util/logger.dart';
import '../util/tox_utils.dart';
import 'fake_managers.dart';

/// Thrown by [requireC2cFriend]; its text keeps the "not in your friend
/// list" wording the home page already maps to `userNotInFriendList`.
class NotFriendSendException implements Exception {
  const NotFriendSendException(this.peerId);

  final String peerId;

  @override
  String toString() => 'Cannot send: $peerId is not in your friend list';
}

/// Tim2Tox queues a C2C text for any key it does not see online, friend or
/// not, and a queue item for someone who is not (or no longer) a friend
/// never drains and never fails. So a C2C text needs a friend in the native
/// list (which includes friends we sent a request to); the note to self is
/// stored locally and needs none.
///
/// The match stays exactly the one sendTextWithResult uses (normalizeToxId,
/// no case folding), so the guard never admits a key the FFI would then
/// treat as an unknown, queued-forever peer.
///
/// SYNCHRONOUS ON PURPOSE. `Tim2ToxSdkPlatform.sendMessage` arms the reply /
/// forward cloudCustomData (and the read-receipt intent) on the shared
/// service right before the provider call, and `sendTextWithResult` consumes
/// it at its entry. An await in between lets a second send re-arm the slot,
/// so one message persisted the other's quote. The friend list is therefore
/// read from the same native export `FfiChatService.getFriendList` parses,
/// without its async nickname/status cache work.
void requireC2cFriend(FfiChatService ffi, String peerId) {
  if (ffi.isSelfPeer(peerId)) return;
  final id = normalizeToxId(peerId);
  final friends = (debugNativeFriendIds ?? _nativeFriendIds)(ffi);
  if (!friends.any((f) => normalizeToxId(f) == id)) {
    throw NotFriendSendException(peerId);
  }
}

/// Stands in for the native friend list in tests whose service is a fake.
/// Null => the native export.
@visibleForTesting
List<String> Function(FfiChatService ffi)? debugNativeFriendIds;

/// The user ids of `tim2tox_ffi_get_friend_list`: one friend per line,
/// tab-separated fields, the id first (the format and buffer size
/// `FfiChatService.getFriendList` uses).
List<String> _nativeFriendIds(FfiChatService ffi) {
  const capacity = 64 * 1024;
  final buf = malloc.allocate<Int8>(capacity);
  try {
    final n = ffi.tim2toxFfi.getFriendList(buf, capacity);
    if (n <= 0) return const [];
    return [
      for (final line in buf.cast<Utf8>().toDartString().split('\n'))
        if (line.split('\t').first case final uid when uid.isNotEmpty) uid,
    ];
  } finally {
    malloc.free(buf);
  }
}

/// Posts a local failure notice into [conversationID]; best effort: a
/// refused notice (no manager, no longer a friend) is logged, never thrown
/// out of the error handler that sends it.
Future<void> sendFailureNotice(
  FakeMessageManager? manager,
  String conversationID,
  String text,
) async {
  if (manager == null) return;
  try {
    await manager.sendText(conversationID, text);
  } catch (e, st) {
    AppLogger.logError('[FailureNotice] not sent to $conversationID', e, st);
  }
}
