// L1 lock test for locale/language persistence (scenario S38 — language switch).
//
// Pure Dart + SharedPreferences. No FfiChatService, no FFI, no dylib.
// Verifies the contract between [Prefs] (storage) and [AppLocale] (controller):
//
//   * Prefs round-trips every supported language code, including the
//     scriptCode-qualified zh variants (zh_Hans / zh_Hant).
//   * AppLocale.set() persists through Prefs, and a "cold restart"
//     (AppLocale.initFromPrefs after resetting the in-memory notifier)
//     reflects the persisted value rather than the system default.
//   * AppLocale.initFromPrefs() with no stored value follows the system
//     locale resolution rather than blindly persisting a default.
//
// AppLocale (the controller under test):
//   lib/util/locale_controller.dart
//     - AppLocale.locale            : ValueNotifier<Locale> (line 7)
//     - AppLocale.initFromPrefs()   : load persisted/ system locale (line 9)
//     - AppLocale.set(Locale)       : update notifier + persist (line 30)
//
// NOT LOCKED HERE: the specific system-fallback *rules* in the private
// `_resolveSystemLocale` (locale_controller.dart:15-28) — unsupported lang →
// en, zh+Hant → zh_Hant, zh (no script) → zh_Hans, supported lang → itself.
// Those rules read `PlatformDispatcher.instance.locale`, which is not
// overridable from a pure unit test (no test hook, and the method is private
// so it cannot be called directly with a crafted Locale). This test therefore
// only locks the *deterministic* part of the no-stored-value path: that
// initFromPrefs does not persist a code and resolves to a member of the
// supported set. A dedicated test that overrides the platform locale (e.g. a
// widget test driving `MaterialApp.localeResolutionCallback`, or production
// exposing a testable seam) would be needed to lock the per-rule mapping.
//
// Supported locale set (lib/i18n/app_localizations.dart:99-107 and the
// supportedCodes list in locale_controller.dart:17):
//   ar, en, ja, ko, zh, zh_Hans, zh_Hant

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/util/locale_controller.dart';
import 'package:toxee/util/prefs.dart';

