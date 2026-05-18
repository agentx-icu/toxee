import 'dart:async';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/prefs.dart';
import '../util/tox_utils.dart';
import '../util/logger.dart';
import 'fake_event_bus.dart';
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
  Timer? _startupFastPollTimer;
  Timer? _startupSlowPollTimer;
  StreamSubscription<dynamic>? _avatarUpdatedSub;
  StreamSubscription<dynamic>? _nicknameUpdatedSub;
  StreamSubscription<dynamic>? _messagesSub;
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

  void start() {
    // When a friend's avatar is received and saved, refresh conversations and contact list so the UI updates
    _avatarUpdatedSub = ffi.avatarUpdated.listen((uid) {
      if (_disposed) return;
      unawaited(_refreshConversations());
      unawaited(_emitContacts());
    });
    // When a friend's nickname changes, refresh conversations so the UI updates
    _nicknameUpdatedSub = ffi.nicknameUpdated.listen((uid) {
      if (_disposed) return;
      unawaited(_refreshConversations());
    });
    // Reduced delay from 2000ms to 500ms for faster startup
    // Start checking friend list immediately with shorter initial delay
    // This allows faster detection of friend online status
    _startupInitTimer?.cancel();
    _startupInitTimer = Timer(const Duration(milliseconds: 500), () async {
      if (_disposed) return;
      // Retry mechanism: if friend list is empty, wait a bit more and retry
      // Use exponential backoff for retries: 200ms, 400ms, 800ms, 1600ms, 3200ms
      int retries = 0;
      const maxRetries = 5;
      int retryDelay = 200; // Start with 200ms

      while (retries < maxRetries) {
        if (_disposed) return;
        final friends = await ffi.getFriendList();
        if (_disposed) return;
        if (friends.isNotEmpty || retries >= maxRetries - 1) {
          // Friend list is populated or we've exhausted retries, proceed with initialization
          // Seed conversations from friend list
          unawaited(_refreshConversations());
          unawaited(_emitContacts());
          if (_disposed) return;
          _seedHistory();
          break;
        }
        // Friend list is still empty, wait and retry with exponential backoff
        retries++;
        await Future.delayed(Duration(milliseconds: retryDelay));
        retryDelay = (retryDelay * 2).clamp(200, 3200); // Exponential backoff, max 3200ms
      }

      if (_disposed) return;

      // After initial emit, start a more frequent polling for online status updates
      // Optimized: Poll every 500ms for the first 10 seconds (20 polls) for faster detection
      // Then switch to 2 seconds for the next 20 seconds (10 polls)
      // This provides faster initial detection while reducing CPU usage after initial period
      int startupPollCount = 0;
      const fastPollDuration = 20; // 20 * 500ms = 10 seconds
      const slowPollDuration = 10; // 10 * 2s = 20 seconds

      // Fast polling phase: 500ms intervals for first 10 seconds
      _startupFastPollTimer =
          Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        if (_disposed) {
          timer.cancel();
          return;
        }
        startupPollCount++;
        if (startupPollCount >= fastPollDuration) {
          timer.cancel();
          _startupFastPollTimer = null;
          // Switch to slower polling
          int slowPollCount = 0;
          _startupSlowPollTimer =
              Timer.periodic(const Duration(seconds: 2), (slowTimer) async {
            if (_disposed) {
              slowTimer.cancel();
              return;
            }
            slowPollCount++;
            if (slowPollCount >= slowPollDuration) {
              slowTimer.cancel();
              _startupSlowPollTimer = null;
              return;
            }

            // Check if any friend's online status has changed
            final friends = await ffi.getFriendList();
            if (_disposed) return;
            bool statusChanged = false;
            for (final friend in friends) {
              if (friend.online) {
                statusChanged = true;
                break;
              }
            }

            if (statusChanged) {
              await _emitContacts();
            }
          });
          return;
        }

        // Check if any friend's online status has changed
        final friends = await ffi.getFriendList();
        if (_disposed) return;
        bool statusChanged = false;
        for (final friend in friends) {
          if (friend.online) {
            statusChanged = true;
            break;
          }
        }

        // If status changed, immediately refresh contacts to update UI
        if (statusChanged) {
          await _emitContacts();
        }
      });
    });
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_disposed) return;
      final friends = await ffi.getFriendList();
      await _refreshConversationsWithFriends(friends);
      await _emitContactsWithFriends(friends);
      await _emitFriendAppsWithFriends(friends);
      _scanTyping();
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
      String convId = ''; // Initialize to avoid compiler error
      if (m.groupId != null) {
        // Group message
        convId = 'group_${m.groupId}';
      } else if (m.isSelf) {
        // Self-sent C2C message: first try to find the conversation from message history
        // This is critical for forward messages, which should be added to the target conversation,
        // not the current active conversation (activePeerId)
        String? targetUserID;
        bool foundInHistory = false;
        if (m.msgID != null) {
          final result = ffi.findUserIDAndGroupIDFromMsgID(m.msgID!);
          targetUserID = result.$1; // userID
          // If found in history, use that conversation
          if (targetUserID != null) {
            convId = 'c2c_$targetUserID';
            foundInHistory = true;
          }
        }
        
        // If not found in history, use activePeerId as fallback
        // This handles the case where message hasn't been saved to history yet
        if (!foundInHistory) {
          if (ffi.activePeerId != null && ffi.activePeerId != ffi.selfId) {
            convId = 'c2c_${ffi.activePeerId}';
          } else {
            // Fallback: find from lastMessages (most recent conversation)
            final recentPeer = ffi.lastMessages.keys.isNotEmpty ? ffi.lastMessages.keys.first : null;
            convId = recentPeer != null && recentPeer != ffi.selfId ? 'c2c_$recentPeer' : 'c2c_${ffi.selfId}';
          }
        }
      } else {
        // Received message: sender is the peer
        // Normalize friend ID to ensure consistent conversationID
        // This matches the normalization used in FfiChatService when saving messages
        final fromUserId = m.fromUserId;
        final normalizedFrom = fromUserId.length > 64 
            ? fromUserId.substring(0, 64).trim() 
            : fromUserId.trim();
        convId = 'c2c_$normalizedFrom';
      }
      final msg = FakeMessage(
        msgID: m.msgID ?? '${m.timestamp.millisecondsSinceEpoch}_${m.fromUserId}',
        conversationID: convId,
        fromUser: m.fromUserId,
        text: m.text,
        timestampMs: m.timestamp.millisecondsSinceEpoch,
        filePath: m.filePath,
        fileName: m.fileName, // Pass original file name
        mediaKind: m.mediaKind,
        isPending: m.isPending,
        isReceived: m.isReceived,
        isRead: m.isRead,
      );
      bus.emit(topicMessage, msg);
      _emitUnreadTotal();
      // Trigger conversation refresh when new message arrives to update lastMessage
      // This ensures the conversation list shows the latest message
      unawaited(_refreshConversations());
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
    _startupInitTimer?.cancel();
    _startupInitTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _startupFastPollTimer?.cancel();
    _startupFastPollTimer = null;
    _startupSlowPollTimer?.cancel();
    _startupSlowPollTimer = null;
    _typingPrev.clear();
    _previousFriendIds.clear();
    _previousGroupIds.clear();
    _previousContactList = null;
    _emitContactsRunning = false;
    _toxFriendListReceived = false;
    _coldStartRestoreAt = null;
  }

  Future<void> _refreshConversations() async {
    final friends = await ffi.getFriendList();
    await _refreshConversationsWithFriends(friends);
  }

  Future<void> _refreshConversationsWithFriends(
      List<({String userId, String nickName, String status, bool online})> friends) async {
    // `pinned` stores **normalized** keys: bare normalized userID for C2C and
    // 'group_${normalizedGid}' for groups (see FakeConversationManager.setPinned).
    // We must check membership using the same shape — using raw 76-char IDs or
    // bare gids would silently lose the pinned flag and let it disagree with
    // FakeConversationManager.getConversationList.
    final pinned = (await Prefs.getPinned())
        .where((s) => s.isNotEmpty)
        .toSet();
    // Get pending friend applications (requests we sent that haven't been accepted yet)
    // These should not appear in the conversation list
    final pendingApps = await ffi.getFriendApplications();
    final pendingFriendIds = pendingApps.map((a) => a.userId).toSet();

    // Create a set of normalized friend IDs from the friend list
    // This is used to check if a pending application has been accepted
    final normalizedFriendIds = friends.map((f) => normalizeToxId(f.userId)).toSet();

    // Build Tox-only friend map keyed by **normalized** ID. Tox is the single
    // source of truth for friends. No longer merge from Prefs — stale Prefs
    // entries caused ghost contacts. Normalization here MUST match what
    // FakeConversationManager.getConversationList emits, otherwise the same
    // friend will produce two different conversationIDs depending on which
    // emitter fired last.
    final friendMap = <String, ({String userId, String nickName, bool online})>{};
    for (final f in friends) {
      final normalizedId = normalizeToxId(f.userId);
      friendMap[normalizedId] = (userId: normalizedId, nickName: f.nickName, online: f.online);
    }

    for (final entry in friendMap.entries) {
      final f = entry.value;
      // Only skip friends that have pending applications (requests not yet accepted)
      // If a friend is in the friend list (normalizedFriendIds), they have been accepted
      // and should appear in the conversation list even if they're still in pendingFriendIds
      // pendingFriendIds is checked against both raw and normalized form because
      // FfiChatService applications may carry either.
      if ((pendingFriendIds.contains(f.userId) ||
              pendingFriendIds.any((p) => normalizeToxId(p) == f.userId)) &&
          !normalizedFriendIds.contains(f.userId)) {
        continue;
      }
      // Load avatar path for conversation list and chat header
      final avatarPath = await Prefs.getFriendAvatarPath(f.userId);
      final conv = FakeConversation(
        conversationID: 'c2c_${f.userId}',
        title: f.nickName.isNotEmpty ? f.nickName : f.userId,
        faceUrl: avatarPath,
        unreadCount: ffi.getUnreadOf(f.userId),
        isGroup: false,
        isPinned: pinned.contains(f.userId),
      );
      bus.emit(topicConversation, conv);
    }
    // Get quit groups first to filter them out
    final quitGroups = await Prefs.getQuitGroups();
    
    // Get groups from knownGroups, but also merge with persisted groups to ensure all groups are shown
    // This is important on startup when knownGroups might not be fully loaded yet
    // Filter out quit groups from persisted groups and knownGroups
    final persistedGroups = await Prefs.getGroups();
    final persistedGroupsFiltered = persistedGroups.where((g) => !quitGroups.contains(g)).toSet();
    final knownGroups = ffi.knownGroups;
    final knownGroupsFiltered = knownGroups.where((g) => !quitGroups.contains(g)).toSet();
    // Merge persisted groups with knownGroups to ensure all groups are included
    // But exclude quit groups
    final groups = {...knownGroupsFiltered, ...persistedGroupsFiltered};
    final currentGroupIds = groups.toSet();
    
    // Detect groups that were deleted (by checking if they were in previous list but not in current)
    final deletedGroupIds = _previousGroupIds.difference(currentGroupIds);
    if (deletedGroupIds.isNotEmpty && _previousGroupIds.isNotEmpty) {
      // Emit group deletion events
      for (final deletedId in deletedGroupIds) {
        // Remove from local groups persistence
        final localGroups = await Prefs.getGroups();
        localGroups.remove(deletedId);
        await Prefs.setGroups(localGroups);
        // Emit deletion event
        bus.emit(topicGroupDeleted, FakeGroupDeleted(groupID: deletedId));
      }
    }
    
    // Update previous group IDs (only non-quit groups)
    _previousGroupIds = currentGroupIds;
    
    // Emit deletion events for groups that are in quitGroups but were previously active
    // This ensures conversations are removed from the conversation list when groups are quit
    for (final quitGid in quitGroups) {
      if (_previousGroupIds.contains(quitGid) && !currentGroupIds.contains(quitGid)) {
        // Group was quit and is no longer in current list, emit deletion event
        bus.emit(topicGroupDeleted, FakeGroupDeleted(groupID: quitGid));
      }
    }
    
    for (final gid in groups) {
      // Note: quitGroups are already filtered out above, but double-check for safety
      if (quitGroups.contains(gid)) {
        continue;
      }
      // Note: If group is in persistedGroups but not in knownGroups,
      // it will be added to knownGroups when init() completes or when the group is accessed
      // For now, we'll just include it in the conversation list
      // Always get the latest group name and avatar from Prefs to ensure consistency
      final savedName = await Prefs.getGroupName(gid);
      final savedAvatar = await Prefs.getGroupAvatar(gid);
      // Use saved name if available and not empty, otherwise fall back to group ID
      // But avoid using default "tox_0" style names - prefer the group ID format
      final name = (savedName != null && savedName.isNotEmpty) ? savedName : gid;
      // Pinned key for groups is 'group_${normalizedGid}' (matches FakeConversationManager.setPinned).
      // Group IDs like 'tox_0' / 'tox_conf_xyz' are short enough to pass through
      // normalizeToxId unchanged, but normalizing keeps the rule uniform.
      final groupPinnedKey = 'group_${normalizeToxId(gid)}';
      final conv = FakeConversation(
        conversationID: 'group_$gid',
        title: name,
        faceUrl: savedAvatar,
        unreadCount: ffi.getUnreadOf(gid),
        isGroup: true,
        isPinned: pinned.contains(groupPinnedKey),
        groupType: gid.startsWith('tox_conf_') ? 'conference' : 'group',
      );
      bus.emit(topicConversation, conv);
    }
    // Note: _emitUnreadTotal() is now called automatically by FakeChatDataProvider
    // when conversation list updates, so we don't need to call it here
    // This ensures immediate synchronization between conversation list and sidebar
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
    for (final f in friends) {
      final normalizedId = normalizeToxId(f.userId);
      toxFriendIds.add(normalizedId);
      final avatarPath = await Prefs.getFriendAvatarPath(normalizedId);
      friendMap[normalizedId] = FakeUser(
        userID: normalizedId,
        nickName: f.nickName,
        status: f.status,
        online: f.online,
        faceUrl: avatarPath,
      );
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
    final deletedFriendIds = inColdStartGrace ? <String>{} : missingFromTox;

    if (inColdStartGrace && missingFromTox.isNotEmpty) {
      // Re-hydrate missing friends from cache so the UI stays stable while
      // Tox finishes loading. They will be marked offline.
      for (final pendingId in missingFromTox) {
        if (friendMap.containsKey(pendingId)) continue;
        final cachedNick = await Prefs.getFriendNickname(pendingId);
        final cachedStatus = await Prefs.getFriendStatusMessage(pendingId);
        final cachedAvatar = await Prefs.getFriendAvatarPath(pendingId);
        friendMap[pendingId] = FakeUser(
          userID: pendingId,
          nickName: cachedNick ?? '',
          status: cachedStatus ?? '',
          online: false,
          faceUrl: cachedAvatar,
        );
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
    // lose the restored entries. Outside grace, Tox is authoritative.
    final authoritativeIds = inColdStartGrace
        ? toxFriendIds.union(missingFromTox)
        : toxFriendIds;
    await Prefs.setLocalFriends(authoritativeIds);

    // Update previous friend IDs for next-poll diff.
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


