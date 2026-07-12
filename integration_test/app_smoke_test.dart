// End-to-end startup smoke for toxee.
//
// **Why this file is in `integration_test/` (not `test/`):**
// On 2026-05-28 this was briefly moved to `test/startup_smoke_test.dart`
// under codex's RANK 1 advice that "tests using TestWidgetsFlutterBinding +
// mock channels are widget tests, not integration tests, and don't need the
// host bundle". The structure agreed but the practice didn't: when actually
// run via `flutter test` from the `test/` location, the test hangs on
// `TencentCloudChatMaterialApp`'s `_getLocale` FutureBuilder. The future
// inside calls `TencentCloudChat.instance.cache.init(...)` which initializes
// Hive — and Hive in test mode (without the host build supplying real
// platform-channel bindings beyond what we mock) never resolves. The
// FutureBuilder stays in its loading-stub state, no LoginPage builds,
// pumpAndSettle returns successfully because nothing is scheduling more
// frames, and `find.byType(LoginPage)` finds zero widgets. The previous
// "passing" status of this test was a fiction — codex never actually ran
// it (their session stalled on `Downloading Web SDK...`), and the
// `@Tags(['needs-native'])` gate kept it off non-opt-in CI, so the hang
// was invisible.
//
// So: it lives back in `integration_test/` with the `needs-native` tag.
// `flutter test integration_test/` builds a real host binary first, which
// pulls in path_provider / shared_preferences / Hive's native pieces in a
// way that lets the FutureBuilder actually resolve. That build path runs
// only via the opt-in `.github/workflows/e2e.yml` (label `ci:e2e`).
//
// Drives the full `runApp(EchoUIKitApp())` → `_StartupGate._runStartup()` →
// resolved-outcome → first-frame chain. CLAUDE.md flags the hybrid startup
// ordering (binary-replacement + Platform path + FakeUIKit +
// Tim2ToxSdkPlatform install) as the most failure-prone seam in the
// codebase; unit tests cover individual pieces (`test/runtime/`,
// `test/auth/`, `test/sdk_fake/`) but nothing else exercises the full chain.
//
// We deliberately do **not** call `AppBootstrap.initialize()` from `main()`:
//
//   1. `LoggingBootstrap` ends with `Tim2ToxFfi.open()` + `setLogFile(...)`,
//      which requires `libtim2tox_ffi` on `dlopen()` paths. CI build machines
//      don't always have that.
//   2. `AppRuntimeBootstrap` / `DesktopShellBootstrap` touch `window_manager`,
//      `tray_manager`, `flutter_local_notifications` — each one's
//      `MissingPluginException` would pollute the report.
//   3. `setNativeLibraryName('tim2tox_ffi')` (also in `LoggingBootstrap`) is
//      only required by call paths that this smoke deliberately avoids.
//
// Instead we drive `EchoUIKitApp` directly with:
//   * `SharedPreferences.setMockInitialValues({})` — empty prefs.
//   * a mocked `plugins.flutter.io/path_provider` channel pointed at a
//     per-test temp dir (Hive's directory probe).
//   * no-op handlers for `flutter_secure_storage`, `xyz.luan/audioplayers`.
//
// With empty prefs, `StartupSessionUseCase.execute()` returns
// [StartupShowLogin] (nickname is null → first branch). `_StartupGate` flips
// `_checking = false` and the build renders `const LoginPage()`. We assert
// the LoginPage's "Register new account" call-to-action is visible — that's
// the user-observable proof that the startup chain completed without throwing.
//
// Run locally (requires host build — slow):
//   flutter test integration_test/app_smoke_test.dart
//
// To skip on lighter CI:
//   flutter test --exclude-tags=needs-native
@Tags(['needs-native'])
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/main.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';

/// Per-suite temp dir + plugin-channel stubs. Returned as a record so the
/// teardown can clear handlers without a stateful helper class.
typedef _SmokeHarness = ({
  Directory root,
  void Function() teardown,
});

