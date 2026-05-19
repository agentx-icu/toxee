import 'dart:async';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/friend_asset_cleanup.dart';
import '../util/prefs.dart';
import '../util/tox_utils.dart';
import '../util/logger.dart';
import 'fake_event_bus.dart';
import 'fake_managers.dart' show buildConversationsFromFriends;
import 'fake_models.dart';

class FakeIM {
  FakeIM(this.ffi, this.bus);
  final FfiChatService ffi;
  final FakeEventBus bus;

  // Topic names chosen to mirror uikit usage style
  static const topicConversation = 'FakeConversation';
  static const topicMessage = 'FakeMessage';
  static const topicTyping = 'FakeTyping';
  static const topicUnread = 'FakeUnread';
  static const topicContacts = 'FakeContacts';
  static const topicFriendApps = 'FakeFriendApps';
  static const topicFriendDeleted = 'FakeFriendDeleted';
  static const topicGroupDeleted = 'FakeGroupDeleted';

  Timer? _refreshTimer;
  Timer? _startupInitTimer;
  StreamSubscription<dynamic>? _avatarUpdatedSub;
  StreamSubscription<dynamic>? _nicknameUpdatedSub;
  StreamSubscription<dynamic>? _messagesSub;
  StreamSubscription<dynamic>? _friendDeletedSub;
  final Map<String, bool> _typingPrev = {};
  Set<String> _previousFriendIds = {};
  Set<String> _previousGroupIds = {};
  List<FakeUser>? _previousContactList; // Cache previous contact list for deduplication
  bool _emitContactsRunning = false; // Reentrant guard: prevents concurrent _emitContactsWithFriends
  bool _toxFriendListReceived = false; // True once Tox has returned a non-empty friend list
  bool _disposed = false;

  // Cold-start grace window. After we restore the friend list from Prefs
  // (because Tox hasn't returned anything yet), Tox usually loads friends
  // incrementally over the next few seconds. During this window we must NOT
  // treat "in previous set but not in current Tox list" as a deletion —
  // those friends may simply not be loaded yet. We also keep rendering them
  // from cache so the contact list doesn't flicker.
  DateTime? _coldStartRestoreAt;
  static const Duration _kColdStartGrace = Duration(seconds: 15);

  /// X9 — pending friend adds (local-storage review 2026-05-18).
  ///
  /// `Prefs.localFriends` plays two roles that conflict during the race
  /// between an app-side friend accept/add and the first Tox poll that
  /// confirms it: (1) cold-start cache, (2) authoritative mirror that
  /// `_emitContactsWithFriendsImpl` overwrites every ~5 s with whatever Tox
  /// returns. The `_toxFriendListReceived` flag mediates the cold-start case
  /// but does NOT protect against the steady-state overwrite — an accept that
  /// happens between two poll cycles is discarded when the next poll arrives
  /// and Tox hasn't yet propagated the new friend.
  ///
  /// `_pendingFriendAdds` is the explicit "I accepted/added X, Tox hasn't
  /// confirmed yet" buffer. Stored as `{normalizedId: expiresAt}` so old
  /// entries get evicted automatically — Tox will normally confirm in
  /// seconds, but if confirmation never arrives we don't want the cache to
  /// be haunted forever.
  final Map<String, DateTime> _pendingFriendAdds = {};
  static const Duration _kPendingFriendAddTtl = Duration(seconds: 30);

  /// Register a friend ID as just-accepted/added but not yet confirmed by
  /// Tox. Caller should pass the raw or normalized ID; we always normalize.
  /// Entry expires automatically after [_kPendingFriendAddTtl] so that a
  /// never-confirmed accept does not leak into the persistent friend list
  /// forever.
  ///
  /// Tests may pass [ttlOverride] to exercise the eviction path without
  /// having to wait the full production TTL.
  void registerPendingFriendAdd(String userId, {Duration? ttlOverride}) {
    final normalized = normalizeToxId(userId);
    if (normalized.isEmpty) return;
    _pendingFriendAdds[normalized] =
        DateTime.now().add(ttlOverride ?? _kPendingFriendAddTtl);
    AppLogger.log(
        '[FakeIM] registerPendingFriendAdd: $normalized (now=${_pendingFriendAdds.length} pending)');
  }

