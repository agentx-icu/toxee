import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_paths.dart';
import 'logger.dart';
import 'tox_utils.dart';

final class AccountPrivacyCleanup {
  const AccountPrivacyCleanup._();

  static const String _failedMessagesBase =
      'tencent_cloud_chat_failed_messages';
  static const String _failedMessagesKeyPrefix = '${_failedMessagesBase}_';
  static const int _legacyToxIdPrefixLength = 16;

  /// Tox public key (32 bytes hex) and full Tox address
  /// (`public_key || nospam || checksum`) widths.
  static const int _publicKeyLength = 64;
  static const int _fullAddressLength = 76;

  /// `Prefs._blackListKey` / `SharedPreferencesAdapter._blackListKey`.
  static const String _blackListKeyPrefix = 'black_list_';

  /// tim2tox `FfiChatService._pendingReadReceiptsKey`.
  static const String _pendingReadReceiptsKeyPrefix = 'pending_read_receipts_';

  static const String _currentAccountKey = 'current_account_tox_id';
  static const String _nicknameKey = 'self_nickname';
  static const String _statusMessageKey = 'self_status_msg';
  static const String _avatarPathKey = 'self_avatar_path';
  static const String _deprecatedFlatLogName = 'flutter_client.log';

  static final RegExp _hexOnly = RegExp(r'^[0-9a-fA-F]+$');

