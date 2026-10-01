// Widget tests for [GlobalSettingsSection].
//
// This section appears on both the login-time and post-login settings pages.
// When `toxId == null` (login flow) the per-account notification-sound block
// is hidden, so the section is hermetic with respect to FFI / FfiChatService
// and we can pump it directly.
//
// Covered behaviors:
//   1. Section renders an Appearance card with three theme segments
//      (System / Light / Dark) gated by the `AppTheme.mode` ValueNotifier.
//   2. Selecting brightness stays local until Apply updates and persists it.
//   3. Tapping the language row expands the language list with one entry per
//      supported locale.
//   4. Selecting a non-default language updates `AppLocale.locale`.
//   5. With `toxId == null` the notification-sound block is NOT rendered.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/global_settings_section.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/locale_controller.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/theme_controller.dart';

Future<void> _initPrefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

Widget _harness({String? toxId}) {
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
      body: SingleChildScrollView(
        child: GlobalSettingsSection(colorTheme: null, toxId: toxId),
      ),
    ),
  );
}

Future<void> _pumpSettled(WidgetTester tester, Widget root) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(root);
  // initState awaits Prefs reads; pump twice to flush microtask + setState.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Reset the global notifiers so prior tests don't leak state across cases.
    AppTheme.mode.value = ThemeMode.system;
    AppLocale.locale.value = const Locale('en');
  });

  group('GlobalSettingsSection - appearance segment', () {
    testWidgets('renders Appearance card with three theme segments', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      // System / Light / Dark segment buttons.
      expect(
        find.byIcon(Icons.brightness_auto),
        findsOneWidget,
        reason: 'System (auto) segment exists',
      );
      expect(find.byIcon(Icons.light_mode), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);
    });

    testWidgets('applying Light selection updates AppTheme.mode', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      expect(
        AppTheme.mode.value,
        ThemeMode.system,
        reason: 'Default before user interaction is system mode',
      );

      // Tap the Light icon — SegmentedButton's children are tappable as a
      // whole; targeting the icon is the most stable affordance.
      await tester.tap(find.byIcon(Icons.light_mode));
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings_appearance_apply')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        AppTheme.mode.value,
        ThemeMode.light,
        reason: 'Apply commits through AppTheme.setAppearance',
      );
    });

    testWidgets('applying Dark selection updates AppTheme.mode', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      await tester.tap(find.byIcon(Icons.dark_mode));
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings_appearance_apply')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(AppTheme.mode.value, ThemeMode.dark);
    });
  });

  group('GlobalSettingsSection - language picker', () {
    testWidgets('language row collapsed by default; expand reveals list', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      expect(
        find.byIcon(Icons.expand_more),
        findsWidgets,
        reason: 'Collapsed language row shows expand_more chevron(s) initially',
      );
      // Tap the first expand_more — the language row chevron is the first one
      // in build order (Appearance segment uses fixed icons, not chevrons).
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // After expand we see the radio_button rows for at least the supported
      // languages — English / Simplified Chinese / Traditional Chinese /
      // Japanese / Korean / Arabic = 6 entries.
      expect(
        find.byIcon(Icons.radio_button_checked),
        findsOneWidget,
        reason: 'Exactly one language is currently selected',
      );
      expect(
        find.byIcon(Icons.radio_button_off),
        findsNWidgets(5),
        reason: 'The other five supported languages are deselected radios',
      );
    });

    testWidgets('selecting Japanese updates AppLocale.locale', (tester) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      // Expand language list first.
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Language labels are autonyms in the en arb (e.g. "日本語" for ja, not
      // "Japanese"). Tap the Japanese row by its autonym; this matches what
      // users see and protects against the english-label-for-en assumption.
      await tester.tap(find.text('日本語'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        AppLocale.locale.value.languageCode,
        'ja',
        reason: 'Selecting a language row writes back to AppLocale.locale',
      );
    });
  });

  group('GlobalSettingsSection - notification sound visibility', () {
    testWidgets('when toxId is null the notification-sound row is suppressed', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      // The notification sound row is gated on `toxId != null && isNotEmpty`.
      // We assert by looking for the localized title; the en arb maps the key
      // to "Notification Sound". Absence is the contract.
      expect(
        find.text('Notification Sound'),
        findsNothing,
        reason:
            'Login-time settings hide the per-account notification '
            'sound toggle; this is what makes the section reusable pre-login',
      );
    });

    testWidgets('when toxId is provided the notification-sound row appears', (
      tester,
    ) async {
      const toxId =
          'TESTTESTTESTTESTTESTTESTTESTTESTTESTTESTTESTTESTTESTTESTTESTTEST';
      // Row visibility is gated purely on `widget.toxId != null && isNotEmpty`
      // (global_settings_section.dart) — no Prefs lookup decides whether the row
      // renders. The seeded pref below uses the real scoped-key format
      // (`acct_notification_sound_${toxId[:16]}`) so the row's Switch reflects
      // the persisted value, but the row would appear even without it.
      await _initPrefs({
        'acct_notification_sound_${toxId.substring(0, 16)}': true,
      });
      await _pumpSettled(tester, _harness(toxId: toxId));

      // We tolerate either text — the en arb is the authoritative copy.
      // If the assertion ever fails, the new copy belongs here.
      expect(
        find.text('Notification Sound'),
        findsOneWidget,
        reason:
            'Per-account notification-sound row must surface when a '
            'logged-in toxId is provided',
      );
      expect(
        find.byKey(UiKeys.settingsNotificationSoundSwitch),
        findsOneWidget,
      );
    });

    testWidgets('download limit field and save button expose stable keys', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      expect(find.byKey(UiKeys.settingsDownloadLimitField), findsOneWidget);
      expect(
        find.byKey(UiKeys.settingsDownloadLimitSaveButton),
        findsOneWidget,
      );
    });
  });
}
