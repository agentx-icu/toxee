// Group-sync logic extracted from _HomePageState.
//
// Owns two entry points:
//   • handleGroupChanged          — group profile/membership change events
//   • loadPersistedGroupsIntoUIKit — startup: load persisted groups into UIKit
//
// ───────────────────────────────────────────────────────────────────────────
// CRITICAL ORDERING INVARIANT (pinned by home_group_controller_ordering_test)
// ───────────────────────────────────────────────────────────────────────────
//
// handleGroupChanged MUST execute these four UIKit operations in this order:
//
//   1. clearMessageList                    — evict stale in-memory messages
//   2. deleteGroupInfoFromJoinedGroupList  — clean UIKit contact state
//   3. unblockConversation                 — counteract the quitGroup side-effect
//                                            fired by step 2 inside UIKit's
//                                            contact data module, which adds
//                                            `group_<id>` to
//                                            FakeChatDataProvider._sdkDeletedConvIds
//   4. refreshConversations                — rebuild the UIKit conversation list
//
// Without step 3, step 4 finds the conversation blocked and skips it, leaving
// a stale/missing entry in the UI conversation list.

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_common/external/chat_data_provider.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';

import '../../sdk_fake/fake_provider.dart';
import '../../sdk_fake/fake_uikit_core.dart';
import '../../sdk_fake/uikit_data_facade.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';

/// Injectable operations that touch UIKit singletons or the FFI service.
///
/// Grouping them here keeps [HomeGroupController]'s constructor readable and
/// lets tests substitute every UIKit/service call with ordered recorders
/// without poking the UIKit process-global singletons.
///
/// Use [GroupSyncOps.real] for production wiring.
class GroupSyncOps {
  GroupSyncOps({
    required this.clearMessageList,
    required this.getGroupListSnapshot,
    required this.deleteGroupInfoFromJoinedGroupList,
    required this.fetchSdkGroupListSnapshot,
    required this.buildGroupList,
    required this.addGroupInfoToJoinedGroupList,
    required this.getKnownGroups,
    required this.unblockConversation,
    required this.refreshConversations,
    required this.onUpdateTray,
  });

  final void Function(String groupID) clearMessageList;
  final List<V2TimGroupInfo> Function() getGroupListSnapshot;
  final void Function(String groupID) deleteGroupInfoFromJoinedGroupList;
  final Future<List<V2TimGroupInfo>> Function() fetchSdkGroupListSnapshot;
  final void Function(List<V2TimGroupInfo> list, String action) buildGroupList;
  final void Function(V2TimGroupInfo info) addGroupInfoToJoinedGroupList;
  final Set<String> Function() getKnownGroups;
  final void Function(String conversationID) unblockConversation;
  final Future<void> Function() refreshConversations;
  final Future<void> Function() onUpdateTray;

  /// Production wiring — every op hits the real UIKit singletons.
  static GroupSyncOps real({
    required Set<String> Function() getKnownGroups,
    required Future<void> Function() onUpdateTray,
  }) {
    return GroupSyncOps(
      clearMessageList: (gid) => UikitDataFacade.clearMessageList(groupID: gid),
      getGroupListSnapshot: () =>
          List<V2TimGroupInfo>.from(UikitDataFacade.groupList),
      // SILENT reconcile delete: handleGroupChanged STEP 2 removes the group
      // from the UIKit joined-list only to force buildGroupList to rebuild from
      // the SDK snapshot — it is NOT a real quit, so fireQuitEvent:false stops
      // the spurious quitGroup event (which used to remove the group from Prefs
      // + clear its conversation, then had to be manually counteracted).
      deleteGroupInfoFromJoinedGroupList: (gid) =>
          UikitDataFacade.deleteGroupInfoFromJoinedGroupList(
            gid,
            fireQuitEvent: false,
          ),
      fetchSdkGroupListSnapshot: () async {
        await TencentCloudChat.instance.chatSDKInstance.contactSDK
            .getGroupList();
        return List<V2TimGroupInfo>.from(UikitDataFacade.groupList);
      },
      buildGroupList: UikitDataFacade.buildGroupList,
      addGroupInfoToJoinedGroupList:
          UikitDataFacade.addGroupInfoToJoinedGroupList,
      getKnownGroups: getKnownGroups,
      unblockConversation: (convId) {
        final provider = ChatDataProviderRegistry.provider;
        if (provider is FakeChatDataProvider) {
          provider.unblockConversation(convId);
        }
      },
      refreshConversations: () async {
        await FakeUIKit.instance.im?.refreshConversations();
      },
      onUpdateTray: onUpdateTray,
    );
  }
}

