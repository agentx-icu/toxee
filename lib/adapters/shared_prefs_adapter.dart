import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/interfaces/extended_preferences_service.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';

import '../util/logger.dart';
import '../util/prefs/scoped_key.dart';

/// Adapter that implements ExtendedPreferencesService using SharedPreferences.
///
/// When [accountPrefix] is provided (recommended), keys are scoped as `${key}_${accountPrefix}`
/// to match the account-scoped pattern used by the UI Prefs utility (first 16 chars of toxId).
/// This ensures both the service layer and UI layer read/write the same SharedPreferences keys.
///
/// Legacy behavior: when [accountPrefix] is null, keys are scoped by FFI instance_id
/// (or unscoped for instance_id=0). On first use with accountPrefix, data is migrated
/// from old unscoped keys to new account-scoped keys.
class SharedPreferencesAdapter implements ExtendedPreferencesService {
  final SharedPreferences _prefs;
  int? _instanceId;
  String? _accountPrefix;

  // Keys
  static const _kGroups = 'groups_list';
  static const _kQuitGroups = 'quit_groups_list';
  static const _kSelfAvatarHash = 'self_avatar_hash';
  static String _friendNicknameKey(String friendId) => 'friend_nickname_$friendId';
  static String _friendStatusMsgKey(String friendId) => 'friend_status_msg_$friendId';
  static String _friendAvatarPathKey(String friendId) => 'friend_avatar_path_$friendId';
  // Matches the key shape used by toxee's UI-side Prefs.setFriendRemark, so
  // both the platform write path and the UI write path land on the same
  // account-scoped slot once `_prefixKey` is applied.
  static String _friendRemarkKey(String friendId) => 'friend_remark_$friendId';
  static const _kLocalFriends = 'local_friends';
  static const _kBootstrapNodeMode = 'bootstrap_node_mode';
  static const _kCurrentBootstrapHost = 'current_bootstrap_host';
  static const _kCurrentBootstrapPort = 'current_bootstrap_port';
  static const _kCurrentBootstrapPubkey = 'current_bootstrap_pubkey';
  static const _kAutoDownloadSizeLimit = 'auto_download_size_limit';
  static String _blackListKey(String? userToxId) => userToxId != null && userToxId.isNotEmpty ? 'black_list_$userToxId' : 'black_list';
  // Per-peer C2C receive option (DND). Account-scoped via the standard
  // 16-char Tox-ID prefix (matches `Prefs._scopedKey` convention used by
  // `group_member_namecard`, drafts, pin/mute, etc.). The blacklist key
  // (`_blackListKey`) uses a full-toxId scheme for legacy reasons; for new
  // keys we follow the 16-char prefix style.
  static String _c2cRecvOptKey(String userID, String? userToxId) {
    final prefix = (userToxId != null && userToxId.length >= 16)
        ? userToxId.substring(0, 16)
        : userToxId;
    return scopedPrefsKey('c2c_recv_opt_$userID', prefix);
  }

  // Group recv-opt key — same scoped format as the C2C key above + Prefs, so
  // both the static Prefs path and this adapter read/write the same entry.
  static String _groupRecvOptKey(String groupID, String? userToxId) {
    final prefix = (userToxId != null && userToxId.length >= 16)
        ? userToxId.substring(0, 16)
        : userToxId;
    return scopedPrefsKey('group_recv_opt_$groupID', prefix);
  }

  SharedPreferencesAdapter(this._prefs, {int? instanceId, String? accountPrefix})
      : _instanceId = instanceId,
        _accountPrefix = accountPrefix;

  /// Set the account prefix post-construction. Used by login flows that can't
  /// know the toxId until after `service.login()` resolves selfId (legacy
  /// account path). Subsequent reads/writes use the account-scoped pattern.
  /// If [_accountPrefix] was already set, this is a no-op (legacy migration
  /// only happens once per process via existing _prefixKey logic).
  void setAccountPrefix(String prefix) {
    if (_accountPrefix != null && _accountPrefix!.isNotEmpty) return;
    _accountPrefix = prefix;
  }