  /// Returns the currently-live (non-expired) pending friend IDs. Used by the
  /// poll path to merge into the authoritative Tox set when writing back to
  /// `Prefs.localFriends`. Also prunes expired entries as a side effect.
  Set<String> _livePendingFriendAdds() {
    final now = DateTime.now();
    _pendingFriendAdds.removeWhere((_, expiresAt) => expiresAt.isBefore(now));
    return _pendingFriendAdds.keys.toSet();
  }

  /// Test/inspection hook: snapshot of the current pending-add map. Returns a
  /// copy so callers cannot mutate internal state.
  Map<String, DateTime> get debugPendingFriendAdds =>
      Map.unmodifiable(_pendingFriendAdds);

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  /// Run an async body inside a timer/listener callback. Catches and logs any
  /// throw so a single failed Tox FFI call cannot kill the polling loop or
  /// stop subsequent invocations.
  Future<void> _runGuarded(String label, Future<void> Function() body) async {
    if (_disposed) return;
    try {
      await body();
    } catch (e, st) {
      AppLogger.logError('[FakeIM] $label failed', e, st);
    }
  }

  void start() {
    // A8: when a friend is deleted (detected by the steady-state poll diffing
    // Tox's friend list against our previous snapshot), purge the on-disk
    // avatar file + avatar_hash_<id> / friend_avatar_path_<id> prefs keys.
    // tim2tox's FfiChatService.deleteFriend does not handle these, so the
    // cleanup has to happen client-side. Subscribing here means *any* path
    // that ends in a topicFriendDeleted emit (manual delete, account switch,
    // remote-side removal) triggers the cleanup.
    _friendDeletedSub =
        bus.on<FakeFriendDeleted>(topicFriendDeleted).listen((evt) {
      final id = evt.userID;
      if (id.isEmpty) return;
      unawaited(_runGuarded('friendDeleted→cleanupAssets',
          () => FriendAssetCleanup.deleteAllAssetsFor(id)));
    }, onError: (e, st) {
      AppLogger.logError('[FakeIM] topicFriendDeleted stream error', e, st);
    });
    // When a friend's avatar is received and saved, refresh conversations and contact list so the UI updates
    _avatarUpdatedSub = ffi.avatarUpdated.listen((uid) {
      if (_disposed) return;
      unawaited(_runGuarded('avatarUpdated→refresh', () async {
        await _refreshConversations();
        await _emitContacts();
      }));
    }, onError: (e, st) {
      AppLogger.logError('[FakeIM] ffi.avatarUpdated stream error', e, st);
    });
    // When a friend's nickname changes, refresh conversations so the UI updates
    _nicknameUpdatedSub = ffi.nicknameUpdated.listen((uid) {
      if (_disposed) return;
      unawaited(_runGuarded('nicknameUpdated→refresh', _refreshConversations));
    }, onError: (e, st) {
      AppLogger.logError('[FakeIM] ffi.nicknameUpdated stream error', e, st);
    });
    // One-shot startup init: wait 500ms for Tox to bootstrap, then do a
    // retry loop to seed conversations + history as soon as the friend
    // list is non-empty. Cold-start grace handles the case where Tox is
    // still loading after the retries exhaust.
    _startupInitTimer?.cancel();
    _startupInitTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_runGuarded('startupInit', () async {
        int retries = 0;
        const maxRetries = 5;
        int retryDelay = 200;
        while (retries < maxRetries) {
          if (_disposed) return;
          final friends = await ffi.getFriendList();
          if (_disposed) return;
          if (friends.isNotEmpty || retries >= maxRetries - 1) {
            unawaited(_runGuarded('startupInit→refreshConv', _refreshConversations));
            unawaited(_runGuarded('startupInit→emitContacts', _emitContacts));
            if (_disposed) return;
            await _runGuarded('startupInit→seedHistory', _seedHistory);
            break;
          }
          retries++;
          await Future.delayed(Duration(milliseconds: retryDelay));
          retryDelay = (retryDelay * 2).clamp(200, 3200);
        }
      }));
    });

    // Single steady-state poller. Previously we ran three overlapping timers
    // (500ms fast × 20, 2s slow × 10, and 5s steady), but the fast/slow tier
    // only re-emitted contacts when "any friend is online" — a broken
    // heuristic that fired every cycle once anyone connected, doing 20-30
    // redundant emits during the first 30s without actually improving
    // online-status detection latency. Now: one 5s timer doing the full
    // refresh. Event-driven streams (avatarUpdated, nicknameUpdated,
    // messages) handle the latency-sensitive cases.
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_runGuarded('steadyRefresh', () async {
        final friends = await ffi.getFriendList();
        await _refreshConversationsWithFriends(friends);
        await _emitContactsWithFriends(friends);
        await _emitFriendAppsWithFriends(friends);
        await _scanTyping();
      }));
    });
    // Also emit contacts immediately after friend operations to ensure UI updates
    // This is handled by the periodic timer, but we can also trigger it manually if needed
    // Listen messages
    // Track conversationID for self messages by checking which peer's history contains the message
    _messagesSub = ffi.messages.listen((m) {
      if (_disposed) return;
      // Debug: log file messages to track where they come from
      if (m.filePath != null || m.mediaKind != null) {
        AppLogger.log('[FakeIM] Received file message from ffi.messages stream: msgID=${m.msgID}, filePath=${m.filePath}, fileName=${m.fileName}, isPending=${m.isPending}');
      }
      String? convId;
      if (m.groupId != null) {
        // Group message
        convId = 'group_${m.groupId}';
      } else if (m.isSelf) {
        // Self-sent C2C message: first try to find the conversation from message history.
        // This is critical for forward messages, which should be added to the target conversation,
        // not the current active conversation (activePeerId).
        if (m.msgID != null) {
          final result = ffi.findUserIDAndGroupIDFromMsgID(m.msgID!);
          final targetUserID = result.$1;
          if (targetUserID != null && targetUserID != ffi.selfId) {
            convId = 'c2c_$targetUserID';
          }
        }
        // Fallbacks if not found in history: activePeerId, then most recent peer.
        // We refuse to emit a self-conversation (`c2c_${selfId}`) because there
        // is no such chat in the product — doing so creates a ghost entry in
        // the conversation list. If we can't resolve a target, drop the
        // immediate emit; the conversation refresh below will pick the message
        // up from history on the next cycle.
        if (convId == null) {
          if (ffi.activePeerId != null && ffi.activePeerId != ffi.selfId) {
            convId = 'c2c_${ffi.activePeerId}';
          } else {
            final recentPeer = ffi.lastMessages.keys
                .firstWhere((k) => k != ffi.selfId, orElse: () => '');
            if (recentPeer.isNotEmpty) {
              convId = 'c2c_$recentPeer';
            }
          }
        }
      } else {
        // Received message: sender is the peer.
        // Normalize friend ID to ensure consistent conversationID
        // (matches FfiChatService normalization when saving history).
        final fromUserId = m.fromUserId;
        final normalizedFrom = fromUserId.length > 64
            ? fromUserId.substring(0, 64).trim()
            : fromUserId.trim();
        // Drop self-echo: a "received" message from selfId is malformed and
        // would land in a ghost self-conversation.
        if (normalizedFrom.isNotEmpty && normalizedFrom != ffi.selfId) {
          convId = 'c2c_$normalizedFrom';
        }
      }

      if (convId == null) {
        AppLogger.log('[FakeIM] dropping unroutable message emit: '
            'msgID=${m.msgID} isSelf=${m.isSelf} groupId=${m.groupId} '
            'fromUser=${m.fromUserId} (no target peer, history refresh will recover)');
      } else {
        final msg = FakeMessage(
          msgID: m.msgID ?? '${m.timestamp.millisecondsSinceEpoch}_${m.fromUserId}',
          conversationID: convId,
          fromUser: m.fromUserId,
          text: m.text,
          timestampMs: m.timestamp.millisecondsSinceEpoch,
          filePath: m.filePath,
          fileName: m.fileName,
          mediaKind: m.mediaKind,
          isPending: m.isPending,
          isReceived: m.isReceived,
          isRead: m.isRead,
        );
        bus.emit(topicMessage, msg);
      }
      _emitUnreadTotal();
      // Always refresh the conversation list so the latest message preview is
      // accurate, even if we dropped the bus emit above.
      unawaited(_runGuarded('messages→refreshConv', _refreshConversations));
    }, onError: (e, st) {
      AppLogger.logError('[FakeIM] ffi.messages stream error', e, st);
    });
  }

  void dispose() {
    _disposed = true;
    _avatarUpdatedSub?.cancel();
    _avatarUpdatedSub = null;
    _nicknameUpdatedSub?.cancel();
    _nicknameUpdatedSub = null;
    _messagesSub?.cancel();
    _messagesSub = null;
    _friendDeletedSub?.cancel();
    _friendDeletedSub = null;
    _startupInitTimer?.cancel();
    _startupInitTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _typingPrev.clear();
    _previousFriendIds.clear();
    _previousGroupIds.clear();
    _previousContactList = null;
    _emitContactsRunning = false;
    _toxFriendListReceived = false;
    _coldStartRestoreAt = null;
    _pendingFriendAdds.clear();
  }

  Future<void> _refreshConversations() async {
    final friends = await ffi.getFriendList();
    await _refreshConversationsWithFriends(friends);
  }

  Future<void> _refreshConversationsWithFriends(
      List<({String userId, String nickName, String status, bool online})> friends) async {
    // `pinned` stores **normalized** keys: bare normalized userID for C2C and
    // 'group_${normalizedGid}' for groups (see FakeConversationManager.setPinned).
    final pinned = (await Prefs.getPinned())
        .where((s) => s.isNotEmpty)
        .toSet();
    // Pending friend applications (we sent, peer hasn't accepted yet): hide
    // from conversation list until they appear in the friend list.
    final pendingApps = await ffi.getFriendApplications();
    final pendingFriendIds = pendingApps.map((a) => a.userId).toSet();
    final quitGroups = await Prefs.getQuitGroups();
    final sortingMode = await Prefs.getFriendListSortingMode();

    // The polling path merges persisted groups with `knownGroups` so groups
    // that haven't fully loaded back into the runtime yet still render on
    // startup. The sync `getConversationList()` path does NOT merge (it trusts
    // the live `knownGroups`), so this merge lives here, not in the builder.
    final persistedGroups = await Prefs.getGroups();
    final mergedGroupCandidates =
        {...ffi.knownGroups, ...persistedGroups};
    final currentGroupIds = mergedGroupCandidates
        .where((g) => !quitGroups.contains(g))
        .toSet();

    // Group-deletion detection — must run BEFORE we hand the merged set to the
    // builder so we can persist the change and emit topicGroupDeleted exactly
    // once. Compare against the previous non-quit set.
    final deletedGroupIds = _previousGroupIds.difference(currentGroupIds);
    if (deletedGroupIds.isNotEmpty && _previousGroupIds.isNotEmpty) {
      for (final deletedId in deletedGroupIds) {
        // Remove from local groups persistence (the source of truth Prefs sees).
        final localGroups = await Prefs.getGroups();
        localGroups.remove(deletedId);
        await Prefs.setGroups(localGroups);
        bus.emit(topicGroupDeleted, FakeGroupDeleted(groupID: deletedId));
      }
    }
    final previousGroupIdsSnapshot = _previousGroupIds;
    _previousGroupIds = currentGroupIds;

    // Mirror the historical behavior: groups that were previously known but
    // have since landed in quitGroups also get a deletion event.
    for (final quitGid in quitGroups) {
      if (previousGroupIdsSnapshot.contains(quitGid) &&
          !currentGroupIds.contains(quitGid)) {
        bus.emit(topicGroupDeleted, FakeGroupDeleted(groupID: quitGid));
      }
    }

    // X5: route through the shared builder so the polling emit and the sync
    // `getConversationList()` cannot drift on normalization / pinned check /
    // group filter again. Steady-state path is Tox-authoritative — no
    // local-friends merge — and emits groupType for the UI.
    final builderFriends = friends
        .map((f) => (userId: f.userId, nickName: f.nickName, online: f.online))
        .toList();
    final convs = await buildConversationsFromFriends(
      friends: builderFriends,
      groupIds: currentGroupIds,
      pinned: pinned,
      quitGroups: quitGroups,
      pendingFriendIds: pendingFriendIds,
      sortingMode: sortingMode,
      getUnreadOf: ffi.getUnreadOf,
      mergeLocalFriendsAsOffline: false,
      emitGroupType: true,
    );
    for (final conv in convs) {
      bus.emit(topicConversation, conv);
    }
    // Note: _emitUnreadTotal() is now called automatically by FakeChatDataProvider
    // when conversation list updates, so we don't need to call it here.
  }

  Future<void> refreshConversations() async {
    await _refreshConversations();
  }

  Future<void> _emitContacts() async {
    final friends = await ffi.getFriendList();
    await _emitContactsWithFriends(friends);
  }

  Future<void> _emitContactsWithFriends(
      List<({String userId, String nickName, String status, bool online})> friends) async {
    // Reentrant guard: multiple timers (startup poll, 5s refresh, onlineStatusChanged)
    // can call this concurrently. Without this guard, a concurrent call may read stale
    // Prefs data (before another call finishes writing the deletion) and re-emit the
    // deleted friend, causing it to reappear in the contact list.
    if (_emitContactsRunning) return;
    _emitContactsRunning = true;
    try {
      await _emitContactsWithFriendsImpl(friends);
    } finally {
      _emitContactsRunning = false;
    }
  }

  Future<void> _emitContactsWithFriendsImpl(
      List<({String userId, String nickName, String status, bool online})> friends) async {
    // Always merge with locally persisted friends to ensure all friends are shown
    // This is important after client restart when Tox hasn't fully restored friends yet
    final localFriends = await Prefs.getLocalFriends();
    final normalizedLocalFriends = localFriends.map((uid) => normalizeToxId(uid)).toSet();

    // If friend list is empty and Tox hasn't returned friends yet,
    // try to restore from local persistence (cold-start fallback).
    // Once Tox has returned a non-empty list, we trust Tox exclusively.
    if (friends.isEmpty && !_toxFriendListReceived && normalizedLocalFriends.isNotEmpty) {
      // Create FakeUser list from local persisted friend IDs
      // These friends will be marked as offline since we don't have online status yet
      // Load nickname and status from cache for restored friends
      final restoredList = await Future.wait(normalizedLocalFriends.map((uid) async {
        final cachedNick = await Prefs.getFriendNickname(uid);
        final cachedStatus = await Prefs.getFriendStatusMessage(uid);
        final cachedAvatar = await Prefs.getFriendAvatarPath(uid);
        return FakeUser(
          userID: uid,
          nickName: cachedNick ?? '',
          status: cachedStatus ?? '',
          online: false,
          faceUrl: cachedAvatar,
        );
      }));
      // Check if restored list is different from previous
      bool hasChanged = false;
      if (_previousContactList == null) {
        hasChanged = true;
      } else {
        if (restoredList.length != _previousContactList!.length) {
          hasChanged = true;
        } else {
          final previousMap = <String, FakeUser>{};
          for (final user in _previousContactList!) {
            previousMap[user.userID] = user;
          }
          for (final user in restoredList) {
            final previous = previousMap[user.userID];
            if (previous == null ||
                previous.nickName != user.nickName ||
                previous.status != user.status ||
                previous.online != user.online ||
                previous.faceUrl != user.faceUrl) {
              hasChanged = true;
              break;
            }
          }
        }
      }
      
      if (hasChanged) {
        bus.emit(topicContacts, restoredList);
        _previousContactList = List.from(restoredList);
      }
      // Update previous friend IDs to include restored friends and start the
      // cold-start grace window. The next non-empty Tox poll will compare its
      // partial list against this restored set, and during the grace window we
      // suppress deletions to avoid wiping not-yet-loaded friends.
      _previousFriendIds = normalizedLocalFriends;
      _coldStartRestoreAt = DateTime.now();
      return;
    }

    // Build the Tox-only friend set FIRST for accurate deletion detection.
    // Deletion must be detected against Tox state (the source of truth), NOT the merged
    // set that includes local persistence — otherwise local persistence re-adds the deleted
    // friend into the merged set, making the difference empty and preventing detection.
    _toxFriendListReceived = true; // Tox returned a non-empty list; trust it from now on
    final friendMap = <String, FakeUser>{};
    final toxFriendIds = <String>{};
    // X9: snapshot pending adds before we touch the Tox set; entries that
    // appear in Tox below are confirmed and dropped from pending.
    final pendingBefore = _livePendingFriendAdds();
    // Parallel-fetch avatar paths instead of N sequential awaits. With ~100
    // friends this collapses the loop from N microtasks to a single batch.
    final normalizedTox = friends
        .map((f) => (
              normalized: normalizeToxId(f.userId),
              source: f,
            ))
        .toList();
    final toxAvatars = await Future.wait(
        normalizedTox.map((e) => Prefs.getFriendAvatarPath(e.normalized)));
    for (int i = 0; i < normalizedTox.length; i++) {
      final normalizedId = normalizedTox[i].normalized;
      final f = normalizedTox[i].source;
      toxFriendIds.add(normalizedId);
      friendMap[normalizedId] = FakeUser(
        userID: normalizedId,
        nickName: f.nickName,
        status: f.status,
        online: f.online,
        faceUrl: toxAvatars[i],
      );
      // X9: a confirmed friend is no longer pending — drop it so the next
      // localFriends-write doesn't include duplicate semantics.
      _pendingFriendAdds.remove(normalizedId);
    }
    // Recompute live pending after the confirmations above.
    final livePending = _livePendingFriendAdds();
    if (pendingBefore.isNotEmpty || livePending.isNotEmpty) {
      AppLogger.log(
          '[FakeIM] X9 pending friend adds: before=${pendingBefore.length} live=${livePending.length}');
    }

    // Compute the diff between what we previously believed the friend list
    // was and what Tox returned now.
    final missingFromTox = _previousFriendIds.isNotEmpty
        ? _previousFriendIds.difference(toxFriendIds)
        : <String>{};

    // Cold-start grace: Tox may return friends incrementally for the first
    // few seconds after restore. During that window, do NOT treat
    // "previously known, not in Tox yet" as deletion — render those friends
    // from Prefs cache instead so they don't disappear from the UI.
    final inColdStartGrace = _coldStartRestoreAt != null &&
        DateTime.now().difference(_coldStartRestoreAt!) < _kColdStartGrace;
    // X9: a friend that's currently pending (recent accept/add, Tox not yet
    // confirmed) must NOT be flagged for deletion. Removing it would emit
    // topicFriendDeleted and wipe its prefs/avatar, defeating the whole
    // purpose of the pending buffer.
    final deletedFriendIds = inColdStartGrace
        ? <String>{}
        : missingFromTox.difference(livePending);

    if (inColdStartGrace && missingFromTox.isNotEmpty) {
      // Re-hydrate missing friends from cache so the UI stays stable while
      // Tox finishes loading. They will be marked offline.
      // Parallel-fetch nickname/status/avatar instead of 3N sequential awaits.
      final toHydrate = missingFromTox
          .where((pendingId) => !friendMap.containsKey(pendingId))
          .toList();
      final hydrated = await Future.wait(toHydrate.map((pendingId) async {
        final results = await Future.wait([
          Prefs.getFriendNickname(pendingId),
          Prefs.getFriendStatusMessage(pendingId),
          Prefs.getFriendAvatarPath(pendingId),
        ]);
        return FakeUser(
          userID: pendingId,
          nickName: results[0] ?? '',
          status: results[1] ?? '',
          online: false,
          faceUrl: results[2],
        );
      }));
      for (final user in hydrated) {
        friendMap[user.userID] = user;
      }
    } else if (_coldStartRestoreAt != null && !inColdStartGrace) {
      // Grace expired: clear the timestamp so we don't keep checking.
      _coldStartRestoreAt = null;
    }

    if (deletedFriendIds.isNotEmpty) {
      final updatedLocalFriends = await Prefs.getLocalFriends();
      for (final deletedId in deletedFriendIds) {
        // Remove ALL variants of this friend ID from local persistence.
        // Prefs may store the 76-char Tox address (pubkey + nospam + checksum)
        // while deletedId is the 64-char public key. A plain remove() won't
        // match. We must remove any ID whose first 64 chars match the deleted
        // public key.
        final pubkey = normalizeToxId(deletedId);
        updatedLocalFriends.removeWhere((id) => normalizeToxId(id) == pubkey);
        bus.emit(topicFriendDeleted, FakeFriendDeleted(userID: deletedId));
      }
      await Prefs.setLocalFriends(updatedLocalFriends);
    }

    // Persist whatever we currently believe the friend list is. During grace
    // we keep the union (Tox + still-pending) so a crash mid-grace doesn't
    // lose the restored entries. Outside grace, Tox is authoritative — except
    // we also merge X9 pending-adds so a friend the app just accepted does
    // not get destroyed by this overwrite before Tox confirms.
    final authoritativeIds = inColdStartGrace
        ? toxFriendIds.union(missingFromTox).union(livePending)
        : toxFriendIds.union(livePending);
    // Only write to SharedPreferences when the set actually changed. The
    // steady-state poll runs every 5s and most cycles see no friend churn —
    // unconditional writes were doing one disk/IPC write per tick for no
    // semantic effect. Compare against `localFriends` we already read at the
    // top of this method; if the deletion path above changed Prefs, that
    // write already covers the diff.
    if (deletedFriendIds.isEmpty &&
        !_setEquals(normalizedLocalFriends, authoritativeIds)) {
      await Prefs.setLocalFriends(authoritativeIds);
    }

    // Update previous friend IDs for next-poll diff. Include pending so the
    // next-poll deletion detection doesn't treat the still-pending entries as
    // "previously known, missing now" (they would otherwise become a
    // false-positive deletion the moment they expire).
    _previousFriendIds = authoritativeIds;
    
    // Emit merged list only if it actually changed
    final list = friendMap.values.toList();
    
    // Check if the contact list has actually changed
    bool hasChanged = false;
    if (_previousContactList == null) {
      // First time emitting, always emit
      hasChanged = true;
    } else {
      // Compare current list with previous list
      if (list.length != _previousContactList!.length) {
        hasChanged = true;
      } else {
        // Create a map for quick lookup
        final previousMap = <String, FakeUser>{};
        for (final user in _previousContactList!) {
          previousMap[user.userID] = user;
        }
        
        // Check if any user has changed
        for (final user in list) {
          final previous = previousMap[user.userID];
          if (previous == null) {
            // New user added
            hasChanged = true;
            break;
          }
          // Check if user info changed
          if (previous.nickName != user.nickName ||
              previous.status != user.status ||
              previous.online != user.online ||
              previous.faceUrl != user.faceUrl) {
            hasChanged = true;
            break;
          }
        }
      }
    }

    // Only emit if data actually changed
    if (hasChanged) {
      AppLogger.log('[FakeIM] _emitContacts: emitting ${list.length} friends: ${list.map((u) => u.userID.substring(0, 8)).toList()}');
      bus.emit(topicContacts, list);
      _previousContactList = List.from(list); // Save a copy for next comparison
    }
  }

  // Public method to trigger immediate contact list refresh
  // This is useful when a friend is added/accepted to ensure UI updates immediately
  Future<void> refreshContacts() async {
    await _emitContacts();
  }

  /// Force re-emit the contact list, even if data hasn't changed.
  /// Useful for late subscribers that missed the initial bus emit (e.g. home_page
  /// initialising after FakeIM already emitted contacts during startup).
  Future<void> forceRefreshContacts() async {
    _previousContactList = null; // reset change-detection cache so the emit is not suppressed
    await _emitContacts();
  }

  /// Returns the last emitted contact list (or null if none yet).
  /// Useful for late subscribers that missed the initial bus emit.
  List<FakeUser>? get lastContactList => _previousContactList;

  Future<void> _emitFriendAppsWithFriends(
      List<({String userId, String nickName, String status, bool online})> friends) async {
    final apps = await ffi.getFriendApplications();
    final friendIds = friends.map((f) => f.userId).toSet();
    final out = apps
        .where((a) => !friendIds.contains(a.userId))
        .map((a) => FakeFriendApplication(userID: a.userId, wording: a.wording))
        .toList();
    bus.emit(topicFriendApps, out);
  }

  Future<void> _seedHistory() async {
    final friends = await ffi.getFriendList();
    for (final f in friends) {
      final hist = ffi.getHistory(f.userId);
      for (final h in hist) {
        final msg = FakeMessage(
          msgID: '${h.timestamp.millisecondsSinceEpoch}_${h.fromUserId}',
          conversationID: 'c2c_${f.userId}',
          fromUser: h.fromUserId,
          text: h.text,
          timestampMs: h.timestamp.millisecondsSinceEpoch,
          filePath: h.filePath,
          fileName: h.fileName, // Pass original file name
          mediaKind: h.mediaKind,
          isPending: h.isPending,
        );
        bus.emit(topicMessage, msg);
      }
    }
    final groups = ffi.knownGroups;
    for (final gid in groups) {
      final hist = ffi.getHistory(gid);
      for (final h in hist) {
        final msg = FakeMessage(
          msgID: '${h.timestamp.millisecondsSinceEpoch}_${h.fromUserId}',
          conversationID: 'group_$gid',
          fromUser: h.fromUserId,
          text: h.text,
          timestampMs: h.timestamp.millisecondsSinceEpoch,
          filePath: h.filePath,
          fileName: h.fileName, // Pass original file name
          mediaKind: h.mediaKind,
          isPending: h.isPending,
        );
        bus.emit(topicMessage, msg);
      }
    }
  }

  /// Call when unread may have changed outside the normal message stream
  /// (e.g. group message received via native OnRecvNewMessage). Updates sidebar and conversation list.
  void refreshUnreadTotal() => _emitUnreadTotal();

  void _emitUnreadTotal() async {
    // Calculate total unread count from all friends and groups
    // This ensures consistency with conversation list unread counts
    int total = 0;
    // Count unread from all friends (even if they have no messages yet)
    final friends = await ffi.getFriendList();
    for (final f in friends) {
      total += ffi.getUnreadOf(f.userId);
    }
    // Count unread from all groups
    for (final gid in ffi.knownGroups) {
      total += ffi.getUnreadOf(gid);
    }
    bus.emit(topicUnread, FakeUnreadTotal(total));
  }

  Future<void> _scanTyping() async {
    final friends = await ffi.getFriendList();
    for (final f in friends) {
      final on = ffi.isTyping(f.userId);
      final prev = _typingPrev[f.userId];
      if (prev == null || prev != on) {
        _typingPrev[f.userId] = on;
        bus.emit(topicTyping, FakeTypingEvent(conversationID: 'c2c_${f.userId}', fromUser: f.userId, on: on));
      }
    }
  }
}


