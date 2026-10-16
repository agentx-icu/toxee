import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tim2tox_dart/models/chat_message.dart'
    show mergeIntoLocalCustomData, queuedCancelledLocalCustomDataKey;

/// Stamps our own message's send state on [msg], as Tim2Tox keeps it on the
/// row (a send still queued is pending, also after a restart):
///
/// - cancelled before it went out: LOCAL_REVOKED plus Tim2Tox's marker, so
///   UIKit shows it like a recalled message (with its re-edit affordance);
/// - queued or on its way: SENDING, however long it waits;
/// - failed: SEND_FAIL (UIKit's Retry re-queues it in place).
///
/// Returns false for a message that went out: its receipts decide the rest.
bool applyOwnSendState(
  V2TimMessage msg, {
  required bool isCancelled,
  required bool isPending,
  required bool isFailed,
}) {
  if (isCancelled) {
    msg.status = MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED;
    msg.localCustomData = mergeIntoLocalCustomData(msg.localCustomData, {
      queuedCancelledLocalCustomDataKey: true,
    });
    return true;
  }
  if (isPending) {
    msg.status = MessageStatus.V2TIM_MSG_STATUS_SENDING;
    return true;
  }
  if (isFailed) {
    msg.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
    return true;
  }
  return false;
}
