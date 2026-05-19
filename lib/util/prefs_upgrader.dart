import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Current schema version for global preferences.
/// Bump this when adding migration steps and implement the new step in [_runGlobalMigration].
const int currentGlobalPrefsVersion = 2;

/// Current schema version for per-account preferences.
/// Bump when adding per-account migration steps.
///
/// v0 → v1: groups/quitGroups from unscoped to account-scoped keys.
/// v1 → v2: eagerly migrate per-account bool settings (autoAcceptFriends,
/// autoAcceptGroupInvites, autoLogin, notificationSoundEnabled) from the
/// `account_list` JSON blob into account-scoped boolean prefs. Previously
/// these were migrated lazily inside the getters on each read; consolidating
/// them here is X3 (single migration registry) from the local-storage review.
const int currentAccountPrefsVersion = 2;

/// Key used to store the global schema version in SharedPreferences.
const String _kPrefsSchemaVersion = 'prefs_schema_version';

/// Key prefix for per-account schema version.
String _accountPrefsVersionKey(String accountPrefix) =>
    'account_prefs_version_$accountPrefix';

/// `account_list` JSON blob key (mirrors `Prefs._kAccountList`). Duplicated
/// here so the upgrader stays standalone — Prefs depends on this file, not
/// the other way around.
const String _kAccountList = 'account_list';

// Scoped per-account boolean keys — these must match the prefixes used by
// Prefs.getAutoAcceptFriends / getAutoAcceptGroupInvites / getAutoLogin /
// getNotificationSoundEnabled. If those keys change, change them here too.
const String _kAccountAutoAcceptFriendsPrefix = 'acct_auto_accept_friends';
const String _kAccountAutoAcceptGroupInvitesPrefix =
    'acct_auto_accept_group_invites';
const String _kAccountAutoLoginPrefix = 'acct_auto_login';
const String _kAccountNotificationSoundPrefix = 'acct_notification_sound';

/// Length of the toxId prefix used for scoped keys (mirrors `Prefs._scopedKey`).
const int _scopedToxIdPrefixLen = 16;

/// Thrown when stored preferences were saved by a newer app version.
/// The app should prompt the user to upgrade and not overwrite data.
class PrefsStorageNewerThanAppException implements Exception {
  final int storedVersion;
  final int currentVersion;

  PrefsStorageNewerThanAppException(this.storedVersion, this.currentVersion);

  @override
  String toString() =>
      'PrefsStorageNewerThanAppException(stored: $storedVersion, current: $currentVersion)';
}

/// Runs schema upgrades for SharedPreferences.
///
/// Handles both global migrations (theme defaults, etc.) and per-account
/// migrations (moving data from unscoped to account-scoped keys).
///
/// Single source of truth for prefs migrations — there must not be any
/// inline lazy migrations inside individual Prefs getters. If you find
/// one, fold it into [_runAccountMigration] under a new version bump.
class PrefsUpgrader {
  PrefsUpgrader._();

  /// Run global schema migrations.
  static Future<void> run(SharedPreferences p) async {
    final stored = p.getInt(_kPrefsSchemaVersion) ?? 0;

    if (stored > currentGlobalPrefsVersion) {
      throw PrefsStorageNewerThanAppException(stored, currentGlobalPrefsVersion);
    }

    if (stored < currentGlobalPrefsVersion) {
      for (int from = stored; from < currentGlobalPrefsVersion; from++) {
        await _runGlobalMigration(from, from + 1, p);
      }
      await p.setInt(_kPrefsSchemaVersion, currentGlobalPrefsVersion);
    }
  }

  /// Run per-account schema migrations for the given account.
  /// Call this when an account is activated (login / switch).
  static Future<void> runAccountMigrations(
    SharedPreferences p,
    String accountPrefix,
  ) async {
    if (accountPrefix.isEmpty) return;

    final versionKey = _accountPrefsVersionKey(accountPrefix);
    final stored = p.getInt(versionKey) ?? 0;

    if (stored >= currentAccountPrefsVersion) return;

    for (int from = stored; from < currentAccountPrefsVersion; from++) {
      await _runAccountMigration(from, from + 1, p, accountPrefix);
    }
    await p.setInt(versionKey, currentAccountPrefsVersion);
  }

  // ---------- Global migrations ----------

