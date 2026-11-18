part of 'package:toxee/util/prefs.dart';

Future<void> _reloadAccountPreferences(SharedPreferences prefs) async {
  if (!await _serializedRegistry(
    () => _refreshAccountRegistryCache(prefs, force: true),
  )) {
    throw StateError('Account preferences could not be reloaded');
  }
}

Future<void> _removeAccountPreferenceKeys(
  SharedPreferences prefs,
  Iterable<String> candidates,
) async {
  final keys = candidates.where(prefs.containsKey).toList();
  try {
    final removed = await Future.wait([for (final key in keys) prefs.remove(key)]);
    if (removed.contains(false)) {
      throw StateError('Account preference removal was refused');
    }
  } catch (_) {
    // SharedPreferences removes from its cache before the platform replies.
    try {
      await _reloadAccountPreferences(prefs);
    } catch (error) {
      AppLogger.warn('Account preference reload failed (${error.runtimeType})');
    }
    rethrow;
  }
}

// Account list (implementation helper used by Prefs)
//
// CORRUPTION POLICY — read before changing the error handling.
//
// This used to `return []` on ANY decode or cast failure, which conflated two
// very different states: "no accounts have been registered" and "the registry
// is unreadable". Every caller reads it as the former, so one malformed row
// made every account disappear from the picker — and the next `addAccount`
// then wrote a single-row list back over the original JSON, destroying the
// other rows for good. The rows hold the only mapping from nickname to Tox ID,
// and an encrypted account cannot be rebuilt by `AccountReconciliation` (it
// skips profiles it cannot decrypt), so that was unrecoverable data loss.
//
// Now:
//   * a row that does not fit `Map<String, String>` is dropped individually,
//     the rest are kept, and the loss is logged;
//   * a payload that is not decodable JSON at all raises
//     [AccountRegistryUnreadableException] rather than masquerading as empty,
//     and a one-time backup of the raw string is kept under
//     [Prefs._kAccountListCorruptBackup] so nothing is destroyed;
//   * writes refuse to publish over a registry that could not be read, so a
//     transient decode failure cannot be laundered into a permanent overwrite.

/// Raised when `account_list` holds a payload that cannot be parsed at all.
///
/// Deliberately NOT swallowed into an empty list: callers that would show "no
/// accounts" must instead surface a problem, because the alternative is
/// overwriting the only copy of the registry.
final class AccountRegistryUnreadableException implements Exception {
  const AccountRegistryUnreadableException(this.detail);

  /// Sanitized reason. Never the payload itself — the rows contain Tox IDs and
  /// nicknames, and this message reaches `flutter_client.log`.
  final String detail;

  @override
  String toString() => 'AccountRegistryUnreadableException: $detail';
}

/// The backing store declined to persist an account-registry update.
final class AccountRegistryWriteException implements Exception {
  const AccountRegistryWriteException();

  @override
  String toString() => 'Account registry write was refused';
}

/// Raised by [Prefs.setCurrentAccountToxId] when the store refused the write.
///
/// The durable pointer still names whatever it named before, so the session the
/// caller is setting up is NOT the one a cold start would restore. Callers roll
/// back (or abort) instead of running on that disagreement; teardown paths that
/// can do nothing about it log and continue.
final class CurrentAccountPointerFailure implements Exception {
  const CurrentAccountPointerFailure(this.intended);

  /// The Tox ID the pointer should now hold, or null for "no active account".
  final String? intended;

  @override
  String toString() =>
      'CurrentAccountPointerFailure: could not persist the current-account '
      'pointer (${intended ?? 'cleared'})';
}

/// The registry as stored, plus whether reading it lost anything.
final class _AccountListRead {
  const _AccountListRead(this.rows, {this.canRewrite = true});

  final List<Map<String, String>> rows;

  /// A partially parsed registry may be rewritten once its raw payload is
  /// durably preserved.
  final bool canRewrite;
}

