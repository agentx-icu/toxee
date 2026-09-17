import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../sdk_fake/fake_uikit_core.dart';
import '../sdk_fake/uikit_data_facade.dart';
import '../sdk_fake/c2c_recv_opt_cache.dart';
import '../util/app_l10n.dart';
import '../util/logger.dart';
import '../util/prefs.dart';
import '../util/tox_utils.dart';
import 'notification_service.dart';

/// Hooks the V2TimAdvancedMsgListener path and posts an OS-level notification
/// whenever a new message arrives that the user should be told about.
///
/// Suppression rules (matches the prompt's contract):
///   - Self-sent messages (message.isSelf == true OR sender == loginUserID)
///   - The app is in the foreground AND the active conversation matches the
///     message's conversation (the user is already looking at it)
///   - Conversation is muted (best-effort: read from the V2TimConversation
///     when available, fall back to "not muted")
///
/// Registration is idempotent: [register] guards on [_registered] so calling
/// twice from HomePage doesn't double-listen. The Tim2Tox platform's
/// listener list is per-instance and we don't have a stable handle back to
/// remove the listener once it's registered — by design this listener lives
/// for the lifetime of the session.
class NotificationMessageListener {
  NotificationMessageListener._(this._service);

  static NotificationMessageListener? _instance;

  /// Returns the singleton, lazily constructed against the given service.
  /// Subsequent calls ignore the [service] argument — the first caller wins
  /// the binding.
  static NotificationMessageListener forService(FfiChatService service) {
    return _instance ??= NotificationMessageListener._(service);
  }

  /// Test seam: evaluate the pure suppression decision (`_shouldSuppress` — the
  /// contract that decides whether an inbound message rings a notification) for
  /// [service] + [message], so a unit test can assert mute/block/self/
  /// active-conversation suppression without the SDK listener + OS plumbing.
  ///
  /// Deliberately a STATIC over a throwaway instance, NOT a public constructor:
  /// it never escapes, never touches the `forService` singleton (`_instance`),
  /// and — having no reachable reference — can never have `register()` called on
  /// it, so it cannot install a second SDK listener (codex). The throwaway only
  /// holds `_service`; `_shouldSuppress` reads nothing the constructor wires.
  @visibleForTesting
  static bool debugShouldSuppressFor(
    FfiChatService service,
    V2TimMessage message,
  ) =>
      NotificationMessageListener._(service)._shouldSuppress(message);

  final FfiChatService _service;
  V2TimAdvancedMsgListener? _listener;
  bool _registered = false;
  StreamSubscription<String>? _onTapSub;

  /// Registers the listener with the SDK. Idempotent.
  ///
  /// [onConversationTapped] (optional) is invoked when the user taps a
  /// notification. The payload is a conversation ID like `c2c_<toxId>` or
  /// `group_<groupId>` — the same identifier we use elsewhere.
  Future<void> register({
    ValueChanged<String>? onConversationTapped,
  }) async {
    if (_registered) {
      AppLogger.debug(
          '[NotificationMessageListener] register() called twice; ignoring');
      // Update the tap handler if a new one was supplied, even on a repeat
      // call — caller may have remounted HomePage and wants the new routing
      // closure.
      if (onConversationTapped != null) {
        await _onTapSub?.cancel();
        _onTapSub = NotificationService.instance.onSelectStream
            .listen(onConversationTapped);
      }
      return;
    }

    // Make sure the service is ready before we start posting.
    await NotificationService.instance.init();

    _listener = V2TimAdvancedMsgListener(
      onRecvNewMessage: _onRecvNewMessage,
    );
    try {
      await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .addAdvancedMsgListener(listener: _listener!);
      _registered = true;
      AppLogger.info(
          '[NotificationMessageListener] Registered V2TimAdvancedMsgListener');
    } catch (e, st) {
      AppLogger.logError(
          '[NotificationMessageListener] Failed to register listener', e, st);
      return;
    }

    if (onConversationTapped != null) {
      _onTapSub = NotificationService.instance.onSelectStream
          .listen(onConversationTapped);
    }

    // Replay the cold-start payload (if any) once a tap handler exists.
    if (onConversationTapped != null) {
      final launchPayload = NotificationService.instance.consumeLaunchPayload();
      if (launchPayload != null && launchPayload.isNotEmpty) {
        // Defer to next microtask so the caller's wiring has time to settle.
        scheduleMicrotask(() => onConversationTapped(launchPayload));
      }
    }
  }

