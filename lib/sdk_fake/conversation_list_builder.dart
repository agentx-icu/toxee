import '../util/prefs.dart';
import '../util/tox_utils.dart';
import 'fake_models.dart';

/// Friend record shape used by the shared conversation-list builder. Matches the
/// `FfiChatService.getFriendList()` element record so callers can pass results
/// straight in without copying.
typedef ConvBuilderFriend = ({String userId, String nickName, bool online});

/// The self conversation (`c2c_<own public key>`, the user's local notebook —
/// see tim2tox `FfiChatService.isSelfPeer`): [key] is the canonical public
/// key, [title] the own nickname, [faceUrl] the own avatar, [activity] its
/// last message time (for activity sorting). It is not a friend (toxcore
/// refuses the own key), so the builder adds it explicitly.
typedef SelfConversationInput = ({
  String key,
  String title,
  String? faceUrl,
  DateTime? activity,
});

/// Single conversation-list builder used by both `FakeConversationManager.getConversationList()`
/// and `FakeIM._refreshConversationsWithFriends()`.
///
/// X5 (local-storage review 2026-05-18): previously the two callers built the
/// conversation list independently with subtly different normalization, pinned
/// checks, and group filtering. Drift between the two paths produced concrete
/// bugs (A6: pinned flag dropped on bus emit). This helper is the single source
/// of truth for the per-conversation shape — all variability lives in the
/// parameters.
///
/// Inputs:
/// - [friends]: friend records returned by FFI (already-loaded; caller decides
///   whether to merge with `Prefs.localFriends` via [mergeLocalFriendsAsOffline]).
/// - [groupIds]: candidate group IDs (typically `ffi.knownGroups`, optionally
///   merged with `Prefs.getGroups()` for the polling path).
/// - [pinned]: normalized pinned set. C2C entries are bare normalized userIDs;
///   group entries are `'group_${normalizedGid}'`. Use `Prefs.getPinned()`.
/// - [quitGroups]: group IDs that have been quit and must be filtered out.
/// - [pendingFriendIds]: friend application IDs we sent but the peer hasn't
///   accepted yet — these are filtered out unless the friend now appears in
///   the friend list (i.e. the application was accepted).
/// - [sortingMode]: when `'activity'`, C2C entries are sorted by last activity
///   timestamp (newest first); otherwise by title.
/// - [getUnreadOf]: hook so we don't depend on `FfiChatService` directly.
/// - [mergeLocalFriendsAsOffline]: when true, locally-persisted friends not in
///   the Tox friend list are added with `online: false` (used by the cold-start
///   sync read path in `getConversationList()`). When false, Tox is the sole
///   authority (used by the steady-state bus-emit path).
/// - [emitGroupType]: when true, `FakeConversation.groupType` is populated via
///   the canonical resolver so `Public` / `Meeting` / `AVChatRoom` /
///   `Community` survive sparse refreshes, while `group` / `conference` remain
///   the fallback shapes when no authoritative type is available.
/// - [self]: the self conversation (the user's local notebook), always listed
///   while an identity is loaded; pinned like any C2C through [pinned].
///
/// The function does not mutate any of its inputs or call into `Prefs`/`ffi`
/// outside the read-side helpers. All Prefs reads happen in parallel (batched
/// `Future.wait`) per friend/group to keep the cost O(1) round-trips.
Future<List<FakeConversation>> buildConversationsFromFriends({
  required List<ConvBuilderFriend> friends,
  required Iterable<String> groupIds,
  required Set<String> pinned,
  required Set<String> quitGroups,
  required Set<String> pendingFriendIds,
  required String sortingMode,
  required int Function(String id) getUnreadOf,
  bool mergeLocalFriendsAsOffline = false,
  bool emitGroupType = false,
  int? Function(String groupId)? getGroupActivityMs,
  String? Function(String groupId)? getGroupType,
  SelfConversationInput? self,
}) async {
  // ---- C2C: build the normalized friend map ----
  final friendMap = <String, ConvBuilderFriend>{};
  for (final f in friends) {
    final normalized = normalizeToxId(f.userId);
    friendMap[normalized] = (
      userId: normalized,
      nickName: f.nickName,
      online: f.online,
    );
  }

  // Optionally merge in locally-persisted friends not yet in the Tox list, so
  // cold-start renders can show offline friends with cached metadata.
  if (mergeLocalFriendsAsOffline) {
    final localFriends = await Prefs.getLocalFriends();
    for (final raw in localFriends) {
      final normalized = normalizeToxId(raw);
      if (normalized.isEmpty || friendMap.containsKey(normalized)) continue;
      final cachedNick = await Prefs.getFriendNickname(normalized);
      friendMap[normalized] = (
        userId: normalized,
        nickName: cachedNick ?? '',
        online: false,
      );
    }
  }

  // Build the normalized friend-id set used by the pending-app filter so a
  // newly-accepted friend (in the friend list AND still in pending apps) is
  // emitted instead of suppressed.
  final normalizedFriendIds = friendMap.keys.toSet();
  final normalizedPendingIds = pendingFriendIds.map(normalizeToxId).toSet();

  // Filter pending-but-not-yet-accepted friends.
  final emitFriends = friendMap.values.where((f) {
    final normalizedUserId = normalizeToxId(f.userId);
    if (normalizedPendingIds.contains(normalizedUserId) &&
        !normalizedFriendIds.contains(normalizedUserId)) {
      return false;
    }
    return true;
  }).toList();

  // Parallel-fetch avatar + activity for each friend so N friends collapse to
  // one batch round-trip instead of 2N sequential awaits.
  final c2cMeta = await Future.wait(
    emitFriends.map((f) async {
      final res = await Future.wait<Object?>([
        Prefs.getFriendAvatarPath(f.userId),
        Prefs.getFriendActivity(f.userId),
      ]);
      return (avatar: res[0] as String?, activity: res[1] as DateTime?);
    }),
  );

  final list = <FakeConversation>[];
  final activityByC2cId = <String, DateTime?>{};
  for (int i = 0; i < emitFriends.length; i++) {
    final f = emitFriends[i];
    final normalizedUserId = normalizeToxId(f.userId);
    activityByC2cId['c2c_${f.userId}'] = c2cMeta[i].activity;
    list.add(
      FakeConversation(
        conversationID: 'c2c_${f.userId}',
        title: f.nickName.isNotEmpty ? f.nickName : f.userId,
        faceUrl: c2cMeta[i].avatar,
        unreadCount: getUnreadOf(f.userId),
        isGroup: false,
        isPinned: pinned.contains(normalizedUserId),
      ),
    );
  }

  // ---- The self conversation: always present while an identity is loaded.
  if (self != null && !friendMap.containsKey(normalizeToxId(self.key))) {
    final convId = 'c2c_${self.key}';
    activityByC2cId[convId] = self.activity;
    list.add(
      FakeConversation(
        conversationID: convId,
        title: self.title,
        faceUrl: self.faceUrl,
        unreadCount: 0,
        isGroup: false,
        isPinned: pinned.contains(normalizeToxId(self.key)),
      ),
    );
  }

  // ---- Groups: dedupe candidate set, drop quit groups, batch-fetch metadata.
  final emitGroups = groupIds
      .toSet()
      .where((g) => !quitGroups.contains(g))
      .toList();
  final groupMeta = await Future.wait(
    emitGroups.map((gid) async {
      final res = await Future.wait<Object?>([
        Prefs.resolveGroupDisplayName(gid),
        Prefs.getGroupAvatar(gid),
      ]);
      return (name: res[0] as String, avatar: res[1] as String?);
    }),
  );
  // Activity timestamps for groups: previously hard-coded to 0 in the
  // sort, which pinned every group below every C2C in activity mode
  // regardless of recency. Now sourced from the caller-provided lookup
  // (typically `_ffi.lastMessages[gid]?.timestamp`).
  final activityByGroupId = <String, int>{};
  for (int i = 0; i < emitGroups.length; i++) {
    final gid = emitGroups[i];
    final groupPinnedKey = 'group_${normalizeToxId(gid)}';
    final convId = 'group_$gid';
    if (getGroupActivityMs != null) {
      final ms = getGroupActivityMs(gid);
      if (ms != null) activityByGroupId[convId] = ms;
    }
    list.add(FakeConversation(
      conversationID: convId,
      title: groupMeta[i].name,
      faceUrl: groupMeta[i].avatar,
      unreadCount: getUnreadOf(gid),
      isGroup: true,
      isPinned: pinned.contains(groupPinnedKey),
      groupType: emitGroupType
          ? resolveFakeConversationGroupType(
              groupId: gid,
              authoritativeGroupType: getGroupType?.call(gid),
            )
          : null,
    ));
  }

  // ---- Sort: pinned first, then by mode (activity timestamp or title).
  list.sort((a, b) {
    final aPinned = a.isPinned ? 0 : 1;
    final bPinned = b.isPinned ? 0 : 1;
    if (aPinned != bPinned) return aPinned.compareTo(bPinned);
    if (sortingMode == 'activity') {
      final aMs = a.conversationID.startsWith('c2c_')
          ? (activityByC2cId[a.conversationID]?.millisecondsSinceEpoch ?? 0)
          : (activityByGroupId[a.conversationID] ?? 0);
      final bMs = b.conversationID.startsWith('c2c_')
          ? (activityByC2cId[b.conversationID]?.millisecondsSinceEpoch ?? 0)
          : (activityByGroupId[b.conversationID] ?? 0);
      final cmp = bMs.compareTo(aMs);
      if (cmp != 0) return cmp;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

  return list;
}