  static Future<void> _runGlobalMigration(
      int from, int to, SharedPreferences p) async {
    if (from == 0 && to == 1) {
      // v0→v1: previously this step forced theme_mode = 'light' when missing.
      // That overrode Prefs.getThemeMode()'s 'system' default for every user
      // who first ran the app on this migration step, locking them to light
      // mode regardless of OS theme. The default now stays 'system' (the
      // getter handles missing keys); existing 'light' values written by
      // earlier builds are preserved as-is so we don't surprise users who
      // explicitly chose light.
      return;
    }
    if (from == 1 && to == 2) {
      // v1→v2: no-op placeholder. Per-account settings migration was moved
      // from read-time fallback into eager runAccountMigrations() v1→v2 (see
      // _runAccountMigration), so no global eager migration is needed here.
      return;
    }
  }

  // ---------- Per-account migrations ----------

  static Future<void> _runAccountMigration(
      int from, int to, SharedPreferences p, String accountPrefix) async {
    if (from == 0 && to == 1) {
      // v0→v1: Migrate groups/quitGroups from unscoped to account-scoped keys.
      // This absorbs the logic previously in SharedPreferencesAdapter._migrateIfNeeded().
      final accountGroupsKey = 'groups_list_$accountPrefix';
      final existing = p.getStringList(accountGroupsKey);
      if (existing != null && existing.isNotEmpty) return; // already migrated

      final oldGroups = p.getStringList('groups_list');
      if (oldGroups != null && oldGroups.isNotEmpty) {
        await p.setStringList(accountGroupsKey, oldGroups);
        final oldQuit = p.getStringList('quit_groups_list');
        if (oldQuit != null && oldQuit.isNotEmpty) {
          await p.setStringList('quit_groups_list_$accountPrefix', oldQuit);
        }
        // Clear unscoped keys after copying so only THIS account gets the data.
        // Otherwise every other account that runs migration would copy the same
        // global list and show groups they never joined (e.g. nick22 seeing 4 groups).
        await p.remove('groups_list');
        await p.remove('quit_groups_list');
      }
      return;
    }
    if (from == 1 && to == 2) {
      // v1→v2: Eagerly migrate per-account boolean settings from the
      // `account_list` JSON blob into scoped boolean prefs. Previously, each
      // of the four getters (getAutoAcceptFriends, getAutoAcceptGroupInvites,
      // getAutoLogin, getNotificationSoundEnabled) ran this same logic lazily
      // on every read. Folded into a single eager migration here (X3 from
      // the 2026-05-18 local-storage review).
      //
      // Behavior is identical to the old lazy path: the scoped key is only
      // written if (a) it is not already set AND (b) the account_list entry
      // contains the corresponding key. The JSON entry is intentionally
      // left untouched — the lazy path never cleared it, and we mirror that
      // so downstream code paths that still read `account_list` keep working.
      await _migrateAccountBoolSettings(p, accountPrefix);
      return;
    }
  }

  /// Find the account-list entry whose toxId begins with [accountPrefix] (the
  /// first 16 chars Prefs uses for scoped keys) and copy its bool-shaped
  /// settings into scoped boolean prefs. Best-effort: malformed JSON or
  /// missing entries are silent no-ops.
  static Future<void> _migrateAccountBoolSettings(
      SharedPreferences p, String accountPrefix) async {
    final raw = p.getString(_kAccountList);
    if (raw == null || raw.isEmpty) return;
    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return; // malformed; nothing we can migrate
    }

    Map<String, dynamic>? account;
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final toxId = entry['toxId']?.toString().trim();
      if (toxId == null || toxId.isEmpty) continue;
      final prefix = toxId.length >= _scopedToxIdPrefixLen
          ? toxId.substring(0, _scopedToxIdPrefixLen)
          : toxId;
      if (prefix == accountPrefix) {
        account = Map<String, dynamic>.from(entry);
        break;
      }
    }
    if (account == null) return;

    Future<void> copyBool(String jsonKey, String prefKeyPrefix) async {
      if (!account!.containsKey(jsonKey)) return;
      final scopedKey = '${prefKeyPrefix}_$accountPrefix';
      // Don't overwrite a value the user (or a write since the lazy era) set.
      if (p.containsKey(scopedKey)) return;
      // The JSON path historically stored these as the string 'true' / 'false';
      // be permissive in case future writers store actual booleans.
      final raw = account[jsonKey];
      final boolVal = raw is bool ? raw : raw?.toString() == 'true';
      await p.setBool(scopedKey, boolVal);
    }

    await copyBool('autoAcceptFriends', _kAccountAutoAcceptFriendsPrefix);
    await copyBool(
        'autoAcceptGroupInvites', _kAccountAutoAcceptGroupInvitesPrefix);
    await copyBool('autoLogin', _kAccountAutoLoginPrefix);
    await copyBool(
        'notificationSoundEnabled', _kAccountNotificationSoundPrefix);
  }
}
