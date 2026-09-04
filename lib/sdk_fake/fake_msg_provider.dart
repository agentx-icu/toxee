import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_sdk/enum/image_types.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/tim2tox_failed_message_persistence.dart';
import 'package:tim2tox_dart/utils/control_message_envelope.dart';
import '../sdk_fake/fake_uikit_core.dart';
import '../sdk_fake/fake_im.dart';
import '../sdk_fake/fake_models.dart';
import '../sdk_fake/uikit_data_facade.dart';
import '../util/prefs.dart';
import '../util/tox_utils.dart';
import '../util/logger.dart';

part 'fake_msg_provider_file_progress.dart';
part 'fake_msg_provider_routing.dart';
part 'fake_msg_provider_mapping.dart';

/// Per-conversation history-reload bookkeeping for [FakeChatMessageProvider].
///
/// `loadedAtMs` is the wall-clock timestamp of the last successful reload
/// from the persistence layer. `inFlight` non-null when a reload is
/// currently running so we don't fan out concurrent disk reads when the
/// stream is subscribed multiple times in quick succession (page switch,
/// hot-reload, etc.).
class _HistoryReloadEntry {
  int loadedAtMs;
  int mutationGeneration;
  Future<void>? inFlight;
  _HistoryReloadEntry(this.loadedAtMs, this.mutationGeneration);
}

