import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import '../util/responsive_layout.dart';

/// Slate-900 base background for call surfaces — aliased to the shared
/// `AppThemeConfig.darkScaffoldBackground` token so the call screen reads as a
/// continuation of the app, not a separate aesthetic.
const Color kCallBackgroundBase = AppThemeConfig.darkScaffoldBackground;

/// Shared page shell for all call screens: dark surface, safe area, top bar, content, bottom dock.
class CallSceneShell extends StatelessWidget {
  const CallSceneShell({
    super.key,
    required this.child,
    this.topBar,
    this.bottomBar,
    this.overlayBars = false,
  });

  final Widget child;
  final Widget? topBar;
  final Widget? bottomBar;

  /// `true` floats the bars over an edge-to-edge [child] (video calls, where
  /// the remote frame must bleed behind notch and dock); the child is then
  /// responsible for clearing them via [topBarHeight]. `false` (audio,
  /// ringing, conference) puts bars and child in one Column, so the centred
  /// identity stage can never slide under the dock on a short viewport —
  /// the Stack version reserved only the dock's *outer* spacing and collided
  /// on landscape phones.
  final bool overlayBars;

  /// Height reserved for [CallTopStatusBar]: 2×md vertical padding around the
  /// taller of its 48-px IconButton and the title+subtitle lines, never below
  /// the per-tier floor. Each line is derived from the theme style it renders
  /// with — font size scaled on its own (so non-linear Android scaling is
  /// honoured) times that style's line height. Overlay children position
  /// themselves below this.
  static double topBarHeight(BuildContext context) {
    final floor = ResponsiveLayout.responsiveValue<double>(
      context,
      mobile: 56,
      tablet: 64,
      desktop: 72,
    );
    final textTheme = Theme.of(context).textTheme;
    final lines = scaledLineHeight(context, textTheme.titleMedium, 16, 1.5) +
        scaledLineHeight(context, textTheme.bodySmall, 12, 1.33);
    return math.max(floor, 2 * AppSpacing.md + math.max(48, lines));
  }

  /// Rendered height of one line of [style] under the ambient text scaler:
  /// `scale(fontSize) × height`, with Material defaults as fallbacks. Rounded
  /// UP to a whole pixel because text layout snaps line boxes upward (a
  /// 70.9-px estimate overflowed a real 71.0-px pair of lines by 0.1 px).
  static double scaledLineHeight(
    BuildContext context,
    TextStyle? style,
    double fallbackSize,
    double fallbackHeight, {
    double? fontSize,
  }) {
    final size = fontSize ?? style?.fontSize ?? fallbackSize;
    final height = style?.height ?? fallbackHeight;
    return (MediaQuery.textScalerOf(context).scale(size) * height)
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final topBarHeight = CallSceneShell.topBarHeight(context);
    final bottomPadding = ResponsiveLayout.responsiveValue<double>(
      context,
      mobile: AppSpacing.lg,
      tablet: AppSpacing.xl,
      desktop: AppSpacing.xl,
    );
    final horizontalPadding =
        ResponsiveLayout.responsiveHorizontalPadding(context);

    final Widget? framedTop = topBar == null
        ? null
        : ConstrainedBox(
            constraints: BoxConstraints(minHeight: topBarHeight),
            child: topBar!,
          );
    final Widget? framedBottom = bottomBar == null
        ? null
        : Padding(
            padding: EdgeInsets.symmetric(
              vertical: bottomPadding,
              horizontal: horizontalPadding,
            ),
            child: bottomBar!,
          );

    if (!overlayBars) {
      // Background reaches the screen edges; SafeArea keeps every control
      // clear of notch / home indicator / desktop title-bar inset.
      return Container(
        color: kCallBackgroundBase,
        child: SafeArea(
          child: Column(
            children: [
              if (framedTop != null) framedTop,
              Expanded(child: child),
              if (framedBottom != null) framedBottom,
            ],
          ),
        ),
      );
    }

    return Container(
      color: kCallBackgroundBase,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Edge-to-edge video stage. It clears the bars itself (see
          // `topBarHeight`), so no padding here — padding would letterbox the
          // remote frame behind the notch.
          Positioned.fill(child: child),
          if (framedTop != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(bottom: false, child: framedTop),
            ),
          if (framedBottom != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(top: false, child: framedBottom),
            ),
        ],
      ),
    );
  }
}
