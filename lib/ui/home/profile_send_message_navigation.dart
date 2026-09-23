import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';

import '../../i18n/app_localizations.dart';
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
  return top != null && routeIsMessageFor(top, userID: userID, groupID: groupID);
}

/// Whether [route] is the UIKit message route bound to the given chat target.
bool routeIsMessageFor(
  Route<dynamic> route, {
  String? userID,
  String? groupID,
}) {
  if (route.settings.name != TencentCloudChatRouteNames.message) return false;
  final args = route.settings.arguments;
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

/// Finish a "leave / dismiss group" started from the group profile.
///
/// On success the profile closes AND, on a compact layout where the profile
/// was opened from the chat header, so does the chat underneath: the toxee
/// profile override used to pop only itself, leaving the user inside the chat
/// of the group they had just left, composer still live. (Upstream pops with
/// `true` and lets the header pop the chat; that contract is lost once the
/// profile body is overridden, and the header's desktop builder ignores it.)
/// On failure the user is told — a timed-out quit used to show nothing.
Future<void> finishLeaveGroup(
  BuildContext context, {
  required String groupID,
  required bool succeeded,
}) async {
  if (!succeeded) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context)!.leaveGroupFailed),
    ));
    return;
  }
  final navigator = Navigator.of(context);
  // Close exactly the profile route [context] lives in — never "whatever is on
  // top". The quit awaits the network, and something can open over the
  // profile meanwhile (the group-invite prompt, a toast-triggered dialog): a
  // bare `maybePop()` closed THAT instead and left the left group's profile
  // behind. Same on desktop (profile is a full-window root route) and compact.
  final profileRoute = ModalRoute.of(context);
  if (profileRoute != null && profileRoute.isActive) {
    if (profileRoute.isCurrent) {
      navigator.pop();
    } else {
      // Remove it where it stands and leave the covering route on screen. The
      // chat beneath (compact, profile opened from the chat header) can only
      // be checked once that cover is gone, so wait for it.
      final cover = topRouteOf(navigator);
      navigator.removeRoute(profileRoute);
      if (cover == null || identical(cover, profileRoute)) return;
      await cover.popped;
      if (!navigator.mounted) return;
    }
  }
  // Only the message route bound to THIS group, and only when it is on top.
  if (topRouteIsMessageFor(navigator, groupID: groupID)) {
    navigator.pop();
  }
}
