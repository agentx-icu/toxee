/// Shared key-scoping helper for account-scoped SharedPreferences storage.
///
/// Historically two parallel implementations of this same `${key}_${prefix}`
/// pattern existed:
///
///   * `Prefs._scopedKey` in `lib/util/prefs.dart`
///   * `SharedPreferencesAdapter._prefixKey` in `lib/adapters/shared_prefs_adapter.dart`
///
/// They could drift silently — fixing a bug in one didn't fix the other.
/// X2 from `docs/designs/local-storage-review-2026-05-18.md` calls for a
/// single shared helper. Both call sites now delegate here.
///
/// Contract:
///   * [accountPrefix] is passed through verbatim (callers are responsible
///     for any truncation, e.g. `Prefs` truncates the toxId to 16 chars
///     before calling).
///   * When [accountPrefix] is null or empty, [rawKey] is returned unchanged
///     (no scope applied — used for global keys and legacy/unscoped fallback).
///   * Otherwise, returns `'${rawKey}_${accountPrefix}'` — the format that
///     both legacy call sites produced, kept byte-identical so existing
///     on-disk SharedPreferences entries continue to be found.
String scopedPrefsKey(String rawKey, String? accountPrefix) {
  if (accountPrefix == null || accountPrefix.isEmpty) return rawKey;
  return '${rawKey}_$accountPrefix';
}

/// Number of leading Tox-ID characters used as the account scope suffix.
/// Mirrors `Prefs._scopedKey`, `Prefs.clearScopedKeysForAccount`,
/// `SharedPreferencesAdapter.clear`, and `PrefsUpgrader`.
const int scopedPrefsAccountPrefixLength = 16;

/// Truncate a Tox ID to the account scope prefix used by every scoped key.
///
/// Returns null for a null/empty id — callers MUST treat that as "no scope
/// available", never as "write the unscoped key" (see the recvOpt builders
/// below for why an unscoped key is unrecoverable).
String? scopedPrefsAccountPrefix(String? accountToxId) {
  if (accountToxId == null || accountToxId.isEmpty) return null;
  return accountToxId.length >= scopedPrefsAccountPrefixLength
      ? accountToxId.substring(0, scopedPrefsAccountPrefixLength)
      : accountToxId;
}

// ---------------------------------------------------------------------------
// Per-peer / per-group receive-message-option (mute / do-not-disturb) keys.
//
// THE SLOT HAS TWO INDEPENDENT ADDRESSERS and they must agree byte-for-byte:
//
//   * `Prefs.get/setC2CReceiveMessageOpt` + `get/setGroupReceiveMessageOpt`
//     — the UI/read side.
//   * `SharedPreferencesAdapter.get/setC2CReceiveMessageOpt` +
//     `get/setGroupReceiveMessageOpt` — the object toxee injects into tim2tox
//     as `ExtendedPreferencesService`, i.e. the platform WRITE side
//     (`Tim2ToxSdkPlatform.setC2CReceiveMessageOpt`) and a platform READ side
//     (`tim2tox_sdk_platform_converters._mapConv`, `getGroupsInfo`).
//
// tim2tox itself never builds these key strings — it only calls the interface
// — so this file is the single source of truth for the on-disk shape, and no
// cross-repo change is needed to alter it.
//
// ID REPRESENTATION — deliberately VERBATIM, no normalisation:
//   * No case folding. Every producer that feeds these keys emits UPPERCASE
//     hex (`%02X` in `V2TIMFriendshipManagerImpl`, `V2TIMConversationManagerImpl`,
//     `ToxUtil.h`/`ToxUtils.h`), so there is no case split to repair; folding
//     here would orphan every existing entry for no benefit.
//   * No 64-char truncation. [c2cRecvOptPrefsKey] and [groupRecvOptPrefsKey]
//     share one shape, and the group id is NOT a Tox public key — truncating
//     it could collapse two distinct groups onto one mute. The 76-vs-64 Tox
//     address hazard is handled one layer up in `C2CRecvOptCache`, which
//     normalises before it calls in here AND migrates any entry an older build
//     parked under the longer id.
// ---------------------------------------------------------------------------

/// SharedPreferences key for the per-peer C2C receive option.
/// [accountPrefix] must already be truncated (see [scopedPrefsAccountPrefix]).
String c2cRecvOptPrefsKey(String userID, String? accountPrefix) =>
    scopedPrefsKey('c2c_recv_opt_$userID', accountPrefix);

/// SharedPreferences key for the per-group receive option. Tox has no native
/// group recv-opt, so this key IS the source of truth for group mute.
/// [accountPrefix] must already be truncated (see [scopedPrefsAccountPrefix]).
String groupRecvOptPrefsKey(String groupID, String? accountPrefix) =>
    scopedPrefsKey('group_recv_opt_$groupID', accountPrefix);