  /// Tears down the listener completely:
  ///   - cancels the notification-tap subscription
  ///   - removes the SDK-level [V2TimAdvancedMsgListener] so a new session
  ///     bound to a different [FfiChatService] doesn't double-listen
  ///   - clears the singleton + `_registered` flag so the next
  ///     [forService] call constructs a fresh listener
  ///
  /// Wrapped in try/catch on the SDK removal because the platform may
  /// already be torn down by the time we get here (e.g. logout dispose order
  /// has the Tim2Tox platform swap happen alongside this teardown).
  ///
  /// Most callers should use [disposeAndReset] instead — it deals with the
  /// "singleton was never created" case without forcing them to null-check.
  Future<void> dispose() async {
    await _onTapSub?.cancel();
    _onTapSub = null;

    final listener = _listener;
    if (listener != null) {
      try {
        await TencentImSDKPlugin.v2TIMManager
            .getMessageManager()
            .removeAdvancedMsgListener(listener: listener);
      } catch (e) {
        AppLogger.debug(
            '[NotificationMessageListener] removeAdvancedMsgListener failed (platform likely torn down): $e');
      }
    }
    _listener = null;
    _registered = false;
    if (identical(_instance, this)) {
      _instance = null;
    }
  }

  /// Disposes the current singleton (if any) and clears the static slot so
  /// the next [forService] call constructs a fresh listener bound to the
  /// new session's [FfiChatService]. Safe to call when no singleton has
  /// been created yet — it becomes a no-op.
  ///
  /// Strict superset of [resetForTest]: that one only clears the static
  /// slot for unit tests that never registered with the SDK, this one also
  /// removes the SDK listener and cancels subscriptions.
  static Future<void> disposeAndReset() async {
    final s = _instance;
    _instance = null;
    await s?.dispose();
  }

  void _onRecvNewMessage(V2TimMessage message) {
    try {
      if (_shouldSuppress(message)) return;
      final senderName = _resolveSenderName(message);
      final conversationId = _resolveConversationId(message);
      if (conversationId == null) {
        AppLogger.debug(
            '[NotificationMessageListener] Skipping: no conversationId for msgID=${message.msgID}');
        return;
      }
      final preview = _buildPreview(message);
      // Avatar best-effort — only resolves a path for C2C messages where we
      // have the sender's friend avatar cached in Prefs. Group avatars are
      // intentionally skipped to keep the path resolution off the hot path.
      _resolveAvatar(message).then((avatarPath) {
        NotificationService.instance.showMessageNotification(
          conversationId: conversationId,
          senderName: senderName,
          preview: preview,
          avatarPath: avatarPath,
        );
      });
    } catch (e, st) {
      AppLogger.logError(
          '[NotificationMessageListener] Error handling new message', e, st);
    }
  }

  bool _shouldSuppress(V2TimMessage message) {
    // Self-sent guard. Check both isSelf and sender vs the session's selfId
    // because some control-signal paths land with isSelf unset.
    if (message.isSelf ?? false) return true;
    final sender = message.sender ?? '';
    if (sender.isNotEmpty &&
        normalizeToxId(sender) == normalizeToxId(_service.selfId)) {
      return true;
    }
    // S29: a blocked sender must never ring a notification. This listener fires
    // (via the binary-replacement path) before the hook's block guard, so check
    // here too — `isBlocked` normalizes, so a 76-char sender matches a 64-char
    // stored id.
    if (sender.isNotEmpty && _service.isBlocked(sender)) {
      return true;
    }

    // Skip control-signal text messages that bubble up as plain text but
    // shouldn't trigger a notification (revoke / face / custom / location).
    if (message.elemType == MessageElemType.V2TIM_ELEM_TYPE_TEXT) {
      final text = message.textElem?.text ?? '';
      if (text.startsWith('__revoke__:')) return true;
    }

    // Foreground + active conversation guard. The user shouldn't get a
    // banner for the chat they're actively looking at.
    final lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    final isFocused = lifecycle == AppLifecycleState.resumed;
    final activeConv = UikitDataFacade.currentConversation;
    final activeConvId = activeConv?.conversationID;
    final messageConvId = _resolveConversationId(message);
    if (isFocused &&
        activeConvId != null &&
        messageConvId != null &&
        activeConvId == messageConvId) {
      return true;
    }

    // Mute guard — best-effort. Prefer the C2C recv-opt projection cache, which
    // is updated SYNCHRONOUSLY by the native SetC2CReceiveMessageOpt push: it
    // reflects a mute immediately, closing the "message arrives right after mute,
    // before the next ~5s conversation rebuild" race that the conversation-list
    // recvOpt (updated only on rebuild) would otherwise leave open. Fall back to
    // the UIKit conversation-list recvOpt (covers any path the cache missed).
    try {
      if (sender.isNotEmpty && C2CRecvOptCache.isMuted(sender)) {
        return true;
      }
      if (messageConvId != null) {
        final convs = UikitDataFacade.conversationList;
        for (final c in convs) {
          if (c.conversationID == messageConvId) {
            final recvOpt = c.recvOpt;
            if (recvOpt != null && recvOpt != 0) return true;
            break;
          }
        }
      }
    } catch (e) {
      // Don't let a UIKit data-layer hiccup block the notification.
      AppLogger.debug(
          '[NotificationMessageListener] mute lookup failed: $e (continuing)');
    }

    return false;
  }

