import 'package:flutter/material.dart';
import '../../util/responsive_layout.dart';

/// A responsive Scaffold that adapts its layout based on screen size
/// 
/// - Mobile: Uses bottom navigation bar
/// - Tablet/Desktop: Uses drawer/sidebar navigation
class ResponsiveScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? drawer;
  final Widget? endDrawer;
  final FloatingActionButton? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? appBar;
  final Color? backgroundColor;
  final bool extendBody;
  final bool extendBodyBehindAppBar;

  const ResponsiveScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.drawer,
    this.endDrawer,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.appBar,
    this.backgroundColor,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final isDesktop = ResponsiveLayout.isDesktop(context);

    // On mobile, use bottom navigation if provided
    // On tablet/desktop, use drawer if provided
    Widget? effectiveDrawer;
    Widget? effectiveBottomNav;

    if (isMobile) {
      effectiveBottomNav = bottomNavigationBar;
      // On mobile, drawer can still be used but is typically accessed via hamburger menu
      effectiveDrawer = drawer;
    } else {
      // On tablet/desktop, use drawer for navigation
      effectiveDrawer = drawer;
      effectiveBottomNav = null;
    }

    // Build app bar
    PreferredSizeWidget? effectiveAppBar = appBar;
    if (effectiveAppBar == null && title != null) {
      final hasActions = actions != null && actions!.isNotEmpty;
      effectiveAppBar = AppBar(
        title: Text(title!),
        actions: [
          ...?actions,
          if (hasActions) SizedBox(width: ResponsiveLayout.responsiveHorizontalPadding(context)),
        ],
        automaticallyImplyLeading: isMobile && drawer != null,
      );
    }

    return Scaffold(
      appBar: effectiveAppBar,
      drawer: effectiveDrawer,
      endDrawer: endDrawer,
      body: _buildBody(context, isMobile, isDesktop),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: effectiveBottomNav,
      backgroundColor: backgroundColor,
      extendBody: extendBody,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
    );
  }

  Widget _buildBody(BuildContext context, bool isMobile, bool isDesktop) {
    // Horizontal-only padding — `SafeArea` (typically wrapping `body`) is
    // already responsible for top/bottom insets. Doubling them up made the
    // layout feel collapsed on small phones and produced uneven gutters
    // around the appBar / bottom nav.
    final horizontalPadding =
        ResponsiveLayout.responsiveHorizontalPadding(context);
    final maxWidth = ResponsiveLayout.responsiveMaxWidth(context);

    Widget content = Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: body,
    );

    // On desktop/tablet, center content with max width
    if (maxWidth != null && !isMobile) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: content,
        ),
      );
    }

    return content;
  }
}

