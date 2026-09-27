import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';

import '../../navigation/root_route_tracker.dart';
import '../../util/logger.dart';

/// A conversation to keep open across a master-detail transition.
@immutable
class ChatTarget {
  const ChatTarget({this.userID, this.groupID});

  final String? userID;
  final String? groupID;

  bool get isValid =>
      (userID?.isNotEmpty ?? false) || (groupID?.isNotEmpty ?? false);

  @override
  bool operator ==(Object other) =>
      other is ChatTarget && other.userID == userID && other.groupID == groupID;

  @override
  int get hashCode => Object.hash(userID, groupID);

  @override
  String toString() => 'ChatTarget(userID: $userID, groupID: $groupID)';
}

/// The conversation a pushed UIKit message route shows, or null when [route]
/// is not one. Same argument shape as `routeIsMessageFor`.
ChatTarget? chatTargetOfRoute(Route<dynamic>? route) {
  if (route?.settings.name != TencentCloudChatRouteNames.message) return null;
  final args = route!.settings.arguments;
  if (args is! Map) return null;
  final options = args['options'];
  if (options is! TencentCloudChatMessageOptions) return null;
  final target = ChatTarget(userID: options.userID, groupID: options.groupID);
  return target.isValid ? target : null;
}

/// What the transition needs from the home shell. Closures, so the shell's
/// private state stays private and tests can drive every branch.
class MasterDetailHost {
  const MasterDetailHost({
    required this.isMounted,
    required this.isChatsTabIdle,
    required this.homeRoute,
    required this.showsMasterDetailNow,
    required this.accountKey,
    required this.wideSelection,
    required this.rootNavigator,
    required this.applyConfig,
    required this.openChat,
  });

  final bool Function() isMounted;

  /// On the Chats tab and not inside a contact-profile flow.
  final bool Function() isChatsTabIdle;

  /// The route hosting the home shell.
  final Route<dynamic>? Function() homeRoute;

  /// The breakpoint evaluated against the current size.
  final bool Function() showsMasterDetailNow;
  final String Function() accountKey;

  /// The conversation bound to the master-detail right pane.
  final ChatTarget? Function() wideSelection;
  final NavigatorState? Function() rootNavigator;

  /// Switches UIKit between the master-detail and the phone layout. Throws
  /// when UIKit is not ready yet.
  final void Function(bool wide) applyConfig;

  /// Opens [ChatTarget] the way the current layout opens chats: a pushed
  /// message route on a compact layout, the right pane on a wide one.
  final void Function(ChatTarget target) openChat;
}

/// Keeps the open conversation open when the layout crosses the
/// master-detail breakpoint at runtime (rotation, split screen, a desktop
/// window resize).
///
/// A compact layout shows a chat as a pushed message route; a wide one binds
/// it to the right pane. Switching only UIKit's layout mode (what the shell
/// used to do) moves neither: wide → compact dropped the user back on the
/// conversation list, and compact → wide left the chat route covering the
/// whole master-detail shell. This moves the one conversation that is
/// actually visible, and nothing else — a chat covered by another page
/// (group profile, search, a dialog) is left where it is.
class MasterDetailTransition {
  MasterDetailTransition({
    required this.host,
    RootRouteTracker? tracker,
    @visibleForTesting void Function(VoidCallback callback)? schedule,
    this.maxConfigAttempts = 10,
  }) : tracker = tracker ?? RootRouteTracker.instance,
       _schedule = schedule ?? _schedulePostFrame;

  final MasterDetailHost host;
  final RootRouteTracker tracker;
  final int maxConfigAttempts;
  final void Function(VoidCallback callback) _schedule;

  bool? _lastWide;
  int _generation = 0;

  /// The breakpoint side seen by the last build; null before the first one.
  bool? get lastWide => _lastWide;

  /// A conversation whose route was popped for a compact → wide move that a
  /// newer transition superseded before it could reopen it; the newer one
  /// takes it over instead of losing the chat.
  ChatTarget? _inFlight;

  /// The target of a transition whose layout switch ran out of attempts,
  /// with its account: the next build re-runs the switch and still owes it.
  ({ChatTarget target, String account})? _deferred;

