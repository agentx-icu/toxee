// Real-UI gates for how the self-profile is PRESENTED on the tablet form
// factor, including the orientation split that only tablets can produce.
//
// What is under test
// ------------------
// `showSelfProfile` (`lib/ui/settings/sidebar.dart:57-200`) forks twice:
//
//   1. `if (ResponsiveLayout.shouldShowBottomNav(context))` -> push a
//      fullscreen `MaterialPageRoute` with a `Scaffold`+`AppBar` whose leading
//      close button carries `UiKeys.profileCloseButton` (sidebar.dart:126-153).
//      Otherwise -> `showDialog` of an `AppDialog` (sidebar.dart:155-199).
//      `shouldShowBottomNav` is width-driven (`width < 720`), so a 7-inch
//      tablet in PORTRAIT takes the route path while the very same device in
//      landscape takes the dialog path.
//
//   2. Inside the dialog branch: `isWide = size.width > 900` picks an 880pt
//      two-column dialog over a 500pt single-column one. On an iPad this flips
//      purely on rotation — 834pt portrait is narrow, 1194pt landscape is wide.
//
// Both forks are pure layout policy that no unit test can reach from the test
// host without `ResponsiveLayout.debugIsDesktopPlatformOverride`, because
// `shouldShowBottomNav` is width-only but the surrounding tier assertions
// (`isTablet`, `isTabletPortrait`) short-circuit to false on a desktop host.
//
// Real controls driven here
// -------------------------
//   * `UiKeys.sidebarUserAvatar` — the production `InkWell` in the real
//     `buildSidebar`; tapping it runs `_openProfile` -> `showSelfProfile`.
//     Used at the two iPad sizes, where production really does show a rail.
//   * `UiKeys.profileCloseButton` — the real `AppBar` leading close button of
//     the fullscreen route; tapping it must unmount the profile.
//
// For the sub-720 tablet case the harness calls `showSelfProfile` directly
// from a button instead of the rail: at that width production shows the bottom
// nav (no rail at all) and reaches the very same function from the Settings
// page (`lib/ui/settings/settings_page.dart:1418`). Driving the shared
// production entry keeps the boundary comparison honest — the only variable
// between the 719 and 720 cases is the viewport.
//
// Harness notes
// -------------
//   * `pumpAndSettle()` is avoided: `ProfileQrSection` holds a perpetual
//     `CircularProgressIndicator`. A fixed 8x100ms pump is used, matching
//     `test/ui/profile_open_and_edit_toggle_real_ui_test.dart`.
//   * Mobile parity: `sidebar.dart` is shared Dart; the route-vs-dialog fork
//     asserted here is exactly the fork iOS/Android phones take, so these
//     cases also pin the phone presentation contract from the tablet side.
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
import 'package:toxee/ui/widgets/app_dialog.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/responsive_layout.dart';

const String _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567';
const String _nickname = 'TabletProfileNick';
const String _statusMessage = 'TabletProfileStatus';

class _ProfileHarnessService extends FfiChatService {
  _ProfileHarnessService() : super();

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

late BuildContext _harnessContext;

Widget _app(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

/// The real rail, as the iPad actually renders it.
Widget _railHarness(_ProfileHarnessService service) {
  return _app(
    Builder(
      builder: (ctx) {
        _harnessContext = ctx;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: ResponsiveLayout.responsiveSidebarWidth(ctx),
              child: buildSidebar(
                context: ctx,
                selectedIndex: 0,
                onTap: (_) {},
                service: service,
                connectionStatusStream: service.connectionStatusStream,
              ),
            ),
            const Expanded(child: SizedBox.shrink()),
          ],
        );
      },
    ),
  );
}

