import 'package:shared_preferences/shared_preferences.dart';

/// Newer data must stay untouched until a compatible app is installed.
class PrefsStorageNewerThanAppException implements Exception {
  PrefsStorageNewerThanAppException(this.storedVersion, this.currentVersion);
  final int storedVersion;
  final int currentVersion;

  @override
  String toString() =>
      'Preferences require a newer app '
      '(stored: $storedVersion, supported: $currentVersion). Update toxee to continue.';
}

void validatePrefsSchemas(
  SharedPreferences prefs, {
  required int globalVersion,
  required int accountVersion,
}) {
  final global = prefs.getInt('prefs_schema_version') ?? 0;
  if (global > globalVersion) {
    throw PrefsStorageNewerThanAppException(global, globalVersion);
  }
  for (final key in prefs.getKeys()) {
    if (!key.startsWith('account_prefs_version_')) continue;
    final stored = prefs.getInt(key) ?? 0;
    if (stored > accountVersion) {
      throw PrefsStorageNewerThanAppException(stored, accountVersion);
    }
  }
}