/// Re-seed SharedPreferences with [seed] and (re)initialize the Prefs cache.
/// Resetting the mock store between tests is what makes "cold restart"
/// scenarios meaningful: nothing persists across [setUp] runs.
Future<void> _initPrefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The simple (non-script) language codes that round-trip as a plain
  // languageCode string. Confirmed against AppLocalizations.supportedLocales
  // and locale_controller.dart supportedCodes.
  const simpleCodes = <String>['ar', 'en', 'ja', 'ko', 'zh'];

  setUp(() async {
    await _initPrefs();
    // Reset the in-memory notifier so each test starts from a known default
    // and cold-restart assertions are not contaminated by prior tests.
    AppLocale.locale.value = const Locale('en');
  });

  group('Prefs language code round-trip (S38 storage contract)', () {
    for (final code in simpleCodes) {
      test('setLanguageCode($code) -> getLanguageCode() == $code', () async {
        await Prefs.setLanguageCode(code);
        expect(
          await Prefs.getLanguageCode(),
          code,
          reason:
              'Prefs must persist and return the exact language code "$code"',
        );
      });
    }

    test('overwriting a stored code replaces it (last write wins)', () async {
      await Prefs.setLanguageCode('en');
      await Prefs.setLanguageCode('ja');
      expect(
        await Prefs.getLanguageCode(),
        'ja',
        reason:
            'A subsequent setLanguageCode must overwrite the previous value',
      );
    });

    test('getLanguageCode() is null when nothing was ever stored', () async {
      expect(
        await Prefs.getLanguageCode(),
        isNull,
        reason: 'A fresh install has no stored language and must follow system',
      );
    });
  });

  group('generated Chinese app strings', () {
    test(
      'fallback labels are localized instead of falling back to English',
      () {
        final zhHans = lookupAppLocalizations(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        );
        final zhHant = lookupAppLocalizations(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        );

        expect(zhHans.unknown, '未知');
        expect(zhHans.unknownError, '未知错误');
        expect(zhHans.ircStatusDisconnected, '已断开');
        expect(zhHans.ircStatusConnecting, '连接中');
        expect(zhHans.ircStatusConnected, '已连接');
        expect(zhHans.ircStatusAuthenticating, '认证中');
        expect(zhHans.ircStatusReconnecting, '重连中');
        expect(zhHans.ircStatusError, '错误');
        expect(zhHant.unknown, '未知');
        expect(zhHant.unknownError, '未知錯誤');
        expect(zhHant.ircStatusDisconnected, '已斷開');
        expect(zhHant.ircStatusConnecting, '連線中');
        expect(zhHant.ircStatusConnected, '已連線');
        expect(zhHant.ircStatusAuthenticating, '認證中');
        expect(zhHant.ircStatusReconnecting, '重新連線中');
        expect(zhHant.ircStatusError, '錯誤');
      },
    );
  });

  group('Prefs locale round-trip incl. scriptCode (zh Hans/Hant)', () {
    test('plain Locale(en) round-trips without a scriptCode', () async {
      await Prefs.setLocale(const Locale('en'));
      final got = await Prefs.getLocale();
      expect(got, isNotNull, reason: 'A stored locale must be retrievable');
      expect(
        got!.languageCode,
        'en',
        reason: 'languageCode must survive the round-trip',
      );
      expect(
        got.scriptCode,
        isNull,
        reason: 'A plain locale must not gain a scriptCode',
      );
    });

    test('zh_Hans round-trips preserving scriptCode Hans', () async {
      const locale = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      await Prefs.setLocale(locale);
      final got = await Prefs.getLocale();
      expect(got, isNotNull);
      expect(
        got!.languageCode,
        'zh',
        reason: 'Simplified Chinese languageCode must survive',
      );
      expect(
        got.scriptCode,
        'Hans',
        reason: 'Simplified Chinese scriptCode (Hans) must survive',
      );
    });

    test('zh_Hant round-trips preserving scriptCode Hant', () async {
      const locale = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      await Prefs.setLocale(locale);
      final got = await Prefs.getLocale();
      expect(got, isNotNull);
      expect(
        got!.languageCode,
        'zh',
        reason: 'Traditional Chinese languageCode must survive',
      );
      expect(
        got.scriptCode,
        'Hant',
        reason: 'Traditional Chinese scriptCode (Hant) must survive',
      );
    });

    test('Hans and Hant are distinct stored values, not collapsed', () async {
      await Prefs.setLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      final first = await Prefs.getLocale();
      await Prefs.setLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      final second = await Prefs.getLocale();
      expect(first!.scriptCode, 'Hant');
      expect(
        second!.scriptCode,
        'Hans',
        reason: 'Switching zh script must not silently keep the old script',
      );
    });

    test('every supported scriptCode-qualified locale round-trips', () async {
      for (final locale in AppLocalizations.supportedLocales) {
        await Prefs.setLocale(locale);
        final got = await Prefs.getLocale();
        expect(got, isNotNull, reason: 'Supported locale $locale must persist');
        expect(
          got!.languageCode,
          locale.languageCode,
          reason: 'languageCode mismatch for supported locale $locale',
        );
        expect(
          got.scriptCode,
          locale.scriptCode,
          reason: 'scriptCode mismatch for supported locale $locale',
        );
      }
    });
  });

  group('AppLocale controller round-trip + cold restart', () {
    test('set(locale) updates the notifier immediately', () async {
      await AppLocale.set(const Locale('ko'));
      expect(
        AppLocale.locale.value.languageCode,
        'ko',
        reason: 'AppLocale.set must update the in-memory notifier',
      );
    });

    test('set(locale) persists through Prefs', () async {
      await AppLocale.set(const Locale('ja'));
      expect(
        await Prefs.getLanguageCode(),
        'ja',
        reason: 'AppLocale.set must persist the language code to Prefs',
      );
    });

    test('set(zh_Hant) persists the scriptCode-qualified locale', () async {
      await AppLocale.set(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      final stored = await Prefs.getLocale();
      expect(stored, isNotNull);
      expect(stored!.languageCode, 'zh');
      expect(
        stored.scriptCode,
        'Hant',
        reason: 'AppLocale.set must persist the zh scriptCode',
      );
    });

    test('cold restart reflects persisted locale, not the default', () async {
      // User picks Korean and the app shuts down.
      await AppLocale.set(const Locale('ko'));

      // Simulate process restart: in-memory notifier reset to default,
      // but the persisted store is untouched.
      AppLocale.locale.value = const Locale('en');

      await AppLocale.initFromPrefs();
      expect(
        AppLocale.locale.value.languageCode,
        'ko',
        reason:
            'After restart AppLocale must restore the persisted '
            'language, not fall back to the system/default',
      );
    });

    test('cold restart restores zh scriptCode exactly', () async {
      await AppLocale.set(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      AppLocale.locale.value = const Locale('en');

      await AppLocale.initFromPrefs();
      expect(
        AppLocale.locale.value.languageCode,
        'zh',
        reason: 'Restored language must be Chinese',
      );
      expect(
        AppLocale.locale.value.scriptCode,
        'Hans',
        reason: 'Restored Chinese variant must keep scriptCode Hans',
      );
    });
  });

  // NOTE: this group deliberately does NOT lock the per-rule mapping of
  // `_resolveSystemLocale` (unsupported→en, zh+Hant→zh_Hant, etc.). That
  // method reads `PlatformDispatcher.instance.locale`, which a pure unit test
  // cannot override, and it is private so it cannot be invoked directly with a
  // crafted Locale. We only assert the deterministic, system-independent
  // properties of the no-stored-value path. See the file header for what would
  // be required to lock the individual rules.
  group('AppLocale no-stored-value path (deterministic properties only)', () {
    test('initFromPrefs with empty store does not persist a value', () async {
      // No language was ever chosen -> follow system, leaving Prefs unset so
      // the app keeps tracking system changes until the user picks explicitly.
      // This is fully deterministic regardless of the host system locale.
      await AppLocale.initFromPrefs();
      expect(
        await Prefs.getLanguageCode(),
        isNull,
        reason: 'Following the system locale must not write a stored code',
      );
    });

    test(
      'initFromPrefs with empty store resolves to a supported locale',
      () async {
        await AppLocale.initFromPrefs();
        // Whatever the host system locale is, resolution must land inside the
        // supported set (its only escape hatch is the en fallback). This guards
        // against resolving to an unsupported/garbage locale, but NOT against a
        // specific wrong rule (e.g. a regression to "always en when unset" would
        // still satisfy this coarse assertion — that gap is documented above and
        // is not lockable from a pure unit test).
        const supportedCodes = <String>['ar', 'en', 'ja', 'ko', 'zh'];
        expect(
          supportedCodes,
          contains(AppLocale.locale.value.languageCode),
          reason:
              'System resolution must yield a supported languageCode '
              '(unsupported codes fall back to en)',
        );
        if (AppLocale.locale.value.languageCode == 'zh') {
          expect(
            AppLocale.locale.value.scriptCode,
            anyOf('Hans', 'Hant'),
            reason: 'Resolved Chinese must carry a Hans/Hant scriptCode',
          );
        }
      },
    );
  });
}