/// Direct entry into the same production function, for widths where the rail
/// is not on screen.
Widget _entryButtonHarness(_ProfileHarnessService service) {
  return _app(
    Builder(
      builder: (ctx) {
        _harnessContext = ctx;
        return Center(
          child: ElevatedButton(
            onPressed: () => showSelfProfile(
              ctx,
              service,
              service.connectionStatusStream,
              nickName: _nickname,
              statusMessage: _statusMessage,
            ),
            child: const Text('open profile'),
          ),
        );
      },
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late Directory tempRoot;
  late _ProfileHarnessService service;

  const MethodChannel platformChannel = MethodChannel(
    'flutter/platform',
    JSONMethodCodec(),
  );
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  setUp(() async {
    ResponsiveLayout.debugIsDesktopPlatformOverride = () => false;

    tempRoot = await Directory.systemTemp.createTemp(
      'tablet_profile_presentation_real_ui_test_',
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
    await Prefs.addAccount(
      toxId: _toxId,
      nickname: _nickname,
      statusMessage: _statusMessage,
    );
    await Prefs.setCurrentAccountToxId(_toxId);
    await Prefs.setNickname(_nickname);
    await Prefs.setStatusMessage(_statusMessage);
  });

  tearDown(() {
    ResponsiveLayout.debugIsDesktopPlatformOverride = null;
    messenger.setMockMethodCallHandler(platformChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  /// Builds the stub service (which dlopens `libtim2tox_ffi` in
  /// `FfiChatService`'s constructor) and pumps [harnessBuilder] at [size].
  /// Returns false — WITHOUT constructing the service — when the native
  /// library is unavailable, so the caller can report a real skip.
  Future<bool> boot(
    WidgetTester tester,
    Size size,
    Widget Function(_ProfileHarnessService) harnessBuilder,
  ) async {
    if (!_ffiAvailable()) return false;
    service = _ProfileHarnessService();
    addTearDown(service.disposeStub);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harnessBuilder(service));
    await _settle(tester);
    return true;
  }

  // -------------------------------------------------------------------------
  // iPad Pro 11" — the same device, two orientations, two dialog widths.
  // -------------------------------------------------------------------------
  group('iPad rotation changes the self-profile dialog width', () {
    testWidgets(
      'portrait 834x1194: avatar tap opens the NARROW (500pt) profile dialog',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(834, 1194), _railHarness)) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        expect(ResponsiveLayout.isTabletPortrait(_harnessContext), isTrue);
        expect(
          find.byType(AppDialog),
          findsNothing,
          reason: 'pre-condition: no profile is open before the tap',
        );

        // REAL CONTROL: the production avatar InkWell.
        await tester.tap(find.byKey(UiKeys.sidebarUserAvatar));
        await _settle(tester);

        expect(
          find.byType(AppDialog),
          findsOneWidget,
          reason:
              'width 834 >= 720 => shouldShowBottomNav is false => the dialog '
              'branch, not the fullscreen route',
        );
        expect(
          find.byType(AppBar),
          findsNothing,
          reason: 'the fullscreen-route branch (its AppBar) must NOT be taken',
        );

        // isWide == (834 > 900) == false -> (834-32).clamp(280, 500) == 500
        final AppDialog dialog = tester.widget<AppDialog>(
          find.byType(AppDialog),
        );
        expect(
          dialog.maxWidth,
          500.0,
          reason:
              'portrait iPad is below the 900pt two-column threshold, so the '
              'profile stays single-column at 500pt',
        );
        // maxHCap = (1194*0.9).clamp(400,1200) = 1074.6
        // maxH    = (1194-100).clamp(400, 1074.6) = 1074.6
        expect(
          dialog.maxHeight,
          closeTo(1074.6, 0.01),
          reason:
              'the tall-tablet height cap must follow 90% of the viewport '
              '(the fix that stopped clipping the QR action row on iPad)',
        );

        // The real ProfilePage mounted with the resolved Tox ID.
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(UiKeys.profileToxIdSelectableText),
              )
              .data,
          _toxId,
          reason: 'the opened profile must show the resolved account Tox ID',
        );
      },
    );

    testWidgets(
      'landscape 1194x834: avatar tap opens the WIDE (880pt) profile dialog',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(1194, 834), _railHarness)) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        expect(ResponsiveLayout.isTabletLandscape(_harnessContext), isTrue);

        await tester.tap(find.byKey(UiKeys.sidebarUserAvatar));
        await _settle(tester);

        final AppDialog dialog = tester.widget<AppDialog>(
          find.byType(AppDialog),
        );
        // isWide == (1194 > 900) == true -> (1194-32).clamp(280, 880) == 880
        expect(
          dialog.maxWidth,
          880.0,
          reason:
              'rotating the SAME tablet past 900pt must switch the profile to '
              'the wide two-column dialog',
        );
        // maxHCap = (834*0.9).clamp(400,1200) = 750.6
        // maxH    = (834-100).clamp(400, 750.6) = 734
        expect(dialog.maxHeight, closeTo(734.0, 0.01));
      },
    );
  });

  // -------------------------------------------------------------------------
  // Boundary: largePhoneBreakpoint == 720 on WIDTH, evaluated on a tablet-class
  // device so only the width changes. This is the edge that decides
  // fullscreen-route vs dialog for the whole app.
  // -------------------------------------------------------------------------
  group('bottom-nav/sidebar boundary at width 720', () {
    testWidgets(
      '719x1000 tablet: profile opens as the FULLSCREEN ROUTE and its close button dismisses it',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(719, 1000), _entryButtonHarness)) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        expect(
          ResponsiveLayout.isTablet(_harnessContext),
          isTrue,
          reason: 'shortestSide 719 is still inside the tablet tier',
        );
        expect(
          ResponsiveLayout.shouldShowBottomNav(_harnessContext),
          isTrue,
          reason: 'one pixel below 720 the app is still bottom-nav driven',
        );

        await tester.tap(find.text('open profile'));
        await _settle(tester);

        expect(
          find.byType(AppBar),
          findsOneWidget,
          reason:
              'below 720 the profile is pushed as a fullscreen route with an '
              'AppBar, not shown as a dialog',
        );
        expect(
          find.byType(AppDialog),
          findsNothing,
          reason: 'the dialog branch must NOT be taken below 720',
        );
        expect(find.byKey(UiKeys.profileCloseButton), findsOneWidget);

        // REAL CONTROL: the AppBar leading close button pops the route.
        await tester.tap(find.byKey(UiKeys.profileCloseButton));
        await _settle(tester);

        expect(
          find.byType(AppBar),
          findsNothing,
          reason: 'tapping close must unmount the pushed profile route',
        );
        expect(
          find.byKey(UiKeys.profileToxIdSelectableText),
          findsNothing,
          reason: 'the profile content must be gone after the dismiss',
        );
      },
    );

    testWidgets(
      '720x1000 tablet: one pixel wider flips the SAME entry to the dialog branch',
      (WidgetTester tester) async {
        if (!await boot(tester, const Size(720, 1000), _entryButtonHarness)) {
          markTestSkipped('libtim2tox_ffi is not loadable in this environment');
          return;
        }

        expect(
          ResponsiveLayout.shouldShowBottomNav(_harnessContext),
          isFalse,
          reason: 'the sidebar tier is inclusive at exactly 720',
        );

        await tester.tap(find.text('open profile'));
        await _settle(tester);

        expect(
          find.byType(AppDialog),
          findsOneWidget,
          reason: 'at exactly 720 the profile becomes a dialog',
        );
        expect(find.byType(AppBar), findsNothing);
        // isWide == (720 > 900) == false -> (720-32).clamp(280, 500) == 500
        expect(
          tester.widget<AppDialog>(find.byType(AppDialog)).maxWidth,
          500.0,
        );
      },
    );
  });
}
