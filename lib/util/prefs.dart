import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'logger.dart';
import 'tox_utils.dart';
import '../models/account_summary.dart';

part 'prefs/window_prefs.dart';
part 'prefs/security_prefs.dart';
part 'prefs/account_prefs.dart';
part 'prefs/chat_prefs.dart';

/// Static facade for app preferences. New code should prefer repository instances
/// ([PrefsImpl] or [prefs_interfaces.dart] interfaces) for testability and bounded context.
/// See [PrefsImpl.global] and [prefs_interfaces.dart] for migration.
class Prefs {
  static const _kServerId = 'server_id';
  static String _draftKey(String peerId) => 'draft_$peerId';
  static const _kPinned = 'pinned_peers';
  static const _kMuted = 'muted_peers';
  static const _kGroups = 'groups_list';
  static const _kQuitGroups = 'quit_groups_list'; // Groups that user has quit
  static const _kNickname = 'self_nickname';
  static const _kStatusMsg = 'self_status_msg';
  static const _kThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const _kAvatarPath = 'self_avatar_path';
  static String _groupNameKey(String gid) => 'group_name_$gid';
  // Local alias for a group the user has joined (not the canonical group
  // name). Stored separately so the canonical name from peers can still
  // populate `_groupNameKey` without clobbering the user's chosen alias.
  static String _groupAliasKey(String gid) => 'group_alias_$gid';
  static const _kLocalFriends = 'local_friends';
  static const _kLanguage = 'language_code'; // e.g. 'en', 'zh'
  static const _kCurrentBootstrapHost = 'current_bootstrap_host';
  static const _kCurrentBootstrapPort = 'current_bootstrap_port';
  static const _kCurrentBootstrapPubkey = 'current_bootstrap_pubkey';
  static const _kBootstrapNodeMode = 'bootstrap_node_mode'; // 'manual', 'auto', or 'lan'
  static const _kLanBootstrapPort = 'lan_bootstrap_port'; // Local bootstrap service port
  static const _kLanBootstrapServiceRunning = 'lan_bootstrap_service_running'; // Service running status
  static const _kAutoAcceptFriends = 'auto_accept_friends';
  static const _kAutoAcceptGroupInvites = 'auto_accept_group_invites';
  static const _kAutoLogin = 'auto_login';
  static const _kNotificationSoundEnabled = 'notification_sound_enabled';
  static const _kCardText = 'self_card_text';
  static const _kCurrentAccountToxId = 'current_account_tox_id'; // Which account is active (for per-account avatar/pinned/localFriends)
  static const _kDownloadsDirectory = 'downloads_directory';
  static const _kProfileStorageRoot = 'profile_storage_root'; // Optional custom root for tox profiles (survives uninstall when outside app)
  static const _kAutoDownloadSizeLimit = 'auto_download_size_limit'; // in MB
  static const _kIrcAppInstalled = 'irc_app_installed'; // bool
  static const _kIrcChannels = 'irc_channels'; // List<String> - JSON array of channel names
  static const _kIrcServer = 'irc_server'; // String - IRC server address (default: "irc.libera.chat")
  static const _kIrcPort = 'irc_port'; // int - IRC server port (default: 6667)
  static const _kIrcUseSasl = 'irc_use_sasl'; // bool - Whether to use SASL authentication
  static String _ircChannelPasswordKey(String channel) => 'irc_channel_password_$channel';
  // Window/layout state (desktop)
  static const _kWindowBounds = 'window_bounds'; // "left,top,width,height"
  static const _kWindowMaximized = 'window_maximized';
  static const _kSplitterPosition = 'splitter_position'; // conversation list width or ratio (0.0-1.0)
  // Contact list sorting
  static const _kFriendListSortingMode = 'friend_list_sorting_mode'; // 'name' | 'activity'
  static String _friendActivityKey(String userId) => 'friend_activity_$userId';

  // Password salt key prefix
  static const _kPasswordSaltPrefix = 'account_password_salt_';
  static String _passwordSaltKey(String toxId) => '$_kPasswordSaltPrefix$toxId';

  /// PBKDF2 stored hash prefix (new format); without it we treat as legacy SHA256.
  static const _kPbkdf2Prefix = 'pbkdf2:';
  static const int _pbkdf2Iterations = 150000;
  static const int _pbkdf2Bits = 256;

  // Per-account settings keys (scoped by account prefix, replacing JSON storage)
  static const _kAccountAutoAcceptFriends = 'acct_auto_accept_friends';
  static const _kAccountAutoAcceptGroupInvites = 'acct_auto_accept_group_invites';
  static const _kAccountAutoLogin = 'acct_auto_login';
  static const _kAccountNotificationSound = 'acct_notification_sound';

  // ---- Cached state (set by initialize / setCurrentAccountToxId) ----
  static SharedPreferences? _cachedPrefs;
  static bool _accountToxIdCached = false;
  static String? _cachedCurrentAccountToxId;

  /// Secure storage for IRC channel passwords and account password hashes
  /// (platform Keychain / Keystore / libsecret / DPAPI).
  static FlutterSecureStorage get _secureStorage => const FlutterSecureStorage();

