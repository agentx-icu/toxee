// Real-UI L1 gate for S105 — Settings: Export-account option chooser.
//
// What this proves (the REAL path, not a `findsOneWidget` smoke):
//   * The PRODUCTION `SettingsPage` Account card renders the real
//     `UiKeys.settingsExportAccountButton`, wired to the real
//     `_showExportOptions`.
//   * Tapping that REAL button opens the REAL chooser surface and renders
//     BOTH real keyed option tiles — `settingsExportProfileToxOption`
//     ("Profile (.tox)") and `settingsExportFullBackupOption`
//     ("Full Backup (.zip)") — plus the "Export Account" chooser title (S105
//     A1 + A3).
//   * Tapping the REAL `.tox` tile runs its real `onTap`
//     (`Navigator.of(ctx).pop('tox')`, settings_page.dart:347): the chooser is
//     DISMISSED (both tiles gone). The exact popped VALUE is `'tox'` (the
//     profile branch, not `'zip'`) — proven by a `NavigatorObserver` that
//     captures the chooser route and reads its pop result. (S105 A2.)
//
// What stays out of scope (S105 owns the CHOOSER only; the save dialog + file
// write are L3, cross-ref S43): the native save panel never fires here. The
// chooser's terminal save step is short-circuited by the in-repo L3
// export-save override seam (`debugSetL3TestSurfaceEnabledForTests` +
// `debugSetExportSaveFileOverridePathForTests`), exactly the seam S43 documents
// for the file-write leg, so `runL3AwareExportSaveFilePicker` returns a fixed
// path before `FilePicker.platform.saveFile` (NSSavePanel on desktop) can run.
//
// Surface: desktop. On the macOS/Windows/Linux test host
// `ResponsiveLayout.isMobile` is `false` regardless of size (it checks
// `Platform.is*` first), so the chooser takes the `showDialog` (Dialog) branch
// — the desktop container. The bottom-sheet (mobile) container renders the SAME
// two keyed tiles via the same `buildOptions`, so A1/A2 hold there too; the
// desktop surface is set large for belt-and-suspenders.
//
// Mobile parity: `_showExportOptions`, both option tiles, and `_exportAccount`
// are shared Dart in `lib/ui/settings/` — only the chooser CONTAINER forks
// (bottom sheet on mobile vs Dialog on desktop), and both render the same two
// keyed tiles, so this gate covers the chooser + 'tox'-pop behavior on both
// platforms. The native save dialog itself is platform-specific (S43 territory)
// and deliberately not driven here.

library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';
import 'package:path/path.dart' as p;

// A 76-hex-char Tox address so account-scoped Prefs / display logic behave like
// a real signed-in account (matches the format `_SidebarHarnessService` uses in
// profile_anchor_keys_test.dart).
const String _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567';

