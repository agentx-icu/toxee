import 'prefs.dart';
import 'tox_utils.dart';

/// Allocates the `account_list` nickname for a newly imported account.
///
/// WHY THIS EXISTS: `Prefs.addAccount` throws
/// `StateError('Nickname already used by another account')` when another row
/// already holds the same trimmed nickname, and that constraint is load-bearing
/// — auto-login and manual login both resolve an account BY NICKNAME
/// (`Prefs.getUniqueAccountByNickname`), so a duplicate makes the account
/// unreachable. It cannot simply be relaxed.
///
/// The bug that motivated this: a `.tox` file carries no nickname that toxee
/// reads back (`importAccountData` returns only the id and the profile bytes),
/// so every `.tox` import fell back to ONE constant default — "Imported
/// account". The first import worked; the SECOND threw, after the profile had
/// already been written to disk, and surfaced as a generic "import failed"
/// dialog. Restoring two `.tox` profiles onto one device was impossible, with
/// no hint as to why.
///
/// [allocate] resolves the collision instead of hitting it: it appends the
/// account's short id, then a numeric suffix, until the name is free. Callers
/// pass the name they WANT (a nickname recovered from a `.zip`'s metadata, or
/// the localized default for a bare `.tox`) and get one that `addAccount` will
/// accept.
abstract final class ImportedAccountName {
  ImportedAccountName._();

  /// Longest nickname this will produce. Keeps the disambiguated name from
  /// growing without bound if a caller passes something already very long.
  static const int maxLength = 64;

  /// A nickname based on [preferred] that no OTHER account currently holds.
  ///
  /// Returns [preferred] unchanged when it is already free, or when the only
  /// row holding it IS [toxId] (re-importing over your own row must not keep
  /// renaming it). Otherwise appends ` (<first 8 hex of toxId>)`, and failing
  /// that ` (<short id> 2)`, ` (<short id> 3)`, … Falls back to a
  /// timestamp-suffixed name in the pathological case where every candidate is
  /// taken, so this never throws and never loops forever.
  static Future<String> allocate({
    required String preferred,
    required String toxId,
  }) async {
    final base = preferred.trim().isEmpty ? 'Imported account' : preferred.trim();
    if (!await _taken(base, toxId)) return base;

    final shortId = _shortId(toxId);
    if (shortId.isNotEmpty) {
      final withId = _clamp('$base ($shortId)');
      if (!await _taken(withId, toxId)) return withId;
      for (var n = 2; n <= 99; n++) {
        final candidate = _clamp('$base ($shortId $n)');
        if (!await _taken(candidate, toxId)) return candidate;
      }
    }
    // Nothing in a 99-deep sweep was free. Rather than throw — which would
    // fail the import the same way the original bug did — fall back to
    // something guaranteed unique.
    return _clamp('$base (${DateTime.now().millisecondsSinceEpoch})');
  }

  /// Whether [nickname] belongs to an account OTHER than [toxId].
  ///
  /// Uses [compareToxIds] for the self-check so a caller holding a 64-char
  /// public key still recognises its own 76-char row (the representations
  /// diverge until `ShortToxIdBackfill` runs) — mirroring the comparison
  /// `Prefs.addAccount` itself performs, so this predicate and that guard
  /// cannot disagree.
  static Future<bool> _taken(String nickname, String toxId) async {
    final matches = await Prefs.getAccountsByNickname(nickname);
    for (final account in matches) {
      if (!compareToxIds(account['toxId'] ?? '', toxId)) return true;
    }
    return false;
  }

  static String _shortId(String toxId) {
    final normalized = toxId.trim();
    if (normalized.length < 8) return normalized;
    return normalized.substring(0, 8).toUpperCase();
  }

  static String _clamp(String value) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);
}
