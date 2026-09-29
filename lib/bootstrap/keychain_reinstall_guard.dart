import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../util/app_paths.dart';
import '../util/logger.dart';

/// Keychain operations the guard needs, with explicit failure (the
/// `toxee/keychain_probe` channel in `ios/Runner/AppDelegate.swift`).
/// flutter_secure_storage's own deleteAll/readAll are not used: on iOS it turns
/// a locked Keychain's read error into "no value" (checklist B9), so an empty
/// answer would be indistinguishable from a refused one.
abstract class KeychainMaintenance {
  /// Delete every item of the secure-storage service; false when refused.
  Future<bool> wipeAll();

  /// Every key (item account name) of the service; throws when refused.
  Future<List<String>> listKeys();

  /// Delete these keys; false when any delete was refused.
  Future<bool> deleteKeys(List<String> keys);
}

class _ChannelKeychainMaintenance implements KeychainMaintenance {
  const _ChannelKeychainMaintenance();

  static const MethodChannel _channel = MethodChannel('toxee/keychain_probe');

  @override
  Future<bool> wipeAll() async =>
      await _channel.invokeMethod<String>('wipeAll') == 'ok';

  @override
  Future<List<String>> listKeys() async =>
      (await _channel.invokeListMethod<String>('listKeys')) ?? const [];

  @override
  Future<bool> deleteKeys(List<String> keys) async =>
      await _channel.invokeMethod<String>('deleteKeys', {'keys': keys}) ==
      'ok';
}

/// Drops the secure-storage items a PREVIOUS installation left in the iOS
/// Keychain (P3, doc/reference/MOBILE_DEVICE_FEATURES.md).
///
/// Deleting an iOS app removes its container — SharedPreferences, profiles,
/// history — but not its Keychain items. A reinstall therefore starts with no
/// accounts yet still holds the old accounts' password verifiers
/// (`pwd_<toxId>` / `pwd_salt_<toxId>`) and IRC channel passwords
/// (`irc_channel_password_<channel>_<toxId prefix>`). Reproduced on the
/// simulator: restoring an unprotected `.tox` of such an account made it
/// silently demand the old installation's password after the first logout.
///
/// First launch of this build on an installation ([markerKey] unset):
/// * FRESH — no account registry (nor a preserved corrupt one), no current
///   account pointer, and no profile on disk (profile roots, the legacy
///   `tim2tox/tox_profile_*.tox`): every item is orphaned, wipe them all.
/// * otherwise (an upgrade — possibly of an installation that was itself a
///   reinstall and still carries an older one's items — or a container with
///   profiles that reconciliation will recover): delete only the items no
///   registered account and no on-disk profile owns (by the 16-char toxId
///   prefix the keys and profile directories carry); unknown keys are kept.
///   With an unreadable registry nothing is deleted and the run stays pending.
///
/// The marker goes to `pending` BEFORE the cleanup and to `done` only after
/// the Keychain confirmed it, so a refused cleanup is retried on every launch
/// (as the fresh wipe while still fresh, otherwise as the orphan sweep).
/// Residual, documented: restoring the SAME account while a refused fresh
/// wipe is still pending keeps its old verifier — it needs the Keychain to
/// refuse a foreground first launch.
///
/// iOS only. Android deletes the Keystore keys and the plugin's encrypted prefs
/// on uninstall, and backups are off (`android:allowBackup="false"`). Desktop
/// keychains do outlive app data too, but there several harness instances share
/// one keychain under different prefs prefixes, so a wipe keyed on one
/// instance's prefs would destroy another's secrets.
class KeychainReinstallGuard {
  KeychainReinstallGuard._();

  static const String markerKey = 'secure_store_install_marker';
  static const String _pending = 'pending';
  static const String _done = 'done';

  // Registry keys, mirrored from `Prefs` (private there).
  static const String _accountListKey = 'account_list';
  static const String _accountListCorruptBackupKey =
      'account_list_corrupt_backup';
  // Written before the registry row on some paths: its presence alone proves
  // an account existed (a crash between the two leaves an empty registry).
  static const String _currentAccountKey = 'current_account_tox_id';
  static const int _ownerPrefixLength = 16; // AppPaths p_<first 16>, scoped keys
  static const String _verifierSaltPrefix = 'pwd_salt_';
  static const String _verifierPrefix = 'pwd_';
  static const String _ircPasswordPrefix = 'irc_channel_password_';

