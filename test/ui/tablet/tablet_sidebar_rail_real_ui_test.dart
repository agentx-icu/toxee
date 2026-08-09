// Real-UI gates for the navigation rail on the TABLET form factor.
//
// What is under test
// ------------------
// `ResponsiveLayout.responsiveSidebarWidth` (`responsive_layout.dart:237-240`)
// and its derived `isCompactRail` (`:246-249`) decide whether the rail is the
// 200pt labelled sidebar or the 72pt icon-only rail, and `buildSidebar`
// (`lib/ui/settings/sidebar.dart:203`) branches every item on `isCompactRail`
// (`:406`, `:584`, `:812`).
//
//     responsiveSidebarWidth(ctx):
//       if (shouldShowBottomNav(ctx))  -> 0     // width < 720
//       return isDesktop(ctx) ? 200 : 72
//
// Because a tablet reports `isDesktop == true` (the product rule in
// `responsive_layout.dart:113-126`), **a tablet can never reach the 72pt
// compact rail**: below 720pt of width it gets the bottom nav (0), and at or
// above 720pt it gets 200. The 72pt tier is reachable only by a *phone*-class
// device that is wide enough for a sidebar — i.e. `shortestSide < 600`
// (so `isDesktop` is false) AND `720 <= width < 1024`, which is exactly a
// landscape large phone. The last group in this file pins that down so the
// "tablet, 72px" wording in the sidebar comments is not mistaken for a
// reachable tablet state.
//
// Real controls driven here
// -------------------------
// `UiKeys.sidebarChats` / `sidebarContacts` / `sidebarApplications` /
// `sidebarSettings` — the production `InkWell`s inside `buildSidebar`. Each
// tap must deliver the right tab index to the real `onTap` callback that
// `HomePage` passes in, at every tablet size and orientation.
//
// Harness follows `test/ui/profile_anchor_keys_test.dart`, which already
// mounts the real `buildSidebar` with a stub `FfiChatService`, mocked
// `flutter/platform` + `path_provider` channels and seeded `Prefs`. The rail
// is hosted inside a `Row` (as `HomePage.build` does at `home_page.dart:1293`)
// because a bare `SizedBox(width: …)` under a `Scaffold` body would be forced
// to the tight body constraints and the width assertion would be meaningless.
//
// Mobile parity: `sidebar.dart` and `responsive_layout.dart` are shared Dart —
// the tiers asserted here are the same on iPadOS and Android tablets. The only
// platform fork inside `buildSidebar` is the macOS traffic-light spacer
// (`Platform.isMacOS`), which changes vertical offset only, never the width or
// the labelled/compact decision.
//
// NOT executed in this environment (no dart/flutter available) — reviewed by
// reading only.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/sidebar.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/responsive_layout.dart';

const String _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567';
const String _nickname = 'RailNick';

/// Key on the host `SizedBox` that receives `responsiveSidebarWidth(context)`,
/// mirroring `home_page.dart:1293-1297`. Measuring it measures the production
/// value after layout, not a re-computation of the formula.
const Key _railHostKey = ValueKey<String>('tablet_rail_host');

class _RailHarnessService extends FfiChatService {
  _RailHarnessService() : super();

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  @override
  String get selfId => _toxId;

  @override
  String? getSelfToxId() => _toxId;

  @override
  Future<void> updateSelfProfile({
    required String nickname,
    required String statusMessage,
  }) async {}

  @override
  Future<void> updateAvatar(String? avatarPath) async {}

  void disposeStub() => unawaited(_connection.close());
}

bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

/// Captured inside the harness so tests can interrogate `ResponsiveLayout`
/// with the same context the rail was built from. Guards against a vacuous
/// run if the platform override ever stops taking effect.
late BuildContext _railContext;

/// Tab indices recorded from the production `onTap` callback.
final List<int> _tappedIndices = <int>[];

Widget _app(_RailHarnessService service) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: Builder(
        builder: (ctx) {
          _railContext = ctx;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: _railHostKey,
                width: ResponsiveLayout.responsiveSidebarWidth(ctx),
                child: buildSidebar(
                  context: ctx,
                  selectedIndex: 0,
                  onTap: _tappedIndices.add,
                  service: service,
                  connectionStatusStream: service.connectionStatusStream,
                ),
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          );
        },
      ),
    ),
  );
}

