// Real-UI L1 WidgetTester coverage for [GlobalSettingsSection].
//
// This is the "drive the REAL section widget, assert the REAL observable"
// companion to global_settings_section_test.dart. Where the sibling file
// proves the rows render, this file proves every interactive control's
// *side effect*:
//   - the notification-sound Switch flips AND persists to Prefs (scoped key);
//   - the download-limit field + Save button persist to Prefs only for valid
//     values, and reject the invalid / boundary inputs (0, 10001, abc);
//   - Apply commits the selected theme segment to AppTheme.mode AND persists
//     via Prefs.getThemeMode();
//   - each language option drives AppLocale.locale AND persists via
//     Prefs.getLocale().
//
// The section is hermetic: it never touches FfiChatService. Appearance commits
// through AppTheme.setAppearance; EchoUIKitApp listens to AppTheme.changes to
// update UIKit. Language still uses applyLocaleEverywhere. Platform haptic
// calls are mocked here so Material controls can run without native plugins.
//
// Mobile parity: every behavior here lives in shared Dart
// (lib/ui/settings/global_settings_section.dart + lib/util/prefs.dart +
// theme/locale controllers) and therefore covers iOS/Android identically.
// The only desktop-only affordance in this section is the downloads-directory
// *picker* button (FilePicker.getDirectoryPath, gated on
// _supportsDirectoryPicker). That picker needs a native plugin and a real
// directory dialog, so it cannot be driven hermetically — see the file-level
// note in the returned report.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const String _toxId =
    'AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555FFFF6666AAAA7777BBBB8888';

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

  // HapticFeedback (and other haptic-emitting Material controls) call
  // SystemChannels.platform; swallow it so it never throws under the binding.
  final List<MethodCall> platformCalls = <MethodCall>[];
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });
  tearDownAll(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  setUp(() {
    platformCalls.clear();
    // These notifiers are process-global; reset before and after each test so
    // leaked state can't poison other suites (or other cases here).
    AppTheme.mode.value = ThemeMode.system;
    AppLocale.locale.value = const Locale('en');
  });
  tearDown(() {
    AppTheme.mode.value = ThemeMode.system;
    AppLocale.locale.value = const Locale('en');
  });

  // ----------------------------------------------------------------------
  // 1. Notification-sound switch: flip the REAL Switch, assert value + Prefs.
  // ----------------------------------------------------------------------
  group('notification-sound switch', () {
    testWidgets('flips the Switch and persists the new value to Prefs', (
      tester,
    ) async {
      // Seed the scoped key true so the row starts ON.
      await _initPrefs({
        'acct_notification_sound_${_toxId.substring(0, 16)}': true,
      });
      await _pumpSettled(tester, _harness(toxId: _toxId));

      final switchFinder = find.byKey(UiKeys.settingsNotificationSoundSwitch);
      expect(switchFinder, findsOneWidget);
      expect(
        tester.widget<Switch>(switchFinder).value,
        isTrue,
        reason: 'Seeded scoped pref is true → Switch renders ON',
      );

      // Flip it OFF by tapping.
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        tester.widget<Switch>(switchFinder).value,
        isFalse,
        reason: 'Tapping the Switch flips its rendered value',
      );
      expect(
        await Prefs.getNotificationSoundEnabled(_toxId),
        isFalse,
        reason: 'The flip wrote the scoped per-account pref',
      );

      // Flip it back ON to prove the round trip both ways.
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      expect(await Prefs.getNotificationSoundEnabled(_toxId), isTrue);
    });

    testWidgets('starts OFF when the scoped pref is seeded false', (
      tester,
    ) async {
      await _initPrefs({
        'acct_notification_sound_${_toxId.substring(0, 16)}': false,
      });
      await _pumpSettled(tester, _harness(toxId: _toxId));

      final switchFinder = find.byKey(UiKeys.settingsNotificationSoundSwitch);
      expect(
        tester.widget<Switch>(switchFinder).value,
        isFalse,
        reason: 'initState loads the seeded false value into the Switch',
      );

      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      expect(await Prefs.getNotificationSoundEnabled(_toxId), isTrue);
    });
  });

  // ----------------------------------------------------------------------
  // 2. Download-limit field + Save: valid persists, invalid/boundary reject.
  // ----------------------------------------------------------------------
  group('download-limit field + save', () {
    Future<void> enterAndSave(WidgetTester tester, String text) async {
      final field = find.byKey(UiKeys.settingsDownloadLimitField);
      await tester.enterText(field, text);
      await tester.pump();
      await tester.tap(find.byKey(UiKeys.settingsDownloadLimitSaveButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('valid value (50) persists to Prefs', (tester) async {
      // Seed a known starting limit so we can prove the change, not a default.
      await _initPrefs({'auto_download_size_limit': 7});
      await _pumpSettled(tester, _harness(toxId: null));

      expect(
        await Prefs.getAutoDownloadSizeLimit(),
        7,
        reason: 'Sanity: starts at the seeded value',
      );

      await enterAndSave(tester, '50');

      expect(
        await Prefs.getAutoDownloadSizeLimit(),
        50,
        reason: 'A valid in-range int is persisted on Save',
      );
    });

    testWidgets('boundary 1 (min valid) persists', (tester) async {
      await _initPrefs({'auto_download_size_limit': 30});
      await _pumpSettled(tester, _harness(toxId: null));

      await enterAndSave(tester, '1');

      expect(
        await Prefs.getAutoDownloadSizeLimit(),
        1,
        reason: 'limit==1 is inside the (0, 10000] accepted range',
      );
    });

    testWidgets('boundary 10000 (max valid) persists', (tester) async {
      await _initPrefs({'auto_download_size_limit': 30});
      await _pumpSettled(tester, _harness(toxId: null));

      await enterAndSave(tester, '10000');

      expect(
        await Prefs.getAutoDownloadSizeLimit(),
        10000,
        reason: 'limit==10000 is the inclusive upper bound',
      );
    });

    testWidgets('invalid 0 is rejected (no Prefs change)', (tester) async {
      await _initPrefs({'auto_download_size_limit': 30});
      await _pumpSettled(tester, _harness(toxId: null));

      await enterAndSave(tester, '0');

      expect(
        await Prefs.getAutoDownloadSizeLimit(),
        30,
        reason: 'limit==0 fails the `> 0` guard; Prefs is untouched',
      );
    });

    testWidgets('invalid 10001 (over max) is rejected (no Prefs change)', (
      tester,
    ) async {
      await _initPrefs({'auto_download_size_limit': 30});
      await _pumpSettled(tester, _harness(toxId: null));

      await enterAndSave(tester, '10001');

      expect(
        await Prefs.getAutoDownloadSizeLimit(),
        30,
        reason: 'limit==10001 fails the `<= 10000` guard; Prefs is untouched',
      );
    });

    testWidgets('non-numeric "abc" is rejected (no Prefs change)', (
      tester,
    ) async {
      await _initPrefs({'auto_download_size_limit': 30});
      await _pumpSettled(tester, _harness(toxId: null));

      await enterAndSave(tester, 'abc');

      expect(
        await Prefs.getAutoDownloadSizeLimit(),
        30,
        reason: 'int.tryParse("abc") is null → save is a no-op',
      );
    });

    testWidgets('Save via onSubmitted (keyboard) also persists a valid value', (
      tester,
    ) async {
      // The field's onSubmitted wires to the same _saveAutoDownloadSizeLimit,
      // so submitting from the keyboard must persist identically to the button.
      await _initPrefs({'auto_download_size_limit': 30});
      await _pumpSettled(tester, _harness(toxId: null));

      final field = find.byKey(UiKeys.settingsDownloadLimitField);
      await tester.enterText(field, '128');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        await Prefs.getAutoDownloadSizeLimit(),
        128,
        reason: 'onSubmitted path shares the same validated save handler',
      );
    });
  });

  // ----------------------------------------------------------------------
  // 3. Theme segments: drive AppTheme.mode AND assert Prefs persistence.
  // ----------------------------------------------------------------------
  group('theme segments', () {
    testWidgets('Light segment → AppTheme.mode.light + Prefs "light"', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      expect(AppTheme.mode.value, ThemeMode.system, reason: 'default');

      await tester.tap(find.byIcon(Icons.light_mode));
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings_appearance_apply')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(AppTheme.mode.value, ThemeMode.light);
      expect(
        await Prefs.getThemeMode(),
        'light',
        reason: 'Apply → AppTheme.setAppearance persists "light"',
      );
    });

    testWidgets('Dark segment → AppTheme.mode.dark + Prefs "dark"', (
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
      expect(await Prefs.getThemeMode(), 'dark');
    });

    testWidgets('System segment (after Dark) → mode.system + Prefs "system"', (
      tester,
    ) async {
      // Start from dark so selecting System is a genuine state change, not a
      // no-op against the default.
      await _initPrefs({'theme_mode': 'dark'});
      AppTheme.mode.value = ThemeMode.dark;
      await _pumpSettled(tester, _harness(toxId: null));

      expect(AppTheme.mode.value, ThemeMode.dark, reason: 'seeded dark');

      await tester.tap(find.byIcon(Icons.brightness_auto));
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings_appearance_apply')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(AppTheme.mode.value, ThemeMode.system);
      expect(await Prefs.getThemeMode(), 'system');
    });
  });

  // ----------------------------------------------------------------------
  // 4. Language selection: drive AppLocale.locale AND assert Prefs.
  // ----------------------------------------------------------------------
  group('language selection', () {
    Future<void> expandLanguageList(WidgetTester tester) async {
      // The language row chevron is the first expand_more in build order
      // (the Appearance segment uses fixed icons, not chevrons).
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    testWidgets('选择 简体中文 → AppLocale zh/Hans + Prefs "zh_Hans"', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      await expandLanguageList(tester);
      await tester.tap(find.text('简体中文'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(AppLocale.locale.value.languageCode, 'zh');
      expect(
        AppLocale.locale.value.scriptCode,
        'Hans',
        reason: 'Simplified Chinese carries the Hans script subtag',
      );
      final persisted = await Prefs.getLocale();
      expect(persisted?.languageCode, 'zh');
      expect(
        persisted?.scriptCode,
        'Hans',
        reason: 'AppLocale.set serializes scriptCode into Prefs (zh_Hans)',
      );
    });

    testWidgets('选择 繁體中文 → AppLocale zh/Hant + Prefs "zh_Hant"', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      await expandLanguageList(tester);
      await tester.tap(find.text('繁體中文'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(AppLocale.locale.value.languageCode, 'zh');
      expect(AppLocale.locale.value.scriptCode, 'Hant');
      final persisted = await Prefs.getLocale();
      expect(persisted?.languageCode, 'zh');
      expect(persisted?.scriptCode, 'Hant');
    });

    testWidgets('选择 日本語 then back to English round-trips locale + Prefs', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      // → Japanese.
      await expandLanguageList(tester);
      await tester.tap(find.text('日本語'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(AppLocale.locale.value.languageCode, 'ja');
      expect((await Prefs.getLocale())?.languageCode, 'ja');

      // Selecting collapses the list; re-expand and pick English.
      await expandLanguageList(tester);
      await tester.tap(find.text('English'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(AppLocale.locale.value.languageCode, 'en');
      expect(
        (await Prefs.getLocale())?.languageCode,
        'en',
        reason: 'Switching back to English persists "en"',
      );
    });

    testWidgets('selecting a language collapses the expanded list', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester, _harness(toxId: null));

      await expandLanguageList(tester);
      // Radios visible while expanded.
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

      await tester.tap(find.text('한국어'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byIcon(Icons.radio_button_checked),
        findsNothing,
        reason: 'selectLocale sets _languageExpanded=false, hiding the radios',
      );
      expect(AppLocale.locale.value.languageCode, 'ko');
    });
  });
}