  /// Get instance ID (lazy, gets from FFI if not set)
  int? get _effectiveInstanceId {
    if (_instanceId != null) {
      return _instanceId;
    }
    try {
      final ffi = Tim2ToxFfi.open();
      final id = ffi.getCurrentInstanceId();
      _instanceId = id != 0 ? id : null;
      return _instanceId;
    } catch (e) {
      return null;
    }
  }

  /// Prefix key with account prefix (matching Prefs._scopedKey format) or instance_id fallback.
  /// Account-scoped: `${key}_${accountPrefix}` — matches UI Prefs pattern, formatted
  ///   via the shared [scopedPrefsKey] helper (X2 in
  ///   `local-storage-review-2026-05-18.md`).
  /// Instance-scoped (legacy): `instance_${id}_${key}` — only when no accountPrefix
  String _prefixKey(String key) {
    // Prefer account-scoped keys (consistent with UI Prefs)
    if (_accountPrefix != null && _accountPrefix!.isNotEmpty) {
      return scopedPrefsKey(key, _accountPrefix);
    }
    // Legacy: instance-scoped keys
    final instanceId = _effectiveInstanceId;
    if (instanceId != null && instanceId != 0) {
      return 'instance_${instanceId}_$key';
    }
    return key;
  }

  /// Read a string with scoped key, falling back to the old unscoped key if not found.
  /// Migrates the data to the scoped key on read so future reads are fast.
  Future<String?> _getStringScoped(String rawKey) async {
    final scopedKey = _prefixKey(rawKey);
    final value = _prefs.getString(scopedKey);
    if (value != null) return value;
    // Fallback: data may have been written before scoping was added
    if (scopedKey != rawKey) {
      final legacy = _prefs.getString(rawKey);
      if (legacy != null && legacy.isNotEmpty) {
        await _prefs.setString(scopedKey, legacy);
        await _prefs.remove(rawKey);
        return legacy;
      }
    }
    return null;
  }

  /// Migration is now handled centrally by PrefsUpgrader.runAccountMigrations().
  /// This method is kept as a no-op guard for backward compatibility with
  /// code that still calls it (getGroups, setGroups, etc.).
  Future<void> _migrateIfNeeded() async {
    // No-op: migration is handled centrally by PrefsUpgrader.
  }
  
  // Basic PreferencesService methods
  @override
  Future<String?> getString(String key) async => _prefs.getString(key);
  
  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  
  @override
  Future<bool?> getBool(String key) => Future.value(_prefs.getBool(key));
  
  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
  
