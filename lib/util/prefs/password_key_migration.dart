part of 'package:toxee/util/prefs.dart';

// Password-key namespace migration, split out of `prefs.dart` when that file
// grew past its complexity-gate pin.
//
// This is a `part`, so it can reach `Prefs`'s private secure-storage helpers
// (`_secureRead` / `_secureWrite` / `_secureDelete`) and `_getPrefs()` — the
// reason the logic stays in the Prefs library instead of becoming a standalone
// class. `Prefs.migrateAccountPasswordKeys` is the public entry point.

/// See `Prefs.migrateAccountPasswordKeys`.
Future<PasswordMigrationOutcome> migrateAccountPasswordKeysImpl({
  required String fromToxId,
  required String toToxId,
}) async {
  if (fromToxId.isEmpty || toToxId.isEmpty || fromToxId == toToxId) {
    return PasswordMigrationOutcome.migratedNothing;
  }

  // Snapshot source values from both storage layers.
  final fromHashKey = PasswordVerifier.secureHashKey(fromToxId);
  final fromSaltKey = PasswordVerifier.secureSaltKey(fromToxId);
  final toHashKey = PasswordVerifier.secureHashKey(toToxId);
  final toSaltKey = PasswordVerifier.secureSaltKey(toToxId);
  final fromLegacyHashKey = PasswordVerifier.legacyHashKey(fromToxId);
  final fromLegacySaltKey = PasswordVerifier.legacySaltKey(fromToxId);
  final toLegacyHashKey = PasswordVerifier.legacyHashKey(toToxId);
  final toLegacySaltKey = PasswordVerifier.legacySaltKey(toToxId);

  // Read the SOURCE slots through the availability-reporting API, not the lossy
  // `_secureRead`.
  //
  // THIS IS A SECURITY CHECK, not defensiveness. `_secureRead` collapses "no
  // such key" and "the Keychain refused to answer" into null. With an
  // unavailable secure store and no legacy hash, that made every source look
  // empty, this function reported `migratedNothing`, and the caller
  // (`PlaceholderAccountMigration`, `ShortToxIdBackfill`) happily renamed the
  // account's identity — leaving the verifier stranded under the OLD toxId.
  // Once the store came back, the protection query for the NEW id answered
  // `none`, and a plaintext-at-rest profile was then enough for auto-login to
  // open a password-protected account with no prompt. An unreadable credential
  // store must ABORT identity migration, not license it.
  final secureHashRead = await Prefs._secureReadOutcome(fromHashKey);
  final secureSaltRead = await Prefs._secureReadOutcome(fromSaltKey);
  if (secureHashRead.unavailable || secureSaltRead.unavailable) {
    AppLogger.warn(
      '[Prefs.migrateAccountPasswordKeys] secure storage unavailable; '
      'refusing to migrate password keys (migrating the identity while the '
      'verifier cannot be read would strand it under the old namespace)',
    );
    return PasswordMigrationOutcome.migrationFailed;
  }
  final secureHash = secureHashRead.value;
  final secureSalt = secureSaltRead.value;
  final prefs = await Prefs._getPrefs();
  final legacyHash = prefs.getString(fromLegacyHashKey);
  final legacySalt = prefs.getString(fromLegacySaltKey);

  final anySource =
      secureHash != null ||
      secureSalt != null ||
      legacyHash != null ||
      legacySalt != null;
  if (!anySource) return PasswordMigrationOutcome.migratedNothing;

  // Pre-flight: refuse to clobber an existing target slot. A populated
  // target slot means a real-toxId password is already configured —
  // overwriting would corrupt the existing account's auth. An UNREADABLE
  // destination is equally disqualifying: we cannot prove the slot is free, and
  // overwriting a live verifier would lock that account out.
  final destHashRead = await Prefs._secureReadOutcome(toHashKey);
  final destSaltRead = await Prefs._secureReadOutcome(toSaltKey);
  if (destHashRead.unavailable || destSaltRead.unavailable) {
    return PasswordMigrationOutcome.migrationFailed;
  }
  final destHash = destHashRead.value;
  final destSalt = destSaltRead.value;
  final destLegacyHash = prefs.getString(toLegacyHashKey);
  final destLegacySalt = prefs.getString(toLegacySaltKey);
  if (destHash != null ||
      destSalt != null ||
      destLegacyHash != null ||
      destLegacySalt != null) {
    return PasswordMigrationOutcome.migrationFailed;
  }

  // Copy under new keys. Track each write so a downstream failure can
  // unwind to "nothing changed".
  final undoSecure = <String>[];
  final undoLegacy = <String>[];
  try {
    if (secureHash != null) {
      if (!await Prefs._secureWrite(toHashKey, secureHash)) {
        throw StateError('secure write of $toHashKey failed');
      }
      undoSecure.add(toHashKey);
    }
    if (secureSalt != null) {
      if (!await Prefs._secureWrite(toSaltKey, secureSalt)) {
        throw StateError('secure write of $toSaltKey failed');
      }
      undoSecure.add(toSaltKey);
    }
    if (legacyHash != null) {
      if (!await prefs.setString(toLegacyHashKey, legacyHash)) {
        throw StateError('prefs write of $toLegacyHashKey failed');
      }
      undoLegacy.add(toLegacyHashKey);
    }
    if (legacySalt != null) {
      if (!await prefs.setString(toLegacySaltKey, legacySalt)) {
        throw StateError('prefs write of $toLegacySaltKey failed');
      }
      undoLegacy.add(toLegacySaltKey);
    }
  } catch (_) {
    for (final k in undoSecure) {
      try {
        await Prefs._secureDelete(k);
      } catch (_) {
        /* best effort */
      }
    }
    for (final k in undoLegacy) {
      try {
        await prefs.remove(k);
      } catch (_) {
        /* best effort */
      }
    }
    return PasswordMigrationOutcome.migrationFailed;
  }

  // Source removal is non-fatal. The new keys are now authoritative;
  // a lingering old key is harmless (no caller reads under the old
  // toxId after account_list is migrated).
  try {
    if (secureHash != null) await Prefs._secureDelete(fromHashKey);
  } catch (_) {
    /* best effort */
  }
  try {
    if (secureSalt != null) await Prefs._secureDelete(fromSaltKey);
  } catch (_) {
    /* best effort */
  }
  try {
    if (legacyHash != null) await prefs.remove(fromLegacyHashKey);
  } catch (_) {
    /* best effort */
  }
  try {
    if (legacySalt != null) await prefs.remove(fromLegacySaltKey);
  } catch (_) {
    /* best effort */
  }

  return PasswordMigrationOutcome.migratedFully;
}