  String _resolveSenderName(V2TimMessage message) {
    // Priority: friendRemark > nickName > sender (toxId) > "Unknown".
    final remark = message.friendRemark;
    if (remark != null && remark.isNotEmpty) return remark;
    final nick = message.nickName;
    if (nick != null && nick.isNotEmpty) return nick;
    final sender = message.sender;
    if (sender != null && sender.isNotEmpty) {
      // Trim long Tox IDs to the first 12 chars so the banner title isn't
      // a 76-char hex blob.
      if (sender.length > 16) {
        return '${sender.substring(0, 12)}…';
      }
      return sender;
    }
    return currentAppL10n().notificationNewMessage;
  }

  /// Returns `c2c_<publicKey>` or `group_<groupID>` to match the rest of the
  /// app's conversation identifier scheme. The Tox ID is normalized to its
  /// 64-char public-key form (`normalizeToxId`) because `FakeConversation`
  /// entries are built with the normalized key — if the SDK happens to
  /// deliver a 76-char full Tox address here, the raw form would miss both
  /// the conversation-lookup and the active-conversation/mute checks.
  /// Returns null when we can't determine either.
  String? _resolveConversationId(V2TimMessage message) {
    final groupId = message.groupID;
    if (groupId != null && groupId.isNotEmpty) {
      return 'group_$groupId';
    }
    final userId = message.userID;
    if (userId != null && userId.isNotEmpty) {
      return 'c2c_${normalizeToxId(userId)}';
    }
    final sender = message.sender;
    if (sender != null && sender.isNotEmpty) {
      return 'c2c_${normalizeToxId(sender)}';
    }
    return null;
  }

  String _buildPreview(V2TimMessage message) {
    final l10n = currentAppL10n();
    switch (message.elemType) {
      case MessageElemType.V2TIM_ELEM_TYPE_TEXT:
        final text = message.textElem?.text ?? '';
        if (text.isEmpty) return l10n.previewMessage;
        return text;
      case MessageElemType.V2TIM_ELEM_TYPE_IMAGE:
        return l10n.previewImage;
      case MessageElemType.V2TIM_ELEM_TYPE_VIDEO:
        return l10n.previewVideo;
      case MessageElemType.V2TIM_ELEM_TYPE_SOUND:
        final dur = message.soundElem?.duration;
        if (dur != null && dur > 0) return l10n.previewVoiceWithDuration(dur);
        return l10n.previewVoice;
      case MessageElemType.V2TIM_ELEM_TYPE_FILE:
        final name = message.fileElem?.fileName;
        if (name != null && name.isNotEmpty) {
          return l10n.previewFileWithName(name);
        }
        return l10n.previewFile;
      case MessageElemType.V2TIM_ELEM_TYPE_FACE:
        return l10n.previewSticker;
      case MessageElemType.V2TIM_ELEM_TYPE_LOCATION:
        return l10n.previewLocation;
      case MessageElemType.V2TIM_ELEM_TYPE_CUSTOM:
        return l10n.previewCustomMessage;
      case MessageElemType.V2TIM_ELEM_TYPE_GROUP_TIPS:
        return l10n.previewGroupEvent;
      default:
        return l10n.previewMessage;
    }
  }

  Future<String?> _resolveAvatar(V2TimMessage message) async {
    final groupId = message.groupID;
    if (groupId != null && groupId.isNotEmpty) {
      // Group sender avatar — skip; rendering a per-sender avatar in a
      // group banner is more work than this initial pass should do.
      return null;
    }
    final userId = message.userID ?? message.sender;
    if (userId == null || userId.isEmpty) return null;
    try {
      return await Prefs.getFriendAvatarPath(userId);
    } catch (e) {
      AppLogger.debug(
          '[NotificationMessageListener] avatar lookup failed for $userId: $e');
      return null;
    }
  }

  /// Test-only — does not unregister the SDK listener (no-op there is by
  /// design; see class-level comment).
  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }

  /// Test-only — returns whether the listener has been added to the SDK.
  @visibleForTesting
  bool get registeredForTest => _registered;
}

/// Convenience hook: pulls the active FfiChatService off [FakeUIKit] when
/// the caller doesn't have a handle. Returns null if FakeUIKit hasn't been
/// started yet — callers should retry once the session is ready.
NotificationMessageListener? notificationListenerFromFakeUiKit() {
  final ffi = FakeUIKit.instance.im?.ffi;
  if (ffi == null) return null;
  return NotificationMessageListener.forService(ffi);
}
