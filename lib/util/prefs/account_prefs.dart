part of 'package:toxee/util/prefs.dart';

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

/// The registry as stored, plus whether reading it lost anything.
final class _AccountListRead {
  const _AccountListRead(this.rows, {required this.lossy});

  final List<Map<String, String>> rows;

  /// True when at least one row could not be parsed and was dropped, so [rows]
  /// is a RECONSTRUCTION. Publishing it would erase the dropped rows, which is
  /// why [_setAccountListImpl]'s caller refuses unless the raw payload was
  /// durably preserved first.
  final bool lossy;
}

Future<_AccountListRead> _readAccountList(SharedPreferences p) async {
  final accountsJson = p.getString(Prefs._kAccountList);
  if (accountsJson == null || accountsJson.isEmpty) {
    // GROWABLE, and not `const`: callers such as `Prefs.addAccount` build the
    // next registry by mutating what they read. A const literal here is
    // unmodifiable, so registering the very first account threw
    // "Cannot add to an unmodifiable list".
    return _AccountListRead(<Map<String, String>>[], lossy: false);
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
  if (dropped > 0) {
    await _backUpCorruptAccountList(p, accountsJson);
    AppLogger.warn(
      '[Prefs] account_list: dropped $dropped malformed row(s); '
      '${rows.length} kept. Raw payload preserved under '
      '${Prefs._kAccountListCorruptBackup}.',
    );
  }
  return _AccountListRead(rows, lossy: dropped > 0);
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
  if (current.lossy &&
      (p.getString(Prefs._kAccountListCorruptBackup) ?? '').isEmpty) {
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
  await p.setString(Prefs._kAccountList, jsonEncode(accounts));
}

/// Preserve the raw payload once, before anything can overwrite it.
///
/// Only the FIRST corruption is kept: a later well-meaning write must not push
/// the original out of the backup slot. Confirmed with a reload because
/// `SharedPreferences` updates its cache before the platform write completes,
/// so an unchecked `setString` can leave a cached value that merely looks
/// durable.
Future<void> _backUpCorruptAccountList(
  SharedPreferences p,
  String rawPayload,
) async {
  try {
    if ((p.getString(Prefs._kAccountListCorruptBackup) ?? '').isNotEmpty) {
      return;
    }
    final wrote = await p.setString(
      Prefs._kAccountListCorruptBackup,
      rawPayload,
    );
    if (!wrote) {
      AppLogger.warn(
        '[Prefs] account_list: could not preserve the corrupt payload; a lossy '
        'rewrite will be refused',
      );
    }
  } catch (e) {
    AppLogger.warn(
      '[Prefs] account_list: preserving the corrupt payload threw '
      '(${e.runtimeType}); a lossy rewrite will be refused',
    );
  }
}
