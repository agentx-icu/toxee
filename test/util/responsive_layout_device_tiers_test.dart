// Device-tier coverage for `ResponsiveLayout`, using the
// `debugIsDesktopPlatformOverride` seam added 2026-08-08.
//
// Companion to `responsive_layout_desktop_classification_test.dart`, which
// covers the width-driven helpers and documents (in its header) exactly why the
// device tiers were untestable: `_isDesktopPlatform()` reads `dart:io`
// `Platform.isMacOS/isWindows/isLinux`, which `debugDefaultTargetPlatformOverride`
// does NOT affect, so on a desktop CI host `isMobile`/`isLargePhone`/`isTablet`
// short-circuited to false and `isDesktop` to true for EVERY viewport. That
// file's own "worth considering" note proposed the seam; this file is what it
// unlocks.
//
// Why it matters beyond this class: 27 files under `lib/` call `ResponsiveLayout`,
// and the phone/tablet branches drive real UI — dialog sizing in
// `add_friend_dialog.dart` / `add_group_dialog.dart`, the login/register
// max-width clamps, the axis switch in `bootstrap_settings_section.dart`. All of
// those were unreachable from `flutter test`.
//
// Mobile parity: `ResponsiveLayout` is plain shared Dart with no platform
// stripping, so these tiers behave identically on iOS and Android.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/responsive_layout.dart';

void main() {
  setUp(() {
    // Pretend we are NOT on a desktop OS, i.e. a phone or tablet build.
    ResponsiveLayout.debugIsDesktopPlatformOverride = () => false;
  });

  tearDown(() {
    // Process-global — leaking it would silently reclassify every later test.
    ResponsiveLayout.debugIsDesktopPlatformOverride = null;
  });

  group('phone tier', () {
    testWidgets('portrait 390x844 is mobile, not tablet, not desktop',
        (tester) async {
      final p = await _probeAt(tester, const Size(390, 844));
      expect(p.isMobile, isTrue);
      expect(p.isLargePhone, isFalse);
      expect(p.isTablet, isFalse);
      // Previously unreachable: isDesktop could never be false on a CI host.
      expect(p.isDesktop, isFalse);
      expect(p.shouldShowBottomNav, isTrue);
      expect(p.sidebarWidth, 0.0);
    });

    testWidgets('landscape 844x390 stays mobile (shortestSide), but the '
        'width-driven nav flips to a sidebar', (tester) async {
      // The one combination that trips people up: device class uses
      // shortestSide (390 -> phone) while shouldShowBottomNav uses width
      // (844 >= largePhoneBreakpoint 720 -> sidebar). Both are deliberate;
      // pin them together so a future "just use shortestSide everywhere"
      // refactor has to confront the choice.
      final p = await _probeAt(tester, const Size(844, 390));
      expect(p.isMobile, isTrue, reason: 'shortestSide 390 < 600');
      expect(p.shouldShowBottomNav, isFalse, reason: 'width 844 >= 720');
      expect(p.shouldShowMasterDetail, isTrue, reason: 'width 844 >= 800');
    });
  });

  group('large-phone tier overlaps the tablet tier (documented consequence)',
      () {
    testWidgets('shortestSide 660 is BOTH isLargePhone and isTablet',
        (tester) async {
      // isLargePhone = 600 <= s < 720; isTablet = 600 <= s < 1024. The ranges
      // overlap by construction, so a 7" device answers true to both. Callers
      // must therefore check isLargePhone BEFORE isTablet, or they get the
      // tablet branch on a large phone. Pinned because nothing else states it.
      final p = await _probeAt(tester, const Size(660, 900));
      expect(p.isLargePhone, isTrue);
      expect(p.isTablet, isTrue);
      // isDesktop is true here purely because isTablet is true.
      expect(p.isDesktop, isTrue);
      // ...yet the nav is still the touch-first bottom bar (width 660 < 720),
      // which is the whole point of the large-phone tier.
      expect(p.shouldShowBottomNav, isTrue);
      expect(p.sidebarWidth, 0.0);
    });
  });

  group('tablet tier', () {
    testWidgets('iPad portrait 834x1194 -> tablet + portrait + desktop layout',
        (tester) async {
      final p = await _probeAt(tester, const Size(834, 1194));
      expect(p.isTablet, isTrue);
      expect(p.isLargePhone, isFalse, reason: 'shortestSide 834 >= 720');
      expect(p.isTabletPortrait, isTrue);
      expect(p.isTabletLandscape, isFalse);
      // Product direction (documented on isDesktop): tablets take the DESKTOP
      // layout in every orientation.
      expect(p.isDesktop, isTrue);
      expect(p.shouldShowBottomNav, isFalse);
      expect(p.shouldShowMasterDetail, isTrue, reason: 'width 834 >= 800');
    });

    testWidgets('iPad landscape 1194x834 -> tablet + landscape',
        (tester) async {
      final p = await _probeAt(tester, const Size(1194, 834));
      expect(p.isTablet, isTrue);
      expect(p.isTabletLandscape, isTrue);
      expect(p.isTabletPortrait, isFalse);
      expect(p.shouldShowMasterDetail, isTrue);
    });

    testWidgets('small tablet portrait 768x1024 -> tablet, but NO '
        'master-detail (width 768 < 800)', (tester) async {
      final p = await _probeAt(tester, const Size(768, 1024));
      expect(p.isTablet, isTrue);
      expect(p.isTabletPortrait, isTrue);
      expect(p.shouldShowBottomNav, isFalse, reason: 'width 768 >= 720');
      expect(p.shouldShowMasterDetail, isFalse, reason: 'width 768 < 800');
    });
  });

  group('tier boundaries', () {
    testWidgets('shortestSide exactly 600 leaves mobile and enters '
        'large-phone/tablet', (tester) async {
      final p = await _probeAt(tester, const Size(600, 900));
      expect(p.isMobile, isFalse, reason: 'the check is `< 600`, not `<= 600`');
      expect(p.isLargePhone, isTrue);
      expect(p.isTablet, isTrue);
    });

    testWidgets('shortestSide 1023 is still tablet; 1024 is not',
        (tester) async {
      final below = await _probeAt(tester, const Size(1023, 1400));
      expect(below.isTablet, isTrue);

      final at = await _probeAt(tester, const Size(1024, 1400));
      expect(at.isTablet, isFalse, reason: 'the check is `< 1024`');
      // Still desktop, now via the width >= tabletBreakpoint fallback rather
      // than via isTablet.
      expect(at.isDesktop, isTrue);
    });
  });

  group('compact rail (72pt) — reachable, but never on a tablet', () {
    // `responsiveSidebarWidth` is `shouldShowBottomNav ? 0 : (isDesktop ? 200 : 72)`.
    // The doc comment on it says "Tablet: 72 (compact icon-only rail)", and the
    // same wording appears in `sidebar.dart`. That wording is WRONG for tablets:
    // every tablet is `isDesktop` by design, so a tablet gets 0 (below 720pt
    // width) or 200 (at/above), never 72.
    //
    // The tier that DOES reach 72 is a landscape phone: shortestSide < 600 keeps
    // `isDesktop` false, while width >= 720 suppresses the bottom nav. Both
    // halves are pinned below so the tablet assertion cannot pass vacuously.

    testWidgets('every tablet size yields 200, never the compact rail',
        (tester) async {
      for (final size in const [
        Size(834, 1194), // iPad Pro 11 portrait
        Size(1194, 834), // iPad Pro 11 landscape
        Size(768, 1024), // small tablet portrait
      ]) {
        final p = await _probeAt(tester, size);
        expect(p.sidebarWidth, 200.0, reason: 'size=$size');
        expect(p.isCompactRail, isFalse, reason: 'size=$size');
      }
    });

    testWidgets('landscape phone 892x412 DOES get the 72pt compact rail',
        (tester) async {
      final p = await _probeAt(tester, const Size(892, 412));
      expect(p.isMobile, isTrue, reason: 'shortestSide 412 < 600');
      expect(p.isTablet, isFalse);
      expect(p.isDesktop, isFalse, reason: 'not a tablet, width 892 < 1024');
      expect(p.shouldShowBottomNav, isFalse, reason: 'width 892 >= 720');
      expect(p.sidebarWidth, 72.0);
      expect(p.isCompactRail, isTrue);
    });
  });

  group('seam hygiene', () {
    testWidgets('override(true) reproduces desktop-host behaviour',
        (tester) async {
      // Guards the seam itself: with the override forced true, a phone-sized
      // viewport must classify exactly the way an un-overridden desktop host
      // did before the seam existed.
      ResponsiveLayout.debugIsDesktopPlatformOverride = () => true;
      final p = await _probeAt(tester, const Size(390, 844));
      expect(p.isMobile, isFalse);
      expect(p.isTablet, isFalse);
      expect(p.isDesktop, isTrue);
    });
  });
}

