import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../adapters/bootstrap_adapter.dart';
import '../adapters/logger_adapter.dart';
import '../adapters/shared_prefs_adapter.dart';
import 'app_paths.dart';
import 'logger.dart';
import 'prefs.dart';
import 'prefs/scoped_key.dart';
import 'prefs_upgrader.dart';

/// One-shot migration for accounts that historically stored the V2TIM login
/// `userId` placeholder (`'FlutterUIKitClient'`) as if it were the user's Tox
/// ID. `FfiChatService.selfId` returns the V2TIM login string, not the Tox
/// identity — toxee's legacy login paths in `LoginUseCase` and
/// `StartupSessionUseCase` used `selfId` for `Prefs.addAccount(toxId: ...)`,
/// so every record those paths wrote ended up keyed by the placeholder.
/// That string then surfaced everywhere the UI displayed "User ID", AND
/// account-scoped files (`account_data/FlutterUIKitClie/...`,
/// `p_FlutterUIKitClie/tox_profile.tox`) AND account-scoped SharedPreferences
/// keys (suffixed `_FlutterUIKitClie`) all sit under the wrong prefix.
///
/// Forward fixes in those use-cases switched to `service.getSelfToxId()`.
/// This helper handles the already-corrupted on-disk state for users
/// upgrading from a broken build: discover the real Tox ID, then atomically
/// move every piece of placeholder-keyed state to the real ID. Steps are
/// applied in an order that lets each later step be rolled back to its
/// pre-migration form when a downstream step fails — the worst outcome on
/// failure is "no migration this boot, retry next time", never a partially
/// migrated account.
///
/// Idempotent. Safe to call on every cold start.
class PlaceholderAccountMigration {
  static const placeholderToxId = 'FlutterUIKitClient';

  /// First 16 chars of the placeholder — the suffix used in scoped
  /// SharedPreferences keys (see `lib/util/prefs/scoped_key.dart`) and the
  /// directory-name prefix used by `AppPaths` for `account_data/` and
  /// profile dirs (see `lib/util/app_paths.dart:_accountPrefix`).
  static String get _placeholderPrefix => placeholderToxId.length >= 16
      ? placeholderToxId.substring(0, 16)
      : placeholderToxId;

  /// Runs the migration if any placeholder-keyed state is detected.
  /// Returns the real Tox ID when migration succeeded (or wasn't needed but
  /// a real ID is now in Prefs); null when no real ID could be discovered,
  /// nothing needed migrating, or the migration aborted with a rollback.
  static Future<String?> migrateIfNeeded() async {
    final pointer = await Prefs.getCurrentAccountToxId();
    final accounts = await Prefs.getAccountList();
    final placeholderIdx =
        accounts.indexWhere((a) => a['toxId'] == placeholderToxId);
    final pointerIsPlaceholder = pointer == placeholderToxId;

    if (placeholderIdx < 0 && !pointerIsPlaceholder) {
      return null; // Nothing to migrate.
    }

    AppLogger.log('[PlaceholderAccountMigration] Detected placeholder-keyed '
        'state (pointer=$pointerIsPlaceholder, listIdx=$placeholderIdx); '
        'discovering real Tox ID…');

    final realToxId = await _discoverRealToxId();
    if (realToxId == null || realToxId.isEmpty) {
      AppLogger.warn(
          '[PlaceholderAccountMigration] Failed to discover real Tox ID; '
          'migration skipped. The placeholder-keyed account record will '
          'continue to surface as "FlutterUIKitClient" in the UI.');
      return null;
    }
    if (realToxId == placeholderToxId) {
      // `getSelfToxId()` returned the V2TIM login userId by mistake. Bail
      // rather than rename-to-self.
      AppLogger.warn('[PlaceholderAccountMigration] Discovered ID equals '
          'placeholder; aborting');
      return null;
    }

    AppLogger.log('[PlaceholderAccountMigration] Real Tox ID discovered '
        '(${_truncate(realToxId)}); migrating…');

    final realPrefix =
        realToxId.length >= 16 ? realToxId.substring(0, 16) : realToxId;
    // Same-prefix collision would mean dirs/scoped-keys already align (which
    // would only happen if the placeholder string somehow shared a 16-char
    // prefix with a hex Tox ID — impossible because the placeholder starts
    // with 'F' followed by 'l', non-hex). Bail defensively.
    if (realPrefix == _placeholderPrefix) {
      AppLogger.warn('[PlaceholderAccountMigration] Real prefix matches '
          'placeholder prefix; aborting to avoid rename-to-self');
      return null;
    }

    final result = await _runTransactionally(
      realToxId: realToxId,
      realPrefix: realPrefix,
      accounts: accounts,
      placeholderIdx: placeholderIdx,
      pointerIsPlaceholder: pointerIsPlaceholder,
    );

    if (result) {
      AppLogger.log('[PlaceholderAccountMigration] Migration complete');
      return realToxId;
    }
    AppLogger.warn('[PlaceholderAccountMigration] Migration aborted and '
        'rolled back; nothing persisted');
    return null;
  }

