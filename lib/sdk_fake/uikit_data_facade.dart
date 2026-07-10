// UIKit data facade.
//
// Single audit point for every write toxee makes against
// `TencentCloudChat.instance.dataInstance.*`. The vendored Tencent Cloud
// Chat UIKit exposes those submodules (`contact`, `conversation`,
// `messageData`, `groupProfile`, `basic`, `search`) as undocumented
// private API — there are no contracts, version markers, or migration
// guarantees. Anything we touch here can break silently on a
// chat-uikit-flutter rebase, so we keep the surface narrow and labelled.
//
// Every method below is a thin forwarder. The docstring names the exact
// UIKit member it wraps so that when the next UIKit upgrade lands you
// can grep this file for "UIKit internal:" and walk every touchpoint.
// See also `doc/architecture/UIKIT_PRIVATE_API.en.md` for the
// regression checklist and CLAUDE.md > "Hybrid architecture" for why
// toxee even talks to UIKit data this way.
//
// Constraints:
//   - All methods are static. `dataInstance` is a process-global
//     singleton; per-instance state would be meaningless.
//   - No batching, dedup, or caching. Pure forwarding.
//   - When adding a new wrapper, the docstring MUST name the UIKit
//     member in the format used by existing methods.

import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/data/basic/tencent_cloud_chat_basic_data.dart';
import 'package:tencent_cloud_chat_common/data/conversation/tencent_cloud_chat_conversation_data.dart';
import 'package:tencent_cloud_chat_common/data/message/tencent_cloud_chat_message_data.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';

import '../util/logger.dart';

/// Thin forwarder over `TencentCloudChat.instance.dataInstance.*`.
///
/// See the file header for the design rationale. Each method is one
/// line where possible; multi-step operations only exist when the
/// previous inlined call site already did multiple things atomically
/// (see [clearAll]).
class UikitDataFacade {
  UikitDataFacade._();