Future<_AccountListRead> _readAccountList(SharedPreferences p) async {
  if (!await _refreshAccountRegistryCache(p)) {
    throw const AccountRegistryUnreadableException(
      'could not reload the account registry after a failed write',
    );
  }
  final accountsJson = p.getString(Prefs._kAccountList);
  if (accountsJson == null || accountsJson.isEmpty) {
    // GROWABLE, and not `const`: callers such as `Prefs.addAccount` build the
    // next registry by mutating what they read. A const literal here is
    // unmodifiable, so registering the very first account threw
    // "Cannot add to an unmodifiable list".
    return _AccountListRead(List<Map<String, String>>.empty(growable: true));
  }
  Object? decoded;
  try {
    decoded = jsonDecode(accountsJson);
  } catch (e) {
    await _backUpCorruptAccountList(p, accountsJson);
    throw AccountRegistryUnreadableException(
      'account_list is not decodable JSON (${e.runtimeType})',
    );
  }
  if (decoded is! List) {
    await _backUpCorruptAccountList(p, accountsJson);
    throw const AccountRegistryUnreadableException(
      'account_list is not a JSON array',
    );
  }
  final rows = <Map<String, String>>[];
  var dropped = 0;
  for (final entry in decoded) {
    try {
      final row = Map<String, String>.from(entry as Map);
      // A row with no usable primary key cannot be acted on by any caller
      // (every lookup is by toxId), so it is noise rather than an account.
      if ((row['toxId'] ?? '').trim().isEmpty) {
        dropped++;
        continue;
      }
      rows.add(row);
    } catch (_) {
      dropped++;
    }
  }
  if (dropped == 0) return _AccountListRead(rows);

  final preserved = await _backUpCorruptAccountList(p, accountsJson);
  AppLogger.warn(
    '[Prefs] account_list: dropped $dropped malformed row(s); '
    '${rows.length} kept, backup available: $preserved',
  );
  return _AccountListRead(rows, canRewrite: preserved);
}

/// Whether [toxId] is in the registry, answered without trusting the parsed
/// rows: [_readAccountList] DROPS malformed rows, so "not in the decoded list"
/// does not prove absence. Callers that would destroy something on absence
/// (e.g. `StrandedVerifierCleanup`) must act only on [absent].
enum AccountRegistryPresence {
  /// Some row names this identity (full address, 64-char public key or the
  /// 16-char legacy form), whether or not the rest of the row decodes.
  present,

  /// The payload decodes as a JSON array, every row carries a readable
  /// `toxId`, and none of them is this identity.
  absent,

  /// The payload cannot be decoded, or some row's identity cannot be read,
  /// so absence cannot be proven.
  unknown,
}

/// Identity equivalence as the registry stores it: a row may hold the 76-char
/// address, the 64-char public key (imports) or the 16-char legacy prefix, so
/// two ids are the same identity when they agree over the shorter of the two —
/// capped at the 64-char public key, because the nospam + checksum suffix can
/// change while the identity (and its verifier alias, keyed by public key)
/// stays the same; never shorter than the 16-char prefix the on-disk layout
/// is keyed by.
bool _sameRegistryIdentity(String a, String b) {
  var n = a.length < b.length ? a.length : b.length;
  if (n > 64) n = 64;
  if (n < 16) return a == b;
  return a.substring(0, n) == b.substring(0, n);
}

Future<AccountRegistryPresence> _accountRegistryPresenceImpl(
  SharedPreferences p,
  String toxId,
) async {
  final wanted = toxId.trim().toUpperCase();
  if (wanted.isEmpty || !await _refreshAccountRegistryCache(p)) {
    return AccountRegistryPresence.unknown;
  }
  final accountsJson = p.getString(Prefs._kAccountList);
  if (accountsJson == null || accountsJson.isEmpty) {
    return AccountRegistryPresence.absent;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(accountsJson);
  } catch (_) {
    return AccountRegistryPresence.unknown;
  }
  if (decoded is! List) return AccountRegistryPresence.unknown;
  // Inspect the identity field of each row directly, never through the
  // `Map<String, String>` cast the decoder applies to whole rows: a row with a
  // valid toxId and, say, a numeric nickname is still that account.
  var ambiguous = false;
  for (final row in decoded) {
    if (row is! Map) {
      ambiguous = true;
      continue;
    }
    final id = row['toxId'];
    if (id is! String) {
      ambiguous = true;
      continue;
    }
    final rowId = id.trim().toUpperCase();
    // No usable key: noise, not an account (the decoder drops it too).
    if (rowId.isEmpty) continue;
    if (_sameRegistryIdentity(rowId, wanted)) {
      return AccountRegistryPresence.present;
    }
  }
  return ambiguous
      ? AccountRegistryPresence.unknown
      : AccountRegistryPresence.absent;
}