  /// Spin up a short-lived [FfiChatService] using the placeholder paths,
  /// log in to populate the FFI's internal Tox identity, read the Tox
  /// address, then tear the service back down. The session-side service
  /// (created later by the normal startup path) will be re-instantiated
  /// against the migrated paths.
  static Future<String?> _discoverRealToxId() async {
    final prefs = await SharedPreferences.getInstance();
    final accountPrefix = _placeholderPrefix;

    final historyDir =
        await AppPaths.getAccountChatHistoryPath(placeholderToxId);
    final queuePath =
        await AppPaths.getAccountOfflineQueueFilePath(placeholderToxId);
    final fileRecvPath =
        await AppPaths.getAccountFileRecvPath(placeholderToxId);
    final avatarsPath = await AppPaths.getAccountAvatarsPath(placeholderToxId);
    final profileDir =
        await AppPaths.getProfileDirectoryForToxId(placeholderToxId);
    final profileFile = AppPaths.profileFileInDirectory(profileDir);

    if (!await File(profileFile).exists()) {
      AppLogger.warn(
          '[PlaceholderAccountMigration] Profile blob missing at $profileFile; '
          'cannot discover real Tox ID');
      return null;
    }

    await Directory(historyDir).create(recursive: true);
    await Directory(avatarsPath).create(recursive: true);

    FfiChatService? service;
    try {
      service = FfiChatService(
        preferencesService:
            SharedPreferencesAdapter(prefs, accountPrefix: accountPrefix),
        loggerService: AppLoggerAdapter(),
        bootstrapService: BootstrapNodesAdapter(prefs),
        historyDirectory: historyDir,
        queueFilePath: queuePath,
        fileRecvPath: fileRecvPath,
        avatarsPath: avatarsPath,
      );
      await service.init(profileDirectory: profileDir);
      await service.login(
          userId: placeholderToxId, userSig: 'dummy_sig');
      return service.getSelfToxId();
    } catch (e, st) {
      AppLogger.logError(
          '[PlaceholderAccountMigration] Discovery service init failed', e, st);
      return null;
    } finally {
      try {
        await service?.dispose();
      } catch (e, st) {
        AppLogger.logError(
            '[PlaceholderAccountMigration] Failed to dispose discovery service '
            '(non-fatal)',
            e,
            st);
      }
    }
  }