  // ===========================================================================
  // contact submodule
  // Wraps `TencentCloudChat.instance.dataInstance.contact.*`.
  // ===========================================================================

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.addGroupInfoToJoinedGroupList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void addGroupInfoToJoinedGroupList(V2TimGroupInfo groupInfo) {
    TencentCloudChat.instance.dataInstance.contact
        .addGroupInfoToJoinedGroupList(groupInfo);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.applicationUnreadCount` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static int get applicationUnreadCount =>
      TencentCloudChat.instance.dataInstance.contact.applicationUnreadCount;

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.buildApplicationList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void buildApplicationList(
      List<V2TimFriendApplication> applicationList, String action) {
    TencentCloudChat.instance.dataInstance.contact
        .buildApplicationList(applicationList, action);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.buildFriendList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void buildFriendList(List<V2TimFriendInfo> contactList, String action) {
    TencentCloudChat.instance.dataInstance.contact
        .buildFriendList(contactList, action);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.buildGroupList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void buildGroupList(List<V2TimGroupInfo> groupList, String action) {
    TencentCloudChat.instance.dataInstance.contact
        .buildGroupList(groupList, action);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.buildUserStatusList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void buildUserStatusList(List<V2TimUserStatus> list, String action) {
    TencentCloudChat.instance.dataInstance.contact
        .buildUserStatusList(list, action);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.contactEventHandlers = ...`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static set contactEventHandlers(dynamic value) {
    TencentCloudChat.instance.dataInstance.contact.contactEventHandlers = value;
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.contactList` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static List<V2TimFriendInfo> get contactList =>
      TencentCloudChat.instance.dataInstance.contact.contactList;

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.deleteFromFriendList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void deleteFromFriendList(List<String> contactList, String action) {
    TencentCloudChat.instance.dataInstance.contact
        .deleteFromFriendList(contactList, action);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.deleteGroupInfoFromJoinedGroupList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  /// [fireQuitEvent] false performs a SILENT delete (no quitGroup event) — used
  /// by the group-list reconcile, which deletes-then-rebuilds and must not
  /// signal a real quit. Defaults true so real quit/dismiss paths are unchanged.
  static void deleteGroupInfoFromJoinedGroupList(String groupID,
      {bool fireQuitEvent = true}) {
    TencentCloudChat.instance.dataInstance.contact
        .deleteGroupInfoFromJoinedGroupList(groupID, fireQuitEvent: fireQuitEvent);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.getGroupInfo(...)` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static V2TimGroupInfo getGroupInfo(String groupID) {
    return TencentCloudChat.instance.dataInstance.contact.getGroupInfo(groupID);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.groupList` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static List<V2TimGroupInfo> get groupList =>
      TencentCloudChat.instance.dataInstance.contact.groupList;

  /// Wraps `TencentCloudChat.instance.dataInstance.contact.setApplicationUnreadCount(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void setApplicationUnreadCount(
      List<V2TimFriendApplication>? applicationList) {
    TencentCloudChat.instance.dataInstance.contact
        .setApplicationUnreadCount(applicationList);
  }

  // ===========================================================================
  // conversation submodule
  // Wraps `TencentCloudChat.instance.dataInstance.conversation.*`.
  // ===========================================================================

  /// Wraps `TencentCloudChat.instance.dataInstance.conversation.buildConversationList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void buildConversationList(
      List<V2TimConversation> convList, String action) {
    TencentCloudChat.instance.dataInstance.conversation
        .buildConversationList(convList, action);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.conversation.conversationConfig.setConfigs(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void setConversationConfig({bool? forceDesktopLayout}) {
    TencentCloudChat.instance.dataInstance.conversation.conversationConfig
        .setConfigs(forceDesktopLayout: forceDesktopLayout);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.conversation.conversationList` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static List<V2TimConversation> get conversationList =>
      TencentCloudChat.instance.dataInstance.conversation.conversationList;

  /// Wraps `TencentCloudChat.instance.dataInstance.conversation.currentConversation` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static V2TimConversation? get currentConversation =>
      TencentCloudChat.instance.dataInstance.conversation.currentConversation;

  /// Wraps `TencentCloudChat.instance.dataInstance.conversation.currentConversation = ...`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static set currentConversation(V2TimConversation? value) {
    TencentCloudChat.instance.dataInstance.conversation.currentConversation =
        value;
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.conversation.currentTargetMessage = ...`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static set currentTargetMessage(V2TimMessage? value) {
    TencentCloudChat.instance.dataInstance.conversation.currentTargetMessage =
        value;
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.conversation.notifyListener(TencentCloudChatConversationDataKeys.currentConversation)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void notifyCurrentConversation() {
    TencentCloudChat.instance.dataInstance.conversation
        .notifyListener(TencentCloudChatConversationDataKeys.currentConversation as dynamic);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.conversation.removeConversation(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void removeConversation(List<String> convIds) {
    TencentCloudChat.instance.dataInstance.conversation
        .removeConversation(convIds);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.conversation.setTotalUnreadCount(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void setTotalUnreadCount(int count) {
    TencentCloudChat.instance.dataInstance.conversation
        .setTotalUnreadCount(count);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.conversation.totalUnreadCount` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static int get totalUnreadCount =>
      TencentCloudChat.instance.dataInstance.conversation.totalUnreadCount;

  // ===========================================================================
  // messageData submodule
  // Wraps `TencentCloudChat.instance.dataInstance.messageData.*`.
  // ===========================================================================

  /// Wraps `TencentCloudChat.instance.dataInstance.messageData.clearMessageList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void clearMessageList({String? userID, String? groupID}) {
    TencentCloudChat.instance.dataInstance.messageData
        .clearMessageList(userID: userID, groupID: groupID);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.messageData.getMessageList(key: ...)` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static List<V2TimMessage> getMessageList({required String key}) {
    return TencentCloudChat.instance.dataInstance.messageData
        .getMessageList(key: key);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.messageData.messageListMap.keys` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  /// Exposed for the L3 Bug-C render check, which must enumerate EVERY render
  /// key and match by logical Tox identity rather than guess a single key form:
  /// the map is exact-string keyed and toxee populates it under several id forms
  /// (64-char pubkey, 76-char full id, with/without `c2c_` prefix, mixed case).
  static Iterable<String> messageListKeys() {
    return TencentCloudChat.instance.dataInstance.messageData.messageListMap.keys;
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.messageData.notifyListener(TencentCloudChatMessageDataKeys.messageNeedUpdate, userID, groupID)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void notifyMessageNeedUpdate({String? userID, String? groupID}) {
    TencentCloudChat.instance.dataInstance.messageData.notifyListener(
      TencentCloudChatMessageDataKeys.messageNeedUpdate as dynamic,
      userID: userID,
      groupID: groupID,
    );
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.messageData.onReceiveNewMessage(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void onReceiveNewMessage(V2TimMessage message) {
    TencentCloudChat.instance.dataInstance.messageData
        .onReceiveNewMessage(message);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.messageData.messageNeedUpdate = ...`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void setMessageNeedUpdate(V2TimMessage? message) {
    TencentCloudChat.instance.dataInstance.messageData.messageNeedUpdate =
        message;
  }

  // ===========================================================================
  // groupProfile submodule
  // Wraps `TencentCloudChat.instance.dataInstance.groupProfile.*`.
  // ===========================================================================

  /// Wraps `TencentCloudChat.instance.dataInstance.groupProfile.getGroupMemberList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static List<V2TimGroupMemberFullInfo?> getGroupMemberList(String? groupID) {
    return TencentCloudChat.instance.dataInstance.groupProfile
        .getGroupMemberList(groupID);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.groupProfile.loadGroupMemberList(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static Future<List<V2TimGroupMemberFullInfo?>> loadGroupMemberList({
    String? groupID,
    required bool loadGroupAdminAndOwnerOnly,
    String nextSeq = '0',
  }) {
    return TencentCloudChat.instance.dataInstance.groupProfile
        .loadGroupMemberList(
      groupID: groupID,
      loadGroupAdminAndOwnerOnly: loadGroupAdminAndOwnerOnly,
      nextSeq: nextSeq,
    );
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.groupProfile.updateGroupID` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static String get updateGroupID =>
      TencentCloudChat.instance.dataInstance.groupProfile.updateGroupID;

  /// Wraps `TencentCloudChat.instance.dataInstance.groupProfile.updateGroupID = ...`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static set updateGroupID(String value) {
    TencentCloudChat.instance.dataInstance.groupProfile.updateGroupID = value;
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.groupProfile.updateGroupInfo` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static V2TimGroupInfo get updateGroupInfo =>
      TencentCloudChat.instance.dataInstance.groupProfile.updateGroupInfo;

  /// Wraps `TencentCloudChat.instance.dataInstance.groupProfile.updateGroupInfo = ...`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static set updateGroupInfo(V2TimGroupInfo value) {
    TencentCloudChat.instance.dataInstance.groupProfile.updateGroupInfo = value;
  }

  // ===========================================================================
  // basic submodule
  // Wraps `TencentCloudChat.instance.dataInstance.basic.*`.
  //
  // The plugin/used-component plumbing is necessarily wider than the
  // other submodules because UIKit threads its component-registration
  // dance through `basic` (`addPlugin`, `addUsedComponent`,
  // `notifyListener(addUsedComponent)`).
  // ===========================================================================

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.addPlugin(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void addPlugin(TencentCloudChatPluginItem plugin) {
    TencentCloudChat.instance.dataInstance.basic.addPlugin(plugin);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.addUsedComponent(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void addUsedComponent(
      ({
        TencentCloudChatComponentsEnum componentEnum,
        TencentCloudChatWidgetBuilder widgetBuilder
      }) component) {
    TencentCloudChat.instance.dataInstance.basic.addUsedComponent(component);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.currentUser` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static V2TimUserFullInfo? get currentUser =>
      TencentCloudChat.instance.dataInstance.basic.currentUser;

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.getPlugin(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static TencentCloudChatPluginItem? getPlugin(String name) {
    return TencentCloudChat.instance.dataInstance.basic.getPlugin(name);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.hasPlugins(...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static bool hasPlugin(String name) {
    return TencentCloudChat.instance.dataInstance.basic.hasPlugins(name)
        as bool;
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.notifyListener(TencentCloudChatBasicDataKeys.addUsedComponent)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void notifyAddUsedComponent() {
    TencentCloudChat.instance.dataInstance.basic.notifyListener(
        TencentCloudChatBasicDataKeys.addUsedComponent as dynamic);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.plugins` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static List<TencentCloudChatPluginItem> get plugins =>
      TencentCloudChat.instance.dataInstance.basic.plugins;

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.updateCurrentUserInfo(userFullInfo: ...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void updateCurrentUserInfo(V2TimUserFullInfo userFullInfo) {
    TencentCloudChat.instance.dataInstance.basic
        .updateCurrentUserInfo(userFullInfo: userFullInfo);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.updateInitializedStatus(status: ...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void updateInitializedStatus(bool status) {
    TencentCloudChat.instance.dataInstance.basic
        .updateInitializedStatus(status: status);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.updateLoginStatus(status: ...)`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void updateLoginStatus(bool status) {
    TencentCloudChat.instance.dataInstance.basic
        .updateLoginStatus(status: status);
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.usedComponents` (read).
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static List<TencentCloudChatComponentsEnum> get usedComponents =>
      TencentCloudChat.instance.dataInstance.basic.usedComponents;

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.useCallKit = ...`.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void setUseCallKit(bool value) {
    TencentCloudChat.instance.dataInstance.basic.useCallKit = value;
  }

  /// Wraps `TencentCloudChat.instance.dataInstance.basic.useVideoCall = ...`.
  /// Video-specific gate on top of useCallKit — false on platforms without a
  /// camera capture backend (Windows/Linux) so video-call entry points are
  /// hidden while voice calling stays available.
  /// UIKit internal: private API; verify on every chat-uikit-flutter rebase.
  static void setUseVideoCall(bool value) {
    TencentCloudChat.instance.dataInstance.basic.useVideoCall = value;
  }

  // ===========================================================================
  // search submodule
  // Wraps `TencentCloudChat.instance.dataInstance.search.*`.
  //
  // Currently only touched by `clearAll` (the dispose-time reset). If new
  // search-data writes show up, add them here so they're audited too.
  // ===========================================================================

  // (no per-method wrappers yet — see clearAll below)

  // ===========================================================================
  // Cross-submodule helpers
  // ===========================================================================

  /// Mirrors the per-account reset previously inlined at
  /// `FakeUIKit.dispose()`: calls `clear()` on every submodule and then
  /// notifies listeners for the lists that don't notify on clear.
  ///
  /// UIKit internal: every submodule's `clear()` and the two trailing
  /// `buildGroupList([], ...)` / `buildConversationList([], ...)`
  /// notify-only calls are private API; verify on every chat-uikit-flutter
  /// rebase.
  static void clearAll({required String reason}) {
    try {
      final data = TencentCloudChat.instance.dataInstance;
      data.contact.clear();
      data.conversation.clear();
      data.messageData.clear();
      data.groupProfile.clear();
      data.basic.clear();
      data.search.clear();
      // clear() does not fire notifyListener; UI keeps showing stale
      // rows until something rebuilds the list. Send empty rebuilds so
      // contacts/conversations watchers re-render.
      data.contact.buildGroupList([], reason);
      data.conversation.buildConversationList([], reason);
    } catch (e, st) {
      AppLogger.logError(
          '[UikitDataFacade] clearAll failed (reason=$reason)', e, st);
    }
  }
}
