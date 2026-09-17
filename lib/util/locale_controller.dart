import 'dart:ui';
import 'package:flutter/foundation.dart';

import 'prefs.dart';

class AppLocale {
  static final ValueNotifier<Locale> locale = ValueNotifier<Locale>(const Locale('en'));

  static Future<void> initFromPrefs() async {
    final saved = await Prefs.getLocale();
    locale.value =
        saved ?? resolveSystemLocale(PlatformDispatcher.instance.locale);
  }

  /// Resolves a system locale to a supported one; falls back to English if not
  /// supported.
  @visibleForTesting
  static Locale resolveSystemLocale(Locale system) {
    const supportedCodes = ['ar', 'en', 'ja', 'ko', 'zh'];
    if (!supportedCodes.contains(system.languageCode)) {
      return const Locale('en');
    }
    if (system.languageCode == 'zh') {
      // Android commonly reports Traditional-Chinese regions as zh-TW / zh-HK
      // with no script subtag (iOS sends zh-Hant-TW), so the region has to
      // decide too — otherwise Taiwan/Hong Kong users following the system
      // language got Simplified Chinese.
      const hantRegions = {'TW', 'HK', 'MO'};
      if (system.scriptCode == 'Hant' ||
          (system.scriptCode == null &&
              hantRegions.contains(system.countryCode))) {
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      }
      return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
    }
    return Locale(system.languageCode);
  }

  static Future<void> set(Locale l) async {
    locale.value = l;
    await Prefs.setLocale(l);
  }
}