/// Group sync logic extracted from `_HomePageState`.
///
/// All UIKit-touching operations are injected via [GroupSyncOps] so the
/// ordering invariant can be unit-tested without UIKit singletons.
class HomeGroupController {
  HomeGroupController({required GroupSyncOps ops}) : _ops = ops;

  final GroupSyncOps _ops;

  String _resolveGroupType(String groupId) {
    for (final group in _ops.getGroupListSnapshot()) {
      if (group.groupID == groupId && group.groupType.isNotEmpty) {
        return group.groupType;
      }
    }
    if (groupId.startsWith('tox_conf_')) {
      return GroupType.AVChatRoom;
    }
    return GroupType.Work;
  }

  /// Handle a group profile or membership change event.
  ///
  /// Preserves the four-step ordering invariant documented at the top of this
  /// file. Verified by `test/ui/home/home_group_controller_ordering_test.dart`.
  Future<void> handleGroupChanged(String groupId, {String? displayName}) async {
    if (kDebugMode) {
      debugPrint(
        '[HomeGroupController] handleGroupChanged: '
        'groupId=$groupId, displayName=$displayName',
      );
    }
    if (displayName != null && displayName.isNotEmpty) {
      await Prefs.setGroupName(groupId, displayName);
    }

    // ── STEP 1 ──────────────────────────────────────────────────────────
    // Evict stale in-memory messages so reused group IDs don't carry over
    // _messageListMap entries from the previous group instance.
    _ops.clearMessageList(groupId);

    // Snapshot BEFORE delete + SDK call: buildGroupList() clears the entire
    // UIKit list and only keeps SDK-returned groups; the snapshot lets us
    // merge historical groups back in.
    final existingGroups = _ops.getGroupListSnapshot();
    if (kDebugMode) {
      debugPrint(
        '[HomeGroupController] handleGroupChanged: '
        'snapshot ${existingGroups.length} existing groups',
      );
    }

    // ── STEP 2 ──────────────────────────────────────────────────────────
    // Delete the group from UIKit's joined-list so buildGroupList (which wipes
    // the whole list and keeps only SDK-returned groups) can rebuild it from the
    // merged snapshot below. This is a SILENT reconcile delete — the ops wiring
    // passes fireQuitEvent:false, so it NO LONGER fires a spurious quitGroup
    // event (which previously removed the group from Prefs + cleared its
    // conversation, requiring the manual counteractions that used to live here).
    // Real quit/dismiss/leave still fire the event via their own call sites.
    _ops.deleteGroupInfoFromJoinedGroupList(groupId);

    // Refresh the SDK list and merge with the snapshot.
    try {
      if (kDebugMode) {
        debugPrint(
          '[HomeGroupController] handleGroupChanged: fetchSdkGroupListSnapshot',
        );
      }
      final sdkGroupList = await _ops.fetchSdkGroupListSnapshot();
      if (kDebugMode) {
        debugPrint(
          '[HomeGroupController] handleGroupChanged: '
          'SDK returned ${sdkGroupList.length} groups',
        );
      }

      final existingGroupsMap = <String, V2TimGroupInfo>{};
      for (final group in existingGroups) {
        if (group.groupID.isEmpty) continue;
        if (group.groupID != groupId) {
          existingGroupsMap[group.groupID] = group;
        }
      }
      for (final group in sdkGroupList) {
        if (group.groupID.isEmpty) continue;
        existingGroupsMap[group.groupID] = group;
      }

      final mergedGroups = existingGroupsMap.values.toList();
      if (kDebugMode) {
        debugPrint(
          '[HomeGroupController] handleGroupChanged: '
          'merged ${mergedGroups.length} groups',
        );
      }
      _ops.buildGroupList(mergedGroups, '_handleGroupChanged_merge');
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[HomeGroupController] handleGroupChanged: '
          'fetchSdkGroupListSnapshot failed: $e',
        );
      }
    }

    // resolveGroupDisplayName picks alias > canonical name > gid; pass null
    // when no real name is set so UIKit doesn't render the raw id as a label.
    final resolvedName = await Prefs.resolveGroupDisplayName(groupId);
    final savedAvatar = await Prefs.getGroupAvatar(groupId);
    final groupInfo = V2TimGroupInfo(
      groupID: groupId,
      groupType: _resolveGroupType(groupId),
      groupName: resolvedName == groupId ? null : resolvedName,
      faceUrl: savedAvatar,
    );
    _ops.addGroupInfoToJoinedGroupList(groupInfo);

    // Ensure persistence before refreshConversations.
    final currentPersistedGroups = await Prefs.getGroups();
    if (!currentPersistedGroups.contains(groupId)) {
      currentPersistedGroups.add(groupId);
      await Prefs.setGroups(currentPersistedGroups);
    }

    // Small delay to ensure Prefs commit completes before the conversation
    // refresh reads from Prefs.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // ── STEP 3 ──────────────────────────────────────────────────────────
    // Unblock the conversation in FakeChatDataProvider. With STEP 2 now silent
    // this no longer counteracts a self-inflicted event; it clears any block
    // left by a PRIOR REAL quit/dismiss of this group id, so a re-join/re-create
    // shows its conversation again. MUST run before step 4.
    _ops.unblockConversation('group_$groupId');

    // ── STEP 4 ──────────────────────────────────────────────────────────
    if (kDebugMode) {
      debugPrint(
        '[HomeGroupController] handleGroupChanged: refreshConversations $groupId',
      );
    }
    await _ops.refreshConversations();
    await _ops.onUpdateTray();
  }

  /// Load persisted groups into UIKit on app startup.
  Future<void> loadPersistedGroupsIntoUIKit() async {
    try {
      if (kDebugMode) {
        debugPrint('[HomeGroupController] loadPersistedGroupsIntoUIKit: start');
      }

      final savedGroups = await Prefs.getGroups();
      final quitGroups = await Prefs.getQuitGroups();
      final activeGroups = savedGroups
          .where((g) => !quitGroups.contains(g))
          .toSet();

      final knownGroups = _ops.getKnownGroups();
      final allGroups = {...activeGroups, ...knownGroups};
      if (kDebugMode) {
        debugPrint(
          '[HomeGroupController] loadPersistedGroupsIntoUIKit: '
          '${allGroups.length} total (saved=${savedGroups.length} '
          'quit=${quitGroups.length} known=${knownGroups.length})',
        );
      }

      for (final gid in allGroups) {
        final displayName = await Prefs.resolveGroupDisplayName(gid);
        final savedAvatar = await Prefs.getGroupAvatar(gid);
        final groupInfo = V2TimGroupInfo(
          groupID: gid,
          groupType: _resolveGroupType(gid),
          groupName: displayName == gid ? null : displayName,
          faceUrl: savedAvatar,
        );
        _ops.addGroupInfoToJoinedGroupList(groupInfo);
      }

      final groupsBeforeSDK = _ops.getGroupListSnapshot();
      final sdkGroupList = await _ops.fetchSdkGroupListSnapshot();

      // When allGroups is empty (new account / post-logout), don't merge
      // groupsBeforeSDK — they're stale from the previous account.
      final groupsMap = <String, V2TimGroupInfo>{};
      if (allGroups.isNotEmpty) {
        for (final group in groupsBeforeSDK) {
          if (group.groupID.isEmpty) continue;
          if (!quitGroups.contains(group.groupID)) {
            groupsMap[group.groupID] = group;
          }
        }
      }
      for (final group in sdkGroupList) {
        if (group.groupID.isEmpty) continue;
        if (!quitGroups.contains(group.groupID)) {
          groupsMap[group.groupID] = group;
        }
      }

      final mergedGroups = groupsMap.values.toList();
      _ops.buildGroupList(mergedGroups, '_loadPersistedGroupsIntoUIKit_merge');
      await _ops.refreshConversations();
    } catch (e, stackTrace) {
      AppLogger.logError(
        '[HomeGroupController] loadPersistedGroupsIntoUIKit: error',
        e,
        stackTrace,
      );
    }
  }
}