  static Future<void> purgeDeletedAccountResidue({
    required String toxId,
    required bool deletedCurrentAccount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _purgeDiagnosticLogs();
    await _removeFailedMessagePrefs(prefs, toxId);
    await _removeFullIdScopedPrefs(prefs, toxId);
    await _removeLegacyCurrentAccountPrefs(
      prefs: prefs,
      toxId: toxId,
      deletedCurrentAccount: deletedCurrentAccount,
    );
  }

  /// Key families scoped by the FULL Tox ID rather than the 16-char prefix.
  ///
  /// `Prefs.clearScopedKeysForAccount` and `clearAccountData` only sweep keys
  /// ENDING in `_<first16>`, so anything keyed by a 64- or 76-char id slips
  /// past them and survives account deletion outright. Two families do:
  ///
  ///   * `black_list_<toxId>` — the blocked-peer set (`Prefs._blackListKey` /
  ///     `SharedPreferencesAdapter._blackListKey`). tim2tox writes it under the
  ///     live address (`FfiChatService.prefsAccountScopeToxId`). It is a list of
  ///     contact Tox IDs.
  ///   * `pending_read_receipts_<toxId>_<peerId>` — tim2tox's queue of READ
  ///     receipts that could not be sent (`FfiChatService`
  ///     `_pendingReadReceiptsKey`). Also per-peer, so also a contact list.
  ///
  /// Both are exactly the residue class [_removeFailedMessagePrefs] documents
  /// and fixes for the failed-message queue; this applies the same treatment.
  /// The sweep matches by *representation* rather than by one computed key,
  /// because the deletion driver may hold a 64-char id while the session wrote
  /// under the 76-char one (see the long note on that method).
  static Future<void> _removeFullIdScopedPrefs(
    SharedPreferences prefs,
    String toxId,
  ) async {
    final keysToRemove = <String>{};
    for (final key in prefs.getKeys()) {
      final suffix = _blackListAccountSuffix(key);
      if (suffix != null && _isSameAccount(suffix, toxId)) {
        keysToRemove.add(key);
        continue;
      }
      final receiptScope = _pendingReadReceiptsAccountScope(key);
      if (receiptScope != null && _isSameAccount(receiptScope, toxId)) {
        keysToRemove.add(key);
      }
    }
    if (keysToRemove.isEmpty) return;
    await Future.wait(keysToRemove.map(prefs.remove));
  }

  /// The account-ID suffix of a `black_list_<toxId>` key, or null.
  ///
  /// The bare `black_list` key (no suffix) is deliberately left alone: it is not
  /// attributable to this account, exactly as with the unsuffixed
  /// failed-messages key.
  static String? _blackListAccountSuffix(String key) {
    if (!key.startsWith(_blackListKeyPrefix)) return null;
    return _accountShapedId(key.substring(_blackListKeyPrefix.length));
  }

  /// The account scope embedded in a `pending_read_receipts_<toxId>_<peerId>`
  /// key, or null when [key] is not one.
  ///
  /// The scope sits in the MIDDLE, so this takes the leading run up to the next
  /// `_` and requires it to be an account-shaped hex id. A peer id follows, and
  /// is not examined — every peer of a deleted account goes with it.
  static String? _pendingReadReceiptsAccountScope(String key) {
    if (!key.startsWith(_pendingReadReceiptsKeyPrefix)) return null;
    final rest = key.substring(_pendingReadReceiptsKeyPrefix.length);
    final separator = rest.indexOf('_');
    if (separator <= 0) return null;
    return _accountShapedId(rest.substring(0, separator));
  }

  /// [candidate] when it has the shape of a Tox account id, else null.
  ///
  /// Pinning the shape to the three widths a real identity can produce — the
  /// 16-char legacy prefix, the 64-char public key, the 76-char address — is
  /// what stops the sweep truncating some longer, differently-namespaced key
  /// and mistaking its head for this account.
  static String? _accountShapedId(String candidate) {
    if (candidate.length != _legacyToxIdPrefixLength &&
        candidate.length != _publicKeyLength &&
        candidate.length != _fullAddressLength) {
      return null;
    }
    return _hexOnly.hasMatch(candidate) ? candidate : null;
  }

  /// Deletes the whole diagnostic-log tree, then reopens a working sink.
  ///
  /// DELIBERATE TRADE-OFF — this is **not** scoped to the deleted account:
  /// deleting any one account destroys every account's diagnostic logs.
  ///
  /// It has to be. Unlike per-account state, logs are not partitioned by
  /// account anywhere: [AppPaths.logsDir] is a single global
  /// `<appSupport>/logs`, and [AppPaths.logFilePath] names each file
  /// `app_<sessionTimestamp>.log` with no account segment (contrast
  /// `AppPaths.getAccountDataRoot`, which *is* keyed by the 16-char account
  /// prefix). A single log file also interleaves lines from every session on
  /// the install, including sessions from before an account switch, so even
  /// per-file attribution would not be sound. There is no subset that can be
  /// removed to erase exactly one account's traces.
  ///
  /// Given that, we choose privacy over diagnosability: a deletion that leaves
  /// the deleted account's peer IDs, message metadata and file names sitting
  /// in a shared log defeats the whole operation, whereas a surviving account
  /// only loses replaceable troubleshooting data and immediately gets a fresh
  /// sink. Do not "fix" this by narrowing the delete without first making the
  /// log layout account-scoped.
  static Future<void> _purgeDiagnosticLogs() async {
    final appSupport = await AppPaths.applicationSupportPath;
    final logsDir = await AppPaths.logsDir;
    final flatLog = File(p.join(appSupport, _deprecatedFlatLogName));
    AppLogger.closeLogSinkForDeletion();
    try {
      if (await logsDir.exists()) {
        await logsDir.delete(recursive: true);
      }
      if (await flatLog.exists()) {
        await flatLog.delete();
      }
      await logsDir.create(recursive: true);
      await AppLogger.openFreshLogSink(await AppPaths.logFilePath);
    } catch (_) {
      await _tryReopenLogSink();
      rethrow;
    }
  }

  static Future<void> _tryReopenLogSink() async {
    try {
      final logsDir = await AppPaths.logsDir;
      await logsDir.create(recursive: true);
      await AppLogger.openFreshLogSink(await AppPaths.logFilePath);
    } catch (_) {}
  }

  /// Removes every failed-message queue belonging to the deleted account.
  ///
  /// WHY THIS SWEEPS INSTEAD OF REMOVING ONE COMPUTED KEY
  /// ---------------------------------------------------
  /// The key is `tencent_cloud_chat_failed_messages_<accountToxId>`, where the
  /// suffix is whatever string the **writer** happened to hold:
  /// `Tim2ToxSdkPlatform._persistFinalizedFailedMessage` passes
  /// `FfiChatService.getSelfToxId()`, i.e. the full **76-char** address.
  /// [toxId] here is whatever the **deletion driver** held — either
  /// `Prefs.getCurrentAccountToxId()` (settings page) or an `account_list`
  /// row's `toxId` (login page).
  ///
  /// Those two are not guaranteed to be the same representation. Imported
  /// accounts persist only the 64-char public key (`ShortToxIdBackfill`'s
  /// F12 background). The backfill upgrades them on login, but it explicitly
  /// gives up and leaves the short form persisted when the FFI has no address
  /// yet, when password-key migration fails, when the `account_list` rewrite
  /// throws, or when the live address is not a prefix-extension — and a
  /// failed `current_account_tox_id` rewrite is *logged and swallowed*,
  /// leaving the pointer short while the session keys new queues under the
  /// 76-char address. `AccountDeletionCoordinator._accountDataRootsForDeletion`
  /// already catches `ArgumentError` for exactly this case ("legacy short IDs
  /// have no full-ID scratch root"), so short IDs demonstrably reach this
  /// stage today.
  ///
  /// With an exact-string removal the 76-char key would then survive, and
  /// nothing else would collect it: `Prefs.clearScopedKeysForAccount` only
  /// removes keys ending in `_<first16>`, which a 76-char suffix does not.
  /// The queue rows carry peer conversation IDs and message text, so that is
  /// a real leak, not cosmetics. Normalising [toxId] *up* to 76 chars at the
  /// entry point is impossible here — nospam+checksum live in the tox
  /// profile, which the earlier `profileDirectory` deletion stage already
  /// removed — so instead we remove every stored key whose suffix is some
  /// representation of this same account.
  static Future<void> _removeFailedMessagePrefs(
    SharedPreferences prefs,
    String toxId,
  ) async {
    // Exact-form removals are kept as-is so behaviour is a strict superset of
    // the previous implementation even for suffixes the sweep rejects (e.g.
    // short non-account IDs used by tests and legacy fixtures).
    final keysToRemove = <String>{_failedMessageKey(toxId)};
    final legacyKey = _legacyFailedMessageKey(toxId);
    if (legacyKey != null) {
      keysToRemove.add(legacyKey);
    }
    for (final key in prefs.getKeys()) {
      final suffix = _failedMessageAccountSuffix(key);
      if (suffix != null && _isSameAccount(suffix, toxId)) {
        keysToRemove.add(key);
      }
    }
    await Future.wait(keysToRemove.map(prefs.remove));
  }

  /// The account-ID suffix of a failed-message queue key, or null when [key]
  /// is not an account-scoped one.
  ///
  /// Only the three shapes `Tim2ToxFailedMessagePersistence._storageKey` /
  /// `_legacyStorageKey` can produce from a real Tox identity are accepted: a
  /// 16-char legacy prefix, a 64-char public key, or a 76-char full address,
  /// hex throughout. Pinning the shape is what keeps the sweep from
  /// truncating some longer, differently-namespaced key down to 64 chars and
  /// mistaking its head for this account.
  ///
  /// The unsuffixed `tencent_cloud_chat_failed_messages` key (rows written
  /// before account scoping existed, still maintained by
  /// `_removeFailedMessagesByIDsForCurrentAccount` with `accountToxId: null`)
  /// is deliberately left alone: it is not attributable to the deleted
  /// account, so removing it during a single-account deletion would destroy a
  /// surviving account's pending sends.
  static String? _failedMessageAccountSuffix(String key) {
    if (!key.startsWith(_failedMessagesKeyPrefix)) return null;
    final suffix = key.substring(_failedMessagesKeyPrefix.length);
    if (suffix.length != _legacyToxIdPrefixLength &&
        suffix.length != _publicKeyLength &&
        suffix.length != _fullAddressLength) {
      return null;
    }
    return _hexOnly.hasMatch(suffix) ? suffix : null;
  }

  /// Whether two Tox ID *representations* name the same account.
  ///
  /// Delegates to [compareToxIds] for the actual rule (equal public keys, or
  /// the legacy 16-char profile prefix against a full public key — a window
  /// deliberately no wider than that, so two distinct accounts sharing a run
  /// of leading hex are not collapsed). Case is folded first because Tox IDs
  /// are hex: two IDs differing only in case are always the same account, so
  /// matching them can widen this sweep but can never over-delete.
  static bool _isSameAccount(String a, String b) {
    return compareToxIds(a.toLowerCase(), b.toLowerCase());
  }

  static Future<void> _removeLegacyCurrentAccountPrefs({
    required SharedPreferences prefs,
    required String toxId,
    required bool deletedCurrentAccount,
  }) async {
    if (!deletedCurrentAccount) return;
    final current = prefs.getString(_currentAccountKey);
    // Bail out only when the pointer names a *different, surviving* account —
    // clearing the globals then would wipe that account's profile.
    if (current != null &&
        current.isNotEmpty &&
        !compareToxIds(current, toxId)) {
      return;
    }
    // Past this point the pointer is absent, empty, or this account. An empty
    // pointer names no account, so it cannot be a survivor's and removing it
    // cannot unseat anyone; it is the same "no owner" verdict we just used to
    // justify clearing the globals. Leaving the key behind as an empty string
    // would contradict that and keep a vestigial entry in a store we have
    // declared clean.
    await Future.wait(<Future<bool>>[
      prefs.remove(_nicknameKey),
      prefs.remove(_statusMessageKey),
      prefs.remove(_avatarPathKey),
      if (current != null) prefs.remove(_currentAccountKey),
    ]);
  }

  static String _failedMessageKey(String toxId) {
    return '${_failedMessagesBase}_$toxId';
  }

  static String? _legacyFailedMessageKey(String toxId) {
    if (toxId.length < _legacyToxIdPrefixLength) return null;
    return '${_failedMessagesBase}_${toxId.substring(0, _legacyToxIdPrefixLength)}';
  }
}
