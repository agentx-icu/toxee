import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';

import 'fake_models.dart';

/// Merge a refreshed conversation row into the existing one so a SPARSE emit
/// (recvOpt push, post-send / pin / draft notify built without a cached
/// snapshot) never clobbers known display fields with "" / null placeholders.
/// Split out of fake_provider.dart (complexity ratchet); behaviour unchanged.
V2TimConversation mergeExternalConversationUpdate({
  V2TimConversation? existing,
  required V2TimConversation refreshed,
}) {
  if (existing == null) return refreshed;

  // Display fields: treat EMPTY strings as absent, not just null. Sparse/minimal
  // native emits (the recvOpt mute push, post-send / pin / draft notifies built
  // without a cached snapshot) fill these with "" placeholders, which must not
  // clobber known values.
  if (refreshed.faceUrl == null || refreshed.faceUrl!.isEmpty) {
    refreshed.faceUrl = existing.faceUrl;
  }
  if (refreshed.showName == null || refreshed.showName!.isEmpty) {
    refreshed.showName = existing.showName;
  }
  refreshed.lastMessage ??= existing.lastMessage;
  // Scalars: sparse emits carry 0/false placeholders here too, but per-field
  // ownership is ambiguous (the pin notify legitimately owns isPinned while the
  // mute push does not), so keep null-coalescing. A placeholder that slips
  // through is transient: the ~5s FakeConversation rebuild restores the real
  // values from Prefs/FfiChatService.
  refreshed.orderkey ??= existing.orderkey;
  refreshed.unreadCount ??= existing.unreadCount;
  refreshed.isPinned ??= existing.isPinned;
  final groupId =
      refreshed.groupID ??
      existing.groupID ??
      refreshed.conversationID.replaceFirst('group_', '');
  final existingGroupType = resolveFakeConversationGroupType(
    groupId: groupId,
    authoritativeGroupType: existing.groupType,
  );
  final refreshedGroupType = resolveFakeConversationGroupType(
    groupId: groupId,
    authoritativeGroupType: refreshed.groupType,
  );
  final normalizedExistingGroupType = existingGroupType.trim().toLowerCase();
  final normalizedRefreshedGroupType = refreshedGroupType.trim().toLowerCase();
  final preserveExistingGroupType =
      (normalizedExistingGroupType == 'av_conference' &&
          normalizedRefreshedGroupType != 'av_conference') ||
      (normalizedExistingGroupType == 'conference' &&
          normalizedRefreshedGroupType == 'group') ||
      (normalizedExistingGroupType == 'public' &&
          normalizedRefreshedGroupType == 'group') ||
      (normalizedExistingGroupType == 'meeting' &&
          normalizedRefreshedGroupType == 'group') ||
      (normalizedExistingGroupType == 'community' &&
          normalizedRefreshedGroupType == 'group');
  if (preserveExistingGroupType) {
    refreshed.groupType = existing.groupType;
  } else {
    refreshed.groupType ??= existing.groupType;
  }
  refreshed.draftText ??= existing.draftText;
  refreshed.draftTimestamp ??= existing.draftTimestamp;
  return refreshed;
}
