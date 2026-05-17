import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';

// 4pt matches AppSpacing.xs grid — keeps skeleton bars aligned to the
// same rhythm as live content.
const double _kSkeletonRadius = 4.0;

// 1.2s linear cycle — feels lively without becoming a distraction.
const Duration _kShimmerCycle = Duration(milliseconds: 1200);

/// A skeleton/shimmer loading placeholder for lists.
/// Uses pure Flutter animations without external packages.
///
/// Base / highlight colors derive from the active `ColorScheme`:
/// - base = `cs.surfaceContainerHighest`
/// - highlight = `cs.surface`
///
/// Respects `MediaQuery.disableAnimationsOf`: when reduced motion is on the
/// shimmer holds at the base color (no animation, no flashing) but the
/// skeleton layout still renders so the loading affordance is preserved.
class LoadingShimmer extends StatefulWidget {
  const LoadingShimmer({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 64.0,
  });

  final int itemCount;
  final double itemHeight;

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _kShimmerCycle,
    );
    // Start/stop is decided at build time based on MediaQuery — see build().
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Scheme-driven shimmer palette — adapts automatically to dark mode.
    final baseColor = cs.surfaceContainerHighest;
    final highlightColor = cs.surface;

    // Gate the animation behind reduced-motion. When motion is reduced we
    // stop and hold at the base color (no shimmer band, no flashing).
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Column(
          children: List.generate(widget.itemCount, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: SizedBox(
                height: widget.itemHeight,
                child: Row(
                  children: [
                    // Avatar placeholder
                    _ShimmerBox(
                      width: 48,
                      height: 48,
                      isCircle: true,
                      baseColor: baseColor,
                      highlightColor: highlightColor,
                      progress: _controller.value,
                      animate: !reduceMotion,
                    ),
                    AppSpacing.horizontalMd,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Title placeholder
                          _ShimmerBox(
                            width: double.infinity,
                            height: 14,
                            baseColor: baseColor,
                            highlightColor: highlightColor,
                            progress: _controller.value,
                            animate: !reduceMotion,
                            widthFraction: 0.6 + (index % 3) * 0.1,
                          ),
                          AppSpacing.verticalSm,
                          // Subtitle placeholder
                          _ShimmerBox(
                            width: double.infinity,
                            height: 10,
                            baseColor: baseColor,
                            highlightColor: highlightColor,
                            progress: _controller.value,
                            animate: !reduceMotion,
                            widthFraction: 0.4 + (index % 2) * 0.2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.baseColor,
    required this.highlightColor,
    required this.progress,
    this.isCircle = false,
    this.widthFraction = 1.0,
    this.animate = true,
  });

  final double width;
  final double height;
  final Color baseColor;
  final Color highlightColor;
  final double progress;
  final bool isCircle;
  final double widthFraction;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    // When reduced-motion is on, pin to the base color (no shimmer band).
    final color = animate
        ? Color.lerp(
            baseColor,
            highlightColor,
            (0.5 + 0.5 * (progress * 2 - 1).abs()).clamp(0.0, 1.0),
          )!
        : baseColor;
    return FractionallySizedBox(
      widthFactor: isCircle ? null : widthFraction,
      child: Container(
        width: isCircle ? width : null,
        height: height,
        decoration: BoxDecoration(
          color: color,
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle ? null : BorderRadius.circular(_kSkeletonRadius),
        ),
      ),
    );
  }
}
