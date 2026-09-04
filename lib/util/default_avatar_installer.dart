import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_paths.dart';
import 'logger.dart';
import 'prefs.dart';
import 'prefs/scoped_key.dart';
import 'tox_utils.dart';

abstract final class DefaultAvatarInstaller {
  static const String defaultUserAsset = 'assets/avatars/default_user.png';
  static const String defaultGroupAsset = 'assets/avatars/default_group.png';

  /// Base of the account-scoped key under which Tim2Tox's preferences
  /// adapter (`SharedPreferencesAdapter.setAvatarPath`) stores the self
  /// avatar: `self_avatar_path_<first16>`. Kept in sync with the adapter and
  /// with `Prefs.getAvatarPath`, which falls back to the same key.
  static const String _kSelfAvatarPathBase = 'self_avatar_path';

  static Future<String> installDefaultUserAvatar({
    required String toxId,
    AssetBundle? bundle,
  }) async {
    final avatarsDirPath = await AppPaths.getAccountAvatarsPath(toxId);
    final destPath = p.join(avatarsDirPath, 'avatar_${toxId}_default.png');
    await _writeAsset(
      assetPath: defaultUserAsset,
      destPath: destPath,
      bundle: bundle ?? rootBundle,
    );
    return destPath;
  }

  /// Guarantee that the account [toxId] has a self avatar and that BOTH
  /// stores agree on it: the `account_list` row (what `Prefs.getAvatarPath()`
  /// and every toxee surface read) and the service-scoped
  /// `self_avatar_path_<prefix>` key (what Tim2Tox reads for message bubbles
  /// and for pushing the avatar to friends).
  ///
  /// Only `AccountService.register` used to install the bundled default;
  /// accounts that were recovered from an orphaned profile, imported from a
  /// `.tox` file, restored from a full backup, or logged in through the
  /// legacy path never got one. Such an account then rendered differently on
  /// every surface (stock photo in the sidebar, initial in the profile page,
  /// contact silhouette in message bubbles). This runs at every account
  /// activation, so the state can never persist.
  ///
  /// Resolution order — the first existing file wins:
  ///   1. the `account_list` row's `avatarPath`;
  ///   2. the scoped `self_avatar_path_<prefix>` key (a full-backup restore
  ///      repopulates it without touching the row);
  ///   3. the newest self-avatar file already in the account's avatars
  ///      directory (`avatar_<publicKey>*` / `self_avatar*`, any extension —
  ///      the picker keeps the source extension and older writers used the
  ///      64-char public key where newer ones use the 76-char address);
  ///   4. a fresh copy of the bundled default.
  ///
  /// Never throws: on failure it logs, leaves whatever is stored, and returns
  /// null, so account activation is never blocked by an avatar.
  static Future<String?> ensureSelfAvatar({
    required String toxId,
    AssetBundle? bundle,
  }) async {
    final normalizedId = toxId.trim();
    if (normalizedId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final scopedKey = scopedPrefsKey(
        _kSelfAvatarPathBase,
        _accountPrefixOf(normalizedId),
      );

      final row = await Prefs.getAccountByToxId(normalizedId);
      String? resolved = await _existingFile(row?['avatarPath']);
      resolved ??= await _existingFile(prefs.getString(scopedKey));
      resolved ??= await _newestSelfAvatarOnDisk(normalizedId);
      resolved ??= await installDefaultUserAvatar(
        toxId: normalizedId,
        bundle: bundle,
      );

      // Write through to both stores. `Prefs.setAccountAvatarPath` is a
      // no-op when the row does not exist yet (e.g. a first login that adds
      // the row afterwards); `Prefs.getAvatarPath` then still finds the
      // scoped key, so the two readers never disagree.
      await Prefs.setAccountAvatarPath(normalizedId, resolved);
      await prefs.setString(scopedKey, resolved);
      return resolved;
    } catch (e, st) {
      AppLogger.logError(
        '[DefaultAvatarInstaller] ensureSelfAvatar failed for '
        'prefix=${_accountPrefixOf(normalizedId)}',
        e,
        st,
      );
      return null;
    }
  }

  static String _accountPrefixOf(String toxId) =>
      toxId.length >= 16 ? toxId.substring(0, 16) : toxId;

  static Future<String?> _existingFile(String? path) async {
    if (path == null || path.isEmpty) return null;
    return await File(path).exists() ? path : null;
  }

  /// Newest `avatar_<publicKey>*` / `self_avatar*` file in the account's
  /// avatars directory, or null. Friend and group avatars share that
  /// directory and are skipped by prefix.
  static Future<String?> _newestSelfAvatarOnDisk(String toxId) async {
    final dir = Directory(await AppPaths.getAccountAvatarsPath(toxId));
    if (!await dir.exists()) return null;
    final publicKey = normalizeToxId(toxId).toUpperCase();
    File? newest;
    DateTime? newestModified;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!_isSelfAvatarFileName(p.basename(entity.path), publicKey)) {
        continue;
      }
      final modified = (await entity.stat()).modified;
      if (newestModified == null || modified.isAfter(newestModified)) {
        newest = entity;
        newestModified = modified;
      }
    }
    return newest?.path;
  }

  static bool _isSelfAvatarFileName(String fileName, String publicKey) {
    if (fileName.startsWith('self_avatar')) return true;
    const prefix = 'avatar_';
    if (!fileName.startsWith(prefix)) return false;
    final idPart = fileName.substring(prefix.length);
    if (idPart.length < publicKey.length) return false;
    return idPart.substring(0, publicKey.length).toUpperCase() == publicKey;
  }

  static Future<String> installDefaultGroupAvatar({
    required String groupId,
    String? toxId,
    AssetBundle? bundle,
  }) async {
    final effectiveToxId = toxId?.trim().isNotEmpty == true
        ? toxId!.trim()
        : await Prefs.getCurrentAccountToxId();
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      throw StateError(
        'Cannot install default group avatar without an account',
      );
    }
    final avatarsDirPath = await AppPaths.getAccountAvatarsPath(effectiveToxId);
    final safeGroupId = _sanitizeSegment(groupId);
    final destPath = p.join(avatarsDirPath, 'group_${safeGroupId}_default.png');
    await _writeAsset(
      assetPath: defaultGroupAsset,
      destPath: destPath,
      bundle: bundle ?? rootBundle,
    );
    return destPath;
  }

  static Future<void> _writeAsset({
    required String assetPath,
    required String destPath,
    required AssetBundle bundle,
  }) async {
    final destFile = File(destPath);
    await destFile.parent.create(recursive: true);
    final bytes = await bundle.load(assetPath);
    await destFile.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
  }

  static String _sanitizeSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
