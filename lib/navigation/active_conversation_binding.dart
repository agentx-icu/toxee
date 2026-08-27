import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_navigator.dart';
import 'package:tencent_cloud_chat_sdk/enum/conversation_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../sdk_fake/uikit_data_facade.dart';

/// The BIND half of the active-conversation contract for PUSHED chat routes
/// (compact / phone shells); `ActiveConversationRouteObserver` is the unbind
/// half.
///
/// THE BUG THIS FIXES (found by the full real-UI matrix on iPhone,
/// 2026-08-23). On a compact shell only the conversation ROW tap bound the chat
/// it opened (`onTapConversationItem` → `setActivePeer` + `currentConversation`).
/// Every other way in — `HomePage._openChat` (contact profile "Send a message",
/// notification tap, the L3 seam, the just-created group) and global search —
/// pushed the message route WITHOUT binding. On phones that meant: the open
/// chat's unread count kept counting (`setActivePeer` is what zeroes it and
/// marks the conversation viewed), notifications for the chat the user was
/// looking at were NOT suppressed (`_shouldSuppress` reads
/// `currentConversation`), and `currentConversation` stayed null for every
/// reader. Desktop / tablet never hit this: `_selectConversation` binds the
/// right pane instead of pushing a route.
///
/// Resolve the conversation a chat target refers to: the live UIKit row when
/// the list has one, otherwise a minimal stand-in carrying the ids (a fresh
/// peer or group has no row yet). Shared with the desktop `_selectConversation`
/// so both shells bind the same object.
V2TimConversation resolveConversationTarget({String? peerId, String? groupId}) {
  final hasGroup = groupId != null && groupId.isNotEmpty;
  final targetConvId = hasGroup ? 'group_$groupId' : 'c2c_${peerId!}';
  V2TimConversation? target;
  for (final conv in UikitDataFacade.conversationList) {
    if (conv.conversationID == targetConvId) {
      target = conv;
      break;
    }
  }
  final groupType = hasGroup
      ? (() {
          final fromInfo = UikitDataFacade.getGroupInfo(groupId).groupType;
          return fromInfo.isNotEmpty ? fromInfo : target?.groupType;
        })()
      : null;
  if (target == null) {
    return V2TimConversation(
      conversationID: targetConvId,
      type: hasGroup
          ? ConversationType.V2TIM_GROUP
          : ConversationType.V2TIM_C2C,
      userID: hasGroup ? null : peerId,
      groupID: hasGroup ? groupId : null,
      showName: hasGroup ? groupId : peerId,
      groupType: groupType,
      unreadCount: 0,
    );
  }
  return V2TimConversation(
    conversationID: target.conversationID,
    type:
        target.type ??
        (hasGroup ? ConversationType.V2TIM_GROUP : ConversationType.V2TIM_C2C),
    userID: hasGroup ? null : peerId,
    groupID: hasGroup ? groupId : null,
    showName: target.showName ?? (hasGroup ? groupId : peerId) ?? targetConvId,
    faceUrl: target.faceUrl,
    // A C2C row keeps whatever groupType it carried (verbatim from the old
    // inline normalization); only group targets re-resolve it above.
    groupType: hasGroup ? groupType : target.groupType,
    unreadCount: target.unreadCount ?? 0,
    lastMessage: target.lastMessage,
    draftText: target.draftText,
    draftTimestamp: target.draftTimestamp,
    isPinned: target.isPinned,
    recvOpt: target.recvOpt,
    orderkey: target.orderkey,
    markList: target.markList,
    customData: target.customData,
    conversationGroupList: target.conversationGroupList,
    c2cReadTimestamp: target.c2cReadTimestamp,
    groupReadSequence: target.groupReadSequence,
    groupAtInfoList: target.groupAtInfoList,
  );
}

/// Bind [peerId] / [groupId] as the ACTIVE conversation before (or right
/// after) pushing its chat route on a compact shell — exactly what the
/// conversation row tap does, so every entry point leaves the app in the same
/// state. The route observer unbinds when the route leaves the stack.
void bindActiveConversation({
  required FfiChatService service,
  String? peerId,
  String? groupId,
}) {
  final target = resolveConversationTarget(peerId: peerId, groupId: groupId);
  service.setActivePeer(target.conversationID);
  UikitDataFacade.currentConversation = target;
}

/// Bind, then push the UIKit message route for a compact shell — the one call
/// every non-row entry point should make (global search today; `HomePage
/// ._openChat` binds inline because it also flips the shell to the Chats tab).
/// [targetMessage] lets a search hit land on the matched bubble.
void pushCompactChatRoute({
  required BuildContext context,
  required FfiChatService? service,
  String? userID,
  String? groupID,
  V2TimMessage? targetMessage,
}) {
  if (service != null) {
    bindActiveConversation(service: service, peerId: userID, groupId: groupID);
  }
  navigateToMessage(
    context: context,
    options: TencentCloudChatMessageOptions(
      userID: userID,
      groupID: groupID,
      targetMessage: targetMessage,
    ),
  );
}
