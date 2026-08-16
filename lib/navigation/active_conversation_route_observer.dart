import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';

import '../sdk_fake/fake_uikit_core.dart';
import '../sdk_fake/uikit_data_facade.dart';
import '../util/logger.dart';

/// Clears the ACTIVE conversation when the pushed chat route leaves the stack.
///
/// THE BUG THIS FIXES (found by the mobile real-UI sweep, 2026-08-16). On a
/// compact/phone shell there is no master-detail right pane, so opening a chat
/// PUSHES the UIKit message route (`HomePage._openChat` -> `navigateToMessage`,
/// and the conversation list's own row tap). Binding happens on the way in —
/// `onTapConversationItem` calls `FfiChatService.setActivePeer(conversationID)`
/// — but nothing on the way OUT: popping the route (back chevron, iOS edge
/// swipe, Android system back) left `_activePeerId` pointing at the chat the
/// user had just LEFT.
///
/// That is not cosmetic. `FfiChatService.getC2CUnreadCount` short-circuits to 0
/// for `_activePeerId`, and the store's aggregate `totalUnreadCount` is built
/// from those per-conversation counts. So every later message from that peer
/// was silently counted as already-read: no unread badge on the conversation
/// row, no bottom-nav badge, no tray/app badge — indefinitely, until the user
/// happened to open some other chat. The desktop / tablet master-detail shell
/// is NOT affected, because it never pushes this route: it rebinds the right
/// pane through `_selectConversation`, and `HomePage.dispose` / the L3 home-root
/// applier are the only other unbinders.
///
/// WHY AN OBSERVER RATHER THAN AN `await`-AND-CLEAR AT THE PUSH SITE. The route
/// is pushed from at least four places (the toxee `_openChat`, the UIKit
/// conversation row, the contact profile's "Send a message" tile, global
/// search), and it can also be removed WITHOUT its pusher's future completing
/// (`pushAndRemoveUntil` on logout, the harness's `l3_pop_to_root`). One
/// observer on the root navigator covers all of them, including the gestures
/// that have no call site at all.
///
/// MOBILE PARITY. Registered on the single root `MaterialApp`, so iOS and
/// Android are covered by the same object; on desktop/tablet it simply never
/// fires because the message route is never pushed there.
class ActiveConversationRouteObserver extends NavigatorObserver {
  ActiveConversationRouteObserver();

  /// Route names whose disappearance means "the user is no longer looking at a
  /// conversation". `TencentCloudChatRouteNames.message` is the pushed chat
  /// page; it is stamped onto the route's [RouteSettings] by
  /// `TencentCloudChatRouter.navigateTo`, which is the only thing that pushes
  /// it.
  static bool _isChatRoute(Route<dynamic>? route) =>
      route?.settings.name == TencentCloudChatRouteNames.message;

  void _clearActiveConversation(String trigger) {
    final service = FakeUIKit.instance.im?.ffi;
    if (service == null) return;
    final previous = service.activePeerId;
    if (previous == null || previous.isEmpty) return;
    service.setActivePeer(null);
    UikitDataFacade.currentConversation = null;
    AppLogger.debug(
      '[ActiveConversationRouteObserver] $trigger: unbound active peer '
      '$previous so its unread count resumes counting',
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isChatRoute(route)) _clearActiveConversation('didPop');
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isChatRoute(route)) _clearActiveConversation('didRemove');
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_isChatRoute(oldRoute) && !_isChatRoute(newRoute)) {
      _clearActiveConversation('didReplace');
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
