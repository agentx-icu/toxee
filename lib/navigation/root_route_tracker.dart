import 'package:flutter/widgets.dart';

/// Mirrors the ROOT navigator's route stack so code outside a route can ask
/// "what is on top right now?" — something [NavigatorState] does not expose.
///
/// Used by the master-detail transition (`lib/ui/home/master_detail_transition.dart`)
/// to tell which conversation is actually on screen when a rotation / split
/// screen / window resize crosses the master-detail breakpoint: a chat route
/// pushed by ANY caller (the UIKit conversation row, global search, a profile's
/// "Send a message", `HomePage._openChat`) shows up here, and so does anything
/// covering it (a group profile, a dialog, the search page).
///
/// Must be ONE long-lived instance: the root `MaterialApp` sits inside theme /
/// locale rebuild callbacks, and a fresh observer attached on a rebuild would
/// never see the routes pushed before it. Always register [instance].
class RootRouteTracker extends NavigatorObserver {
  RootRouteTracker._();

  /// A standalone tracker for tests (attach it to a test navigator).
  @visibleForTesting
  RootRouteTracker.forTest();

  static final RootRouteTracker instance = RootRouteTracker._();

  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  /// Bumped on every change to the stack, for code that follows what is on
  /// screen (e.g. saving the open conversation for state restoration).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// The route currently on top of the root navigator, or null before the
  /// first push.
  Route<dynamic>? get topRoute => _stack.isEmpty ? null : _stack.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    revision.value++;
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    revision.value++;
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    revision.value++;
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (newRoute != null) {
      if (index >= 0) {
        _stack[index] = newRoute;
      } else {
        _stack.add(newRoute);
      }
    } else if (index >= 0) {
      _stack.removeAt(index);
    }
    revision.value++;
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
