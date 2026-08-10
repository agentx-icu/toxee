// L2 host-bundle regression for the UIKit-fork MaterialApp theme-listener leak.
//
// Bug (fixed in
// third_party/chat-uikit-flutter/tencent_cloud_chat_common/lib/widgets/material_app.dart):
// `_TencentCloudChatMaterialAppState` subscribed to the global
// `TencentCloudChatTheme` event bus in `initState` but DISCARDED the
// `StreamSubscription` and had no `dispose()`. The event bus outlives the
// widget, so after the State was disposed its `_themeDataChangeCallback` still
// fired and called `setState()` on an unmounted State. In a shared test
// isolate this surfaced when a SECOND app mounted and ran
// `TencentCloudChatTheme.init` (during `_getLocale → cache.init`): the init
// event was delivered to the FIRST, already-disposed subscriber →
// "setState() called after dispose()" reported after the prior test completed.
// That leak is exactly why the other L2 smokes are one-test-per-file.
//
// The fix retains the subscription, cancels it in a new `dispose()`, and guards
// the callback with `mounted`.
//
// This regression reproduces the leak within a SINGLE test: mount the app
// (subscribes a `_TencentCloudChatMaterialAppState` to the bus) → dispose it by
// pumping a bare widget → RE-mount the app, which re-fires a
// `TencentCloudChatTheme` event on the global bus (from
// `EchoUIKitApp.initState`'s `_syncUIKitThemeBrightness`, main.dart:~223, and
// again via `TencentCloudChatTheme.init` during `_getLocale → cache.init`).
// Pre-fix, the
// first, now-disposed subscriber received that event and called `setState()`
// on an unmounted State; the framework surfaces it via `takeException()`. With
// the fix the first subscription was cancelled on dispose, so the re-mount is
// clean.
//
// One `testWidgets` (not two): this host-bundle file uses
// IntegrationTestWidgetsFlutterBinding so its result is reported through the
// integration-test device protocol; mount→dispose→remount remains one complete
// regression sequence.
@Tags(['needs-native'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:toxee/ui/login_page.dart';
import 'package:toxee/util/locale_controller.dart';
import 'package:toxee/util/theme_controller.dart';

import 'login_page_states_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LoginStatesHarness harness;

  setUp(() async {
    harness = await installPluginStubs();
  });

  tearDown(() async {
    harness.teardown();
    AppTheme.mode.value = ThemeMode.system;
    AppLocale.locale.value = const Locale('en');
    try {
      await harness.root.delete(recursive: true);
    } catch (_) {
      // Best-effort temp cleanup.
    }
  });

  testWidgets(
      're-mounting the app does not trip the prior (disposed) MaterialApp '
      'theme listener', (WidgetTester tester) async {
    await seedPrefsAndControllers(<String, Object>{});

    // Mount #1 — subscribes to the global TencentCloudChatTheme event bus.
    await pumpToLogin(tester);
    expect(find.byType(LoginPage), findsOneWidget,
        reason: 'sanity: first mount reaches LoginPage');

    // Dispose mount #1 (its State.dispose runs → with the fix, cancels the
    // theme subscription).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // Mount #2 — its TencentCloudChatTheme.init fires the theme event. Pre-fix,
    // mount #1's leaked subscriber received it and called setState() after
    // dispose; the fix makes this a no-op.
    await pumpToLogin(tester);
    expect(find.byType(LoginPage), findsOneWidget,
        reason: 'second mount reaches LoginPage');

    expect(tester.takeException(), isNull,
        reason: 'a disposed MaterialApp theme listener must not call setState '
            'when a later app mount re-inits the theme (the leak this fix '
            'closes)');
  });
}
