import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_paths.dart';
import 'logger.dart';
import 'prefs.dart';

// Storage form of a group avatar path (the `group_avatar_<id>` pref).
//
// Group avatars live in the per-account avatars directory
// (`<appSupport>/account_data/<prefix>/avatars`, see
// [AppPaths.getAccountAvatarsPath]). That directory's ABSOLUTE path is not
// stable on iOS: the app container (its UUID segment) changes on reinstall /
// update / backup restore, so a stored absolute path points into a container
// that no longer exists and the avatar silently falls back to the
// placeholder. The pref therefore stores the path RELATIVE to the account
// avatars dir and re-anchors it on read.
//
// Values written before this change are absolute; [resolveStoredGroupAvatar]
// keeps them working and re-anchors a dead one onto the current avatars dir.
// Anything that is not a file under an account avatars dir (a URL, a file
// elsewhere) is stored and returned verbatim.
//
// Encoding is PURE string work on the `account_data/<prefix>/avatars` tail —
// no filesystem or path_provider round trip — so writing the pref costs
// nothing extra (and cannot stall a caller running under fake async).

/// The part of [path] below an `account_data/<prefix>/avatars` directory, or
/// null when [path] is not inside one (or, with [accountPrefix], not inside
/// THAT account's one).
String? avatarsRelativePart(String path, {String? accountPrefix}) {
  if (path.isEmpty || !p.isAbsolute(path)) return null;
  final parts = p.split(path);
  for (var i = parts.length - 2; i >= 2; i--) {
    if (parts[i] != 'avatars' || parts[i - 2] != 'account_data') continue;
    if (accountPrefix != null && parts[i - 1] != accountPrefix) return null;
    return p.joinAll(parts.sublist(i + 1));
  }
  return null;
}

/// First 16 chars of a Tox ID — the `<prefix>` of the account data dir.
String accountDirPrefix(String toxId) {
  final t = toxId.trim();
  return t.length >= 16 ? t.substring(0, 16) : t;
}

String toStoredGroupAvatar(String path, String accountPrefix) =>
    avatarsRelativePart(path, accountPrefix: accountPrefix) ?? path;

/// Inverse of [toStoredGroupAvatar] against the CURRENT [avatarsDir].
/// [exists] is injectable for tests.
String resolveStoredGroupAvatar(
  String stored,
  String avatarsDir, {
  bool Function(String path)? exists,
}) {
  if (stored.isEmpty || stored.contains('://')) return stored;
  if (!p.isAbsolute(stored)) return p.join(avatarsDir, stored);
  final fileExists = exists ?? (String path) => File(path).existsSync();
  if (fileExists(stored)) return stored;
  // Legacy absolute path into a container that moved: the file itself was
  // carried along inside the avatars dir, only the prefix changed.
  final tail = avatarsRelativePart(stored);
  if (tail == null) return stored;
  final rebased = p.join(avatarsDir, tail);
  return fileExists(rebased) ? rebased : stored;
}

/// Cached per call chain by [AppPaths]; named so the migration and the
/// resolution cannot drift onto different roots.
Future<String> _avatarsDir(String toxId) =>
    AppPaths.getAccountAvatarsPath(toxId);

Future<String?> _currentToxId(String? accountToxId) async =>
    (accountToxId == null || accountToxId.isEmpty)
    ? await Prefs.getCurrentAccountToxId()
    : accountToxId;

/// Pref value to write for [faceUrl] (see [toStoredGroupAvatar]).
/// [accountToxId] may be the full Tox ID or its 16-char prefix.
Future<String> encodeGroupAvatarForStorage(
  String faceUrl,
  String? accountToxId,
) async {
  final id = await _currentToxId(accountToxId);
  if (id == null || id.isEmpty) return faceUrl;
  return toStoredGroupAvatar(faceUrl, accountDirPrefix(id));
}

/// Usable path for a stored pref value (see [resolveStoredGroupAvatar]).
/// Only touches [AppPaths] when the value actually needs anchoring (relative,
/// or a missing legacy avatars-dir path) — plain absolute paths and URLs are
/// answered without it.
/// [rewriteLegacy], when given, is called ONCE with the relative form of a
/// legacy absolute value (see [migratedGroupAvatarStorage]) so the caller can
/// persist it: every later read then skips the `existsSync` this one pays.
Future<String?> decodeStoredGroupAvatar(
  String? stored,
  String? accountToxId, {
  Future<void> Function(String value)? rewriteLegacy,
}) async {
  if (stored == null || stored.isEmpty || stored.contains('://')) {
    return stored;
  }
  if (p.isAbsolute(stored) && avatarsRelativePart(stored) == null) {
    return stored; // not ours: returned verbatim, no stat
  }
  final absoluteAndPresent = p.isAbsolute(stored) && File(stored).existsSync();
  try {
    final id = await _currentToxId(accountToxId);
    if (id == null || id.isEmpty) return stored;
    final resolved = absoluteAndPresent
        ? stored
        : resolveStoredGroupAvatar(stored, await _avatarsDir(id));
    if (rewriteLegacy != null) {
      final migrated = migratedGroupAvatarStorage(
          stored, resolved, accountDirPrefix(id), await _avatarsDir(id));
      if (migrated != null) await rewriteLegacy(migrated);
    }
    return resolved;
  } on Object catch (e) {
    AppLogger.warn('[GroupAvatar] returning stored path verbatim: $e');
    return stored;
  }
}

/// The value [stored] should be REWRITTEN to, or null to leave it alone.
///
/// A legacy absolute path inside an account avatars dir costs a synchronous
/// `existsSync` on every read (every conversation-list rebuild, per group).
/// Rewriting it to the relative form once removes that stat for good, and
/// makes the value survive the next iOS container move like a fresh one.
/// Only rewritten when the resolved file is actually there: a path whose file
/// is temporarily unavailable keeps its absolute value rather than being
/// turned into a relative path under a directory it was never in.
String? migratedGroupAvatarStorage(
  String stored,
  String? resolved,
  String accountPrefix,
  String avatarsDir, {
  bool Function(String path)? exists,
}) {
  if (resolved == null || resolved.isEmpty) return null;
  if (!p.isAbsolute(stored) || stored.contains('://')) return null;
  if (avatarsRelativePart(stored) == null) return null; // not ours to rewrite
  final relative = toStoredGroupAvatar(resolved, accountPrefix);
  if (relative == resolved || relative.isEmpty) return null;
  final fileExists = exists ?? (String path) => File(path).existsSync();
  // Check what the relative form will RESOLVE TO, not the absolute value we
  // started from: when the stored path sits under a different avatars root
  // than the account's current one, rewriting would turn a working absolute
  // value into a relative one pointing at a file that is not there.
  return fileExists(p.join(avatarsDir, relative)) ? relative : null;
}

/// [store]-backed [decodeStoredGroupAvatar]: resolves the value at [key] and
/// migrates a legacy absolute one in place.
///
/// The write is skipped when the pref changed while this was resolving (two
/// awaits), so a `setGroupAvatar` that landed in that window is not clobbered
/// by the migration.
Future<String?> decodeStoredGroupAvatarFromPrefs(
  SharedPreferences store,
  String key,
  String accountToxId,
) async {
  final stored = store.getString(key);
  return decodeStoredGroupAvatar(stored, accountToxId,
      rewriteLegacy: (value) async {
    if (store.getString(key) == stored) await store.setString(key, value);
  });
}