Future<List<Map<String, String>>> _getAccountListImpl(
  SharedPreferences p,
) async {
  return (await _readAccountList(p)).rows;
}

/// Publish [accounts], refusing when the current payload cannot be read or when
/// reading it lost rows that were not durably preserved.
///
/// Every mutating caller builds its new list from the read, so publishing over
/// an unreadable or lossily-read payload destroys whatever did not parse. The
/// rows are the only nickname -> Tox ID mapping and an encrypted account cannot
/// be rebuilt by `AccountReconciliation`, so that loss is permanent.
Future<void> _setAccountListGuarded(
  SharedPreferences p,
  List<Map<String, String>> accounts,
) async {
  final current = await _readAccountList(p); // throws when unreadable
  if (!current.canRewrite) {
    // The backup write is what makes a lossy rewrite survivable. Without it the
    // dropped rows would be gone for good.
    throw const AccountRegistryUnreadableException(
      'refusing to publish a partially-parsed account_list: the original '
      'payload could not be preserved',
    );
  }
  await _setAccountListImpl(p, accounts);
}

Future<void> _setAccountListImpl(
  SharedPreferences p,
  List<Map<String, String>> accounts,
) async {
  if (!await _writeAccountRegistryString(
    p,
    Prefs._kAccountList,
    jsonEncode(accounts),
  )) {
    throw const AccountRegistryWriteException();
  }
}

/// Preserve the raw payload once, before anything can overwrite it.
///
/// Only the FIRST corruption is kept: a later well-meaning write must not push
/// the original out of the backup slot. Readers outside the registry gate
/// also attempt this backup, so serialize it before trusting the cached slot.
final _accountRegistryBackupGate = AsyncGate();

Future<bool> _backUpCorruptAccountList(
  SharedPreferences p,
  String rawPayload,
) => _accountRegistryBackupGate.run(() async {
  if (!await _refreshAccountRegistryCache(p)) return false;
  try {
    if ((p.getString(Prefs._kAccountListCorruptBackup) ?? '').isNotEmpty) {
      return true;
    }
    final wrote = await _writeAccountRegistryString(
      p,
      Prefs._kAccountListCorruptBackup,
      rawPayload,
    );
    if (!wrote) {
      AppLogger.warn(
        '[Prefs] account_list: could not preserve the corrupt payload; a lossy '
        'rewrite will be refused',
      );
    }
    return wrote;
  } catch (e) {
    AppLogger.warn(
      '[Prefs] account_list: preserving the corrupt payload threw '
      '(${e.runtimeType}); a lossy rewrite will be refused',
    );
    return false;
  }
});

// SharedPreferences updates its cache before the platform write returns.
// Require a successful reload before reading either key again after a failure.
final _accountRegistryNeedsReload = Expando<bool>();
final _accountRegistryReloads = Expando<Future<bool>>();

Future<bool> _writeAccountRegistryString(
  SharedPreferences prefs,
  String key,
  String value,
) async {
  var wrote = false;
  try {
    wrote = await prefs.setString(key, value);
    return wrote;
  } finally {
    if (!wrote) _accountRegistryNeedsReload[prefs] = true;
  }
}

Future<bool> _refreshAccountRegistryCache(
  SharedPreferences prefs, {
  bool force = false,
}) async {
  final pending = _accountRegistryReloads[prefs];
  if (pending != null) return pending;
  if (!force && _accountRegistryNeedsReload[prefs] != true) return true;
  final reload = _reloadAccountRegistryCache(prefs);
  _accountRegistryReloads[prefs] = reload;
  return reload;
}

Future<bool> _reloadAccountRegistryCache(SharedPreferences prefs) async {
  try {
    await prefs.reload();
    _accountRegistryNeedsReload[prefs] = null;
    return true;
  } catch (_) {
    return false;
  } finally {
    _accountRegistryReloads[prefs] = null;
  }
}