  /// Apply every step of the migration with a per-step rollback stack. The
  /// first step that fails or precondition-rejects unwinds everything done
  /// so far. Returns true only when every step succeeded and the durable
  /// state (account list + pointer) was committed.
  static Future<bool> _runTransactionally({
    required String realToxId,
    required String realPrefix,
    required List<Map<String, String>> accounts,
    required int placeholderIdx,
    required bool pointerIsPlaceholder,
  }) async {
    final rollbacks = <_RollbackOp>[];
    final prefs = await SharedPreferences.getInstance();

    try {
      // Step 1: account_data directory
      final dataFrom = await AppPaths.getAccountDataRoot(placeholderToxId);
      final dataTo = await AppPaths.getAccountDataRoot(realToxId);
      final dataMove = await _renameDir(
        from: dataFrom,
        to: dataTo,
        label: 'account_data root',
      );
      if (dataMove.failed) {
        throw _MigrationAborted('account_data rename failed');
      }
      if (dataMove.renamed) {
        rollbacks.add(_RollbackOp(
          label: 'undo account_data rename',
          run: () => _renameDir(from: dataTo, to: dataFrom, label: 'rollback'),
        ));
      }

      // Step 2: profile directory
      final profileFrom =
          await AppPaths.getProfileDirectoryForToxId(placeholderToxId);
      final profileTo = await AppPaths.getProfileDirectoryForToxId(realToxId);
      final profileMove = await _renameDir(
        from: profileFrom,
        to: profileTo,
        label: 'profile directory',
      );
      if (profileMove.failed) {
        throw _MigrationAborted('profile dir rename failed');
      }
      if (profileMove.renamed) {
        rollbacks.add(_RollbackOp(
          label: 'undo profile rename',
          run: () =>
              _renameDir(from: profileTo, to: profileFrom, label: 'rollback'),
        ));
      }

      // Step 3: scoped SharedPreferences keys (`*_<oldPrefix>` → `*_<newPrefix>`)
      // Collect everything first, write new keys, only delete olds after all
      // writes succeed. Tracked in rollbacks so a later failure can undo
      // every write + restore every delete.
      final scopedMoved = await _migrateScopedPrefs(
        prefs: prefs,
        oldPrefix: _placeholderPrefix,
        newPrefix: realPrefix,
      );
      if (scopedMoved == null) {
        throw _MigrationAborted('scoped prefs migration failed');
      }
      if (scopedMoved.isNotEmpty) {
        rollbacks.add(_RollbackOp(
          label: 'undo scoped prefs migration',
          run: () => _rollbackScopedPrefs(prefs, scopedMoved),
        ));
      }

      // Step 3b: account password (secure-storage hash+salt and any legacy
      // plain-prefs copies). Keyed by full toxId — if we don't move it the
      // user's password becomes unreachable on the next login because
      // `PasswordVerifier.verifyPassword(realToxId, ...)` looks under the
      // real toxId namespace and finds nothing. `Prefs.migrateAccountPasswordKeys`
      // already does its own internal rollback on partial failure, so by
      // the time we see `migrationFailed` here, nothing changed; on
      // `migratedFully` we register a rollback that moves the keys back.
      final passwordOutcome = await Prefs.migrateAccountPasswordKeys(
        fromToxId: placeholderToxId,
        toToxId: realToxId,
      );
      if (passwordOutcome == PasswordMigrationOutcome.migrationFailed) {
        throw _MigrationAborted('account password migration failed');
      }
      if (passwordOutcome == PasswordMigrationOutcome.migratedFully) {
        rollbacks.add(_RollbackOp(
          label: 'undo password key migration',
          run: () async {
            // Reverse-migration can `migrationFailed` itself — most
            // commonly when the original forward pass couldn't fully
            // delete the source placeholder keys (best-effort) and the
            // reverse pass now sees them as a "destination collision".
            // We can't unwind further from rollback, but a silent
            // failure here would leave the account_list / pointer
            // restored to the placeholder while the password still
            // lives under the real toxId — `verifyPassword` would
            // mismatch on the next login. Surface loudly.
            final reverse = await Prefs.migrateAccountPasswordKeys(
              fromToxId: realToxId,
              toToxId: placeholderToxId,
            );
            if (reverse == PasswordMigrationOutcome.migrationFailed) {
              AppLogger.logError(
                  '[PlaceholderAccountMigration] Rollback: reverse '
                  'password-key migration failed. Password may now '
                  'live under the real Tox ID while account_list / '
                  'pointer were restored to the placeholder; the '
                  'account will appear "password-protected" but '
                  'verification will mismatch. Manual cleanup of '
                  'secure-storage / legacy prefs keys required.');
            }
          },
        ));
      }

      // Step 3c: blacklist. `black_list_<toxId>` is scoped by the FULL id (see
      // `Prefs._blackListKey` / `SharedPreferencesAdapter._blackListKey`), NOT
      // by the 16-char prefix, so Step 3's `endsWith('_$_placeholderPrefix')`
      // scan does not see it and the list would be stranded once the account
      // is re-keyed to its real Tox ID. Previously that went unnoticed because
      // tim2tox ALSO read the list under the placeholder (it passed the login
      // alias `FfiChatService.selfId` as the scope regardless of the account's
      // id); now that it passes the real Tox ID, leaving this behind would
      // silently UNBLOCK everyone the user had blocked.
      final blackListMove = await PrefsUpgrader.migrateBlackListScope(
        prefs,
        fromToxId: placeholderToxId,
        toToxId: realToxId,
      );
      if (blackListMove == null) {
        AppLogger.warn('[PlaceholderAccountMigration] blacklist: the store '
            'refused the write to the real Tox ID scope; nothing changed');
        throw _MigrationAborted('blacklist migration failed');
      }
      if (blackListMove.moved) {
        rollbacks.add(_RollbackOp(
          label: 'undo blacklist migration',
          run: () async {
            if (!await PrefsUpgrader.rollbackBlackListScope(
                prefs, blackListMove)) {
              AppLogger.logError(
                  '[PlaceholderAccountMigration] Rollback: the blacklist could '
                  'not be fully restored to the placeholder scope. The blocked '
                  'list may now live under the real Tox ID while account_list / '
                  'pointer were rolled back to the placeholder — the user would '
                  'see an empty Blocked Users list until the next successful '
                  'migration. Manual cleanup of `black_list_*` may be required.');
            }
          },
        ));
      }

      // Step 4: account_list — replace toxId field on the placeholder row.
      // If there's already a real-ID row (defensive — shouldn't happen on a
      // single-account user), drop the placeholder copy so addAccount's
      // uniqueness invariant holds.
      final accountListSnapshot = _cloneAccounts(accounts);
      if (placeholderIdx >= 0) {
        final existingRealIdx =
            accounts.indexWhere((a) => a['toxId'] == realToxId);
        if (existingRealIdx >= 0 && existingRealIdx != placeholderIdx) {
          AppLogger.warn(
              '[PlaceholderAccountMigration] Real-Tox-ID record already exists '
              'alongside the placeholder; removing the placeholder copy '
              '(its nickname / avatar / settings will be lost)');
          accounts.removeAt(placeholderIdx);
        } else {
          accounts[placeholderIdx]['toxId'] = realToxId;
        }
        await Prefs.setAccountList(accounts);
        rollbacks.add(_RollbackOp(
          label: 'undo account_list update',
          run: () async => Prefs.setAccountList(accountListSnapshot),
        ));
      }

      // Step 5: current-account pointer.
      if (pointerIsPlaceholder) {
        await Prefs.setCurrentAccountToxId(realToxId);
        rollbacks.add(_RollbackOp(
          label: 'undo current-account pointer',
          run: () async => Prefs.setCurrentAccountToxId(placeholderToxId),
        ));
      }

      return true;
    } catch (e, st) {
      AppLogger.logError(
          '[PlaceholderAccountMigration] Step failed; rolling back', e, st);
      for (final op in rollbacks.reversed) {
        try {
          await op.run();
        } catch (re, rst) {
          AppLogger.logError(
              '[PlaceholderAccountMigration] Rollback step "${op.label}" '
              'failed — manual cleanup may be required',
              re,
              rst);
        }
      }
      return false;
    }
  }

