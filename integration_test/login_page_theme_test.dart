// L2 host-bundle smoke: a persisted `theme_mode: dark` is applied at the app
// level (LoginPage renders under a dark Theme).
//
// One `testWidgets` per file by design — see `login_page_states_harness.dart`.
@Tags(['needs-native'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tencent_cloud_chat_common/widgets/material_app.dart';
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
      // Temp cleanup is best-effort; the OS reaps `/tmp` on its own cadence.
    }
  });

  testWidgets('seeded theme_mode=dark is applied at the app level',
      (WidgetTester tester) async {
    // No `self_nickname` — startup stays on StartupShowLogin → LoginPage.
    await seedPrefsAndControllers(<String, Object>{
      'theme_mode': 'dark',
    });

    await pumpToLogin(tester);

    expect(tester.takeException(), isNull,
        reason: 'startup chain must complete without uncaught exceptions');
    expect(find.byType(LoginPage), findsOneWidget);

    // The seeded pref flows: Prefs → AppTheme.initFromPrefs() →
    // AppTheme.mode (ThemeMode.dark) → root app's ValueListenableBuilder →
    // TencentCloudChatMaterialApp.themeMode → effective dark Theme.
    //
    // PRIMARY assertion — the deterministic source of truth. `AppTheme.mode`
    // is driven solely by `AppTheme.initFromPrefs()` reading the seeded pref;
    // it does NOT consult system brightness. A regression where the seeded
    // pref stops driving the theme leaves this at the tearDown/default
    // `ThemeMode.system`, so this fails even on a dark-mode host runner (where
    // the brightness check below would otherwise pass for the wrong reason).
    expect(AppTheme.mode.value, ThemeMode.dark,
        reason: 'seeded theme_mode=dark must drive AppTheme.mode, '
            'independent of host system brightness');

    // PRIMARY assertion — the root MaterialApp must receive ThemeMode.dark.
    // Confirms AppTheme.mode actually flows through to the widget tree rather
    // than only the notifier holding the right value.
    final TencentCloudChatMaterialApp app = tester.widget(
        find.byType(TencentCloudChatMaterialApp));
    expect(app.themeMode, ThemeMode.dark,
        reason: 'root TencentCloudChatMaterialApp must adopt ThemeMode.dark '
            'from the seeded pref');

    // SECONDARY assertion — the effective Theme at the LoginPage subtree is
    // dark. Robust to how the dark ThemeData is constructed, but on its own it
    // could pass spuriously on a dark-mode host (ThemeMode.system + dark OS),
    // which is why the two assertions above are the real gate.
    // `tester.element` is read inline (not stashed across an await) to keep
    // clear of use_build_context_synchronously.
    final Brightness brightness =
        Theme.of(tester.element(find.byType(LoginPage))).brightness;
    expect(brightness, Brightness.dark,
        reason: 'theme_mode=dark must resolve to a dark Theme at LoginPage');
  });
}
