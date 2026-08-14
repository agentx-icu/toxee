// L2 host-bundle smoke: a persisted `language_code: ar` is applied at the app
// level (LoginPage resolves to Arabic and renders a localized string).
//
// One assertion per file by design — see `login_page_states_harness.dart`.
@Tags(['needs-native'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
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

  testWidgets('seeded language_code=ar is applied at the app level', (
    WidgetTester tester,
  ) async {
    // No `self_nickname` — startup stays on StartupShowLogin → LoginPage.
    await seedPrefsAndControllers(<String, Object>{'language_code': 'ar'});

    await pumpToLogin(tester);

    expect(
      tester.takeException(),
      isNull,
      reason: 'startup chain must complete without uncaught exceptions',
    );
    expect(find.byType(LoginPage), findsOneWidget);

    // The seeded pref flows: Prefs → AppLocale.initFromPrefs() →
    // AppLocale.locale (Locale('ar')) → MaterialApp.locale → AppLocalizations
    // resolves Arabic. Assert two ways: the resolved Locale at LoginPage is
    // Arabic, and a localized string actually painted in Arabic (loaded from
    // the delegate so this survives future copy edits).
    //
    // Load the Arabic strings BEFORE the context read so the `await` doesn't
    // straddle a context use (use_build_context_synchronously); the
    // `tester.element` lookup is read inline rather than stashed in a var.
    final l10nAr = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(
      Localizations.localeOf(
        tester.element(find.byType(LoginPage)),
      ).languageCode,
      'ar',
      reason: 'language_code=ar must resolve the app locale to Arabic',
    );
    expect(
      find.text(l10nAr.registerNewAccount),
      findsOneWidget,
      reason: 'LoginPage must render its register CTA in Arabic',
    );
  });
}
