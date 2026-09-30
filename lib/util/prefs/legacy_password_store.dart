// The pre-S1 plain-text SharedPreferences password entries, split out of
// `password_verifier.dart` so the verifier stays under the complexity gate.
// New writes never touch these keys; existing installs may still have them and
// the verifier migrates them on first read.

import 'package:shared_preferences/shared_preferences.dart';

import 'password_verifier.dart';

/// Adapter for the legacy plain-text SharedPreferences password entries
/// (`account_password_<toxId>` hash and `account_password_salt_<toxId>` salt).
abstract class LegacyPasswordStore {
  Future<String?> readLegacyHash(String toxId);
  Future<String?> readLegacySalt(String toxId);
  Future<void> removeLegacyHash(String toxId);
  Future<void> removeLegacySalt(String toxId);
}

/// Default [LegacyPasswordStore] backed by the app's [SharedPreferences]
/// instance. Production callers use this; tests inject an in-memory fake.
class SharedPreferencesLegacyPasswordStore implements LegacyPasswordStore {
  SharedPreferencesLegacyPasswordStore(this._prefsProvider);

  final Future<SharedPreferences> Function() _prefsProvider;

  @override
  Future<String?> readLegacyHash(String toxId) async {
    final p = await _prefsProvider();
    return p.getString(PasswordVerifier.legacyHashKey(toxId));
  }

  @override
  Future<String?> readLegacySalt(String toxId) async {
    final p = await _prefsProvider();
    return p.getString(PasswordVerifier.legacySaltKey(toxId));
  }

  @override
  Future<void> removeLegacyHash(String toxId) async {
    final p = await _prefsProvider();
    await p.remove(PasswordVerifier.legacyHashKey(toxId));
  }

  @override
  Future<void> removeLegacySalt(String toxId) async {
    final p = await _prefsProvider();
    await p.remove(PasswordVerifier.legacySaltKey(toxId));
  }
}