  /// Read a key from secure storage, returning null when the platform channel
  /// is not available (test environment without a mock — flutter_secure_storage
  /// throws [MissingPluginException]). Other errors propagate.
  static Future<String?> _secureRead(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } on MissingPluginException {
      return null;
    }
  }

  /// Write to secure storage; swallow [MissingPluginException] so tests don't
  /// need a platform-channel mock for code paths that don't specifically test
  /// secure-storage behavior.
  static Future<void> _secureWrite(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } on MissingPluginException {
      // Plugin unavailable (test env without mock). Caller's legacy-prefs
      // fallback is still in place for read paths.
    }
  }

  /// Delete from secure storage; swallow [MissingPluginException].
  static Future<void> _secureDelete(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } on MissingPluginException {
      // Plugin unavailable; nothing to delete in secure storage anyway.
    }
  }

  /// Initialize the Prefs cache. Must be called once at app startup after
  /// SharedPreferences.getInstance() returns (typically in main()).
  /// This avoids redundant getInstance() + reload() on every read.
  static Future<void> initialize(SharedPreferences prefs) async {
    _cachedPrefs = prefs;
    _cachedCurrentAccountToxId = prefs.getString(_kCurrentAccountToxId);
    _accountToxIdCached = true;
  }

  /// Get the cached SharedPreferences instance. Falls back to getInstance()
  /// if initialize() hasn't been called yet (e.g. in tests).
  static Future<SharedPreferences> _getPrefs() async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

  static Future<String?> getServerId() async {
    final p = await _getPrefs();
    return p.getString(_kServerId);
    }

  static Future<void> setServerId(String value) async {
    final p = await _getPrefs();
    await p.setString(_kServerId, value);
  }

  static Future<String?> getDraft(String peerId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_draftKey(peerId), current);
    return p.getString(key);
  }

  static Future<void> setDraft(String peerId, String text) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_draftKey(peerId), current);
    if (text.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, text);
    }
  }

  /// Storage key for pinned/conversation list scoped by account (avoids loading other account's data).
  static String _scopedKey(String baseKey, String? toxId) {
    if (toxId == null || toxId.isEmpty) return baseKey;
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    return '${baseKey}_$prefix';
  }

  static Future<String?> getCurrentAccountToxId() async {
    // Return cached value if available (updated by setCurrentAccountToxId).
    // The reload()-on-every-read pattern was causing a disk read per call;
    // the cache is invalidated only on explicit account switch.
    // Use _accountToxIdCached sentinel to distinguish "not loaded" from "loaded null".
    if (_accountToxIdCached) {
      return _cachedCurrentAccountToxId;
    }
    final p = await _getPrefs();
    _cachedCurrentAccountToxId = p.getString(_kCurrentAccountToxId);
    _accountToxIdCached = true;
    return _cachedCurrentAccountToxId;
  }

  static Future<void> setCurrentAccountToxId(String? toxId) async {
    final p = await _getPrefs();
    if (toxId == null || toxId.isEmpty) {
      await p.remove(_kCurrentAccountToxId);
      _cachedCurrentAccountToxId = null;
    } else {
      final trimmed = toxId.trim();
      await p.setString(_kCurrentAccountToxId, trimmed);
      _cachedCurrentAccountToxId = trimmed;
    }
    _accountToxIdCached = true;
  }

  static Future<Set<String>> getPinned() async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return <String>{};
    final p = await _getPrefs();
    final key = _scopedKey(_kPinned, current);
    return p.getStringList(key)?.toSet() ?? <String>{};
  }

  static Future<void> setPinned(Set<String> peers) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_kPinned, current);
    await p.setStringList(key, peers.toList());
  }

  static Future<Set<String>> getMuted() async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return <String>{};
    final p = await _getPrefs();
    final key = _scopedKey(_kMuted, current);
    return p.getStringList(key)?.toSet() ?? <String>{};
  }

  static Future<void> setMuted(Set<String> peers) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_kMuted, current);
    await p.setStringList(key, peers.toList());
  }

  static Future<Set<String>> getGroups() async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return <String>{};
    final p = await _getPrefs();
    final key = _scopedKey(_kGroups, current);
    return p.getStringList(key)?.toSet() ?? <String>{};
  }

  static Future<void> setGroups(Set<String> groups) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_kGroups, current);
    await p.setStringList(key, groups.toList());
  }

  static Future<Set<String>> getQuitGroups() async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return <String>{};
    final p = await _getPrefs();
    final key = _scopedKey(_kQuitGroups, current);
    return p.getStringList(key)?.toSet() ?? <String>{};
  }

  static Future<void> setQuitGroups(Set<String> groups) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_kQuitGroups, current);
    await p.setStringList(key, groups.toList());
  }

  static Future<void> addQuitGroup(String groupId) async {
    final quitGroups = await getQuitGroups();
    quitGroups.add(groupId);
    await setQuitGroups(quitGroups);
  }

  static Future<void> removeQuitGroup(String groupId) async {
    final quitGroups = await getQuitGroups();
    quitGroups.remove(groupId);
    await setQuitGroups(quitGroups);
  }

  static Future<String?> getNickname() async {
    final p = await _getPrefs();
    return p.getString(_kNickname);
  }

  static Future<void> setNickname(String value) async {
    final p = await _getPrefs();
    if (value.isEmpty) {
      await p.remove(_kNickname);
    } else {
      await p.setString(_kNickname, value);
    }
  }

  static Future<String?> getStatusMessage() async {
    final p = await _getPrefs();
    return p.getString(_kStatusMsg);
  }

  static Future<void> setStatusMessage(String value) async {
    final p = await _getPrefs();
    if (value.isEmpty) {
      await p.remove(_kStatusMsg);
    } else {
      await p.setString(_kStatusMsg, value);
    }
  }

  /// Returns one of: 'system' | 'light' | 'dark'.
  /// Default for unknown / unset values is 'system' so first-launch follows
  /// the OS preference.
  static Future<String> getThemeMode() async {
    final p = await _getPrefs();
    final raw = p.getString(_kThemeMode);
    if (raw == 'dark' || raw == 'light' || raw == 'system') return raw!;
    return 'system';
  }

  /// Persists theme mode. Accepts 'system', 'light', 'dark'; any other value
  /// is coerced to 'system'.
  static Future<void> setThemeMode(String mode) async {
    final p = await _getPrefs();
    final normalized = (mode == 'dark' || mode == 'light' || mode == 'system')
        ? mode
        : 'system';
    await p.setString(_kThemeMode, normalized);
  }

  static Future<String?> getAvatarPath() async {
    final current = await getCurrentAccountToxId();
    if (current != null && current.isNotEmpty) {
      final account = await getAccountByToxId(current);
      final path = account?['avatarPath'];
      if (path != null && path.isNotEmpty) return path;
      // Do not fall back to global _kAvatarPath: it may be another account's avatar.
      return null;
    }
    final p = await _getPrefs();
    return p.getString(_kAvatarPath);
  }

  static Future<void> setAvatarPath(String? path) async {
    final current = await getCurrentAccountToxId();
    if (current != null && current.isNotEmpty) {
      // Active account present: write ONLY to the scoped account-list entry.
      //
      // We deliberately do NOT also write the legacy unscoped _kAvatarPath
      // here: that key is global, so writing it would leak the current
      // account's avatar to whoever logs in next (or to the
      // pre-login-account UI). The corresponding getter ([getAvatarPath])
      // already prefers the scoped account-list entry and refuses to fall
      // back to _kAvatarPath when an account is active, mirroring this
      // asymmetry.
      await setAccountAvatarPath(current, path);
      return;
    }
    // No active account — write to the legacy unscoped key. This branch
    // covers pre-login UI surfaces (rare; first-run wizard and similar
    // before a profile has been created).
    final p = await _getPrefs();
    if (path == null || path.isEmpty) {
      await p.remove(_kAvatarPath);
    } else {
      await p.setString(_kAvatarPath, path);
    }
  }

  static Future<String?> getGroupName(String groupId) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return null;
    final p = await _getPrefs();
    final key = _scopedKey(_groupNameKey(groupId), current);
    return p.getString(key);
  }

  static Future<void> setGroupName(String groupId, String name) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_groupNameKey(groupId), current);
    if (name.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, name);
    }
  }

  /// Local-only alias for a joined group. Takes display precedence over the
  /// canonical group name (which may arrive later from peers and would
  /// otherwise overwrite the user's chosen alias). Use for "rename this
  /// group locally" flows; do not use for create-group (which sets the
  /// canonical name).
  static Future<String?> getGroupAlias(String groupId) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return null;
    final p = await _getPrefs();
    final key = _scopedKey(_groupAliasKey(groupId), current);
    return p.getString(key);
  }

  static Future<void> setGroupAlias(String groupId, String alias) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_groupAliasKey(groupId), current);
    if (alias.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, alias);
    }
  }

  /// Resolve the display title for a group, preferring user-set alias over
  /// canonical group name over the raw group ID. Single source of truth for
  /// conversation list / chat header titles so the precedence is consistent.
  static Future<String> resolveGroupDisplayName(String groupId) async {
    final alias = await getGroupAlias(groupId);
    if (alias != null && alias.isNotEmpty) return alias;
    final name = await getGroupName(groupId);
    if (name != null && name.isNotEmpty) return name;
    return groupId;
  }

  static Future<Set<String>> getLocalFriends() async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    return _getLocalFriendsImpl(p, current, _scopedKey);
  }

  static Future<void> setLocalFriends(Set<String> ids) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    return _setLocalFriendsImpl(p, current, ids, _scopedKey);
  }

  static Future<String?> getLanguageCode() async {
    final p = await _getPrefs();
    return p.getString(_kLanguage);
  }

  static Future<void> setLanguageCode(String code) async {
    final p = await _getPrefs();
    await p.setString(_kLanguage, code);
  }

  // Get Locale from preferences (supports scriptCode). Returns null when no language was ever set (follow system).
  static Future<Locale?> getLocale() async {
    final code = await getLanguageCode();
    if (code == null || code.isEmpty) return null;
    return _stringToLocale(code);
  }

  // Save Locale to preferences (supports scriptCode)
  static Future<void> setLocale(Locale locale) async {
    final code = _localeToString(locale);
    await setLanguageCode(code);
  }

  // Helper method to serialize Locale to string
  static String _localeToString(Locale locale) {
    if (locale.scriptCode != null) {
      return '${locale.languageCode}_${locale.scriptCode}';
    }
    return locale.languageCode;
  }

  // Helper method to deserialize string to Locale
  static Locale _stringToLocale(String code) {
    final parts = code.split('_');
    if (parts.length == 2) {
      return Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]);
    }
    return Locale(parts[0]);
  }

  static Future<({String host, int port, String pubkey})?> getCurrentBootstrapNode() async {
    final p = await _getPrefs();
    final host = p.getString(_kCurrentBootstrapHost);
    final port = p.getInt(_kCurrentBootstrapPort);
    final pubkey = p.getString(_kCurrentBootstrapPubkey);
    if (host != null && port != null && pubkey != null) {
      return (host: host, port: port, pubkey: pubkey);
    }
    return null;
  }

  static Future<void> setCurrentBootstrapNode(String host, int port, String pubkey) async {
    final p = await _getPrefs();
    await p.setString(_kCurrentBootstrapHost, host);
    await p.setInt(_kCurrentBootstrapPort, port);
    await p.setString(_kCurrentBootstrapPubkey, pubkey);
  }

  static Future<void> clearCurrentBootstrapNode() async {
    final p = await _getPrefs();
    await p.remove(_kCurrentBootstrapHost);
    await p.remove(_kCurrentBootstrapPort);
    await p.remove(_kCurrentBootstrapPubkey);
  }

  /// Get bootstrap node mode: 'manual', 'auto', or 'lan'
  /// Defaults to 'auto' if not set
  static Future<String> getBootstrapNodeMode() async {
    final p = await _getPrefs();
    return p.getString(_kBootstrapNodeMode) ?? 'auto';
  }

  /// Set bootstrap node mode: 'manual', 'auto', or 'lan'
  static Future<void> setBootstrapNodeMode(String mode) async {
    final p = await _getPrefs();
    if (mode == 'manual' || mode == 'auto' || mode == 'lan') {
      await p.setString(_kBootstrapNodeMode, mode);
    }
  }

  /// Get LAN bootstrap service port
  /// Defaults to 33445 if not set
  static Future<int> getLanBootstrapPort() async {
    final p = await _getPrefs();
    return p.getInt(_kLanBootstrapPort) ?? 33445;
  }

  /// Set LAN bootstrap service port
  static Future<void> setLanBootstrapPort(int port) async {
    final p = await _getPrefs();
    await p.setInt(_kLanBootstrapPort, port);
  }

  /// Get LAN bootstrap service running status
  static Future<bool> getLanBootstrapServiceRunning() async {
    final p = await _getPrefs();
    return p.getBool(_kLanBootstrapServiceRunning) ?? false;
  }

  /// Set LAN bootstrap service running status
  static Future<void> setLanBootstrapServiceRunning(bool running) async {
    final p = await _getPrefs();
    await p.setBool(_kLanBootstrapServiceRunning, running);
  }

  /// Get auto-accept friends setting for a specific account.
  /// Priority: scoped key > account_list JSON fallback > global fallback.
  /// When [toxId] is null, uses current account so callers get the right account's setting.
  static Future<bool> getAutoAcceptFriends([String? toxId]) async {
    final p = await _getPrefs();
    var effectiveToxId = toxId;
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      effectiveToxId = await getCurrentAccountToxId();
    }
    if (effectiveToxId != null && effectiveToxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoAcceptFriends, effectiveToxId);
      final val = p.getBool(key);
      if (val != null) return val;
      // Fallback: check account_list JSON (pre-migration data)
      final account = await getAccountByToxId(effectiveToxId);
      if (account != null && account.containsKey('autoAcceptFriends')) {
        final result = account['autoAcceptFriends'] == 'true';
        // Migrate to scoped key
        await p.setBool(key, result);
        return result;
      }
    }
    return p.getBool(_kAutoAcceptFriends) ?? false;
  }

  /// Set auto-accept friends setting for a specific account.
  /// When [toxId] is null, uses current account.
  static Future<void> setAutoAcceptFriends(bool value, [String? toxId]) async {
    final p = await _getPrefs();
    var effectiveToxId = toxId;
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      effectiveToxId = await getCurrentAccountToxId();
    }
    if (effectiveToxId != null && effectiveToxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoAcceptFriends, effectiveToxId);
      await p.setBool(key, value);
      return;
    }
    await p.setBool(_kAutoAcceptFriends, value);
  }

  /// Get auto-accept group invites setting for a specific account.
  /// When [toxId] is null, uses current account.
  static Future<bool> getAutoAcceptGroupInvites([String? toxId]) async {
    final p = await _getPrefs();
    var effectiveToxId = toxId;
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      effectiveToxId = await getCurrentAccountToxId();
    }
    if (effectiveToxId != null && effectiveToxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoAcceptGroupInvites, effectiveToxId);
      final val = p.getBool(key);
      if (val != null) return val;
      final account = await getAccountByToxId(effectiveToxId);
      if (account != null && account.containsKey('autoAcceptGroupInvites')) {
        final result = account['autoAcceptGroupInvites'] == 'true';
        await p.setBool(key, result);
        return result;
      }
    }
    return p.getBool(_kAutoAcceptGroupInvites) ?? false;
  }

  /// Set auto-accept group invites setting for a specific account.
  /// When [toxId] is null, uses current account.
  static Future<void> setAutoAcceptGroupInvites(bool value, [String? toxId]) async {
    final p = await _getPrefs();
    var effectiveToxId = toxId;
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      effectiveToxId = await getCurrentAccountToxId();
    }
    if (effectiveToxId != null && effectiveToxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoAcceptGroupInvites, effectiveToxId);
      await p.setBool(key, value);
      return;
    }
    await p.setBool(_kAutoAcceptGroupInvites, value);
  }

  /// Get auto-login setting for a specific account.
  /// When [toxId] is null, uses current account (e.g. on startup after current is set).
  static Future<bool> getAutoLogin([String? toxId]) async {
    final p = await _getPrefs();
    var effectiveToxId = toxId;
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      effectiveToxId = await getCurrentAccountToxId();
    }
    if (effectiveToxId != null && effectiveToxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoLogin, effectiveToxId);
      final val = p.getBool(key);
      if (val != null) return val;
      final account = await getAccountByToxId(effectiveToxId);
      if (account != null && account.containsKey('autoLogin')) {
        final result = account['autoLogin'] == 'true';
        await p.setBool(key, result);
        return result;
      }
      return true; // Default for new accounts
    }
    return p.getBool(_kAutoLogin) ?? true;
  }

  /// Set auto-login setting for a specific account.
  /// When [toxId] is null, uses current account.
  static Future<void> setAutoLogin(bool value, [String? toxId]) async {
    final p = await _getPrefs();
    var effectiveToxId = toxId;
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      effectiveToxId = await getCurrentAccountToxId();
    }
    if (effectiveToxId != null && effectiveToxId.isNotEmpty) {
      final key = _scopedKey(_kAccountAutoLogin, effectiveToxId);
      await p.setBool(key, value);
      return;
    }
    await p.setBool(_kAutoLogin, value);
  }

  /// Get notification sound enabled setting for a specific account.
  /// When [toxId] is null, uses current account.
  static Future<bool> getNotificationSoundEnabled([String? toxId]) async {
    final p = await _getPrefs();
    var effectiveToxId = toxId;
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      effectiveToxId = await getCurrentAccountToxId();
    }
    if (effectiveToxId != null && effectiveToxId.isNotEmpty) {
      final key = _scopedKey(_kAccountNotificationSound, effectiveToxId);
      final val = p.getBool(key);
      if (val != null) return val;
      final account = await getAccountByToxId(effectiveToxId);
      if (account != null && account.containsKey('notificationSoundEnabled')) {
        final result = account['notificationSoundEnabled'] == 'true';
        await p.setBool(key, result);
        return result;
      }
      return true; // Default
    }
    return p.getBool(_kNotificationSoundEnabled) ?? true;
  }

  /// Set notification sound enabled setting for a specific account.
  /// When [toxId] is null, uses current account.
  static Future<void> setNotificationSoundEnabled(bool value, [String? toxId]) async {
    final p = await _getPrefs();
    var effectiveToxId = toxId;
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      effectiveToxId = await getCurrentAccountToxId();
    }
    if (effectiveToxId != null && effectiveToxId.isNotEmpty) {
      final key = _scopedKey(_kAccountNotificationSound, effectiveToxId);
      await p.setBool(key, value);
      return;
    }
    await p.setBool(_kNotificationSoundEnabled, value);
  }

  static Future<String?> getCardText() async {
    final p = await _getPrefs();
    return p.getString(_kCardText);
  }

  static Future<void> setCardText(String? value) async {
    final p = await _getPrefs();
    if (value == null || value.isEmpty) {
      await p.remove(_kCardText);
    } else {
      await p.setString(_kCardText, value);
    }
  }

  static Future<String?> getDownloadsDirectory() async {
    final p = await _getPrefs();
    return p.getString(_kDownloadsDirectory);
  }

  static Future<void> setDownloadsDirectory(String? path) async {
    final p = await _getPrefs();
    if (path == null || path.isEmpty) {
      await p.remove(_kDownloadsDirectory);
    } else {
      await p.setString(_kDownloadsDirectory, path);
    }
  }

  static Future<String?> getProfileStorageRoot() async {
    final prefs = await _getPrefs();
    return prefs.getString(_kProfileStorageRoot);
  }

  static Future<void> setProfileStorageRoot(String? path) async {
    final p = await _getPrefs();
    if (path == null || path.isEmpty) {
      await p.remove(_kProfileStorageRoot);
    } else {
      await p.setString(_kProfileStorageRoot, path);
    }
  }

  static Future<int> getAutoDownloadSizeLimit() async {
    final p = await _getPrefs();
    // Default to 30MB if not set
    return p.getInt(_kAutoDownloadSizeLimit) ?? 30;
  }

  static Future<void> setAutoDownloadSizeLimit(int sizeInMB) async {
    final p = await _getPrefs();
    await p.setInt(_kAutoDownloadSizeLimit, sizeInMB);
  }

  // Avatar hash tracking — account-scoped so two accounts that share a friend
  // don't read each other's stale hashes (S6 fix). Reads fall back to the
  // legacy unscoped key once and migrate to the scoped form on first hit.
  static String _avatarHashKey(String friendId) => 'avatar_hash_$friendId';
  static const _selfAvatarHashKey = 'self_avatar_hash';

  static Future<String?> getFriendAvatarHash(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final scopedKey = _scopedKey(_avatarHashKey(friendId), current);
    final scoped = p.getString(scopedKey);
    if (scoped != null) return scoped;
    if (scopedKey != _avatarHashKey(friendId)) {
      final legacy = p.getString(_avatarHashKey(friendId));
      if (legacy != null && legacy.isNotEmpty) {
        unawaited(p.setString(scopedKey, legacy));
        unawaited(p.remove(_avatarHashKey(friendId)));
        return legacy;
      }
    }
    return null;
  }

  static Future<void> setFriendAvatarHash(String friendId, String hash) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final scopedKey = _scopedKey(_avatarHashKey(friendId), current);
    await p.setString(scopedKey, hash);
    // Best-effort: clean up any legacy unscoped value left from older builds.
    if (scopedKey != _avatarHashKey(friendId)) {
      unawaited(p.remove(_avatarHashKey(friendId)));
    }
  }

  /// Remove the cached avatar hash for [friendId] (both scoped and legacy
  /// unscoped variants). Used when a friend is deleted so the on-disk
  /// hash key doesn't linger forever (A8).
  static Future<void> removeFriendAvatarHash(String friendId) async {
    if (friendId.isEmpty) return;
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final scopedKey = _scopedKey(_avatarHashKey(friendId), current);
    await p.remove(scopedKey);
    if (scopedKey != _avatarHashKey(friendId)) {
      await p.remove(_avatarHashKey(friendId));
    }
  }

  static Future<String?> getSelfAvatarHash() async {
    final p = await _getPrefs();
    return p.getString(_selfAvatarHashKey);
  }

  static Future<void> setSelfAvatarHash(String? hash) async {
    final p = await _getPrefs();
    if (hash == null || hash.isEmpty) {
      await p.remove(_selfAvatarHashKey);
    } else {
      await p.setString(_selfAvatarHashKey, hash);
    }
  }

  // Friend avatar path storage
  /// Key uses normalized (64-char) friendId so 64-char and 76-char callers share the same entry.
  static String _friendAvatarPathKey(String friendId) =>
      'friend_avatar_path_${normalizeToxId(friendId)}';

  static Future<String?> getFriendAvatarPath(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendAvatarPathKey(friendId), current);
    final value = p.getString(key);
    if (value != null) return value;
    // Fallback 1: avatar may have been saved with raw 76-char id from native
    if (friendId.length > 64) {
      final legacyKey = _scopedKey('friend_avatar_path_$friendId', current);
      final legacy = p.getString(legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        unawaited(setFriendAvatarPath(friendId, legacy));
        return legacy;
      }
    }
    // Fallback 2: avatar stored by service layer without account scoping
    final rawKey = _friendAvatarPathKey(friendId);
    if (rawKey != key) {
      final raw = p.getString(rawKey);
      if (raw != null && raw.isNotEmpty) {
        unawaited(setFriendAvatarPath(friendId, raw));
        return raw;
      }
    }
    return null;
  }

  static Future<void> setFriendAvatarPath(String friendId, String? path) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendAvatarPathKey(friendId), current);
    if (path == null || path.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, path);
    }
  }

  // Friend nickname storage (from Tox, different from remark which is user-edited)
  static String _friendNicknameKey(String friendId) => 'friend_nickname_$friendId';

  static Future<String?> getFriendNickname(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendNicknameKey(friendId), current);
    return p.getString(key);
  }

  static Future<void> setFriendNickname(String friendId, String nickname) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendNicknameKey(friendId), current);
    if (nickname.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, nickname);
    }
  }

  // Friend status message storage (from Tox, selfSignature)
  static String _friendStatusMessageKey(String friendId) => 'friend_status_message_$friendId';

  static Future<String?> getFriendStatusMessage(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendStatusMessageKey(friendId), current);
    return p.getString(key);
  }

  static Future<void> setFriendStatusMessage(String friendId, String statusMessage) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendStatusMessageKey(friendId), current);
    if (statusMessage.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, statusMessage);
    }
  }

  // Friend remark storage (user-edited, different from nickname)
  static String _friendRemarkKey(String friendId) => 'friend_remark_$friendId';

  static Future<String?> getFriendRemark(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendRemarkKey(friendId), current);
    return p.getString(key);
  }

  static Future<void> setFriendRemark(String friendId, String remark) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendRemarkKey(friendId), current);
    if (remark.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, remark);
    }
  }

  // Do not disturb storage
  static String _doNotDisturbKey(String friendId) => 'do_not_disturb_$friendId';

  static Future<bool> getDoNotDisturb(String friendId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_doNotDisturbKey(friendId), current);
    return p.getBool(key) ?? false;
  }

  static Future<void> setDoNotDisturb(String friendId, bool value) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_doNotDisturbKey(friendId), current);
    await p.setBool(key, value);
  }

  // Blacklist storage (user-specific, bound to current user Tox ID)
  static String _blackListKey(String? userToxId) {
    // Use Tox ID if provided, otherwise use 'default' (should not happen in normal flow)
    final toxId = userToxId ?? 'default';
    return 'black_list_$toxId';
  }

  static Future<Set<String>> getBlackList([String? userToxId]) async {
    final p = await _getPrefs();
    final key = _blackListKey(userToxId);
    final list = p.getStringList(key) ?? const <String>[];
    return list.toSet();
  }

  static Future<void> setBlackList(Set<String> userIDs, [String? userToxId]) async {
    final p = await _getPrefs();
    final key = _blackListKey(userToxId);
    await p.setStringList(key, userIDs.toList());
  }

  static Future<void> addToBlackList(List<String> userIDs, [String? userToxId]) async {
    final blackList = await getBlackList(userToxId);
    blackList.addAll(userIDs);
    await setBlackList(blackList, userToxId);
  }

  static Future<void> removeFromBlackList(List<String> userIDs, [String? userToxId]) async {
    final blackList = await getBlackList(userToxId);
    blackList.removeAll(userIDs);
    await setBlackList(blackList, userToxId);
  }

  // Group member name card storage — account-scoped (S6 fix). Two accounts in
  // the same group must not see each other's per-member nick cards.
  static String _groupMemberNameCardKey(String groupId, String userId) => 'group_member_namecard_${groupId}_$userId';

  static Future<String?> getGroupMemberNameCard(String groupId, String userId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final rawKey = _groupMemberNameCardKey(groupId, userId);
    final scopedKey = _scopedKey(rawKey, current);
    final scoped = p.getString(scopedKey);
    if (scoped != null) return scoped;
    if (scopedKey != rawKey) {
      final legacy = p.getString(rawKey);
      if (legacy != null && legacy.isNotEmpty) {
        unawaited(p.setString(scopedKey, legacy));
        unawaited(p.remove(rawKey));
        return legacy;
      }
    }
    return null;
  }

  static Future<void> setGroupMemberNameCard(String groupId, String userId, String nameCard) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final rawKey = _groupMemberNameCardKey(groupId, userId);
    final scopedKey = _scopedKey(rawKey, current);
    if (nameCard.isEmpty) {
      await p.remove(scopedKey);
    } else {
      await p.setString(scopedKey, nameCard);
    }
    if (scopedKey != rawKey) {
      unawaited(p.remove(rawKey));
    }
  }

  // Group owner storage — account-scoped (S6 fix). Different accounts may see
  // different owners for an out-of-sync group; without scope, the most recent
  // account's owner write bleeds into every other account.
  static String _groupOwnerKey(String groupId) => 'group_owner_$groupId';

  static Future<String?> getGroupOwner(String groupId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final rawKey = _groupOwnerKey(groupId);
    final scopedKey = _scopedKey(rawKey, current);
    final scoped = p.getString(scopedKey);
    if (scoped != null) return scoped;
    if (scopedKey != rawKey) {
      final legacy = p.getString(rawKey);
      if (legacy != null && legacy.isNotEmpty) {
        unawaited(p.setString(scopedKey, legacy));
        unawaited(p.remove(rawKey));
        return legacy;
      }
    }
    return null;
  }

  static Future<void> setGroupOwner(String groupId, String userId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final rawKey = _groupOwnerKey(groupId);
    final scopedKey = _scopedKey(rawKey, current);
    await p.setString(scopedKey, userId);
    if (scopedKey != rawKey) {
      unawaited(p.remove(rawKey));
    }
  }

  // Group avatar (faceUrl) storage
  static String _groupAvatarKey(String groupId) => 'group_avatar_$groupId';

  static Future<String?> getGroupAvatar(String groupId) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return null;
    final p = await _getPrefs();
    final key = _scopedKey(_groupAvatarKey(groupId), current);
    return p.getString(key);
  }

  static Future<void> setGroupAvatar(String groupId, String? faceUrl) async {
    final current = await getCurrentAccountToxId();
    if (current == null || current.isEmpty) return;
    final p = await _getPrefs();
    final key = _scopedKey(_groupAvatarKey(groupId), current);
    if (faceUrl == null || faceUrl.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, faceUrl);
    }
  }

  /// Clear per-account data from SharedPreferences for the given account.
  /// Does NOT remove global settings (bootstrap nodes, theme, language, IRC, etc.).
  /// Also cleans up scoped keys and password hash for the account.
  /// Legacy single-account keys are removed when clearing the current account, or
  /// when logged out (current == null) so startup does not use stale identity after
  /// an account is deleted from the login page.
  static Future<void> clearAccountData(String toxId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final scopedSuffix = _scopedKey('', toxId); // '_$prefix' for target account

    final keysToRemove = <String>{};

    // 1) Remove target account's scoped keys only
    if (scopedSuffix.isNotEmpty) {
      for (final key in p.getKeys()) {
        if (key.endsWith(scopedSuffix)) {
          keysToRemove.add(key);
        }
      }
    }

    // 2) Remove only this account's password-related keys
    keysToRemove.add(_accountPasswordKey(toxId));
    keysToRemove.add(_passwordSaltKey(toxId));

    // 3) Legacy single-account keys: clear when deleting current account, or when
    //    logged out (so deleting an account from login page does not leave stale
    //    nickname/auto-login etc. that startup would still read).
    if (current == toxId || current == null) {
      keysToRemove.addAll(<String>{
        _kPinned,
        _kMuted,
        _kGroups,
        _kQuitGroups,
        _kNickname,
        _kStatusMsg,
        _kAvatarPath,
        _kLocalFriends,
        _kCurrentAccountToxId,
        _kCardText,
        _kAutoAcceptFriends,
        _kAutoAcceptGroupInvites,
        _kNotificationSoundEnabled,
        _selfAvatarHashKey,
        _kAutoLogin,
      });
    }

    await Future.wait(keysToRemove.map((key) => p.remove(key)));

    if (toxId.isNotEmpty) {
      await clearScopedKeysForAccount(toxId);
      await removeAccountPassword(toxId);
    }

    if (current == toxId) {
      _cachedCurrentAccountToxId = null;
      _accountToxIdCached = false;
    }
  }

  /// Remove all SharedPreferences keys scoped to the given account.
  /// Call this when deleting an account so that account's data does not remain.
  static Future<void> clearScopedKeysForAccount(String toxId) async {
    if (toxId.isEmpty) return;
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final suffix = '_$prefix';
    final p = await _getPrefs();
    final keysToRemove = p.getKeys().where((key) => key.endsWith(suffix)).toList();
    await Future.wait(keysToRemove.map((key) => p.remove(key)));
  }

  /// Export all scoped preferences for an account as a serializable map.
  /// Used for full backup (.zip) export.
  static Future<Map<String, dynamic>> exportScopedPrefsForAccount(String toxId) async {
    if (toxId.isEmpty) return {};
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final suffix = '_$prefix';
    final p = await _getPrefs();
    final result = <String, dynamic>{};
    for (final key in p.getKeys()) {
      if (key.endsWith(suffix)) {
        // Strip suffix to get base key name for portability
        final baseKey = key.substring(0, key.length - suffix.length);
        final value = p.get(key);
        if (value != null) {
          result[baseKey] = value;
        }
      }
    }
    return result;
  }

  /// Import scoped preferences for an account from a map.
  /// Used for full backup (.zip) import/restore.
  ///
  /// Each key is imported independently inside a try/catch: if one entry
  /// has a malformed value (e.g. a `List<dynamic>` whose elements aren't
  /// all strings, triggering a CastError inside `.cast<String>()`), we
  /// log a structured warning and continue with the rest of the keys. A
  /// partial restore is strictly better than failing the whole import and
  /// leaving the user with nothing — the user can re-import or repair the
  /// offending key later.
  static Future<void> importScopedPrefsForAccount(String toxId, Map<String, dynamic> data) async {
    if (toxId.isEmpty) return;
    final prefix = toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
    final p = await _getPrefs();
    for (final entry in data.entries) {
      final scopedKey = '${entry.key}_$prefix';
      final value = entry.value;
      try {
        if (value is String) {
          await p.setString(scopedKey, value);
        } else if (value is int) {
          await p.setInt(scopedKey, value);
        } else if (value is double) {
          await p.setDouble(scopedKey, value);
        } else if (value is bool) {
          await p.setBool(scopedKey, value);
        } else if (value is List) {
          // .cast<String>() is lazy; force materialization so any
          // non-string element throws here (in the try) rather than later
          // inside SharedPreferences.
          await p.setStringList(scopedKey, List<String>.from(value));
        }
        // Other types (null, Map, etc.) are silently skipped — there's no
        // SharedPreferences setter for them.
      } catch (e, st) {
        AppLogger.warn(
            '[Prefs.importScopedPrefsForAccount] skipping key '
            '"${entry.key}" for account prefix=$prefix: $e\n$st');
      }
    }
  }

  // IRC App management
  static Future<bool> getIrcAppInstalled() async {
    final p = await _getPrefs();
    return _getIrcAppInstalledImpl(p);
  }

  static Future<void> setIrcAppInstalled(bool installed) async {
    final p = await _getPrefs();
    return _setIrcAppInstalledImpl(p, installed);
  }

  static Future<List<String>> getIrcChannels() async {
    final p = await _getPrefs();
    return _getIrcChannelsImpl(p);
  }

  static Future<void> setIrcChannels(List<String> channels) async {
    final p = await _getPrefs();
    return _setIrcChannelsImpl(p, channels);
  }

  static Future<void> addIrcChannel(String channel) async {
    final channels = await getIrcChannels();
    if (!channels.contains(channel)) {
      channels.add(channel);
      await setIrcChannels(channels);
    }
  }

  static Future<void> removeIrcChannel(String channel) async {
    final channels = await getIrcChannels();
    channels.remove(channel);
    await setIrcChannels(channels);
    // Remove password when channel is removed
    await removeIrcChannelPassword(channel);
  }

  static Future<String?> getIrcChannelPassword(String channel) async {
    final key = _ircChannelPasswordKey(channel);
    // Prefer secure storage
    final fromSecure = await _secureStorage.read(key: key);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
    // Migrate from legacy SharedPreferences
    final p = await _getPrefs();
    final legacy = p.getString(key);
    if (legacy != null) {
      await _secureStorage.write(key: key, value: legacy);
      await p.remove(key);
      return legacy;
    }
    return null;
  }

  static Future<void> setIrcChannelPassword(String channel, String? password) async {
    final key = _ircChannelPasswordKey(channel);
    if (password == null || password.isEmpty) {
      await _secureStorage.delete(key: key);
      final p = await _getPrefs();
      await p.remove(key);
    } else {
      await _secureStorage.write(key: key, value: password);
      final p = await _getPrefs();
      await p.remove(key);
    }
  }

  static Future<void> removeIrcChannelPassword(String channel) async {
    final key = _ircChannelPasswordKey(channel);
    await _secureStorage.delete(key: key);
    final p = await _getPrefs();
    await p.remove(key);
  }

  // IRC Server Configuration
  static Future<String> getIrcServer() async {
    final p = await _getPrefs();
    return _getIrcServerImpl(p);
  }

  static Future<void> setIrcServer(String server) async {
    final p = await _getPrefs();
    return _setIrcServerImpl(p, server);
  }

  static Future<int> getIrcPort() async {
    final p = await _getPrefs();
    return _getIrcPortImpl(p);
  }

  static Future<void> setIrcPort(int port) async {
    final p = await _getPrefs();
    return _setIrcPortImpl(p, port);
  }

  static Future<bool> getIrcUseSasl() async {
    final p = await _getPrefs();
    return _getIrcUseSaslImpl(p);
  }

  static Future<void> setIrcUseSasl(bool useSasl) async {
    final p = await _getPrefs();
    return _setIrcUseSaslImpl(p, useSasl);
  }

  // Account list management for multiple accounts
  static const _kAccountList = 'account_list'; // JSON array of account info

  // Legacy SharedPreferences keys for password hash + salt. Kept ONLY for
  // read-time migration into secure storage; new writes never touch these.
  // Both forms (`account_password_<toxId>` hash, `account_password_salt_<toxId>`
  // salt) were stored as plain text in SharedPreferences and would otherwise
  // sync to iCloud on iOS and sit as world-readable XML on rooted Android.
  static String _accountPasswordKey(String toxId) => 'account_password_$toxId';

  // Secure-storage keys (Keychain on iOS/macOS, Keystore on Android, libsecret/
  // DPAPI on Linux/Windows). flutter_secure_storage defaults to
  // kSecAttrAccessibleWhenUnlocked (non-iCloud-synced) on Apple platforms.
  static String _securePasswordKey(String toxId) => 'pwd_$toxId';
  static String _securePasswordSaltKey(String toxId) => 'pwd_salt_$toxId';

  /// Read PBKDF2 hash from secure storage, migrating any legacy plain-prefs
  /// value into the secure store on first hit. Returns null when no password
  /// is set for the account.
  static Future<String?> _readPasswordHashWithMigration(String toxId) async {
    if (toxId.isEmpty) return null;
    final secureKey = _securePasswordKey(toxId);
    final fromSecure = await _secureRead(secureKey);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
    // Migrate from legacy SharedPreferences (S1: was plain-text on disk).
    final p = await _getPrefs();
    final legacy = p.getString(_accountPasswordKey(toxId));
    if (legacy != null && legacy.isNotEmpty) {
      await _secureWrite(secureKey, legacy);
      await p.remove(_accountPasswordKey(toxId));
      return legacy;
    }
    return null;
  }

  /// Read salt from secure storage, migrating from legacy plain prefs when
  /// present. Returns null when no salt is stored.
  static Future<String?> _readPasswordSaltWithMigration(String toxId) async {
    if (toxId.isEmpty) return null;
    final secureKey = _securePasswordSaltKey(toxId);
    final fromSecure = await _secureRead(secureKey);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
    final p = await _getPrefs();
    final legacy = p.getString(_passwordSaltKey(toxId));
    if (legacy != null && legacy.isNotEmpty) {
      await _secureWrite(secureKey, legacy);
      await p.remove(_passwordSaltKey(toxId));
      return legacy;
    }
    return null;
  }

  /// Account info structure: {toxId (required), nickname, statusMessage, lastLoginTime?, avatarPath?, autoLogin?, ...}
  /// toxId is the primary key for account identification
  static Future<List<Map<String, String>>> getAccountList() async {
    final p = await _getPrefs();
    return _getAccountListImpl(p);
  }

  /// Typed account summaries; preferred over [getAccountList] where type safety helps.
  static Future<List<AccountSummary>> getAccountSummaries() async {
    final raw = await getAccountList();
    return raw.map(AccountSummary.fromMap).toList(growable: false);
  }

  static Future<void> setAccountList(List<Map<String, String>> accounts) async {
    final p = await _getPrefs();
    return _setAccountListImpl(p, accounts);
  }

  /// Add or update an account in the list
  /// toxId is required and used as the primary key
  /// If account with same toxId exists, it will be updated (including nickname)
  static Future<void> addAccount({
    required String toxId,
    String? nickname,
    String? statusMessage,
    String? avatarPath,
    bool? autoLogin,
    bool? autoAcceptFriends,
    bool? autoAcceptGroupInvites,
    bool? notificationSoundEnabled,
  }) async {
    if (toxId.isEmpty) {
      throw ArgumentError('toxId cannot be empty');
    }
    final accounts = await getAccountList();
    final normalizedNickname = nickname?.trim();
    if (normalizedNickname != null && normalizedNickname.isNotEmpty) {
      final duplicate = accounts.any((acc) =>
          acc['toxId'] != toxId &&
          (acc['nickname'] ?? '').trim() == normalizedNickname);
      if (duplicate) {
        throw StateError('Nickname already used by another account');
      }
    }
    // Find existing account by Tox ID (primary key)
    final existingIndex = accounts.indexWhere((acc) => acc['toxId'] == toxId);
    Map<String, String> account;
    
    if (existingIndex >= 0) {
      // Update existing account
      account = accounts[existingIndex];
      account['lastLoginTime'] = DateTime.now().toIso8601String();
      // Update nickname if provided (allows nickname changes)
      if (nickname != null && nickname.isNotEmpty) {
        account['nickname'] = nickname;
      }
      if (statusMessage != null) {
        account['statusMessage'] = statusMessage;
      }
      if (avatarPath != null) {
        account['avatarPath'] = avatarPath;
      }
      if (autoLogin != null) {
        account['autoLogin'] = autoLogin.toString();
      }
      if (autoAcceptFriends != null) {
        account['autoAcceptFriends'] = autoAcceptFriends.toString();
      }
      if (autoAcceptGroupInvites != null) {
        account['autoAcceptGroupInvites'] = autoAcceptGroupInvites.toString();
      }
      if (notificationSoundEnabled != null) {
        account['notificationSoundEnabled'] = notificationSoundEnabled.toString();
      }
      accounts[existingIndex] = account;
    } else {
      // Add new account
      account = <String, String>{
        'toxId': toxId,
        'nickname': nickname ?? '',
        'statusMessage': statusMessage ?? '',
        'lastLoginTime': DateTime.now().toIso8601String(),
      };
      if (avatarPath != null && avatarPath.isNotEmpty) {
        account['avatarPath'] = avatarPath;
      }
      if (autoLogin != null) {
        account['autoLogin'] = autoLogin.toString();
      } else {
        account['autoLogin'] = 'true'; // Default to true
      }
      if (autoAcceptFriends != null) {
        account['autoAcceptFriends'] = autoAcceptFriends.toString();
      } else {
        account['autoAcceptFriends'] = 'false'; // Default to false
      }
      if (autoAcceptGroupInvites != null) {
        account['autoAcceptGroupInvites'] = autoAcceptGroupInvites.toString();
      } else {
        account['autoAcceptGroupInvites'] = 'false'; // Default to false
      }
      if (notificationSoundEnabled != null) {
        account['notificationSoundEnabled'] = notificationSoundEnabled.toString();
      } else {
        account['notificationSoundEnabled'] = 'true'; // Default to true
      }
      accounts.add(account);
    }
    await setAccountList(accounts);
  }

  /// Remove an account from the list by Tox ID
  static Future<void> removeAccount(String toxId) async {
    final accounts = await getAccountList();
    accounts.removeWhere((acc) => acc['toxId'] == toxId);
    await setAccountList(accounts);
  }

  /// Update only the avatar path for an existing account (by toxId).
  /// No-op if account not found.
  static Future<void> setAccountAvatarPath(String toxId, String? path) async {
    if (toxId.isEmpty) return;
    final accounts = await getAccountList();
    final index = accounts.indexWhere((acc) => acc['toxId'] == toxId);
    if (index < 0) return;
    if (path == null || path.isEmpty) {
      accounts[index].remove('avatarPath');
    } else {
      accounts[index]['avatarPath'] = path;
    }
    await setAccountList(accounts);
  }

  /// Get account info by Tox ID (primary key).
  /// Normalizes toxId by trimming whitespace for matching.
  ///
  /// Fallback ordering (preserved across the C9 refactor):
  ///   1. exact match
  ///   2. case-insensitive match
  ///   3. 64-char prefix match (for long toxIds)
  ///   4. compareToxIds predicate (e.g. 16-char list entry vs 64-char lookup)
  ///
  /// Uses [firstWhereOrNull] instead of `firstWhere` + try/catch StateError,
  /// so no exception-as-control-flow.
  static Future<Map<String, String>?> getAccountByToxId(String toxId) async {
    final normalizedToxId = toxId.trim();
    final accounts = await getAccountList();

    // 1. Exact match
    final exact = accounts.firstWhereOrNull((acc) {
      final accToxId = acc['toxId']?.trim() ?? '';
      return accToxId == normalizedToxId;
    });
    if (exact != null) return exact;

    // 2. Case-insensitive match
    final lowered = normalizedToxId.toLowerCase();
    final ci = accounts.firstWhereOrNull((acc) {
      final accToxId = acc['toxId']?.trim() ?? '';
      return accToxId.toLowerCase() == lowered;
    });
    if (ci != null) return ci;

    // 3. 64-char prefix match (only for long lookups)
    if (normalizedToxId.length >= 64) {
      final prefix = normalizedToxId.substring(0, 64);
      final byPrefix = accounts.firstWhereOrNull((acc) {
        final accToxId = acc['toxId']?.trim() ?? '';
        if (accToxId.length >= 64) {
          return accToxId.substring(0, 64) == prefix;
        }
        return false;
      });
      if (byPrefix != null) return byPrefix;
    }

    // 4. compareToxIds fallback (covers 16-char list entry vs 64-char lookup)
    return accounts.firstWhereOrNull((acc) {
      final accToxId = acc['toxId']?.trim() ?? '';
      return compareToxIds(accToxId, normalizedToxId);
    });
  }

  /// All accounts whose nickname (trimmed) matches [nickname].
  static Future<List<Map<String, String>>> getAccountsByNickname(String nickname) async {
    final normalized = nickname.trim();
    final accounts = await getAccountList();
    return accounts
        .where((acc) => (acc['nickname'] ?? '').trim() == normalized)
        .toList();
  }

  /// Account whose nickname uniquely matches [nickname].
  /// Returns null if no match. Throws [StateError] if more than one account has that nickname.
  static Future<Map<String, String>?> getUniqueAccountByNickname(String nickname) async {
    final matches = await getAccountsByNickname(nickname);
    if (matches.isEmpty) return null;
    if (matches.length > 1) {
      throw StateError('Duplicate nickname: $nickname');
    }
    return matches.single;
  }

  /// Get account info by nickname (for backward compatibility and login flow)
  /// Note: This may return null if nickname is not unique
  static Future<Map<String, String>?> getAccountByNickname(String nickname) async {
    final accounts = await getAccountList();
    try {
      return accounts.firstWhere((acc) => acc['nickname'] == nickname);
    } catch (e) {
      return null;
    }
  }

  // Account password management — secure-storage backed since S1 review.
  // Hash + salt live in flutter_secure_storage (Keychain / Keystore / libsecret
  // / DPAPI). Any pre-existing plain-prefs values get migrated on first read.

  /// Check if an account has a password set.
  static Future<bool> hasAccountPassword(String toxId) async {
    if (toxId.isEmpty) return false;
    return (await _readPasswordHashWithMigration(toxId)) != null;
  }

  /// Get account password hash (for verification). Migrates legacy plain-prefs
  /// values into secure storage on first read.
  static Future<String?> getAccountPasswordHash(String toxId) async {
    return _readPasswordHashWithMigration(toxId);
  }

  /// Set account password (stores PBKDF2 hash + salt in secure storage).
  /// New accounts use PBKDF2; legacy SHA256 hashes are migrated on next
  /// successful verify. Also clears any legacy plain-prefs entries.
  static Future<void> setAccountPassword(String toxId, String password) async {
    if (toxId.isEmpty) {
      throw ArgumentError('toxId cannot be empty');
    }
    if (password.isEmpty) {
      await removeAccountPassword(toxId);
      return;
    }
    final salt = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: _pbkdf2Bits,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final hashBytes = await secretKey.extractBytes();
    final storedHash = '$_kPbkdf2Prefix${base64Encode(hashBytes)}';
    final storedSalt = base64Encode(salt);

    await _secureWrite(_securePasswordKey(toxId), storedHash);
    await _secureWrite(_securePasswordSaltKey(toxId), storedSalt);
    // Drop legacy plain-prefs entries if a prior install left them behind.
    final p = await _getPrefs();
    await Future.wait([
      p.remove(_accountPasswordKey(toxId)),
      p.remove(_passwordSaltKey(toxId)),
    ]);
  }

  /// Remove account password and its salt from both secure storage and any
  /// remaining legacy SharedPreferences entries.
  static Future<void> removeAccountPassword(String toxId) async {
    if (toxId.isEmpty) return;
    await _secureDelete(_securePasswordKey(toxId));
    await _secureDelete(_securePasswordSaltKey(toxId));
    final p = await _getPrefs();
    await Future.wait([
      p.remove(_accountPasswordKey(toxId)),
      p.remove(_passwordSaltKey(toxId)),
    ]);
  }

  /// Verify account password.
  /// Supports PBKDF2 (new) and SHA256 salted/unsalted (legacy); migrates legacy
  /// on success. Reads from secure storage with backward-compat plain-prefs
  /// migration.
  static Future<bool> verifyAccountPassword(String toxId, String password) async {
    if (toxId.isEmpty || password.isEmpty) return false;

    final storedHash = await _readPasswordHashWithMigration(toxId);
    if (storedHash == null) return false;
    final saltBase64 = await _readPasswordSaltWithMigration(toxId);

    if (storedHash.startsWith(_kPbkdf2Prefix)) {
      if (saltBase64 == null) return false;
      List<int> salt;
      try {
        salt = base64Decode(saltBase64);
      } catch (_) {
        return false;
      }
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: _pbkdf2Iterations,
        bits: _pbkdf2Bits,
      );
      final secretKey = await pbkdf2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final hashBytes = await secretKey.extractBytes();
      final expected = base64Encode(hashBytes);
      final actual = storedHash.substring(_kPbkdf2Prefix.length);
      return actual == expected;
    }

    // Legacy SHA256 (salted or unsalted) — migrate on success.
    if (saltBase64 != null && saltBase64.isNotEmpty) {
      final bytes = utf8.encode('$saltBase64$password');
      final hash = crypto.sha256.convert(bytes);
      if (storedHash == hash.toString()) {
        await setAccountPassword(toxId, password);
        return true;
      }
      return false;
    }
    final bytes = utf8.encode(password);
    final hash = crypto.sha256.convert(bytes);
    if (storedHash == hash.toString()) {
      await setAccountPassword(toxId, password);
      return true;
    }
    return false;
  }

  // --- Window/layout state (desktop) ---

  /// Saved window bounds (left, top, width, height). Null if not set or invalid.
  static Future<Rect?> getWindowBounds() async {
    final p = await _getPrefs();
    return _getWindowBoundsImpl(p);
  }

  static Future<void> setWindowBounds(Rect rect) async {
    final p = await _getPrefs();
    return _setWindowBoundsImpl(p, rect);
  }

  static Future<bool> getWindowMaximized() async {
    final p = await _getPrefs();
    return _getWindowMaximizedImpl(p);
  }

  static Future<void> setWindowMaximized(bool value) async {
    final p = await _getPrefs();
    return _setWindowMaximizedImpl(p, value);
  }

  /// Saved splitter position (e.g. conversation list width in logical pixels, or ratio 0.0–1.0). Null if not set.
  static Future<double?> getSplitterPosition() async {
    final p = await _getPrefs();
    final v = p.getDouble(_kSplitterPosition);
    return v;
  }

  static Future<void> setSplitterPosition(double value) async {
    final p = await _getPrefs();
    await p.setDouble(_kSplitterPosition, value);
  }

  // --- Friend list sorting (name vs activity) ---

  /// 'name' or 'activity'. Default 'name'.
  static Future<String> getFriendListSortingMode() async {
    final p = await _getPrefs();
    final v = p.getString(_kFriendListSortingMode) ?? 'name';
    return (v == 'activity' || v == 'name') ? v : 'name';
  }

  static Future<void> setFriendListSortingMode(String mode) async {
    final p = await _getPrefs();
    await p.setString(_kFriendListSortingMode, mode == 'activity' ? 'activity' : 'name');
  }

  /// Last activity time (milliseconds since epoch) for a friend. Used for "sort by activity".
  static Future<DateTime?> getFriendActivity(String userId) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendActivityKey(userId), current);
    final ms = p.getInt(key);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> setFriendActivity(String userId, DateTime time) async {
    final p = await _getPrefs();
    final current = await getCurrentAccountToxId();
    final key = _scopedKey(_friendActivityKey(userId), current);
    await p.setInt(key, time.millisecondsSinceEpoch);
  }
}