class _Tiers {
  _Tiers({
    required this.isMobile,
    required this.isLargePhone,
    required this.isTablet,
    required this.isDesktop,
    required this.isTabletPortrait,
    required this.isTabletLandscape,
    required this.isCompactRail,
    required this.shouldShowBottomNav,
    required this.shouldShowMasterDetail,
    required this.sidebarWidth,
  });

  final bool isMobile;
  final bool isLargePhone;
  final bool isTablet;
  final bool isDesktop;
  final bool isTabletPortrait;
  final bool isTabletLandscape;
  final bool isCompactRail;
  final bool shouldShowBottomNav;
  final bool shouldShowMasterDetail;
  final double sidebarWidth;
}

Future<_Tiers> _probeAt(WidgetTester tester, Size size) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: _TierProbe(),
      ),
    ),
  );
  return tester.state<_TierProbeState>(find.byType(_TierProbe)).last!;
}

class _TierProbe extends StatefulWidget {
  const _TierProbe();
  @override
  State<_TierProbe> createState() => _TierProbeState();
}

class _TierProbeState extends State<_TierProbe> {
  _Tiers? last;

  @override
  Widget build(BuildContext context) {
    last = _Tiers(
      isMobile: ResponsiveLayout.isMobile(context),
      isLargePhone: ResponsiveLayout.isLargePhone(context),
      isTablet: ResponsiveLayout.isTablet(context),
      isDesktop: ResponsiveLayout.isDesktop(context),
      isTabletPortrait: ResponsiveLayout.isTabletPortrait(context),
      isTabletLandscape: ResponsiveLayout.isTabletLandscape(context),
      isCompactRail: ResponsiveLayout.isCompactRail(context),
      shouldShowBottomNav: ResponsiveLayout.shouldShowBottomNav(context),
      shouldShowMasterDetail: ResponsiveLayout.shouldShowMasterDetail(context),
      sidebarWidth: ResponsiveLayout.responsiveSidebarWidth(context),
    );
    return const SizedBox.shrink();
  }
}
