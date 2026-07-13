// Shared L2 host-bundle harness for the LoginPage-states smokes.
//
// NOT a test file (no `_test.dart` suffix → `flutter test` does not run it
// directly). It backs the three sibling smokes:
//   * login_page_saved_account_test.dart
//   * login_page_theme_test.dart
//   * login_page_locale_test.dart
//
// ── Why one assertion per file (not three tests in one file) ─────────────────
//
// `_TencentCloudChatMaterialAppState` (UIKit fork,
// `tencent_cloud_chat_common/lib/widgets/material_app.dart`) subscribes to the
// process-global `TencentCloudChatTheme` event-bus stream in `initState` but
// NEVER cancels that subscription in `dispose` — a listener leak. With a single
// `testWidgets` per file (the same shape as `app_smoke_test.dart`) it is
// invisible: the State lives for the whole isolate. But pack multiple tests
// into one file and each new `EchoUIKitApp` mount runs
// `_syncUIKitThemeBrightness → TencentCloudChatTheme.init(...)`, which emits a
// theme event that the PRIOR (now-defunct) test's leaked subscriber still
// receives — throwing `setState() called after dispose()` "after the test had
// completed", where it is unconsumable. `flutter test` runs each *file* in its
// own isolate, so one test per file sidesteps the leak entirely without
// touching the UIKit fork.
//
// ── The L2 ceiling (why every smoke lands on LoginPage) ──────────────────────
//
// `StartupSessionUseCase.execute()` returns `StartupShowLogin` *immediately*
// when the GLOBAL nickname (`Prefs.getNickname()` → key `self_nickname`) is
// null/blank — BEFORE any FFI init, `AppBootstrapCoordinator.boot`, or
// `startPolling()`. That early return keeps these smokes deterministic: nothing
// touches the real Tox/DHT network. Reaching HomePage requires a *live
// connection* (with a global nickname set, `execute()` boots + polls and
// returns `StartupWaitForConnection`, then `_StartupGate` blocks on a real
// `connectionStatusStream` event / 20s timeout) — non-deterministic network,
// strictly L3 and out of scope. So every smoke seeds account-list / theme /
// locale state but keeps the global `self_nickname` UNSET. Saved accounts live
// in the `account_list` JSON blob (read by `LoginPage._loadAccountList()`),
// which does NOT populate `self_nickname` and so does NOT trigger boot.
//
// ── Why we drive `EchoUIKitApp` directly (no `main()`) ───────────────────────
//
// Same three reasons as app_smoke_test.dart: `main()` runs
// `AppBootstrap.initialize()` which (1) `dlopen()`s libtim2tox_ffi, (2) touches
// window_manager / tray_manager / notifications, (3) sets the native library
// name for call paths we avoid. We drive the widget directly and reproduce ONLY
// the bootstrap side-effects these smokes depend on:
//   * `Prefs.initialize(prefs)` — the prefs cache.
//   * `AppTheme.initFromPrefs()` + `AppLocale.initFromPrefs()` — normally run by
//     `AppRuntimeBootstrap`. `EchoUIKitApp` reads the resulting `AppTheme.mode`
//     / `AppLocale.locale` ValueNotifiers to pick themeMode and locale, so
//     without these the seeded `theme_mode` / `language_code` prefs never reach
//     the MaterialApp.
//
// All three smokes carry `@Tags(['needs-native'])` and run only via the opt-in
// `.github/workflows/e2e.yml` (label `ci:e2e`), which invokes
// `flutter test integration_test/ -d macos` (a real host binary, so Hive /
// path_provider resolve — see app_smoke_test.dart's header for the full why).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/main.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/util/locale_controller.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/theme_controller.dart';

/// Per-test temp dir + plugin-channel stubs. Returned as a record so teardown
/// can clear the handlers without a stateful helper class. Mirrors
/// `app_smoke_test.dart`'s harness; kept here (not shared with app_smoke) so
/// neither file has to touch the other.
typedef LoginStatesHarness = ({
  Directory root,
  void Function() teardown,
});