  /// Returns a per-key migration record (old key → new key + value) for
  /// every SharedPreferences entry whose name is `<base>_<oldPrefix>`. On a
  /// successful return, every new key is written and every old key is
  /// deleted; the returned list is the rollback ledger. Returns null when
  /// any precondition fails (collision with an existing new-prefix key, or
  /// a write/remove returned false / threw) — partial writes are undone so
  /// the caller sees a clean "nothing changed" state.
  ///
  /// Collision policy: if *any* `<base>_<newPrefix>` key already exists
  /// when migration runs, the function aborts before writing anything. A
  /// silent-skip-with-warning was the previous behavior; that path left
  /// the old key's value stranded under the placeholder while every other
  /// piece of state moved to the real Tox ID — a classic half-migration.
  /// Aborting forces the user / operator to investigate the collision
  /// rather than silently lose per-account settings.
  static Future<List<_ScopedKeyMove>?> _migrateScopedPrefs({
    required SharedPreferences prefs,
    required String oldPrefix,
    required String newPrefix,
  }) async {
    final suffix = '_$oldPrefix';
    final allKeys = prefs.getKeys().toList();
    final candidates = allKeys.where((k) => k.endsWith(suffix)).toList();
    if (candidates.isEmpty) return const [];

    // Phase A: pre-flight — gather moves and detect collisions. Any
    // collision (a key already keyed by the real prefix) aborts.
    final moves = <_ScopedKeyMove>[];
    for (final oldKey in candidates) {
      final baseKey = oldKey.substring(0, oldKey.length - suffix.length);
      // Use the shared helper to compute the new key so this can't drift
      // from `SharedPreferencesAdapter._prefixKey` / `Prefs._scopedKey`.
      final newKey = scopedPrefsKey(baseKey, newPrefix);
      if (newKey == oldKey) continue; // identity move; nothing to do
      if (prefs.containsKey(newKey)) {
        AppLogger.warn(
            '[PlaceholderAccountMigration] Scoped prefs collision: '
            '"$newKey" already exists alongside "$oldKey"; aborting '
            'migration so the operator can resolve manually');
        return null;
      }
      final value = prefs.get(oldKey);
      if (value == null) continue;
      moves.add(_ScopedKeyMove(oldKey: oldKey, newKey: newKey, value: value));
    }
    if (moves.isEmpty) return const [];

    // Phase B: write all new keys. `SharedPreferences.setX` returns
    // `Future<bool>` — `false` indicates the platform store rejected the
    // write without throwing. Treating that as success is a silent data
    // loss; treat it as failure and unwind.
    final written = <_ScopedKeyMove>[];
    try {
      for (final m in moves) {
        final ok = await _writeTypedValue(prefs, m.newKey, m.value);
        if (!ok) {
          throw StateError(
              'SharedPreferences refused write for "${m.newKey}" '
              '(value type ${m.value.runtimeType})');
        }
        written.add(m);
      }
    } catch (e, st) {
      AppLogger.logError(
          '[PlaceholderAccountMigration] Scoped prefs write failed; '
          'cleaning up partial writes',
          e,
          st);
      for (final m in written) {
        try {
          await prefs.remove(m.newKey);
        } catch (_) {
          // Best-effort cleanup; we already have a primary error.
        }
      }
      return null;
    }

    // Phase C: remove old keys now that every new key landed. Failure to
    // remove an old key is non-fatal (duplicate keys are harmless: the
    // new key shadows the old in every read path because Prefs/Adapter
    // both consult the scoped key first). Log so cleanup is visible.
    for (final m in moves) {
      try {
        final removed = await prefs.remove(m.oldKey);
        if (!removed) {
          AppLogger.warn(
              '[PlaceholderAccountMigration] prefs.remove("${m.oldKey}") '
              'returned false — the value will linger until manual cleanup '
              '(harmless: new key shadows it on read)');
        }
      } catch (e, st) {
        AppLogger.logError(
            '[PlaceholderAccountMigration] Failed to remove old scoped key '
            '"${m.oldKey}" after writing "${m.newKey}"',
            e,
            st);
      }
    }

    return moves;
  }