class FakeChatMessageProvider
    implements
        ChatMessageProviderWithSendResult,
        ChatDraftProviderOwnsConversationState,
        ChatScratchFileProvider {
  static final RegExp _fullToxAddressPattern = RegExp(r'^[0-9A-Fa-f]{76}$');

  final FfiChatService? _ffiService;
  final Future<List<FakeMessage>> Function(String conversationID)?
  _historyLoader;
  final Future<void> Function(FakeMessage message)? _topicMappingBarrier;
  final Map<String, StreamController<List<V2TimMessage>>> _ctrls = {};
  final Map<String, List<V2TimMessage>> _buffers = {};
  final Map<String, _HistoryReloadEntry> _historyReloadGuards = {};
  final Map<String, int> _historyMutationGenerations = {};
  bool _disposed = false;
  static const int _historyReloadTtlMs = 3000;
  StreamSubscription? _sub;
  StreamSubscription? _progressUpdatesSub;
  StreamSubscription? _sendProgressSub;
  StreamSubscription? _fileRequestsSub;
  StreamSubscription? _avatarUpdatedSub;
  String? _cachedSelfAvatarPath; // Cache self avatar path to avoid async calls
  final Map<String, String?> _cachedFriendAvatars =
      {}; // Cache friend avatar paths
  // Track file receive progress: msgID -> (received, total, path)
  final Map<String, ({int received, int total, String? path})> _fileProgress =
      {};

  /// S94/G2: read-only view of in-flight RECEIVE progress, keyed by msgID.
  /// Values are byte counts (received/total), NOT a 0-100 percent — derive
  /// percent as received/total*100. Mirrors the live `progressUpdates` recv
  /// stream that feeds `_onFileProgress`; entries are ADDED per chunk while a
  /// transfer is in flight and REMOVED on completion, so an empty map means
  /// "nothing currently mid-flight" — poll it WHILE a large transfer runs.
  /// SEND-side progress is not tracked here (`_onFileProgress` ignores
  /// isSend==true); only the receiver observes this curve.
  Map<String, ({int received, int total, String? path})> get fileProgress =>
      Map.unmodifiable(_fileProgress);

  /// Test seam (S94): inject an in-flight RECEIVE progress entry so a gate can
  /// deterministically observe the `fileProgress` exposure + the
  /// `l3_dump_state.fileTransfers` projection WITHOUT a live transfer (whose
  /// curve is racy — entries vanish at completion). Writes the same
  /// `(received, total, path)` record the real `_onFileProgress` recv path
  /// writes; use a synthetic msgId so a real message bubble isn't affected.
  @visibleForTesting
  void debugSetFileProgress(
    String msgId, {
    String? peerID,
    required int received,
    required int total,
    String? path,
  }) {
    if (peerID != null) {
      _recordProgressCacheMutation(peerID);
    }
    _fileProgress[msgId] = (received: received, total: total, path: path);
  }

  /// Test seam: capture the currently running reload before a live mutation
  /// invalidates its guard entry, then await that exact stale future.
  @visibleForTesting
  Future<void>? debugHistoryReloadCompletion(String conversationID) =>
      _historyReloadGuards[conversationID]?.inFlight;

  @visibleForTesting
  String? debugCachedFriendAvatar(String userID) =>
      _cachedFriendAvatars[userID];

  @visibleForTesting
  int get debugControllerCount => _ctrls.length;

  /// P1-22 (degraded): mirror of FfiChatService.progressUpdates for messages
  /// that are *being sent* (isSend == true), exposed so call-site UI can
  /// optionally subscribe in a future PR. The full UIKit-facing
  /// `sendMessageProgress` event still fires from UIKit's own send-side
  /// hooks; this stream is additive and unused by UIKit today.
  /// TODO(P1-22): forward each event into UIKit's onSendMessageProgress
  /// once the routing path is stable.
  final _sendProgressCtrl =
      StreamController<({String? msgID, int received, int total})>.broadcast();
  Stream<({String? msgID, int received, int total})> get sendProgressStream =>
      _sendProgressCtrl.stream;

  /// P2-6/P2-7: lazy cache of failed-message IDs for the current account so
  /// the routing layer can answer "is this msgID failed?" without
  /// re-reading SharedPreferences on every incoming event. The cache is
  /// invalidated on any save/remove via [invalidateFailedMsgCache].
  Set<String>? _failedMsgIDsCache;
  bool _failedCacheDirty = true;

  /// Mark the failed-message cache as stale; the next read refreshes it.
  void invalidateFailedMsgCache() {
    _failedCacheDirty = true;
  }

  FakeChatMessageProvider({
    FfiChatService? ffiService,
    @visibleForTesting
    Future<List<FakeMessage>> Function(String conversationID)? historyLoader,
    @visibleForTesting
    Future<void> Function(FakeMessage message)? topicMappingBarrier,
  }) : _ffiService = ffiService,
       _historyLoader = historyLoader,
       _topicMappingBarrier = topicMappingBarrier {
    // Load self avatar path on initialization
    Prefs.getAvatarPath().then((path) {
      if (!_disposed) {
        _cachedSelfAvatarPath = path;
      }
    });
    // Listen for message data updates to sync deletions
    _listenForMessageDeletions();
    // Listen to file transfer progress updates from FfiChatService
    final ffi = _liveFfi;
    if (ffi != null) {
      _progressUpdatesSub = ffi.progressUpdates.listen(_onFileProgress);
      // P1-22: also fan out send-side progress into a public stream that
      // higher layers can subscribe to. Keeps the integration additive
      // until a real onSendMessageProgress bridge is wired up.
      _sendProgressSub = ffi.progressUpdates.listen((p) {
        if (p.isSend) {
          if (!_sendProgressCtrl.isClosed) {
            _sendProgressCtrl.add((
              msgID: p.msgID,
              received: p.received,
              total: p.total,
            ));
          }
        }
      });
      // Ordinary file requests remain pending until the message UI invokes
      // FfiChatService.downloadMessage(). Avatar requests use the dedicated
      // `avatar_request` path in FfiChatService and never reach this stream.
      // When a friend's avatar is received and saved, invalidate our in-memory cache
      // and re-emit the stream for their conversation so message bubbles update immediately.
      _avatarUpdatedSub = ffi.avatarUpdated.listen((uid) async {
        if (_disposed) return;
        final convId = 'c2c_$uid';
        if (_buffers.containsKey(convId) && _ctrls.containsKey(convId)) {
          _recordHistoryMutation(convId);
        }
        _cachedFriendAvatars.remove(uid);
        final newPath = await Prefs.getFriendAvatarPath(uid);
        if (_disposed) return;
        _cachedFriendAvatars[uid] = newPath ?? '';
        if (_buffers.containsKey(convId) && _ctrls.containsKey(convId)) {
          final msgs = _buffers[convId]!;
          _recordHistoryMutation(convId);
          for (final msg in msgs) {
            if (msg.isSelf != true) {
              msg.faceUrl = newPath?.isNotEmpty == true ? newPath : null;
            }
          }
          _ctrls[convId]?.add(List<V2TimMessage>.from(msgs.reversed));
        }
      });
    }
    _sub = FakeUIKit.instance.eventBusInstance
        .on<FakeMessage>(FakeIM.topicMessage)
        .listen(_onTopicMessage);
  }

  FfiChatService? get _liveFfi => _ffiService ?? FakeUIKit.instance.im?.ffi;

  FfiChatService get _draftFfi {
    final ffi = _liveFfi;
    if (ffi == null) {
      throw StateError('Conversation draft persistence is unavailable');
    }
    return ffi;
  }

  Future<FfiChatService> _validatedScratchFfi() async {
    final ffi = _liveFfi;
    if (ffi == null) {
      throw StateError('Scratch storage is unavailable before session startup');
    }

    final activeAccountToxId = (await Prefs.getCurrentAccountToxId())?.trim();
    final liveAccountToxId = ffi.getSelfToxId()?.trim();
    if (activeAccountToxId == null ||
        !_fullToxAddressPattern.hasMatch(activeAccountToxId) ||
        liveAccountToxId == null ||
        !_fullToxAddressPattern.hasMatch(liveAccountToxId)) {
      throw StateError('Scratch storage requires the current full Tox ID');
    }
    if (activeAccountToxId.toUpperCase() != liveAccountToxId.toUpperCase()) {
      throw StateError('Scratch owner does not match the active account');
    }
    return ffi;
  }

  @override
  Future<String> writeScratchBytes({
    required String category,
    required String suggestedFileName,
    required Uint8List bytes,
  }) async {
    final ffi = await _validatedScratchFfi();
    return ffi.writeBytesToScratch(
      bytes,
      category: category,
      suggestedFileName: suggestedFileName,
    );
  }

  @override
  Future<void> deleteScratchFile(String path) async {
    final ffi = await _validatedScratchFfi();
    await ffi.deleteScratchFile(path);
  }

  String _validatedDraftAccountToxId(FfiChatService ffi, String accountToxId) {
    final explicitAccountToxId = accountToxId.trim();
    final isExplicitFull = RegExp(
      r'^[0-9a-fA-F]{76}$',
    ).hasMatch(explicitAccountToxId);
    final isExplicitPublicKey = RegExp(
      r'^[0-9a-fA-F]{64}$',
    ).hasMatch(explicitAccountToxId);
    if (!isExplicitFull && !isExplicitPublicKey) {
      throw ArgumentError.value(
        accountToxId,
        'accountToxId',
        'must contain the full Tox account ID or its 64-character public key',
      );
    }

    final liveAccountToxId = ffi.getSelfToxId()?.trim();
    if (liveAccountToxId == null ||
        !RegExp(r'^[0-9a-fA-F]{76}$').hasMatch(liveAccountToxId)) {
      throw StateError(
        'Conversation drafts require the current full Tox account ID',
      );
    }
    if (toToxPublicKey(liveAccountToxId) !=
        toToxPublicKey(explicitAccountToxId)) {
      throw StateError('Draft account does not match the current Tox account');
    }
    return liveAccountToxId.toUpperCase();
  }

  @override
  Future<String?> loadDraft({
    required String conversationID,
    required String accountToxId,
  }) async {
    final ffi = _draftFfi;
    _validatedDraftAccountToxId(ffi, accountToxId);
    return (await ffi.loadConversationDraft(conversationID))?.text;
  }

  @override
  Future<void> saveDraft({
    required String conversationID,
    required String accountToxId,
    String? draft,
  }) async {
    final ffi = _draftFfi;
    _validatedDraftAccountToxId(ffi, accountToxId);
    await ffi.setConversationDraft(
      conversationID: conversationID,
      draftText: draft,
    );
  }

  /// Find the conversation ID that matches a given userID, handling Tox ID
  /// format differences (64 vs 76 chars). Returns null if not found.
  String? findConversationForUser(String userID) {
    final normalized = normalizeToxId(userID);
    for (final key in _ctrls.keys) {
      if (key.startsWith('c2c_') &&
          normalizeToxId(key.substring(4)) == normalized) {
        return key;
      }
    }
    for (final key in _buffers.keys) {
      if (key.startsWith('c2c_') &&
          normalizeToxId(key.substring(4)) == normalized) {
        return key;
      }
    }
    return null;
  }

  StreamController<List<V2TimMessage>> _controllerFor(String conversationID) =>
      _ctrls[conversationID] ??=
          StreamController<List<V2TimMessage>>.broadcast();

  @override
  Stream<List<V2TimMessage>> streamFor({String? userID, String? groupID}) {
    if (_disposed) {
      return const Stream<List<V2TimMessage>>.empty();
    }
    final conv = (groupID != null && groupID.isNotEmpty)
        ? 'group_$groupID'
        : 'c2c_$userID';
    final stream = _controllerFor(conv).stream;

    // Check if buffer already has messages
    final hasBuffer = _buffers.containsKey(conv) && _buffers[conv]!.isNotEmpty;

    // The reload guard short-circuits when we already pulled history from
    // disk within `_historyReloadTtlMs`. Rapid conversation switching (or
    // multiple subscribers per conversation) used to hit the on-disk
    // persistence layer for every subscribe; now repeat subscribes within
    // the TTL just re-emit the in-memory buffer. Writes call
    // [_recordHistoryMutation] to force the next subscribe to
    // refresh.
    // Start immediately so the reload captures the generation before
    // [streamFor] returns. The async load still yields at its first await and
    // never blocks subscription setup.
    unawaited(_reloadHistoryIfStale(conv));

    // If buffer already has messages, emit them immediately (for real-time updates)
    // But we still reload history in the background to ensure failed messages are restored
    if (hasBuffer) {
      // UIKit's getMessageListForRender reverses the list, so we need to reverse here too
      final reversedList = List<V2TimMessage>.from(_buffers[conv]!.reversed);
      _controllerFor(conv).add(reversedList);
    }

    return stream;
  }

  Future<void> _reloadHistoryIfStale(String conv) {
    if (_disposed) {
      return Future<void>.value();
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final guard = _historyReloadGuards[conv];
    if (guard != null) {
      if (guard.inFlight != null) return guard.inFlight!;
      if (now - guard.loadedAtMs < _historyReloadTtlMs) {
        return Future<void>.value();
      }
    }
    final generation = _historyMutationGenerations[conv] ?? 0;
    final entry = _historyReloadGuards.putIfAbsent(
      conv,
      () => _HistoryReloadEntry(0, generation),
    );
    entry.mutationGeneration = generation;
    late final Future<void> future;
    future = _loadHistoryForConversation(conv).whenComplete(() {
      if (identical(_historyReloadGuards[conv], entry) &&
          identical(entry.inFlight, future)) {
        entry
          ..loadedAtMs = DateTime.now().millisecondsSinceEpoch
          ..inFlight = null;
      }
    });
    entry.inFlight = future;
    return future;
  }

  /// Force the next [streamFor] subscribe to reload history from disk for
  /// [conv]. Call this after any mutation that would make the cached
  /// buffer diverge from persisted history.
  void _invalidateHistoryReloadCache(String conv) {
    _historyReloadGuards.remove(conv);
  }

  /// Record a live in-memory mutation so an older disk read cannot replace it.
  void _recordHistoryMutation(String conv) {
    if (_disposed) {
      return;
    }
    _historyMutationGenerations[conv] =
        (_historyMutationGenerations[conv] ?? 0) + 1;
    _invalidateHistoryReloadCache(conv);
  }

  bool _isCurrentHistoryGeneration(String conv, int generation) =>
      !_disposed && (_historyMutationGenerations[conv] ?? 0) == generation;

  bool _recordProgressCacheMutation(String peerID) {
    final conv = findConversationForUser(peerID);
    if (conv == null) {
      return false;
    }
    _recordHistoryMutation(conv);
    return true;
  }

  @override
  Future<void> sendText({
    String? userID,
    String? groupID,
    required String text,
  }) async {
    await sendTextWithResult(userID: userID, groupID: groupID, text: text);
  }

  @override
  Future<ChatMessageSendResult> sendTextWithResult({
    String? userID,
    String? groupID,
    required String text,
    String? clientMessageID,
  }) async {
    final conv = (groupID != null && groupID.isNotEmpty)
        ? 'group_$groupID'
        : 'c2c_$userID';
    final mgr = FakeUIKit.instance.messageManager;
    if (mgr == null) {
      throw Exception("Message manager is not available");
    }
    // C2C offline is handled inside FfiChatService.sendText: it queues the
    // message and surfaces a pending bubble. Drain runs when the friend's
    // status flips online. No pre-emptive throw here.
    try {
      return await mgr.sendText(conv, text, clientMessageID: clientMessageID);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> sendImage({
    String? userID,
    String? groupID,
    required String imagePath,
    String? imageName,
  }) => sendImageWithResult(
    userID: userID,
    groupID: groupID,
    imagePath: imagePath,
    imageName: imageName,
  );

  @override
  Future<ChatMessageSendResult?> sendImageWithResult({
    String? userID,
    String? groupID,
    required String imagePath,
    String? imageName,
  }) async {
    // P1-21 (degraded): no compression / no EXIF strip (would require new
    // pubspec deps for a real fix). Surface large images in the log so
    // ops can spot the situation; rely on Tox's file_transfer flow
    // otherwise. The size check itself is best-effort.
    try {
      final size = await File(imagePath).length();
      if (size > 5 * 1024 * 1024) {
        AppLogger.log(
          '[sendImage] large image (${size ~/ 1024}KB) sent without compression — TODO(P1-21)',
        );
      }
    } catch (_) {}
    return _sendMediaWithResult(userID: userID, groupID: groupID, path: imagePath);
  }

  @override
  Future<void> sendFile({
    String? userID,
    String? groupID,
    required String filePath,
    String? fileName,
  }) => sendFileWithResult(
    userID: userID,
    groupID: groupID,
    filePath: filePath,
    fileName: fileName,
  );

  @override
  Future<ChatMessageSendResult?> sendFileWithResult({
    String? userID,
    String? groupID,
    required String filePath,
    String? fileName,
  }) => _sendMediaWithResult(userID: userID, groupID: groupID, path: filePath);

  /// Image and file sends share one transport. Returns the echo identity
  /// (real msgID + pending state) so the platform reconciles the UIKit's
  /// `created_temp_id-*` optimistic bubble with the echo on the message
  /// stream, as text always did — media not doing it rendered every send
  /// twice. C2C offline is handled inside FfiChatService.sendFile (queued
  /// transfer + pending bubble; drained when the friend comes online).
  Future<ChatMessageSendResult?> _sendMediaWithResult({
    required String? userID,
    required String? groupID,
    required String path,
  }) async {
    final mgr = FakeUIKit.instance.messageManager;
    if (mgr == null) return null;
    // P1-19: pre-check group transfers. The Tox group layer does not
    // support file transfer; failing fast here prevents UIKit from
    // inserting a SENDING bubble that will never resolve.
    if (groupID != null && groupID.isNotEmpty) {
      throw StateError('Group file transfer is not supported in toxee');
    }
    return mgr.sendFile('c2c_$userID', path);
  }

  /// Find a message by msgID across all conversation buffers
  /// Also searches in FfiChatService history if not found in buffers
  /// Returns the message if found, null otherwise
  /// Update or add a message to the buffer and emit to stream
  /// This is used when messages are added/updated outside of FakeMessage events
  /// (e.g., when sendMessageFinalPhase updates message status to FAIL)
  void updateMessageInBuffer(
    V2TimMessage message, {
    String? userID,
    String? groupID,
  }) {
    if (_disposed) {
      return;
    }
    final conv = (groupID != null && groupID.isNotEmpty)
        ? 'group_$groupID'
        : 'c2c_$userID';
    if (conv.isEmpty) {
      return;
    }

    final list = _buffers.putIfAbsent(conv, () => <V2TimMessage>[]);

    // Check if message already exists by msgID or id
    final existingIndex = list.indexWhere(
      (msg) =>
          (msg.msgID != null && msg.msgID == message.msgID) ||
          (msg.id != null && msg.id == message.id && message.id != null),
    );

    _recordHistoryMutation(conv);
    if (existingIndex >= 0) {
      // Message exists - update it
      list[existingIndex] = message;
    } else {
      // New message - add it
      list.add(message);
    }

    // Sort by timestamp ascending (oldest first, newest last)
    list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));

    // Emit to stream (reversed for UIKit's expected format)
    final reversedList = List<V2TimMessage>.from(list.reversed);
    _ctrls[conv]?.add(reversedList);

    // CRITICAL: Emit FakeMessage event to trigger FakeProvider to update conversation lastMessage
    // This ensures that failed messages appear in the conversation list's second line
    // Only emit if message is failed (status == 3) to avoid duplicate events for normal messages
    if (message.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
      try {
        final ffi = FakeUIKit.instance.im?.ffi;
        final selfId = ffi?.selfId ?? '';
        final isSelf = message.isSelf ?? false;
        final fromUser = isSelf
            ? selfId
            : (message.sender ?? message.userID ?? '');
        final text = message.textElem?.text ?? '';
        final timestampMs =
            (message.timestamp ?? 0) * 1000; // Convert seconds to milliseconds

        final fakeMsg = FakeMessage(
          msgID: message.msgID ?? message.id ?? '',
          conversationID: conv,
          fromUser: fromUser,
          text: text,
          timestampMs: timestampMs,
          filePath: message.fileElem?.path ?? message.imageElem?.path,
          fileName: message.fileElem?.fileName,
          fileSize: message.fileElem?.fileSize,
          mediaKind: message.imageElem != null
              ? 'image'
              : (message.fileElem != null ? 'file' : null),
          cloudCustomData: message.cloudCustomData,
          isPending: false, // Failed messages are not pending
          isReceived: false,
          isRead: false,
        );

        // Emit FakeMessage event to trigger FakeProvider to update conversation lastMessage
        FakeUIKit.instance.eventBusInstance.emit(FakeIM.topicMessage, fakeMsg);
      } catch (e) {
        AppLogger.warn(
          '[FakeMessageProvider] FakeMessage event emission failed: ${e.runtimeType}',
        );
      }
    }
  }

  V2TimMessage? findMessageByID(String msgID) {
    // First, try to find in _buffers (messages that have been loaded into chat windows)
    for (final entry in _buffers.entries) {
      try {
        final foundMessage = entry.value.firstWhere(
          (msg) => msg.msgID == msgID,
        );
        return foundMessage;
      } catch (e) {
        // Message not found in this conversation, continue searching
        continue;
      }
    }

    // If not found in buffers, try to find in FfiChatService history
    // This ensures historical messages that haven't been loaded into chat windows can still be found
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi != null) {
      // Use FfiChatService's findUserIDAndGroupIDFromMsgID to locate the message
      final (userID, groupID) = ffi.findUserIDAndGroupIDFromMsgID(msgID);

      if (userID != null || groupID != null) {
        // Determine conversationID and actual ID
        String conversationID;
        String actualId;
        if (groupID != null) {
          conversationID = 'group_$groupID';
          actualId = groupID;
        } else {
          conversationID = 'c2c_$userID';
          actualId = userID!;
        }

        // Get history for this conversation
        final history = ffi.getHistory(actualId);
        // Search for the message in history
        try {
          final chatMsg = history.firstWhere((m) => m.msgID == msgID);
          // Found the ChatMessage, convert it to FakeMessage then to V2TimMessage
          final fakeMsg = FakeMessage(
            msgID:
                chatMsg.msgID ??
                '${chatMsg.timestamp.millisecondsSinceEpoch}_${chatMsg.fromUserId}',
            conversationID: conversationID,
            fromUser: chatMsg.fromUserId,
            text: chatMsg.text,
            timestampMs: chatMsg.timestamp.millisecondsSinceEpoch,
            filePath: chatMsg.filePath,
            fileName: chatMsg.fileName,
            fileSize: chatMsg.fileSize,
            mediaKind: chatMsg.mediaKind,
            cloudCustomData: chatMsg.cloudCustomData,
            isPending: chatMsg.isPending,
            isReceived: chatMsg.isReceived,
            isRead: chatMsg.isRead,
          );
          // Convert FakeMessage to V2TimMessage using _mapMsg
          return _mapMsg(fakeMsg);
        } catch (e) {
          // Message not found in history (shouldn't happen if findUserIDAndGroupIDFromMsgID worked)
          return null;
        }
      }
    }

    return null;
  }

  @override
  Future<void> deleteMessages({
    String? userID,
    String? groupID,
    required List<String> msgIDs,
  }) async {
    try {
      if (msgIDs.isEmpty) {
        return;
      }

      final conv = (groupID != null && groupID.isNotEmpty)
          ? 'group_$groupID'
          : 'c2c_$userID';

      if (conv.isEmpty || (userID == null && groupID == null)) {
        throw Exception(
          'Invalid conversation: userID and groupID cannot both be null',
        );
      }

      // Remove messages from buffer
      _removeMessagesFromBuffer(conv, msgIDs);

      // Delete messages from history via FakeMessageManager
      final mgr = FakeUIKit.instance.messageManager;
      if (mgr != null) {
        await mgr.deleteMessages(msgIDs);
      } else {
        throw Exception('MessageManager is not available');
      }
    } catch (e) {
      // Re-throw the exception so UIKit knows the provider failed
      rethrow;
    }
  }

  void _listenForMessageDeletions() {
    // Listen to UIKit's message data updates to detect deletions
    // When UIKit deletes messages, it updates the message list, and we need to sync our buffers
    // This is a workaround since UIKit calls SDK directly, not through provider
    // We'll periodically check for deletions by comparing message lists
    // Note: This is not ideal, but it's the best we can do without modifying UIKit
    // A better solution would be to intercept SDK calls, but that requires modifying UIKit code
  }

  /// Remove messages from buffer by their IDs
  /// This is called when messages are deleted
  void _removeMessagesFromBuffer(String conversationID, List<String> msgIDs) {
    _recordHistoryMutation(conversationID);
    final list = _buffers[conversationID];
    if (list == null) {
      return;
    }

    list.removeWhere((msg) {
      final msgID = msg.msgID ?? '';
      // Also check id field as fallback
      final id = msg.id ?? '';
      return msgIDs.contains(msgID) || (id.isNotEmpty && msgIDs.contains(id));
    });

    // Re-sort after removal
    list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
    // Emit updated list to stream
    if (_ctrls[conversationID]?.isClosed == false) {
      final reversedList = List<V2TimMessage>.from(list.reversed);
      _ctrls[conversationID]?.add(reversedList);
    }
  }

  /// Clear message buffer for a conversation and notify UI
  /// This is called when chat history is cleared
  void clearMessageBuffer(String conversationID) {
    _recordHistoryMutation(conversationID);
    // Clear the buffer (remove or clear the list)
    if (_buffers.containsKey(conversationID)) {
      _buffers[conversationID]!.clear();
      _buffers.remove(conversationID);
    }
    // Emit empty list to stream to notify UI (if stream controller exists)
    if (_ctrls[conversationID]?.isClosed == false) {
      _ctrls[conversationID]?.add(<V2TimMessage>[]);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _sub?.cancel();
    _progressUpdatesSub?.cancel();
    _sendProgressSub?.cancel();
    _fileRequestsSub?.cancel();
    _avatarUpdatedSub?.cancel();
    for (final c in _ctrls.values) {
      c.close();
    }
    _ctrls.clear();
    _buffers.clear();
    _historyReloadGuards.clear();
    _historyMutationGenerations.clear();
    _cachedSelfAvatarPath = null;
    _cachedFriendAvatars.clear();
    _fileProgress.clear();
    _failedMsgIDsCache = null;
    _failedCacheDirty = true;
    // P1-22: close the additive send-progress stream so subscribers
    // unsubscribe cleanly during logout.
    if (!_sendProgressCtrl.isClosed) {
      _sendProgressCtrl.close();
    }
  }
}
