import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Current schema version for global preferences.
/// Bump this when adding migration steps and implement the new step in [_runGlobalMigration].
///
/// v0 → v1: retired (used to force `theme_mode = 'light'`); now a no-op.
/// v1 → v2: no-op placeholder — the per-account bool settings migration lives
/// in [_runAccountMigration] instead.
/// v2 → v3: collect the UNSCOPED per-peer mute orphans
/// (`c2c_recv_opt_<id>`, `group_recv_opt_<id>`, `do_not_disturb_<id>`) that
/// older builds minted when no account was known. See
/// [_sweepUnscopedPerPeerMuteOrphans].
/// v3 → v4: rehome (or drop) the per-peer mute + blacklist entries that older
/// builds scoped by the V2TIM login PLACEHOLDER `'FlutterUIKitClient'` instead
/// of the account's Tox ID. See [_rehomePlaceholderScopedAccountState].
const int currentGlobalPrefsVersion = 4;

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

/// Active-account pointer (mirrors `Prefs._kCurrentAccountToxId`). Same
/// standalone-duplication rationale as [_kAccountList].
const String _kCurrentAccountToxId = 'current_account_tox_id';

/// Per-peer / per-group mute key families that are account-scoped as
/// `<prefix><id>_<first16 of account toxId>`. Their unscoped form
/// `<prefix><id>` is what the v2→v3 sweep collects.
const List<String> _perPeerMuteKeyPrefixes = <String>[
  'c2c_recv_opt_',
  'group_recv_opt_',
  'do_not_disturb_',
];

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

/// The V2TIM login `userId` toxee passes to `FfiChatService.login()` from every
/// login path. It is an ALIAS, never a Tox identity — mirrors
/// `PlaceholderAccountMigration.placeholderToxId`, duplicated here for the same
/// standalone reason as [_kAccountList] (that class depends on this file's
/// world, not the other way around).
const String _placeholderLoginUserId = 'FlutterUIKitClient';

/// The scope suffix a `<key>_<first16>` account-scoped key gets when the
/// placeholder is used as the account id: `_FlutterUIKitClie`.
const String _placeholderScopeSuffix = '_FlutterUIKitClie';

/// The blacklist family is scoped by the FULL id (`black_list_<toxId>`, see
/// `Prefs._blackListKey` / `SharedPreferencesAdapter._blackListKey`), so it is
/// NOT truncated to 16 chars and does not carry [_placeholderScopeSuffix].
const String _placeholderBlackListKey = 'black_list_$_placeholderLoginUserId';

/// Ledger for one `black_list_<toxId>` scope move, produced by
/// [PrefsUpgrader.migrateBlackListScope] and consumed by
/// [PrefsUpgrader.rollbackBlackListScope].
class BlackListScopeMigration {
  const BlackListScopeMigration({
    required this.fromKey,
    required this.toKey,
    required this.fromValue,
    required this.priorDestination,
  });

  /// "Nothing to move" — needs no rollback entry.
  const BlackListScopeMigration.noop()
      : fromKey = null,
        toKey = null,
        fromValue = null,
        priorDestination = null;

  final String? fromKey;
  final String? toKey;

  /// The source list as it was before the move.
  final List<String>? fromValue;

  /// The destination list as it was before the merge, or null when the
  /// destination key did not exist. Rollback must then REMOVE it rather than
  /// write an empty list — an empty list is a meaningful "blocked nobody".
  final List<String>? priorDestination;

