import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';

import '../../util/tox_utils.dart';

/// Navigation policy for a profile surface's "Send a message" tile (user
/// profile chat button, group profile chat button), wired to the UIKit fork's
/// dedicated `onNavigateToChat` handler slot.
///
/// Extracted from the `HomePage` closure so the pop-idempotence and
/// duplicate-chat-route rules are L1-testable with a real [Navigator]
/// (see `test/ui/contact/profile_send_message_navigation_test.dart`).
///
/// The policy must hold no matter which surface pushed the profile — the
/// contacts-tab row, the chat-header avatar, or a message-row avatar. The
/// previous design guessed the origin from a flag only the contacts-tab path
/// set, so a profile opened from the chat header misread "Send a message" as
/// a contact-row tap and pushed profile pages in an endless loop.

/// Returns the navigator's current top route without popping anything:
/// `popUntil` invokes the predicate on the top-most active route first, and
/// an immediate `true` stops it before any pop happens. Routes already
/// popped (even mid-transition) are not reported.
Route<dynamic>? topRouteOf(NavigatorState navigator) {
  Route<dynamic>? top;
  navigator.popUntil((route) {
    top ??= route;
    return true;
  });
  return top;
}

/// Whether the navigator's top route is the UIKit message route already bound
/// to the given chat target. Used on compact layouts after popping a profile:
/// an identical chat route beneath means we're already back in the target
/// chat and must not push a duplicate. UIKit routes carry their route name +
/// options in [RouteSettings] (see `TencentCloudChatRouter.navigateTo`).
bool topRouteIsMessageFor(
  NavigatorState navigator, {
  String? userID,
  String? groupID,
}) {
  final top = topRouteOf(navigator);
  if (top?.settings.name != TencentCloudChatRouteNames.message) return false;
  final args = top?.settings.arguments;
  if (args is! Map) return false;
  final options = args['options'];
  if (options is! TencentCloudChatMessageOptions) return false;
  if (userID != null && userID.isNotEmpty) {
    final boundUser = options.userID;
    // Tox ids appear both as 76-char full ids and 64-char public keys.
    return boundUser != null &&
        boundUser.isNotEmpty &&
        normalizeToxId(boundUser) == normalizeToxId(userID);
  }
  if (groupID != null && groupID.isNotEmpty) {
    return options.groupID == groupID;
  }
  return false;
}

/// Handles a profile "Send a message" tap: close the profile route (if it is
/// what's on top) and open the chat via [openChat] — unless the pop already
/// revealed the target chat on a compact layout.
///
/// Returns true when handled (the UIKit hook contract: true suppresses the
/// fork's default navigation). Only an empty target returns false.
///
/// Idempotent against onTap double-fires: the pop is guarded on the top route
/// actually being a profile, so a second fire cannot pop the page beneath,
/// and [openChat] re-binding the same conversation is harmless.
bool handleProfileSendMessage(
  NavigatorState navigator, {
  required bool isCompactLayout,
  required void Function({String? peerId, String? groupId}) openChat,
  String? userID,
  String? groupID,
}) {
  final hasUser = userID != null && userID.isNotEmpty;
  final hasGroup = groupID != null && groupID.isNotEmpty;
  if (!hasUser && !hasGroup) return false;
  final topName = topRouteOf(navigator)?.settings.name;
  if (topName == TencentCloudChatRouteNames.userProfile ||
      topName == TencentCloudChatRouteNames.groupProfile) {
    navigator.pop();
  }
  // Compact layouts PUSH chat routes. When the profile was opened from inside
  // the target chat itself (header avatar), the pop above already reveals
  // that chat — pushing again would stack a duplicate chat page on every
  // profile round-trip. Master-detail layouts bind the right pane instead, so
  // re-opening is a no-op there and needs no guard.
  if (isCompactLayout &&
      topRouteIsMessageFor(navigator, userID: userID, groupID: groupID)) {
    return true;
  }
  openChat(
    peerId: hasUser ? userID : null,
    groupId: hasGroup ? groupID : null,
  );
  return true;
}
