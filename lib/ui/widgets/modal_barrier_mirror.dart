import 'package:flutter/material.dart';

/// Tracks the top-most modal route with a barrier so chrome drawn OUTSIDE the
/// app's Navigator (the desktop caption-button strip in `DesktopWindowFrame`)
/// can dim itself in step with the app content.
///
/// WHY: `ModalBarrier` is an overlay entry inside the Navigator. Anything the
/// `MaterialApp.builder` layers above the Navigator is never covered by it, so
/// the caption strip stayed a bright surface-coloured block at the top-right
/// of an otherwise dimmed window whenever a dialog or picker was open
/// (Windows real-UI screenshot, 2026-09-04). Register the observer in
/// `navigatorObservers` and wrap the chrome in [ModalBarrierMirror].
class ModalBarrierObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  /// The top-most modal route that paints a barrier, or null.
  final ValueNotifier<ModalRoute<dynamic>?> barrierRoute =
      ValueNotifier<ModalRoute<dynamic>?>(null);

  void _recompute() {
    ModalRoute<dynamic>? top;
    for (final r in _stack.reversed) {
      if (r is ModalRoute<dynamic> && (r.barrierColor?.a ?? 0) > 0) {
        top = r;
        break;
      }
      // A full-screen page above the barrier hides it, like the barrier itself.
      if (r is PageRoute<dynamic>) break;
    }
    if (barrierRoute.value != top) barrierRoute.value = top;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _recompute();
  }

  /// `didPop` fires when the reverse transition STARTS, while the real
  /// `ModalBarrier` keeps painting (fading out) until it ends. Keep the route
  /// until its animation is dismissed so the mirror fades in step instead of
  /// snapping clear ~150 ms early.
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final animation = route is TransitionRoute<dynamic> ? route.animation : null;
    if (animation == null || animation.status == AnimationStatus.dismissed) {
      _stack.remove(route);
      _recompute();
      return;
    }
    late final void Function(AnimationStatus) onStatus;
    onStatus = (status) {
      if (status != AnimationStatus.dismissed) return;
      animation.removeStatusListener(onStatus);
      _stack.remove(route);
      _recompute();
    };
    animation.addStatusListener(onStatus);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _recompute();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0) {
      if (newRoute != null) {
        _stack[i] = newRoute;
      } else {
        _stack.removeAt(i);
      }
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _recompute();
  }
}

/// Paints the barrier colour of [observer]'s top-most modal route over [child],
/// following that route's transition animation, so out-of-Navigator chrome dims
/// exactly like the app content does. Pointer events still reach [child].
class ModalBarrierMirror extends StatelessWidget {
  const ModalBarrierMirror({
    super.key,
    required this.observer,
    required this.child,
  });

  final ModalBarrierObserver observer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ModalRoute<dynamic>?>(
      valueListenable: observer.barrierRoute,
      builder: (context, route, _) {
        if (route == null) return child;
        final color = route.barrierColor ?? Colors.transparent;
        // Same curve the route applies to its own ModalBarrier.
        final animation = (route.animation ?? kAlwaysCompleteAnimation)
            .drive(CurveTween(curve: route.barrierCurve));
        return Stack(
          fit: StackFit.passthrough,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: animation,
                  child: ColoredBox(
                    key: const ValueKey('desktop_caption_barrier_mirror'),
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