  /// Reverse a successful scoped-prefs migration: re-write every old key
  /// from the move ledger, then remove the new key. Best-effort — once
  /// we're in rollback we can't unwind further — but we no longer swallow
  /// `Future<bool>` results: every restore/remove returning false is
  /// surfaced as an error log so an operator can spot half-recovered
  /// state in the diagnostics. Throws are also logged but don't stop the
  /// loop (better to keep restoring the remaining keys than bail).
  static Future<void> _rollbackScopedPrefs(
    SharedPreferences prefs,
    List<_ScopedKeyMove> moves,
  ) async {
    for (final m in moves) {
      try {
        final restored = await _writeTypedValue(prefs, m.oldKey, m.value);
        if (!restored) {
          AppLogger.logError(
              '[PlaceholderAccountMigration] Rollback: prefs refused to '
              'restore "${m.oldKey}" (setX returned false); manual cleanup '
              'needed — the new key "${m.newKey}" may still hold the '
              'migrated value');
        }
      } catch (e, st) {
        AppLogger.logError(
            '[PlaceholderAccountMigration] Rollback: failed to restore '
            '"${m.oldKey}"',
            e,
            st);
      }
      try {
        final removed = await prefs.remove(m.newKey);
        if (!removed) {
          AppLogger.logError(
              '[PlaceholderAccountMigration] Rollback: prefs.remove("${m.newKey}") '
              'returned false; both old and new keys may now coexist — '
              'reads prefer the new key, so the rolled-back account may '
              'still see migrated values until manual cleanup');
        }
      } catch (e, st) {
        AppLogger.logError(
            '[PlaceholderAccountMigration] Rollback: failed to remove '
            '"${m.newKey}"',
            e,
            st);
      }
    }
  }

