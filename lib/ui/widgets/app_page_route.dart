import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../util/app_theme_config.dart';

/// Custom page route with platform-aware transitions.
///
/// - **Mobile** (iOS / Android): subtle slide-from-right + fade,
///   duration [AppDurations.medium].
/// - **Desktop / web / tablet**: fade only, duration [AppDurations.fast].
/// - **Reduced motion**: when `MediaQuery.disableAnimationsOf(context)` is
///   true at the moment of [createAnimationController], the transition
///   collapses to [Duration.zero] so the new page appears instantly.
///
/// Public API kept stable: `AppPageRoute<T>({required Widget page})`.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required Widget page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: _buildTransition,
          transitionDuration: _isMobilePlatform
              ? AppDurations.medium
              : AppDurations.fast,
          reverseTransitionDuration: AppDurations.fast,
        );

  static bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  AnimationController createAnimationController() {
    final controller = super.createAnimationController();
    // Honour reduced-motion: if the user has disabled animations system-wide,
    // collapse both directions to zero so the transition is effectively a cut.
    final ctx = navigator?.context;
    if (ctx != null && MediaQuery.maybeDisableAnimationsOf(ctx) == true) {
      controller.duration = Duration.zero;
      controller.reverseDuration = Duration.zero;
    }
    return controller;
  }

  static Widget _buildTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppCurves.enter,
      reverseCurve: AppCurves.exit,
    );

    if (_isMobilePlatform) {
      // Mobile: subtle slide from right + fade.
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    }
    // Desktop / tablet: fade only.
    return FadeTransition(opacity: curved, child: child);
  }
}