  static void _schedulePostFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Call from the shell's build with the breakpoint result.
  void onBuild(bool wide) {
    if (wide == _lastWide) return;
    final isFirst = _lastWide == null;
    _lastWide = wide;
    final generation = ++_generation;
    final account = host.accountKey();
    ChatTarget? target;
    if (!isFirst) {
      target = _captureVisibleChat(toWide: wide) ?? _inFlight;
      _inFlight = null;
    } else if (_deferred?.account == account) {
      target = _deferred!.target;
    }
    _deferred = null;
    AppLogger.debug(
      '[MasterDetailTransition] crossing to wide=$wide gen=$generation '
      'target=$target',
    );
    _schedule(() => _apply(generation, wide, target, account, 1));
  }

  /// The conversation on screen right now in the current layout, or null
  /// (another tab, or a page / dialog covering the chat).
  ChatTarget? visibleChat() =>
      _captureVisibleChat(toWide: !host.showsMasterDetailNow());

  ChatTarget? _captureVisibleChat({required bool toWide}) {
    if (!host.isChatsTabIdle()) return null;
    final top = tracker.topRoute;
    if (toWide) return chatTargetOfRoute(top);
    final home = host.homeRoute();
    if (home == null || !identical(top, home)) return null;
    final selection = host.wideSelection();
    return (selection?.isValid ?? false) ? selection : null;
  }

  bool _stillCurrent(int generation, bool wide, String account) =>
      host.isMounted() &&
      generation == _generation &&
      host.showsMasterDetailNow() == wide &&
      host.accountKey() == account &&
      host.isChatsTabIdle();

  void _apply(
    int generation,
    bool wide,
    ChatTarget? target,
    String account,
    int attempt,
  ) {
    if (!host.isMounted() || generation != _generation) return;
    try {
      host.applyConfig(wide);
    } catch (_) {
      // UIKit's config object may not exist yet (its init is async). Retry
      // on the next frames rather than waiting for a rebuild that may never
      // come; a newer transition cancels this one.
      if (attempt < maxConfigAttempts) {
        _schedule(() => _apply(generation, wide, target, account, attempt + 1));
      } else {
        // Out of attempts: forget the side so the next build re-applies the
        // layout mode instead of believing it is already in place, and keep
        // the chat it still has to carry across.
        _lastWide = null;
        if (target != null) _deferred = (target: target, account: account);
      }
      return;
    }
    if (target != null) unawaited(_migrate(generation, wide, target, account));
  }

  Future<void> _migrate(
    int generation,
    bool wide,
    ChatTarget target,
    String account,
  ) async {
    if (!_stillCurrent(generation, wide, account)) {
      AppLogger.debug('[MasterDetailTransition] gen=$generation stale; skip');
      return;
    }
    if (!wide) {
      final home = host.homeRoute();
      if (home == null || !identical(tracker.topRoute, home)) return;
      host.openChat(target);
      return;
    }
    final chatRoute = tracker.topRoute;
    final navigator = host.rootNavigator();
    if (chatTargetOfRoute(chatRoute) != target || navigator == null) {
      AppLogger.debug('[MasterDetailTransition] chat route no longer on top');
      return;
    }
    // Pop first, then select: popping the chat route unbinds the active
    // conversation (ActiveConversationRouteObserver), so a selection made
    // before the pop would be cleared again.
    _inFlight = target;
    navigator.pop();
    if (chatRoute is TransitionRoute) {
      await chatRoute.completed;
    } else {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (generation != _generation) return; // the newer one took _inFlight
    _inFlight = null;
    // The user may have navigated during the exit animation (opened another
    // chat, the search page): only reopen onto the bare shell with nothing
    // selected, or this would override what they just chose.
    final home = host.homeRoute();
    if (!_stillCurrent(generation, wide, account) ||
        home == null ||
        !identical(tracker.topRoute, home) ||
        host.wideSelection() != null) {
      AppLogger.debug(
        '[MasterDetailTransition] gen=$generation stale after pop',
      );
      return;
    }
    AppLogger.debug('[MasterDetailTransition] reopening $target on wide pane');
    host.openChat(target);
  }
}