  @override
  Future<int?> getInt(String key) => Future.value(_prefs.getInt(key));
  
  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);
  
  @override
  Future<List<String>?> getStringList(String key) => Future.value(_prefs.getStringList(key));
  
  @override
  Future<void> setStringList(String key, List<String> value) => _prefs.setStringList(key, value);
  
  @override
  Future<void> remove(String key) => _prefs.remove(key);
  
  /// S4 fix: do NOT call SharedPreferences.clear() — that would wipe global
  /// settings (theme, locale, bootstrap nodes, account list, every other
  /// account's data) along with the current account's. Instead, scope the
  /// clear to keys ending in `_<accountPrefix>`. When no account prefix is
  /// installed (legacy instance-id mode), refuse and log a warning rather than
  /// silently destroying user data — the interface contract calls this
  /// "clear all preferences", but toxee's prefs store mixes per-account and
  /// global keys in one bucket, so an honest implementation cannot wipe
  /// everything safely.
  @override
  Future<void> clear() async {
    final prefix = _accountPrefix;
    if (prefix == null || prefix.isEmpty) {
      // No way to identify which keys belong to "this account"; refuse rather
      // than wipe the entire SharedPreferences store.
      AppLogger.warn(
          '[SharedPrefsAdapter] refused clear() — no accountPrefix; would wipe global keys');
      return;
    }
    final suffix = '_$prefix';
    final keysToRemove = _prefs.getKeys().where((k) => k.endsWith(suffix)).toList();
    await Future.wait(keysToRemove.map(_prefs.remove));
  }
  
  // ExtendedPreferencesService methods
  @override
  Future<Set<String>> getGroups() async {
    await _migrateIfNeeded();
    return _prefs.getStringList(_prefixKey(_kGroups))?.toSet() ?? <String>{};
  }

  @override
  Future<void> setGroups(Set<String> groups) async {
    await _migrateIfNeeded();
    await _prefs.setStringList(_prefixKey(_kGroups), groups.toList());
  }

  @override
  Future<Set<String>> getQuitGroups() async {
    await _migrateIfNeeded();
    return _prefs.getStringList(_prefixKey(_kQuitGroups))?.toSet() ?? <String>{};
  }

  @override
  Future<void> setQuitGroups(Set<String> groups) async {
    await _migrateIfNeeded();
    await _prefs.setStringList(_prefixKey(_kQuitGroups), groups.toList());
  }
  
  @override
  Future<void> addQuitGroup(String groupId) async {
    final groups = await getQuitGroups();
    groups.add(groupId);
    await setQuitGroups(groups);
  }
  
  @override
  Future<void> removeQuitGroup(String groupId) async {
    final groups = await getQuitGroups();
    groups.remove(groupId);
    await setQuitGroups(groups);
  }
  
  @override
  Future<String?> getSelfAvatarHash() => _getStringScoped(_kSelfAvatarHash);

  @override
  Future<void> setSelfAvatarHash(String? hash) async {
    if (hash != null) {
      await setString(_prefixKey(_kSelfAvatarHash), hash);
    } else {
      await remove(_prefixKey(_kSelfAvatarHash));
    }
  }
  
  @override
  Future<String?> getFriendNickname(String friendId) => _getStringScoped(_friendNicknameKey(friendId));
  
  @override
  Future<void> setFriendNickname(String friendId, String nickname) => 
      setString(_prefixKey(_friendNicknameKey(friendId)), nickname);
  
  @override
  Future<String?> getFriendStatusMessage(String friendId) => 
      _getStringScoped(_friendStatusMsgKey(friendId));
  
  @override
  Future<void> setFriendStatusMessage(String friendId, String statusMessage) => 
      setString(_prefixKey(_friendStatusMsgKey(friendId)), statusMessage);
  
  @override
  Future<String?> getFriendAvatarPath(String friendId) =>
      _getStringScoped(_friendAvatarPathKey(friendId));

  @override
  Future<void> setFriendAvatarPath(String friendId, String? path) async {
    if (path != null) {
      await setString(_prefixKey(_friendAvatarPathKey(friendId)), path);
    } else {
      await remove(_prefixKey(_friendAvatarPathKey(friendId)));
    }
  }

  @override
  Future<String?> getFriendRemark(String friendId) =>
      _getStringScoped(_friendRemarkKey(friendId));

  @override
  Future<void> setFriendRemark(String friendId, String? remark) async {
    final key = _prefixKey(_friendRemarkKey(friendId));
    if (remark == null || remark.isEmpty) {
      await remove(key);
    } else {
      await setString(key, remark);
    }
  }
  
  @override
  Future<Set<String>> getLocalFriends() async {
    final scopedKey = _prefixKey(_kLocalFriends);
    final scoped = _prefs.getStringList(scopedKey);
    if (scoped != null) return scoped.toSet();
    // Fallback: migrate from unscoped key
    if (scopedKey != _kLocalFriends) {
      final legacy = _prefs.getStringList(_kLocalFriends);
      if (legacy != null && legacy.isNotEmpty) {
        await _prefs.setStringList(scopedKey, legacy);
        await _prefs.remove(_kLocalFriends);
        return legacy.toSet();
      }
    }
    return <String>{};
  }

  @override
  Future<void> setLocalFriends(Set<String> ids) async {
    await _prefs.setStringList(_prefixKey(_kLocalFriends), ids.toList());
  }
  
  @override
  Future<String> getBootstrapNodeMode() async {
    return _prefs.getString(_kBootstrapNodeMode) ?? 'auto';
  }
  
  @override
  Future<({String host, int port, String pubkey})?> getCurrentBootstrapNode() async {
    final host = _prefs.getString(_kCurrentBootstrapHost);
    if (host == null) return null;
    final port = _prefs.getInt(_kCurrentBootstrapPort) ?? 33445;
    final pubkey = _prefs.getString(_kCurrentBootstrapPubkey) ?? '';
    if (pubkey.isEmpty) return null;
    return (host: host, port: port, pubkey: pubkey);
  }
  
  @override
  Future<void> setCurrentBootstrapNode(String host, int port, String pubkey) async {
    await _prefs.setString(_kCurrentBootstrapHost, host);
    await _prefs.setInt(_kCurrentBootstrapPort, port);
    await _prefs.setString(_kCurrentBootstrapPubkey, pubkey);
  }
  
  @override
  Future<int> getAutoDownloadSizeLimit() async {
    return _prefs.getInt(_kAutoDownloadSizeLimit) ?? 100; // Default 100MB
  }
  
  @override
  Future<void> setAutoDownloadSizeLimit(int sizeInMB) async {
    await _prefs.setInt(_kAutoDownloadSizeLimit, sizeInMB);
  }
  
  @override
  Future<String?> getAvatarPath() async {
    final scopedKey = _prefixKey('self_avatar_path');
    final scoped = _prefs.getString(scopedKey);
    if (scoped != null && scoped.isNotEmpty) return scoped;

    // Fallback: migrate from unscoped key
    if (scopedKey != 'self_avatar_path') {
      final legacy = _prefs.getString('self_avatar_path');
      if (legacy != null && legacy.isNotEmpty) {
        await _prefs.setString(scopedKey, legacy);
        return legacy;
      }
    }

    // Fallback: avatar stored only in account_list JSON
    if (_accountPrefix != null && _accountPrefix!.isNotEmpty) {
      final listJson = _prefs.getString('account_list');
      if (listJson != null) {
        try {
          final accounts = json.decode(listJson) as List<dynamic>;
          for (final a in accounts) {
            final toxId = a['toxId'] as String? ?? '';
            if (toxId.length >= 16 && toxId.substring(0, 16) == _accountPrefix) {
              final path = a['avatarPath'] as String?;
              if (path != null && path.isNotEmpty) {
                await _prefs.setString(scopedKey, path);
                return path;
              }
            }
          }
        } catch (e) {
          AppLogger.warn(
              '[SharedPrefsAdapter] account_list JSON parse for avatar fallback failed: $e');
        }
      }
    }
    return null;
  }

  @override
  Future<void> setAvatarPath(String? path) async {
    final scopedKey = _prefixKey('self_avatar_path');
    if (path != null) {
      await setString(scopedKey, path);
    } else {
      await remove(scopedKey);
    }
  }
  
  @override
  Future<String?> getFriendAvatarHash(String friendId) => 
      _getStringScoped('friend_avatar_hash_$friendId');
  
  @override
  Future<void> setFriendAvatarHash(String friendId, String hash) => 
      setString(_prefixKey('friend_avatar_hash_$friendId'), hash);
  
  @override
  Future<String?> getDownloadsDirectory() => getString('downloads_directory');
  
  @override
  Future<void> setDownloadsDirectory(String? path) async {
    if (path != null) {
      await setString('downloads_directory', path);
    } else {
      await remove('downloads_directory');
    }
  }
  
  @override
  Future<String?> getGroupName(String groupId) => 
      getString(_prefixKey('group_name_$groupId'));

  @override
  Future<void> setGroupName(String groupId, String name) => 
      setString(_prefixKey('group_name_$groupId'), name);

  @override
  Future<String?> getGroupAvatar(String groupId) => 
      getString(_prefixKey('group_avatar_$groupId'));

  @override
  Future<void> setGroupAvatar(String groupId, String? avatarPath) async {
    if (avatarPath != null) {
      await setString(_prefixKey('group_avatar_$groupId'), avatarPath);
    } else {
      await remove(_prefixKey('group_avatar_$groupId'));
    }
  }

  @override
  Future<String?> getGroupNotification(String groupId) => 
      getString(_prefixKey('group_notification_$groupId'));

  @override
  Future<void> setGroupNotification(String groupId, String? notification) async {
    if (notification != null && notification.isNotEmpty) {
      await setString(_prefixKey('group_notification_$groupId'), notification);
    } else {
      await remove(_prefixKey('group_notification_$groupId'));
    }
  }

  @override
  Future<String?> getGroupIntroduction(String groupId) => 
      getString(_prefixKey('group_introduction_$groupId'));

  @override
  Future<void> setGroupIntroduction(String groupId, String? introduction) async {
    if (introduction != null && introduction.isNotEmpty) {
      await setString(_prefixKey('group_introduction_$groupId'), introduction);
    } else {
      await remove(_prefixKey('group_introduction_$groupId'));
    }
  }

  @override
  Future<String?> getGroupOwner(String groupId) => 
      getString(_prefixKey('group_owner_$groupId'));

  @override
  Future<void> setGroupOwner(String groupId, String ownerId) => 
      setString(_prefixKey('group_owner_$groupId'), ownerId);

  @override
  Future<String?> getGroupConferenceId(String groupId) => 
      getString(_prefixKey('group_conference_id_$groupId'));

  @override
  Future<void> setGroupConferenceId(String groupId, String conferenceId) async {
    if (conferenceId.isNotEmpty) {
      await setString(_prefixKey('group_conference_id_$groupId'), conferenceId);
    } else {
      await remove(_prefixKey('group_conference_id_$groupId'));
    }
  }
  
  @override
  Future<String?> getGroupChatId(String groupId) => 
      getString(_prefixKey('group_chat_id_$groupId'));
  
  @override
  Future<void> setGroupChatId(String groupId, String chatId) async {
    if (chatId.isNotEmpty) {
      await setString(_prefixKey('group_chat_id_$groupId'), chatId);
    } else {
      await remove(_prefixKey('group_chat_id_$groupId'));
    }
  }
  
  Future<Set<String>> getStringSet(String key) async {
    final list = await getStringList(key);
    return list?.toSet() ?? <String>{};
  }
  
  Future<void> setStringSet(String key, Set<String> value) async {
    await setStringList(key, value.toList());
  }
  
  @override
  Future<Set<String>> getBlackList([String? userToxId]) async {
    // userToxId should be provided by the caller (Tim2ToxSdkPlatform)
    // If not provided, return empty list (should not happen in normal flow)
    final key = _blackListKey(userToxId);
    return _prefs.getStringList(key)?.toSet() ?? <String>{};
  }
  
  @override
  Future<void> setBlackList(Set<String> userIDs, [String? userToxId]) async {
    // userToxId should be provided by the caller (Tim2ToxSdkPlatform)
    final key = _blackListKey(userToxId);
    await _prefs.setStringList(key, userIDs.toList());
  }
  
  @override
  Future<void> addToBlackList(List<String> userIDs, [String? userToxId]) async {
    // userToxId should be provided by the caller (Tim2ToxSdkPlatform)
    final blackList = await getBlackList(userToxId);
    blackList.addAll(userIDs);
    await setBlackList(blackList, userToxId);
  }
  
  @override
  Future<void> removeFromBlackList(List<String> userIDs, [String? userToxId]) async {
    // userToxId should be provided by the caller (Tim2ToxSdkPlatform)
    final blackList = await getBlackList(userToxId);
    blackList.removeAll(userIDs);
    await setBlackList(blackList, userToxId);
  }

  @override
  Future<int> getC2CReceiveMessageOpt(String userID, [String? userToxId]) async {
    final key = _c2cRecvOptKey(userID, userToxId);
    return _prefs.getInt(key) ?? 0;
  }

  @override
  Future<void> setC2CReceiveMessageOpt(String userID, int opt,
      [String? userToxId]) async {
    final key = _c2cRecvOptKey(userID, userToxId);
    if (opt == 0) {
      await _prefs.remove(key);
    } else {
      await _prefs.setInt(key, opt);
    }
  }

  @override
  Future<int> getGroupReceiveMessageOpt(String groupID,
      [String? userToxId]) async {
    final key = _groupRecvOptKey(groupID, userToxId);
    return _prefs.getInt(key) ?? 0;
  }

  @override
  Future<void> setGroupReceiveMessageOpt(String groupID, int opt,
      [String? userToxId]) async {
    final key = _groupRecvOptKey(groupID, userToxId);
    if (opt == 0) {
      await _prefs.remove(key);
    } else {
      await _prefs.setInt(key, opt);
    }
  }
}