/// Bounded settle — `_UserAvatar._loadProfile()` is async (Prefs + File.exists)
/// and the avatar image resolves through the asset bundle, so a fixed number
/// of frames is used instead of `pumpAndSettle()`.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The label `Text` a rail item renders only in the WIDE (labelled) tier.
Finder _itemLabel(Key itemKey) =>
    find.descendant(of: find.byKey(itemKey), matching: find.byType(Text));

/// The `Tooltip` a rail item renders only in the COMPACT (icon-only) tier,
/// where the label has nowhere to go (`_compactTooltip`, sidebar.dart:31-37).
Finder _itemTooltip(Key itemKey) =>
    find.descendant(of: find.byKey(itemKey), matching: find.byType(Tooltip));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late Directory tempRoot;
  late _RailHarnessService service;

  const MethodChannel platformChannel = MethodChannel(
    'flutter/platform',
    JSONMethodCodec(),
  );
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  setUp(() async {
    _tappedIndices.clear();
    // Tablets are not a desktop OS. Without this, isTablet is always false on
    // the test host and every tablet expectation below would silently become a
    // desktop-host expectation.
    ResponsiveLayout.debugIsDesktopPlatformOverride = () => false;

    tempRoot = await Directory.systemTemp.createTemp(
      'tablet_sidebar_rail_real_ui_test_',
    );
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      platformChannel,
      (MethodCall call) async => null,
    );
    messenger.setMockMethodCallHandler(pathProviderChannel, (
      MethodCall call,
    ) async {
      switch (call.method) {
        case 'getApplicationSupportDirectory':
        case 'getApplicationDocumentsDirectory':
          return tempRoot.path;
        case 'getApplicationCacheDirectory':
          return p.join(tempRoot.path, 'cache');
        case 'getTemporaryDirectory':
          return p.join(tempRoot.path, 'temp');
        case 'getDownloadsDirectory':
          return p.join(tempRoot.path, 'Downloads');
        default:
          return null;
      }
    });

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(_toxId);
    await Prefs.setNickname(_nickname);
    await Prefs.setStatusMessage('RailStatus');
  });

  tearDown(() {
    ResponsiveLayout.debugIsDesktopPlatformOverride = null;
    messenger.setMockMethodCallHandler(platformChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  Future<bool> boot(WidgetTester tester, Size size) async {
    if (!_ffiAvailable()) return false;
    service = _RailHarnessService();
    addTearDown(service.disposeStub);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(service));
    await _settle(tester);
    return true;
  }

  double railWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(_railHostKey)).width;

  // -------------------------------------------------------------------------
  // iPad Pro 11" portrait — 834 x 1194.
  // -------------------------------------------------------------------------
  group('iPad portrait 834x1194', () {
    testWidgets(
      'rail is the 200pt LABELLED sidebar and its items route the right tab index',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(834, 1194))) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        expect(ResponsiveLayout.isTablet(_railContext), isTrue);
        expect(ResponsiveLayout.isTabletPortrait(_railContext), isTrue);
        expect(
          ResponsiveLayout.isCompactRail(_railContext),
          isFalse,
          reason:
              'a tablet is classified as desktop, so it takes the 200pt rail; '
              'the 72pt compact rail is unreachable for tablets',
        );
        expect(
          railWidth(tester),
          200.0,
          reason:
              'the rendered rail must be the wide labelled sidebar, not 72 '
              'and not 0 (bottom nav)',
        );

        // Labelled tier: every item shows its text label and no tooltip.
        expect(
          _itemLabel(UiKeys.sidebarChats),
          findsOneWidget,
          reason: 'the wide rail renders the Chats label inline',
        );
        expect(
          _itemTooltip(UiKeys.sidebarChats),
          findsNothing,
          reason: 'the wide rail must not add the compact-only tooltip',
        );
        expect(_itemLabel(UiKeys.sidebarContacts), findsOneWidget);
        expect(_itemLabel(UiKeys.sidebarApplications), findsOneWidget);
        expect(_itemLabel(UiKeys.sidebarSettings), findsOneWidget);

        // The avatar block also expands to nickname + presence at 200pt.
        expect(
          find.descendant(
            of: find.byKey(UiKeys.sidebarUserAvatar),
            matching: find.text(_nickname),
          ),
          findsOneWidget,
          reason: 'the wide rail shows the nickname next to the avatar',
        );

        // REAL CONTROLS: tap two rail items and check the delivered indices.
        await tester.tap(find.byKey(UiKeys.sidebarContacts));
        await tester.pump();
        await tester.tap(find.byKey(UiKeys.sidebarSettings));
        await tester.pump();

        expect(
          _tappedIndices,
          <int>[1, 3],
          reason:
              'Contacts must deliver index 1 and Settings index 3 to the real '
              'onTap callback HomePage supplies',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // iPad Pro 11" landscape — 1194 x 834. Same device class, rotated.
  // -------------------------------------------------------------------------
  group('iPad landscape 1194x834', () {
    testWidgets('rotation keeps the 200pt labelled rail and working items', (
      WidgetTester tester,
    ) async {
      if (!await boot(tester, const Size(1194, 834))) {
        markTestSkipped('libtim2tox_ffi is not loadable in this environment');
        return;
      }

      expect(ResponsiveLayout.isTabletLandscape(_railContext), isTrue);
      expect(
        railWidth(tester),
        200.0,
        reason:
            'product direction: tablets use the desktop rail in EVERY '
            'orientation',
      );
      expect(_itemLabel(UiKeys.sidebarApplications), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.sidebarApplications));
      await tester.pump();

      expect(
        _tappedIndices,
        <int>[2],
        reason: 'Applications must deliver index 2 in landscape as well',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 7-9" tablet portrait — 768 x 1024. This is the size that looks like it
  // should get the 72pt "tablet" rail the sidebar comments describe; it does
  // not, because isDesktop is true for every tablet.
  // -------------------------------------------------------------------------
  group('small tablet portrait 768x1024', () {
    testWidgets(
      'still the 200pt rail — the 72pt compact rail is NOT reachable on a tablet',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(768, 1024))) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        expect(ResponsiveLayout.isTablet(_railContext), isTrue);
        expect(
          ResponsiveLayout.shouldShowBottomNav(_railContext),
          isFalse,
          reason: 'width 768 >= largePhoneBreakpoint (720) => sidebar tier',
        );
        expect(
          railWidth(tester),
          200.0,
          reason:
              'documents current behaviour: no tablet width produces the 72pt '
              'rail, because isDesktop short-circuits it',
        );
        expect(_itemLabel(UiKeys.sidebarChats), findsOneWidget);

        await tester.tap(find.byKey(UiKeys.sidebarChats));
        await tester.pump();
        expect(_tappedIndices, <int>[0]);
      },
    );
  });

  // -------------------------------------------------------------------------
  // The ONLY tier that reaches the 72pt rail: a landscape large phone.
  // 892 x 412 (Pixel-6-class rotated): shortestSide 412 < 600 so isTablet is
  // false and isDesktop is false (width 892 < 1024), while width 892 >= 720
  // so the bottom nav is replaced by a sidebar. Included here — not in the
  // phone suite — because it is the control case that gives the tablet
  // assertions above their meaning.
  // -------------------------------------------------------------------------
  group('landscape large phone 892x412 (compact-rail control case)', () {
    testWidgets('rail collapses to 72pt, icon-only with tooltips, and still taps', (
      WidgetTester tester,
    ) async {
      if (!await boot(tester, const Size(892, 412))) {
        markTestSkipped('libtim2tox_ffi is not loadable in this environment');
        return;
      }

      expect(
        ResponsiveLayout.isTablet(_railContext),
        isFalse,
        reason: 'shortestSide 412 < mobileBreakpoint (600)',
      );
      expect(
        ResponsiveLayout.isDesktop(_railContext),
        isFalse,
        reason: 'not a desktop OS, not a tablet, and width 892 < 1024',
      );
      expect(ResponsiveLayout.isCompactRail(_railContext), isTrue);
      expect(
        railWidth(tester),
        72.0,
        reason: 'this is the one tier that renders the icon-only rail',
      );

      // Compact tier: labels are gone, tooltips take their place.
      expect(
        _itemLabel(UiKeys.sidebarChats),
        findsNothing,
        reason: 'the 72pt rail has no room for an inline label',
      );
      expect(
        _itemTooltip(UiKeys.sidebarChats),
        findsOneWidget,
        reason: 'the hidden label must stay discoverable as a tooltip',
      );
      expect(_itemLabel(UiKeys.sidebarSettings), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(UiKeys.sidebarUserAvatar),
          matching: find.text(_nickname),
        ),
        findsNothing,
        reason: 'the compact avatar block drops the nickname column',
      );

      // REAL CONTROL: the icon-only item is still a working tab button.
      await tester.tap(find.byKey(UiKeys.sidebarSettings));
      await tester.pump();
      expect(_tappedIndices, <int>[3]);
    });
  });
}
