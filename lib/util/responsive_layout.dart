import 'package:flutter/material.dart';

/// Responsive layout utility class
/// Provides helper methods for creating responsive layouts that adapt to
/// different screen sizes (mobile, tablet, desktop)
class ResponsiveLayout {
  // Breakpoints for different device types
  static const double mobileBreakpoint = 600.0;
  // Large-phone tier sits between mobile and tablet (e.g. landscape phones,
  // small foldables, 7" tablets). They still want a bottom nav rather than
  // a sidebar even though they're wider than the strict mobile breakpoint.
  static const double largePhoneBreakpoint = 720.0;
  static const double tabletBreakpoint = 1024.0;

  /// Width at or above which we render a master-detail (two-column)
  /// conversation list + chat layout. Below this, the chat fills the
  /// available area like a phone.
  static const double masterDetailBreakpoint = 900.0;

  /// Reserved vertical space at the top of the sidebar on macOS so the
  /// traffic-light buttons do not overlap interactive content (avatar,
  /// menu rows). 28pt matches the standard macOS title-bar inset.
  static const double macTitleBarReservedHeight = 28.0;

  /// Check if current screen is mobile size
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < mobileBreakpoint;
  }

  /// Check if current screen is a "large phone" (landscape phones, small
  /// foldables, 7" tablets) — wider than mobile but still bottom-nav driven.
  static bool isLargePhone(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < largePhoneBreakpoint;
  }

  /// Check if current screen is tablet size
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= mobileBreakpoint && width < tabletBreakpoint;
  }

  /// Check if current screen is desktop size.
  /// Strict `> tabletBreakpoint` so iPad Pro 12.9 portrait (exactly 1024
  /// wide) stays in the tablet tier and gets tablet treatment.
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width > tabletBreakpoint;
  }

  /// True when the device is a tablet held in portrait orientation.
  static bool isTabletPortrait(BuildContext context) {
    return isTablet(context) &&
        MediaQuery.orientationOf(context) == Orientation.portrait;
  }

  /// True when the device is a tablet held in landscape orientation.
  static bool isTabletLandscape(BuildContext context) {
    return isTablet(context) &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  /// Get responsive value based on screen size
  ///
  /// Returns the appropriate value for the current screen size:
  /// - mobile: value for mobile screens (< 600px)
  /// - tablet: value for tablet screens (600px - 1024px)
  /// - desktop: value for desktop screens (> 1024px)
  ///
  /// If a value is not provided for a specific size, it will fall back to:
  /// desktop -> tablet -> mobile
  static T responsiveValue<T>(
    BuildContext context, {
    T? mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context) && desktop != null) {
      return desktop;
    } else if (isTablet(context) && tablet != null) {
      return tablet;
    } else if (isMobile(context) && mobile != null) {
      return mobile;
    }
    // Fallback chain: desktop -> tablet -> mobile
    return desktop ?? tablet ?? mobile ?? (throw ArgumentError('At least one value must be provided'));
  }

  /// Get responsive padding based on screen size.
  ///
  /// Horizontal padding (12/16/24) is wider than the historical 8/16/24
  /// because mobile content was hugging the screen edge. Vertical padding
  /// stays modest (8/12/16) because `SafeArea` usually handles top/bottom.
  static EdgeInsets responsivePadding(BuildContext context) {
    return responsiveValue<EdgeInsets>(
      context,
      mobile: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      tablet: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      desktop: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
    );
  }

  /// Get responsive horizontal padding
  static double responsiveHorizontalPadding(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 12.0,
      tablet: 16.0,
      desktop: 24.0,
    );
  }

  /// Get responsive vertical padding
  static double responsiveVerticalPadding(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 8.0,
      tablet: 16.0,
      desktop: 24.0,
    );
  }

  /// Get responsive column count for grid layouts
  static int responsiveColumnCount(BuildContext context) {
    return responsiveValue<int>(
      context,
      mobile: 1,
      tablet: 2,
      desktop: 3,
    );
  }

  /// Get responsive font size multiplier
  static double responsiveFontSize(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 1.0,
      tablet: 1.1,
      desktop: 1.2,
    );
  }

  /// Get responsive max width for content containers
  static double? responsiveMaxWidth(BuildContext context) {
    return responsiveValue<double?>(
      context,
      mobile: null, // Full width on mobile
      tablet: 800.0,
      desktop: 1200.0,
    );
  }

  /// Get responsive sidebar width
  /// Mobile: 0 (uses Drawer instead of permanent sidebar)
  /// Tablet: 80 (compact icon sidebar)
  /// Desktop: 100 (icon + label sidebar)
  static double responsiveSidebarWidth(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 0.0, // No sidebar on mobile, uses Drawer
      tablet: 80.0,
      desktop: 100.0,
    );
  }

  /// Get responsive bottom navigation bar height
  static double responsiveBottomNavHeight(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 56.0, // Standard bottom nav height
      tablet: 0.0, // No bottom nav on tablet/desktop
      desktop: 0.0,
    );
  }

  /// Check if should show bottom navigation.
  ///
  /// True below `largePhoneBreakpoint` (720) so landscape phones and small
  /// foldables keep the touch-first bottom nav rather than jumping to a
  /// sidebar at 600pt.
  static bool shouldShowBottomNav(BuildContext context) {
    return MediaQuery.of(context).size.width < largePhoneBreakpoint;
  }

  /// Check if should show sidebar
  static bool shouldShowSidebar(BuildContext context) {
    return !shouldShowBottomNav(context);
  }

  /// True when the viewport is wide enough to show a master-detail split
  /// (conversation list on the left, chat on the right).
  static bool shouldShowMasterDetail(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= masterDetailBreakpoint;
  }

  /// Get responsive icon size
  static double responsiveIconSize(BuildContext context) {
    return responsiveValue<double>(
      context,
      mobile: 24.0,
      tablet: 28.0,
      desktop: 32.0,
    );
  }
}
