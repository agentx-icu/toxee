import 'package:flutter/widgets.dart';

import '../i18n/app_localizations.dart';
import 'locale_controller.dart';

/// App strings in the current UI language, for code that has no
/// [BuildContext]: notifications, the tray, background services and data-layer
/// fallbacks. Widgets should keep using `AppLocalizations.of(context)`.
///
/// Resolved on every call from [AppLocale.locale], so a language switch is
/// picked up by the next notification without any re-wiring.
AppLocalizations currentAppL10n() {
  final locale = AppLocale.locale.value;
  try {
    return lookupAppLocalizations(locale);
  } on FlutterError {
    // A persisted locale this build no longer ships must not take down a
    // notification path.
    return lookupAppLocalizations(const Locale('en'));
  }
}
