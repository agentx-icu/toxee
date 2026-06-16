import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
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
  ///
  /// 800pt covers landscape large-phones (e.g. Pixel 6 rotated, 892pt) and
  /// small 7-9" tablets in landscape (typically 1024×768) without forcing
  /// master-detail on portrait phones (which top out around 430pt).
  static const double masterDetailBreakpoint = 800.0;

  /// Reserved vertical space at the top of the sidebar on macOS so the
  /// traffic-light buttons do not overlap interactive content (avatar,
  /// menu rows). 28pt matches the standard macOS title-bar inset.
  static const double macTitleBarReservedHeight = 28.0;

  /// Height of the frameless-window title-bar zone on Windows/Linux — the
  /// transparent drag strip plus the top-right caption buttons. Single source
  /// shared with `kDesktopTitleBarDragHeight` in
  /// `ui/widgets/desktop_window_frame.dart`.
  static const double desktopTitleBarDragHeight = 38.0;

  /// Top inset reserved for the OS window controls on a frameless desktop
  /// window: the macOS traffic lights (top-left) or the Windows/Linux caption
  /// buttons (top-right). Zero on mobile/web. The macOS value reuses
  /// [macTitleBarReservedHeight]; the desktop value reuses
  /// [desktopTitleBarDragHeight].
  static double desktopTitleBarInset() {
    if (!_isDesktopPlatform()) return 0;
    return Platform.isMacOS
        ? macTitleBarReservedHeight
        : desktopTitleBarDragHeight;
  }

  // Device-class checks (isMobile/isLargePhone/isTablet) use `shortestSide`
  // so phone-landscape stays "phone" and foldables/tablets behave by hardware
  // class, not orientation. `isDesktop` is OS-platform driven (with a width
  // fallback for web) so a small MacBook window (e.g. 1280x800, shortestSide
  // 800) still classifies as desktop. The phone/tablet checks exclude desktop
  // platforms so the tiers stay mutually exclusive even though
  // `responsiveValue` checks `isDesktop` first.
  // Layout-capacity checks (shouldShow*) below use `size.width` because they
  // care about available width.

  /// True when running on a desktop OS. Web is excluded because Flutter web
  /// running on a desktop browser still relies on window width for layout.
  static bool _isDesktopPlatform() {
    if (kIsWeb) return false; // avoid touching Platform.* on web
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  /// Check if current screen is mobile size
  static bool isMobile(BuildContext context) {
    if (_isDesktopPlatform()) return false;
    return MediaQuery.of(context).size.shortestSide < mobileBreakpoint;
  }

  /// Check if current screen is a "large phone" (landscape phones, small
  /// foldables, 7" tablets) — wider than mobile but still bottom-nav driven.
  static bool isLargePhone(BuildContext context) {
    if (_isDesktopPlatform()) return false;
    final shortest = MediaQuery.of(context).size.shortestSide;
    return shortest >= mobileBreakpoint && shortest < largePhoneBreakpoint;
  }

  /// Check if current screen is tablet size
  static bool isTablet(BuildContext context) {
    if (_isDesktopPlatform()) return false;
    final shortest = MediaQuery.of(context).size.shortestSide;
    return shortest >= mobileBreakpoint && shortest < tabletBreakpoint;
  }

  /// Desktop classification: true when the OS is a desktop OS, or (on web)
  /// when the window is at least `tabletBreakpoint` wide. Uses width (not
  /// shortestSide) for the web fallback so a wide-but-short browser window
  /// still gets desktop layout.
  static bool isDesktop(BuildContext context) {
    if (_isDesktopPlatform()) return true;
    return MediaQuery.of(context).size.width >= tabletBreakpoint;
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
  /// Mobile / large-phone (bottom-nav tier): 0 (uses Drawer instead of a
  /// permanent sidebar). Tablet: 80 (compact icon sidebar). Desktop: 100
  /// (icon + label sidebar).
  // Sidebar visibility and bottom-nav visibility are controlled by the same
  // check (`shouldShowBottomNav`) so the two never disagree (e.g. landscape
  // large-phones used to get a sidebar AND a bottom nav).
  static double responsiveSidebarWidth(BuildContext context) {
    if (shouldShowBottomNav(context)) return 0.0;
    return isDesktop(context) ? 100.0 : 80.0;
  }

  /// Get responsive bottom navigation bar height.
  // Mirror of `responsiveSidebarWidth`: one source of truth for which nav UI
  // is showing — `shouldShowBottomNav`.
  static double responsiveBottomNavHeight(BuildContext context) {
    return shouldShowBottomNav(context) ? 56.0 : 0.0;
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
