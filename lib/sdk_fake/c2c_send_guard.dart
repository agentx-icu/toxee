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
Future<void> requireC2cFriend(FfiChatService ffi, String peerId) async {
  if (ffi.isSelfPeer(peerId)) return;
  final id = normalizeToxId(peerId);
  final friends = await ffi.getFriendList();
  if (!friends.any((f) => normalizeToxId(f.userId) == id)) {
    throw NotFriendSendException(peerId);
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