  /// Dispatch a typed write based on the runtime type that `prefs.get`
  /// returned. Returns true only when the platform store confirmed the
  /// write (every `setX` returns `Future<bool>` where false means the
  /// store rejected the write without throwing — defensively treated as
  /// failure so the caller can roll back the transaction).
  ///
  /// Returns false for unsupported value types as well — same outcome
  /// from the caller's perspective: don't proceed.
  static Future<bool> _writeTypedValue(
      SharedPreferences prefs, String key, Object value) async {
    if (value is String) return prefs.setString(key, value);
    if (value is bool) return prefs.setBool(key, value);
    if (value is int) return prefs.setInt(key, value);
    if (value is double) return prefs.setDouble(key, value);
    if (value is List<String>) return prefs.setStringList(key, value);
    return false;
  }

  /// Rename a directory with explicit outcome typing. Distinguishes "source
  /// missing" (treat as no-op success) from "destination already exists"
  /// (reject the move — the caller decides whether to abort the
  /// transaction) from "I/O error" (transaction must abort and roll back).
  static Future<_RenameOutcome> _renameDir({
    required String from,
    required String to,
    required String label,
  }) async {
    final fromDir = Directory(from);
    final toDir = Directory(to);

    if (!await fromDir.exists()) {
      AppLogger.log('[PlaceholderAccountMigration] $label: source missing '
          '($from); treating as no-op');
      return _RenameOutcome.noop;
    }
    if (await toDir.exists()) {
      AppLogger.warn(
          '[PlaceholderAccountMigration] $label: destination already exists '
          '($to); refusing to merge');
      return _RenameOutcome.failed;
    }
    try {
      // `Directory.create(parent, recursive: true)` is needed because
      // `rename` does NOT create missing parents on macOS/Linux — when the
      // parent of `to` is absent (e.g. on a fresh install where `p_<real>`
      // would land in an as-yet-uncreated profiles root), the move would
      // fail with ENOENT and we'd lose the source.
      final parent = Directory(_dirname(to));
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await fromDir.rename(to);
      AppLogger.log(
          '[PlaceholderAccountMigration] $label: renamed $from → $to');
      return _RenameOutcome.renamed;
    } catch (e, st) {
      AppLogger.logError(
          '[PlaceholderAccountMigration] $label: rename failed', e, st);
      return _RenameOutcome.failed;
    }
  }

  /// Lightweight `path.dirname` substitute to avoid adding a `path` import
  /// here when the platform separator + a single `lastIndexOf` already does
  /// the right thing for absolute paths produced by `AppPaths`.
  static String _dirname(String path) {
    final sep = Platform.pathSeparator;
    final idx = path.lastIndexOf(sep);
    return idx <= 0 ? path : path.substring(0, idx);
  }

  /// Deep copy of the account list so a rollback can restore the exact
  /// shape (including any per-row keys we didn't touch).
  static List<Map<String, String>> _cloneAccounts(
      List<Map<String, String>> accounts) {
    return accounts.map((a) => Map<String, String>.from(a)).toList();
  }

  static String _truncate(String id) =>
      id.length > 16 ? '${id.substring(0, 16)}…' : id;
}

/// Outcome of a single directory rename, used to drive transaction logic.
enum _RenameOutcome {
  /// Successfully renamed `from` → `to`. The corresponding rollback should
  /// rename in reverse.
  renamed,

  /// Source didn't exist; treat as a success but with no rollback to record.
  noop,

  /// I/O error or precondition violation (e.g. destination already exists).
  /// The transaction must abort.
  failed,
}

extension on _RenameOutcome {
  bool get renamed => this == _RenameOutcome.renamed;
  bool get failed => this == _RenameOutcome.failed;
}

/// A scheduled rollback step — invoked in reverse-completion order if any
/// later step throws.
class _RollbackOp {
  _RollbackOp({required this.label, required this.run});
  final String label;
  final Future<void> Function() run;
}

/// One scoped-prefs key migration record (write `newKey ← value`, then
/// remove `oldKey`).
class _ScopedKeyMove {
  _ScopedKeyMove({
    required this.oldKey,
    required this.newKey,
    required this.value,
  });
  final String oldKey;
  final String newKey;
  final Object value;
}

/// Internal sentinel used to unwind `_runTransactionally`'s rollback stack
/// from precondition checks (no underlying exception to chain).
class _MigrationAborted implements Exception {
  _MigrationAborted(this.message);
  final String message;
  @override
  String toString() => 'MigrationAborted: $message';
}