Future<_SmokeHarness> _installPluginStubs() async {
  final root = await Directory.systemTemp.createTemp('toxee_smoke_');
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

  // audioplayers: FakeUIKit.startWithFfi is NOT called in this smoke (we
  // never reach the runtime coordinator), but stub the channel to defend
  // against transitive touches in MaterialApp builder.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SmokeHarness harness;

  setUp(() async {
    harness = await _installPluginStubs();
    // Empty prefs → Prefs.getNickname() returns null → StartupShowLogin.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
  });

  tearDown(() async {
    harness.teardown();
    try {
      await harness.root.delete(recursive: true);
    } catch (_) {
      // Temp cleanup is best-effort; the OS reaps `/tmp` on its own cadence.
    }
  });

  testWidgets('cold start with no profile renders LoginPage without exceptions',
      (WidgetTester tester) async {
    // Drive `EchoUIKitApp` directly (no main() — see file header for why).
    // The pumpWidget renders the app frame; the `_StartupGate` then runs its
    // async startup chain off the main thread, and we wait it out with
    // pumpAndSettle.
    await tester.pumpWidget(const EchoUIKitApp());

    // Pump through the cold-start async chain until the LoginPage render lands:
    //   * TencentCloudChatMaterialApp's FutureBuilder for _getLocale (which
    //     calls Hive.initFlutter under the mocked path_provider)
    //   * _StartupGate.initState() → _runStartup() → StartupShowLogin
    //   * setState that flips _checking = false
    //   * the next build that returns `const LoginPage()`.
    //
    // We CANNOT use a single pumpAndSettle here: on the iOS simulator the startup
    // Futures (session use case / FFI init) resolve via microtasks WITHOUT
    // scheduling a frame, and `_StartupGate`'s `_checking` status view is static —
    // so pumpAndSettle can "settle" (no frames scheduled) while startup is still
    // in flight, before `_checking` flips. Pump in a bounded loop that yields to
    // the event loop each step so those real Futures can progress, until LoginPage
    // mounts (StartupShowLogin) or the 30s cold-Hive worst case elapses. Still
    // non-masking: a genuine startup hang or a wrong-outcome branch never mounts
    // LoginPage and fails the assertion below (we don't touch takeException here,
    // so an escaped startup exception is still surfaced by the check that follows).
    var landedLogin = false;
    for (var i = 0; i < 300 && !landedLogin; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      landedLogin = find.byType(LoginPage).evaluate().isNotEmpty;
    }
    if (landedLogin) {
      // Let the LoginPage finish its own initState async loads before asserting.
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
    }

    // No exception escaped the framework's error handler during the startup
    // chain — this is the headline assertion (CLAUDE.md flags the startup
    // ordering as the most failure-prone seam in the codebase).
    expect(tester.takeException(), isNull,
        reason: 'startup chain must complete without uncaught exceptions');

    // We landed on the LoginPage — the only widget that `_StartupGate.build`
    // returns when the outcome is `StartupShowLogin`. Anything else means the
    // use case took a different branch and the test setup is stale.
    expect(find.byType(LoginPage), findsOneWidget,
        reason: 'StartupShowLogin must resolve to a LoginPage render');

    // Sanity: the localized "Register new account" call-to-action is on
    // screen. This proves AppLocalizations is wired (delegate registered,
    // English fallback resolved) and the LoginPage actually painted past its
    // initState async loads. Load the string from the delegate rather than
    // hard-coding English so a future i18n tweak doesn't break the smoke.
    final String registerLabel =
        (await AppLocalizations.delegate.load(const Locale('en')))
            .registerNewAccount;
    expect(find.text(registerLabel), findsOneWidget,
        reason:
            'LoginPage should render its localized register-new-account CTA');

    // Locate the "Restore from .tox file" card by its ValueKey. This is the
    // canonical pattern AI-driven automation (marionette, mcp_toolkit) uses
    // to target widgets — key lookup is i18n-proof and survives label edits.
    // The key is declared in `lib/ui/testing/ui_keys.dart` as
    // `UiKeys.loginPageRestoreFromToxFile` and wired up in
    // `lib/ui/login_page.dart`. Use it here as a working example so a future
    // smoke that adds keys on the LoginPage form has a precedent.
    expect(find.byKey(UiKeys.loginPageRestoreFromToxFile), findsOneWidget,
        reason:
            'LoginPage should expose the restore-from-tox-file card by key');
  });
}