/// Recording stub that satisfies the `FfiChatService` the real `SettingsPage`
/// requires, without booting the native FFI session. Mirrors
/// `_SidebarHarnessService` in `test/ui/profile_anchor_keys_test.dart`:
/// `selfId` / `getSelfToxId` resolve to a stable Tox ID so `accountKey`
/// (the export's `widget.service.accountKey`) is non-empty, and the streams /
/// profile mutations are no-ops.
class _ExportHarnessService extends FfiChatService {
  _ExportHarnessService() : super();

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

Widget _app(Widget child) {
  return MaterialApp(
    // The fork chat widgets + the app pages read both delegate families at
    // build; omit any and the page throws on first localization lookup.
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

/// Bounded settle: the real `SettingsPage` runs several `initState` Prefs reads
/// and a `StaggeredListItem` entrance animation. `pumpAndSettle` is unsafe here
/// (the settings tree contains perpetual-ish async/animated descendants), so we
/// pump a fixed budget — long enough to flush the Prefs microtasks + the
/// stagger — without waiting for a settled tree.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<SettingsPage> _pumpSettingsPage(
  WidgetTester tester,
  FfiChatService service,
) async {
  final page = SettingsPage(
    service: service,
    connectionStatusStream: service.connectionStatusStream,
    autoAcceptFriends: false,
    onAutoAcceptFriendsChanged: (_) {},
    autoAcceptGroupInvites: false,
    onAutoAcceptGroupInvitesChanged: (_) {},
  );
  await tester.pumpWidget(_app(page));
  await _settle(tester);
  return page;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  // `flutter/platform` swallows haptics/clipboard system calls; `path_provider`
  // feeds the temp dirs the settings/account code reads.
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  // file_picker's method channel. On desktop `saveFile` bypasses this channel
  // and calls NSSavePanel directly, which is why the L3 override (below) — not
  // this mock — is what actually prevents the native picker. We still install a
  // null handler so any incidental file_picker channel call is inert.
  const filePickerChannel = MethodChannel(
    'miguelruivo.flutter.plugins.filepicker',
  );
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'settings_export_chooser_test_',
    );
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      platformChannel,
      (MethodCall call) async => null,
    );
    messenger.setMockMethodCallHandler(filePickerChannel, (
      MethodCall call,
    ) async => null);
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
    // Seed a current account so the Account card renders its body (the export
    // button is gated behind `_currentNickname != null`, settings_page_build
    // .dart:40) and `accountKey` resolves.
    await Prefs.setCurrentAccountToxId(_toxId);
    await Prefs.setNickname('Export Nick');
    await Prefs.setStatusMessage('Export Status');
    await Prefs.addAccount(toxId: _toxId, nickname: 'Export Nick');
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(filePickerChannel, null);
    // Always clear the L3 export-save override + surface flag so it can't leak
    // into other tests.
    debugResetL3FilePickerOverridesForTests();
    debugSetL3TestSurfaceEnabledForTests(null);
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'S105-A1/A3: real export button opens chooser with both keyed tiles',
    (WidgetTester tester) async {
      final service = _ExportHarnessService();
      addTearDown(service.disposeStub);

      // Desktop surface so the chooser renders as a centered Dialog (the
      // `showDialog` branch). On the desktop test host this branch is taken
      // regardless, but the size keeps the gate honest for the web fallback.
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettingsPage(tester, service);

      // The REAL export button (settings_page_build.dart:168) must be present
      // and the chooser must NOT be open yet.
      expect(find.byKey(UiKeys.settingsExportAccountButton), findsOneWidget);
      expect(find.byKey(UiKeys.settingsExportProfileToxOption), findsNothing);
      expect(find.byKey(UiKeys.settingsExportFullBackupOption), findsNothing);
      // Baseline "Export Account" count BEFORE opening (the button label) so the
      // A3 chooser-title assertion below is a non-vacuous delta, not a bare
      // findsWidgets the button label alone would satisfy.
      final exportAccountBefore = find.text('Export Account').evaluate().length;

      // Drive the REAL interaction: tap the production button → its real
      // `onPressed: _showExportOptions` opens the real chooser.
      await tester.ensureVisible(find.byKey(UiKeys.settingsExportAccountButton));
      await tester.pump();
      await tester.tap(find.byKey(UiKeys.settingsExportAccountButton));
      await _settle(tester);

      // A1: BOTH real keyed option tiles render (the `.zip` tile is asserted
      // PRESENT here even though we only drive the `.tox` tile in A2).
      expect(
        find.byKey(UiKeys.settingsExportProfileToxOption),
        findsOneWidget,
        reason: 'Profile (.tox) chooser tile must render',
      );
      expect(
        find.byKey(UiKeys.settingsExportFullBackupOption),
        findsOneWidget,
        reason: 'Full Backup (.zip) chooser tile must render',
      );
      // Both are tappable ListTiles wired to a non-null onTap (the pop).
      final toxTile = tester.widget<ListTile>(
        find.byKey(UiKeys.settingsExportProfileToxOption),
      );
      final zipTile = tester.widget<ListTile>(
        find.byKey(UiKeys.settingsExportFullBackupOption),
      );
      expect(toxTile.onTap, isNotNull);
      expect(zipTile.onTap, isNotNull);

      // A1 labels (unique to the chooser tiles).
      expect(find.text('Profile (.tox)'), findsOneWidget);
      expect(find.text('Full Backup (.zip)'), findsOneWidget);
      // A3: the chooser added its own "Export Account" title — strictly MORE
      // occurrences than the pre-open baseline (the button label alone would not
      // increase the count). settings_page.dart:335.
      expect(
        find.text('Export Account').evaluate().length,
        greaterThan(exportAccountBefore),
        reason: 'A3: opening the chooser must surface the "Export Account" title',
      );
    },
  );

  testWidgets(
    'S105-A2: tapping the real .tox tile dismisses the chooser (native picker '
    "bypassed; the exact 'tox' pop value is asserted by the observer test below)",
    (WidgetTester tester) async {
      // Arm the in-repo L3 export-save override so that IF the `'tox'` pop
      // routes into `_exportAccount` and reaches the save step, the native
      // NSSavePanel is short-circuited (override returns a fixed path before
      // `FilePicker.platform.saveFile` runs). This is the same seam S43 uses
      // for the file-write leg.
      debugSetL3TestSurfaceEnabledForTests(true);
      final overridePath = p.join(tempRoot.path, 'export_probe.tox');
      debugSetExportSaveFileOverridePathForTests(overridePath);

      final service = _ExportHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettingsPage(tester, service);

      // Open the real chooser.
      await tester.ensureVisible(find.byKey(UiKeys.settingsExportAccountButton));
      await tester.pump();
      await tester.tap(find.byKey(UiKeys.settingsExportAccountButton));
      await _settle(tester);
      expect(find.byKey(UiKeys.settingsExportProfileToxOption), findsOneWidget);
      expect(find.byKey(UiKeys.settingsExportFullBackupOption), findsOneWidget);

      // Drive the REAL `.tox` tile: its production onTap is
      // `Navigator.of(ctx).pop('tox')` (settings_page.dart:347).
      await tester.tap(find.byKey(UiKeys.settingsExportProfileToxOption));
      await _settle(tester);

      // A2: the chooser is DISMISSED — both option tiles gone — which happens
      // when the real tile onTap ran `Navigator.pop(...)` and
      // `_showExportOptions`'s `await` returned. (That the popped VALUE is
      // exactly 'tox' — i.e. the profile-export branch, not 'zip' — is asserted
      // by the NavigatorObserver test below, which reads the route's pop result.)
      expect(
        find.byKey(UiKeys.settingsExportProfileToxOption),
        findsNothing,
        reason: 'Profile (.tox) tile gone → real pop ran',
      );
      expect(
        find.byKey(UiKeys.settingsExportFullBackupOption),
        findsNothing,
        reason: 'Full Backup (.zip) tile gone → chooser dismissed',
      );

      // The native save panel never blocked the test: the L3 override is armed,
      // so any save step (had `_exportAccount` proceeded) would be short-circuited
      // instead of opening NSSavePanel. This asserts the bypass seam is in place
      // (it does NOT by itself prove `_exportAccount` ran — that file-write leg is
      // L3 / S43; this gate owns the chooser surface only).
      expect(
        debugCurrentExportSaveFileOverridePath,
        overridePath,
        reason: 'L3 export-save override stayed armed (native picker bypassed)',
      );
    },
  );

  testWidgets(
    "S105-A2 (direct): the real chooser route pops exactly 'tox'",
    (WidgetTester tester) async {
      // This captures the pop VALUE directly. The chooser is a real route in
      // OUR Navigator; when the production `.tox` tile's onTap runs
      // `Navigator.of(ctx).pop('tox')` (settings_page.dart:347), that route's
      // `popped` future completes with the value passed to pop. We grab the
      // chooser route on `didPush` and read its `popped` result — the exact
      // value the real chooser routes back into `_showExportOptions`.
      final service = _ExportHarnessService();
      addTearDown(service.disposeStub);

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Suppress the post-pop native save step (we only care about the routed
      // value, not the file write).
      debugSetL3TestSurfaceEnabledForTests(true);
      debugSetExportSaveFileOverridePathForTests(
        p.join(tempRoot.path, 'direct_probe.tox'),
      );

      Object? choiceResult;
      var sawChoiceResult = false;
      final observer = _ChooserResultObserver(
        // The chooser is the route pushed AFTER the home route (a popup/dialog
        // route, not a PageRoute). Capture its result.
        onRouteResult: (value) {
          sawChoiceResult = true;
          choiceResult = value;
        },
      );

      final page = SettingsPage(
        service: service,
        connectionStatusStream: service.connectionStatusStream,
        autoAcceptFriends: false,
        onAutoAcceptFriendsChanged: (_) {},
        autoAcceptGroupInvites: false,
        onAutoAcceptGroupInvitesChanged: (_) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            TencentCloudChatLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          navigatorObservers: [observer],
          home: Scaffold(body: page),
        ),
      );
      await _settle(tester);

      await tester.ensureVisible(find.byKey(UiKeys.settingsExportAccountButton));
      await tester.pump();
      await tester.tap(find.byKey(UiKeys.settingsExportAccountButton));
      await _settle(tester);
      expect(find.byKey(UiKeys.settingsExportProfileToxOption), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.settingsExportProfileToxOption));
      await _settle(tester);

      // The chooser route's `popped` future resolved to 'tox'.
      expect(
        sawChoiceResult,
        isTrue,
        reason: 'chooser route was pushed and later popped',
      );
      expect(
        choiceResult,
        'tox',
        reason: "real .tox tile routes Navigator.pop('tox')",
      );
    },
  );
}

/// Observer that, for every dialog/popup route pushed (anything that is not the
/// initial home PageRoute), attaches to the route's public `popped` future and
/// reports the value it completes with. We use the FIRST such route — in this
/// test that is the export chooser dialog opened by `_showExportOptions`.
class _ChooserResultObserver extends NavigatorObserver {
  _ChooserResultObserver({required this.onRouteResult});

  final void Function(Object? value) onRouteResult;
  bool _captured = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Skip the initial home route (it has no previousRoute); capture the first
    // route pushed ON TOP of an existing route — the export chooser.
    if (!_captured && previousRoute != null) {
      _captured = true;
      // `popped` completes with the value passed to Navigator.pop(result).
      unawaited(route.popped.then((value) => onRouteResult(value)));
    }
    super.didPush(route, previousRoute);
  }
}