  bool get moved => fromKey != null;
}

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

  /// Move `black_list_<fromToxId>` onto `black_list_<toToxId>`.
  ///
  /// Lives here rather than in `PlaceholderAccountMigration` (its only caller
  /// today) because this file is the declared single source of truth for prefs
  /// migrations — and because the transactional migration itself cannot be
  /// driven from a unit test (it needs a live `FfiChatService`), so the actual
  /// key surgery has to be reachable on its own to be provable.
  ///
  /// MERGE rather than abort on collision — deliberately the opposite call from
  /// `PlaceholderAccountMigration._migrateScopedPrefs`. A blacklist is a safety
  /// control, so its two error directions are not symmetric: over-blocking is
  /// visible in the Blocked Users list and one click to undo, while dropping an
  /// entry silently lets a blocked peer back through. Set union is also
  /// idempotent, so a re-run after a partial application is safe.
  ///
  /// Returns null when the destination write failed or threw — nothing has been
  /// changed at that point, because that write is the first mutation. Removal
  /// of the source is best-effort: with the destination written, a lingering
  /// source key is inert (nothing reads the old scope any more).
  static Future<BlackListScopeMigration?> migrateBlackListScope(
    SharedPreferences p, {
    required String fromToxId,
    required String toToxId,
  }) async {
    final fromKey = 'black_list_$fromToxId';
    final toKey = 'black_list_$toToxId';
    if (fromKey == toKey) return const BlackListScopeMigration.noop();

    final stranded = p.getStringList(fromKey);
    if (stranded == null) return const BlackListScopeMigration.noop();

    final priorDestination = p.getStringList(toKey);
    final merged = <String>{...?priorDestination, ...stranded}.toList();

    try {
      if (!await p.setStringList(toKey, merged)) return null;
    } catch (_) {
      return null;
    }

    try {
      await p.remove(fromKey);
    } catch (_) {
      // Inert leftover; the destination already holds the union.
    }

    return BlackListScopeMigration(
      fromKey: fromKey,
      toKey: toKey,
      fromValue: stranded,
      priorDestination: priorDestination,
    );
  }

  /// Reverse [migrateBlackListScope]: restore the source list and put the
  /// destination back to exactly what it held before (REMOVING it when it did
  /// not exist). Returns false when any step failed, so the caller can log the
  /// half-recovered state — rollback cannot unwind any further than this.
  static Future<bool> rollbackBlackListScope(
    SharedPreferences p,
    BlackListScopeMigration move,
  ) async {
    final fromKey = move.fromKey;
    final fromValue = move.fromValue;
    final toKey = move.toKey;
    if (fromKey == null || fromValue == null || toKey == null) return true;

    var ok = true;
    try {
      ok = await p.setStringList(fromKey, fromValue);
    } catch (_) {
      ok = false;
    }
    try {
      final prior = move.priorDestination;
      if (prior == null) {
        await p.remove(toKey);
      } else {
        if (!await p.setStringList(toKey, prior)) ok = false;
      }
    } catch (_) {
      ok = false;
    }
    return ok;
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
    if (from == 2 && to == 3) {
      await _sweepUnscopedPerPeerMuteOrphans(p);
      return;
    }
    if (from == 3 && to == 4) {
      await _rehomePlaceholderScopedAccountState(p);
      return;
    }
  }

  /// v3→v4 — repair the per-account state that older builds filed under the
  /// V2TIM login PLACEHOLDER instead of the account's Tox ID.
  ///
  /// WHAT THE ENTRIES ARE
  /// --------------------
  /// `Tim2ToxSdkPlatform` used to pass `FfiChatService.selfId` as the
  /// `userToxId` scope for `ExtendedPreferencesService`. `selfId` is
  /// `V2TIMManagerImpl::GetLoginUser()` — the login ALIAS, which toxee passes
  /// as the constant `'FlutterUIKitClient'` from all three of its login paths.
  /// So `SharedPreferencesAdapter` minted:
  ///   * `c2c_recv_opt_<peer>_FlutterUIKitClie`
  ///   * `group_recv_opt_<gid>_FlutterUIKitClie`   (16-char scope prefix)
  ///   * `black_list_FlutterUIKitClient`           (full-id scope, no truncation)
  /// tim2tox now passes `FfiChatService.prefsAccountScopeToxId`, so the live
  /// code addresses the real per-account slot — which leaves everything the
  /// user already muted/blocked stranded under the placeholder. Without this
  /// step the visible symptom is "all my mutes and my whole blocked list
  /// disappeared after updating".
  ///
  /// ATTRIBUTION — THE HARD PART
  /// ---------------------------
  /// The placeholder slot is SHARED by every local account, so on a
  /// multi-account install the entries are commingled and un-attributable. The
  /// two families get different verdicts because their failure modes are not
  /// symmetric in the same direction:
  ///
  ///   * MUTE (`c2c_recv_opt_*`, `group_recv_opt_*`): claiming for the wrong
  ///     account SILENTLY suppresses notifications for a peer that account
  ///     never muted — invisible, and exactly the bug class this scoping
  ///     exists to prevent. Dropping costs one re-mute and the banner makes it
  ///     obvious. So: claim only when the install has exactly ONE account
  ///     (then it is not a guess at all); otherwise DELETE. This is the same
  ///     verdict [_sweepUnscopedPerPeerMuteOrphans] reached for the unscoped
  ///     variant of the same keys.
  ///
  ///   * BLACKLIST (`black_list_FlutterUIKitClient`): here DELETING is the
  ///     silent-and-harmful direction — a peer the user deliberately blocked
  ///     would quietly start getting through, which is a safety control
  ///     failing open. Claiming too widely only over-blocks, and that is
  ///     visible and one click to undo in the Blocked Users list. So the
  ///     blacklist is MERGED (set union, order-preserving) into every account
  ///     this install knows about. On the single-account install that
  ///     everybody actually has, "merge into every account" IS "claim".
  ///
  /// DEFERRAL — DO NOT FIGHT `PlaceholderAccountMigration`
  /// ----------------------------------------------------
  /// A separate, older defect wrote the placeholder as the ACCOUNT's own id
  /// (`account_list` / `current_account_tox_id` contain `'FlutterUIKitClient'`).
  /// `PlaceholderAccountMigration` repairs that at login time — after this
  /// upgrader has already run — and its `_migrateScopedPrefs` step moves every
  /// `*_FlutterUIKitClie` key to the discovered real prefix, and its Step 3c
  /// calls [migrateBlackListScope] for the full-id blacklist key. If we acted
  /// first we would see "zero real accounts" and delete state that migration
  /// was about to relocate correctly. So when the placeholder still appears as
  /// an account identity, this step does NOTHING and leaves the keys to it.
  ///
  /// Refuses to guess when the account registry is unreadable
  /// ([_knownAccountToxIds] returns null), and the whole body is guarded
  /// because it runs inside `PrefsBootstrap.initialize()` and must never block
  /// startup. In both cases the entries simply survive — the status quo.
  ///
  /// Idempotent: it consumes the placeholder-suffixed keys, so a second run
  /// finds nothing (and the schema stamp stops it re-running anyway).
  static Future<void> _rehomePlaceholderScopedAccountState(
      SharedPreferences p) async {
    try {
      final scopedOrphans = p
          .getKeys()
          .where((k) =>
              k.endsWith(_placeholderScopeSuffix) &&
              _perPeerMuteKeyPrefixes.any(k.startsWith))
          .toList();
      final hasBlacklistOrphan = p.containsKey(_placeholderBlackListKey);
      if (scopedOrphans.isEmpty && !hasBlacklistOrphan) return;

      final knownToxIds = _knownAccountToxIds(p);
      if (knownToxIds == null) return; // unreadable registry — do not guess

      // Deferral: the placeholder is still acting as an account identity.
      final placeholderLowered = _placeholderLoginUserId.toLowerCase();
      if (knownToxIds
          .any((id) => id.toLowerCase() == placeholderLowered)) {
        return;
      }

      // Mute families.
      if (scopedOrphans.isNotEmpty) {
        // Count DISTINCT accounts case-insensitively (Tox IDs are hex, so the
        // pointer and the account_list row can legitimately disagree on case
        // and still name one account). The claimant prefix itself is taken
        // verbatim from the first-seen spelling — pointer before account_list,
        // per [_knownAccountToxIds]' insertion order — because scoped keys are
        // byte-compared, so re-casing would just orphan them again.
        final byLoweredPrefix = <String, String>{};
        for (final id in knownToxIds) {
          final prefix = _accountPrefixOf(id);
          byLoweredPrefix.putIfAbsent(prefix.toLowerCase(), () => prefix);
        }
        final claimant = byLoweredPrefix.length == 1
            ? byLoweredPrefix.values.single
            : null;
        for (final oldKey in scopedOrphans) {
          if (claimant != null) {
            final base = oldKey.substring(
                0, oldKey.length - _placeholderScopeSuffix.length);
            final newKey = '${base}_$claimant';
            final value = p.get(oldKey);
            // A value already sitting on the real key was written by the
            // post-fix code and is authoritative; never clobber it.
            if (value != null && !p.containsKey(newKey)) {
              await _writeTypedValue(p, newKey, value);
            }
          }
          await p.remove(oldKey);
        }
      }

      // Blacklist family.
      if (hasBlacklistOrphan) {
        final stranded =
            p.getStringList(_placeholderBlackListKey) ?? const <String>[];
        if (stranded.isNotEmpty) {
          for (final toxId in knownToxIds) {
            final key = 'black_list_$toxId';
            final merged = <String>{
              ...?p.getStringList(key),
              ...stranded,
            }.toList();
            await p.setStringList(key, merged);
          }
        }
        await p.remove(_placeholderBlackListKey);
      }
    } catch (_) {
      // Best-effort: leaving the entries behind is the pre-migration state.
    }
  }

  /// Every account Tox ID (FULL, untruncated) this install knows about, or null
  /// when the registry cannot be read. The blacklist key family is scoped by
  /// the full id, so [_knownAccountPrefixes]' 16-char form is not usable there.
  static Set<String>? _knownAccountToxIds(SharedPreferences p) {
    final ids = <String>{};

    final current = p.getString(_kCurrentAccountToxId)?.trim();
    if (current != null && current.isNotEmpty) ids.add(current);

    final raw = p.getString(_kAccountList);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return null;
        for (final entry in decoded) {
          if (entry is! Map) continue;
          final toxId = entry['toxId']?.toString().trim();
          if (toxId == null || toxId.isEmpty) continue;
          ids.add(toxId);
        }
      } catch (_) {
        return null;
      }
    }

    return ids;
  }

  static String _accountPrefixOf(String toxId) =>
      toxId.length >= _scopedToxIdPrefixLen
          ? toxId.substring(0, _scopedToxIdPrefixLen)
          : toxId;

  /// Typed re-write of a value read back via `SharedPreferences.get`.
  /// Returns false for a type the store cannot hold (never happens for the
  /// int/bool mute families, but the caller must not silently believe a write
  /// happened).
  static Future<bool> _writeTypedValue(
      SharedPreferences p, String key, Object value) async {
    if (value is String) return p.setString(key, value);
    if (value is bool) return p.setBool(key, value);
    if (value is int) return p.setInt(key, value);
    if (value is double) return p.setDouble(key, value);
    if (value is List<String>) return p.setStringList(key, value);
    return false;
  }

  /// v2→v3 — DELETE the un-attributable per-peer mute entries that older
  /// builds wrote when they had no account to scope by.
  ///
  /// WHAT THE ORPHANS ARE
  /// --------------------
  /// `Prefs.setDoNotDisturb`, `Prefs.setC2CReceiveMessageOpt`,
  /// `Prefs.setGroupReceiveMessageOpt` and
  /// `SharedPreferencesAdapter.set*ReceiveMessageOpt` all built their key via
  /// `scopedPrefsKey(base, prefix)`, which returns `base` UNCHANGED when the
  /// prefix is null or empty. `ffiService.selfId` is `''` before login and the
  /// `userToxId` argument is optional, so a pre-login write landed on
  /// `c2c_recv_opt_<id>` / `group_recv_opt_<id>` / `do_not_disturb_<id>`.
  /// Those entries are now doubly dead: the getters were changed to require a
  /// scope (so nobody reads them), and every teardown path
  /// (`Prefs.clearScopedKeysForAccount`, `Prefs.clearAccountData`,
  /// `SharedPreferencesAdapter.clear`) sweeps on the `_<first16>` suffix, so
  /// nobody deletes them either. Only a one-shot sweep can.
  ///
  /// WHY DELETE RATHER THAN CLAIM FOR THE CURRENT ACCOUNT
  /// ---------------------------------------------------
  /// The entry is un-attributable BY CONSTRUCTION — that is the defect. The
  /// two failure modes are not symmetric:
  ///   * Delete: a user who muted a peer pre-login has to mute again. Visible
  ///     (the banner fires), one click, recoverable.
  ///   * Claim: an account that never muted that peer silently stops getting
  ///     its notifications. Invisible, and the symptom ("I stopped seeing
  ///     their messages") is exactly the bug class this whole family exists to
  ///     avoid. On a multi-account install it is a straight privacy/UX
  ///     regression for a stranger's setting.
  /// `AccountPrivacyCleanup._failedMessageAccountSuffix` already made the same
  /// call for the unsuffixed failed-message queue: an unattributable key is
  /// never treated as belonging to some particular account.
  ///
  /// SAFETY — WHAT COUNTS AS "STILL SCOPED"
  /// --------------------------------------
  /// A key is KEPT when it ends in `_<prefix>` for any account prefix this
  /// install knows about: `account_list` entries, the `current_account_tox_id`
  /// pointer, and every `account_prefs_version_<prefix>` stamp (which names an
  /// account that was activated at least once, even if it later fell out of
  /// `account_list`). Matching is case-insensitive because Tox IDs are hex —
  /// folding case can only ever widen the KEEP set, never the delete set.
  ///
  /// `_FlutterUIKitClie` is ALSO kept: that suffix means "scoped by the V2TIM
  /// login placeholder", which is a different (and repairable) defect owned by
  /// the v3→v4 step [_rehomePlaceholderScopedAccountState].
  ///
  /// When the install knows about NO account at all, nothing passes the KEEP
  /// test and every such key is removed. That is the intended reading, not an
  /// accident: with no account on disk there is no owner any of these entries
  /// could belong to. The `account_prefs_version_<prefix>` stamps are what
  /// keep this from firing on a store whose `account_list` was rewritten.
  ///
  /// If `account_list` is present but unparseable we cannot tell scoped from
  /// unscoped, so the sweep does NOTHING rather than guess. Same for any
  /// unexpected throw: the whole body is guarded, because this runs inside
  /// `PrefsBootstrap.initialize()` and must never block startup. In both cases
  /// the version stamp still advances and the orphans simply survive — which
  /// is exactly the status quo, so nothing regresses.
  ///
  /// Idempotent: after the first run there is nothing left that fails the
  /// KEEP test, and the schema stamp stops it re-running anyway.
  static Future<void> _sweepUnscopedPerPeerMuteOrphans(
      SharedPreferences p) async {
    try {
      final candidates = p
          .getKeys()
          .where((k) => _perPeerMuteKeyPrefixes.any(k.startsWith))
          .toList();
      if (candidates.isEmpty) return;

      final knownPrefixes = _knownAccountPrefixes(p);
      if (knownPrefixes == null) return; // unreadable registry — do not guess

      final lowered = <String>[
        ...knownPrefixes.map((prefix) => '_${prefix.toLowerCase()}'),
        // NOT an orphan of THIS class. A `_FlutterUIKitClie`-suffixed key is
        // scoped — just scoped by the V2TIM login placeholder instead of a Tox
        // ID — and the v3→v4 step
        // ([_rehomePlaceholderScopedAccountState]) knows how to rehome it to a
        // real account. Deleting it here would destroy, on the single upgrade
        // hop 2→3→4, exactly the mutes that step exists to rescue.
        _placeholderScopeSuffix.toLowerCase(),
      ];
      final orphans = candidates.where((key) {
        final lowerKey = key.toLowerCase();
        return !lowered.any(lowerKey.endsWith);
      }).toList();
      if (orphans.isEmpty) return;

      await Future.wait(orphans.map(p.remove));
    } catch (_) {
      // Best-effort: leaving the orphans behind is the pre-migration state.
    }
  }

  /// Every account-scope prefix this install knows about, or null when the
  /// account registry cannot be read (in which case the caller must not
  /// classify anything as an orphan).
  static Set<String>? _knownAccountPrefixes(SharedPreferences p) {
    String prefixOf(String toxId) => toxId.length >= _scopedToxIdPrefixLen
        ? toxId.substring(0, _scopedToxIdPrefixLen)
        : toxId;

    final prefixes = <String>{};

    final current = p.getString(_kCurrentAccountToxId)?.trim();
    if (current != null && current.isNotEmpty) {
      prefixes.add(prefixOf(current));
    }

    final raw = p.getString(_kAccountList);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        // Not a list => not the registry we know how to read. Same verdict as
        // a parse failure: refuse to classify rather than under-count accounts.
        if (decoded is! List) return null;
        for (final entry in decoded) {
          if (entry is! Map) continue;
          final toxId = entry['toxId']?.toString().trim();
          if (toxId == null || toxId.isEmpty) continue;
          prefixes.add(prefixOf(toxId));
        }
      } catch (_) {
        return null;
      }
    }

    // An `account_prefs_version_<prefix>` stamp proves the account was
    // activated on this install; keep its keys even if `account_list` no
    // longer lists it (a half-finished deletion would otherwise let this
    // sweep finish the job for keys deletion itself is supposed to own).
    const versionKeyPrefix = 'account_prefs_version_';
    for (final key in p.getKeys()) {
      if (!key.startsWith(versionKeyPrefix)) continue;
      final suffix = key.substring(versionKeyPrefix.length);
      if (suffix.isNotEmpty) prefixes.add(suffix);
    }

    return prefixes;
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
