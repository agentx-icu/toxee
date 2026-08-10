// L2 host-bundle smoke: a saved account in the real SharedPreferences-backed
// `account_list` renders its card on LoginPage.
//
// `account_list` is a JSON blob in SharedPreferences, decoded by
// `Prefs.getAccountList()` (lib/util/prefs.dart). It is NOT Hive-backed —
// Hive/path_provider matter to the host-bundle harness generally, but the
// account_list source of truth here is SharedPreferences.
//
// One assertion per file by design — see `login_page_states_harness.dart` for
// the full rationale (UIKit theme-listener leak across multiple tests in one
// isolate) and the L2 ceiling (every smoke must keep the global
// `self_nickname` UNSET to stay off the boot/connection path).
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

  testWidgets(
      'saved-account card renders from real SharedPreferences-backed '
      'account_list (global nickname unset)', (WidgetTester tester) async {
    const savedNickname = 'SavedUser';
    // 76-char Tox ID (64-char public key + 8-char nospam + 4-char checksum),
    // the canonical full-address length the UI expects.
    const toxId =
        '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789AB';
    expect(toxId.length, 76, reason: 'sanity: seed a full 76-char Tox address');

    // Seed the `account_list` JSON blob in exactly the shape
    // `Prefs._getAccountListImpl` decodes (a JSON array of String→String maps,
    // toxId the primary key). NO `self_nickname` key — the saved account lives
    // only in account_list, so startup stays on StartupShowLogin.
    await seedPrefsAndControllers(<String, Object>{
      'account_list': '[{"toxId":"$toxId","nickname":"$savedNickname",'
          '"statusMessage":"","autoLogin":"true"}]',
    });

    await pumpToLogin(tester);

    expect(tester.takeException(), isNull,
        reason: 'startup chain must complete without uncaught exceptions');
    expect(find.byType(LoginPage), findsOneWidget,
        reason: 'StartupShowLogin must resolve to a LoginPage render');

    // The saved-accounts header renders only when the list is non-empty, and
    // each card shows `account['nickname']` in a Text widget
    // (lib/ui/login_page.dart ~L903-910). Asserting both proves the real
    // SharedPreferences-backed account_list → LoginPage card pipeline.
    final l10nEn = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10nEn.savedAccounts), findsOneWidget,
        reason:
            'a non-empty account_list must render the saved-accounts header');
    expect(find.text(savedNickname), findsOneWidget,
        reason: 'the seeded account nickname must appear on its login card');
  });
}