Future<LoginStatesHarness> installPluginStubs() async {
  final root = await Directory.systemTemp.createTemp('toxee_login_states_');
  final appSupport = Directory(p.join(root.path, 'app_support'));
  final downloads = Directory(p.join(root.path, 'downloads'));
  final cache = Directory(p.join(root.path, 'cache'));
  final temp = Directory(p.join(root.path, 'temp'));
  for (final d in [appSupport, downloads, cache, temp]) {
    await d.create(recursive: true);
  }

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // path_provider: route every channel call to our temp dirs so any code path
  // that calls `getApplicationDocumentsDirectory()` (e.g. Hive used by
  // TencentCloudChatMaterialApp.cache.init) lands inside the sandbox.
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  messenger.setMockMethodCallHandler(pathProviderChannel,
      (MethodCall call) async {
    switch (call.method) {
      case 'getApplicationSupportDirectory':
      case 'getApplicationDocumentsDirectory':
        return appSupport.path;
      case 'getApplicationCacheDirectory':
        return cache.path;
      case 'getTemporaryDirectory':
        return temp.path;
      case 'getDownloadsDirectory':
        return downloads.path;
      default:
        return null;
    }
  });

  // flutter_secure_storage: not reached on the StartupShowLogin path, but a
  // no-op handler keeps the report clean if a future change touches it.
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  messenger.setMockMethodCallHandler(secureStorageChannel,
      (MethodCall call) async {
    switch (call.method) {
      case 'read':
      case 'readAll':
        return null;
      case 'containsKey':
        return false;
      default:
        return null;
    }
  });

  // audioplayers: FakeUIKit.startWithFfi is NOT called on the LoginPage path
  // (we never reach the runtime coordinator), but stub the channel to defend
  // against transitive touches in the MaterialApp builder.
  const audioplayersChannel = MethodChannel('xyz.luan/audioplayers');
  messenger.setMockMethodCallHandler(
      audioplayersChannel, (MethodCall call) async => null);
  const audioplayersGlobalChannel =
      MethodChannel('xyz.luan/audioplayers.global');
  messenger.setMockMethodCallHandler(
      audioplayersGlobalChannel, (MethodCall call) async => null);

  void teardown() {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
    messenger.setMockMethodCallHandler(audioplayersChannel, null);
    messenger.setMockMethodCallHandler(audioplayersGlobalChannel, null);
  }

  return (root: root, teardown: teardown);
}

/// Seeds [SharedPreferences] with [seed], reinitializes the [Prefs] cache, and
/// re-resolves the theme / locale controllers from those prefs — the minimal
/// slice of `AppRuntimeBootstrap` that `EchoUIKitApp` reads at build time.
///
/// CRITICAL: callers must NOT include `self_nickname` in [seed]; an unset
/// global nickname is what keeps `StartupSessionUseCase` on the deterministic
/// `StartupShowLogin` branch (see this file's header L2-ceiling note).
Future<void> seedPrefsAndControllers(Map<String, Object> seed) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
  await AppTheme.initFromPrefs();
  await AppLocale.initFromPrefs();
}

/// Pump `EchoUIKitApp` and settle to the LoginPage.
///
/// Bounded settle through: TencentCloudChatMaterialApp's _getLocale
/// FutureBuilder (Hive init under the mocked path_provider) → _StartupGate
/// (_runStartup → StartupShowLogin → setState flips _checking) → the
/// `const LoginPage()` build and its initState async loads (_loadAccountList /
/// _loadSettings) → the StaggeredListItem entrance cascade (kicked off by a
/// `Future.delayed`, capped at 150ms on desktop).
///
/// A single `pumpAndSettle` is NOT enough here (found live on the iOS
/// Simulator 2026-07-12, same failure app_smoke_test.dart documents): the
/// startup futures — Hive `cache.init` inside the _getLocale FutureBuilder,
/// then the _StartupGate chain — resolve via real async/microtasks WITHOUT
/// scheduling a frame, so pumpAndSettle "settles" (no frames scheduled) while
/// startup is still in flight and LoginPage never mounts. Pump in a bounded
/// loop that yields to the event loop each step until LoginPage mounts (or the
/// 30s cold-Hive worst case elapses), then settle the page's own entrance
/// animations. Still non-masking: a genuine startup hang never mounts
/// LoginPage and the caller's `find.byType(LoginPage)` assertion fails.
///
/// 100ms steps — NOT a multi-second first arg, which would fast-forward
/// virtual time and silently fire any due startup Timer, masking real
/// cold-start regressions. (Same rationale as app_smoke_test.dart.)
Future<void> pumpToLogin(WidgetTester tester) async {
  await tester.pumpWidget(const EchoUIKitApp());
  var landedLogin = false;
  for (var i = 0; i < 300 && !landedLogin; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    landedLogin = find.byType(LoginPage).evaluate().isNotEmpty;
  }
  if (landedLogin) {
    // Let LoginPage finish its initState async loads + entrance cascade.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
  }
}