  /// Run after `Prefs.initialize` (the profile root may be a custom one) and
  /// after `PrefsUpgrader` accepted the stored schema (a downgrade from a newer
  /// build must not be judged by this build's idea of the registry), before
  /// anything reads secure storage (`PrefsBootstrap.initialize`).
  static Future<void> run(
    SharedPreferences prefs, {
    @visibleForTesting bool? isIOS,
    @visibleForTesting KeychainMaintenance? keychain,
    @visibleForTesting Future<Set<String>> Function()? profilePrefixes,
  }) async {
    if (!(isIOS ?? (!kIsWeb && Platform.isIOS))) return;
    final state = prefs.getString(markerKey);
    if (state == _done) return;
    final ops = keychain ?? const _ChannelKeychainMaintenance();
    try {
      final onDisk = {...await (profilePrefixes ?? _profilePrefixesOnDisk)()};
      final registry = _registeredPrefixes(prefs);
      final current = prefs.get(_currentAccountKey);
      if (current is String && current.trim().isNotEmpty) {
        onDisk.add(_ownerPrefix(current));
      }
      final fresh = registry != null && registry.isEmpty && onDisk.isEmpty;
      await prefs.setString(markerKey, _pending);
      final bool ok;
      if (fresh) {
        ok = await ops.wipeAll();
      } else if (registry == null) {
        ok = false; // registry unreadable: cannot tell owned from orphaned
      } else {
        final owners = {...registry, ...onDisk};
        final orphans = (await ops.listKeys())
            .where((key) => _isOrphan(key, owners))
            .toList();
        ok = orphans.isEmpty || await ops.deleteKeys(orphans);
      }
      if (!ok) {
        AppLogger.log(
          '[KeychainReinstallGuard] Keychain refused the cleanup; '
          'retrying on the next launch',
        );
        return;
      }
      await prefs.setString(markerKey, _done);
      AppLogger.log(
        '[KeychainReinstallGuard] cleared secure-storage items left by a '
        'previous installation',
      );
    } catch (e) {
      // MissingPluginException / PlatformException / IO: stay pending, retry.
      AppLogger.log('[KeychainReinstallGuard] cleanup failed: $e');
    }
  }

  /// The 16-char toxId prefixes of registered accounts; empty when there is
  /// no registry; null when the registry exists but cannot be read (a
  /// preserved corrupt payload, or undecodable JSON).
  static Set<String>? _registeredPrefixes(SharedPreferences prefs) {
    if (prefs.containsKey(_accountListCorruptBackupKey)) return null;
    final raw = prefs.get(_accountListKey);
    if (raw == null) return {};
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final prefixes = <String>{};
      for (final row in decoded) {
        final toxId = row is Map ? row['toxId'] : null;
        if (toxId is! String || toxId.trim().isEmpty) return null;
        prefixes.add(_ownerPrefix(toxId));
      }
      return prefixes;
    } on FormatException {
      return null;
    }
  }

  static Future<Set<String>> _profilePrefixesOnDisk() async {
    final prefixes = <String>{};
    // Legacy location `<appSupport>/tim2tox/tox_profile_<toxId>.tox`, still
    // resolved by `AppPaths.resolveToxProfilePath`.
    final legacy = await AppPaths.toxProfileDir;
    if (await legacy.exists()) {
      await for (final entry in legacy.list(followLinks: false)) {
        final name = p.basename(entry.path);
        if (name.startsWith('tox_profile_') && name.endsWith('.tox')) {
          prefixes.add(_ownerPrefix(name.substring('tox_profile_'.length)));
        }
      }
    }
    final roots = {
      await AppPaths.getProfileStorageRoot(),
      p.join(await AppPaths.applicationSupportPath, 'profiles'),
    };
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      await for (final entry in dir.list(followLinks: false)) {
        final name = p.basename(entry.path);
        // Anything in a profile root counts as account state; only p_<id>
        // directories name their owner.
        prefixes.add(
          name.startsWith('p_') ? _ownerPrefix(name.substring(2)) : name,
        );
      }
    }
    return prefixes;
  }

  static String _ownerPrefix(String toxId) {
    final id = toxId.trim().toUpperCase();
    return id.length > _ownerPrefixLength
        ? id.substring(0, _ownerPrefixLength)
        : id;
  }

  @visibleForTesting
  static bool isOrphanForTest(String key, Set<String> owners) =>
      _isOrphan(key, owners);

  static bool _isOrphan(String key, Set<String> owners) {
    final String? owner;
    if (key.startsWith(_verifierSaltPrefix)) {
      owner = key.substring(_verifierSaltPrefix.length);
    } else if (key.startsWith(_verifierPrefix)) {
      owner = key.substring(_verifierPrefix.length);
    } else if (key.startsWith(_ircPasswordPrefix)) {
      final cut = key.lastIndexOf('_');
      owner = cut > _ircPasswordPrefix.length - 1
          ? key.substring(cut + 1)
          : null;
    } else {
      return false; // not a key this app is known to write: keep it
    }
    if (owner == null || owner.isEmpty) return false;
    return !owners.contains(_ownerPrefix(owner));
  }
}
