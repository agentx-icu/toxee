part of 'package:toxee/util/prefs.dart';

// Secure-storage secrets owned by one account, and how account deletion gets rid
// of them. Split out of `prefs.dart` (complexity-gate pin); a `part` so it can
// reach `Prefs`'s private key builders and `_secureDelete`.

/// See `Prefs.purgeAccountSecureSecrets`.
///
/// ORDERING CONSTRAINT: this MUST run before the deletion's prefs stage clears
/// `irc_channels_<prefix>` — that list is the only record of which channels to
/// look up, so afterwards there is nothing left to enumerate and the secrets
/// stay on the device forever.
///
/// Takes an explicit [toxId] rather than reading the active account: deletion
/// runs for non-current accounts too (the login-page path has no session at
/// all), and the "current account" convention every other IRC accessor uses
/// would purge the wrong scope, or nothing.
///
/// Returns false when any delete was refused, so the caller can leave the
/// deletion tombstone pending and retry rather than declaring success over
/// secrets that are still there.
Future<bool> purgeAccountSecureSecretsImpl(String toxId) async {
  final normalized = toxId.trim();
  if (normalized.isEmpty) return true;
  final p = await Prefs._getPrefs();
  final channels = await _getIrcChannelsImpl(
    p,
    Prefs._scopedKey(Prefs._kIrcChannels, normalized),
  );
  var allDeleted = true;
  for (final channel in channels) {
    final key = Prefs._scopedKey(Prefs._ircChannelPasswordKey(channel), normalized);
    if (!await Prefs._secureDelete(key)) allDeleted = false;
  }
  return allDeleted;
}
