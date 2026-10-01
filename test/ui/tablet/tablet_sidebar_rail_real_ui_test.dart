// Real-UI gates for the navigation rail on the TABLET form factor.
//
// Intermediate tablet windows (<1100 logical pixels) use a 72px compact rail
// with tooltips. Wider windows keep the 200px labelled rail. These tests drive
// the real sidebar tab controls in both forms, preserving their destinations.
// The host Row mirrors HomePage so width measurements reflect actual layout.
// FFI availability is checked because the sidebar's profile UI uses the native
// service; unavailable native libraries are reported as skipped tests.
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
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
      'rail is compact with tooltips and its items route the right tab index',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(834, 1194))) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        expect(ResponsiveLayout.isTablet(_railContext), isTrue);
        expect(ResponsiveLayout.isTabletPortrait(_railContext), isTrue);
        expect(ResponsiveLayout.isCompactRail(_railContext), isTrue);
        expect(railWidth(tester), 72.0);
        for (final key in [
          UiKeys.sidebarChats,
          UiKeys.sidebarContacts,
          UiKeys.sidebarApplications,
          UiKeys.sidebarSettings,
        ]) {
          expect(_itemLabel(key), findsNothing);
          expect(_itemTooltip(key), findsOneWidget);
        }
        expect(
          find.descendant(
            of: find.byKey(UiKeys.sidebarUserAvatar),
            matching: find.text(_nickname),
          ),
          findsNothing,
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
        reason: 'wide tablet landscape has room for navigation labels',
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
  // Smaller tablet windows also use compact navigation.
  // -------------------------------------------------------------------------
  group('small tablet portrait 768x1024', () {
    testWidgets(
      'small tablet uses compact tooltips and working chat navigation',
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
        expect(railWidth(tester), 72.0);
        expect(_itemLabel(UiKeys.sidebarChats), findsNothing);
        expect(_itemTooltip(UiKeys.sidebarChats), findsOneWidget);

        await tester.tap(find.byKey(UiKeys.sidebarChats));
        await tester.pump();
        expect(_tappedIndices, <int>[0]);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Landscape phones retain the same compact navigation.
  // -------------------------------------------------------------------------
  group('landscape large phone 892x412 (compact-rail control case)', () {
    testWidgets(
      'rail collapses to 72pt, icon-only with tooltips, and still taps',
      (WidgetTester tester) async {
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
          reason: 'landscape phones keep the icon-only rail',
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
      },
    );
  });
}
