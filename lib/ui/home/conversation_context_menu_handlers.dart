import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_conversation_event_handlers.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart'
    as conv_pkg;
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

import '../../util/logger.dart';

/// Install toxee's conversation-row context menu as UIKit's long-press /
/// secondary-tap handler and return the matching teardown.
///
/// The teardown only undoes what THIS call installed. A HomePage remount via
/// `pushAndRemoveUntil` (forceHomeRoot recovery, account switch) builds and
/// first-frames the NEW HomePage — which installs its own handlers in its
/// post-frame callback — BEFORE the OLD route is disposed. An unconditional
/// reset on dispose therefore clobbered the new handlers, and every long-press
/// / secondary-tap on a conversation row silently fell back to UIKit's
/// upstream action sheet (Mark as Read / Hide / Delete) instead of toxee's
/// context menu. Seen live 2026-08-23 on all three mobile pairs (`sweep_conv`
/// first attempt, screenshot-confirmed); same identity-guard pattern as the
/// L3 reader registrations in `home_page_bootstrap.dart`.
///
/// [isMounted] is consulted on every event so a handler can never drive a
/// disposed State; [showMenu] is the menu itself. [handlers] is the UIKit
/// registry to install into — production uses UIKit's live one, tests hand in
/// a bare `TencentCloudChatConversationUIEventHandlers()` (the live accessor
/// needs an initialized `TencentCloudChat.instance`).
VoidCallback installConversationContextMenuHandlers({
  required bool Function() isMounted,
  required Future<void> Function(
    V2TimConversation conversation,
    Offset position,
  )
  showMenu,
  @visibleForTesting TencentCloudChatConversationUIEventHandlers? handlers,
}) {
  final uiHandlers =
      handlers ??
      conv_pkg
          .TencentCloudChatConversationManager
          .eventHandlers
          .uiEventHandlers;

  Future<bool> onSecondaryTap({
    required V2TimConversation conversation,
    required Offset position,
  }) async {
    if (!isMounted()) return false;
    await showMenu(conversation, position);
    return true;
  }

  Future<bool> onLongPress({
    required V2TimConversation conversation,
    required Offset position,
  }) async {
    if (!isMounted()) return false;
    await showMenu(conversation, position);
    return true;
  }

  uiHandlers.setEventHandlers(
    onSecondaryTapConversationItem: onSecondaryTap,
    onLongPressConversationItem: onLongPress,
  );

  return () {
    // There is no "clear" API: a handler is retired by replacing it with a
    // no-op that returns false (UIKit's default). Only retire the closures
    // that are still ours — a newer HomePage's registration wins.
    try {
      final stillOursSecondary = identical(
        uiHandlers.onSecondaryTapConversationItem,
        onSecondaryTap,
      );
      final stillOursLongPress = identical(
        uiHandlers.onLongPressConversationItem,
        onLongPress,
      );
      if (!stillOursSecondary && !stillOursLongPress) return;
      uiHandlers.setEventHandlers(
        onSecondaryTapConversationItem: stillOursSecondary
            ? ({
                required V2TimConversation conversation,
                required Offset position,
              }) async => false
            : null,
        onLongPressConversationItem: stillOursLongPress
            ? ({
                required V2TimConversation conversation,
                required Offset position,
              }) async => false
            : null,
      );
    } catch (e) {
      AppLogger.warn(
        '[HomePage] failed to restore conversation context-menu no-ops: $e',
      );
    }
  };
}
