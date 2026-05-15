import 'package:flutter/material.dart';

import '../../util/platform_utils.dart';

/// Wraps a list item with a staggered entrance animation (slide up + fade in).
class StaggeredListItem extends StatefulWidget {
  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
    this.staggerDelay = const Duration(milliseconds: 50),
    this.animationDuration = const Duration(milliseconds: 300),
  });

  final int index;
  final Widget child;
  final Duration staggerDelay;
  final Duration animationDuration;

  @override
  State<StaggeredListItem> createState() => _StaggeredListItemState();
}

class _StaggeredListItemState extends State<StaggeredListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Stagger start based on index. Cap is platform-adaptive: desktop users
    // are mouse-driven and perceive long sub-second tails as sluggish, so we
    // tighten to 150ms there. On touch, the slower 300ms cap still feels like
    // a deliberate cascade rather than a snap.
    final delay = widget.staggerDelay * widget.index;
    final cap = PlatformUtils.isDesktop
        ? const Duration(milliseconds: 150)
        : const Duration(milliseconds: 300);
    final cappedDelay = delay > cap ? cap : delay;
    Future.delayed(cappedDelay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
