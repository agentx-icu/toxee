import 'dart:ui';
import '../prefs.dart';
import 'prefs_interfaces.dart';

/// Single implementation of all Prefs interfaces, delegating to [Prefs] static methods.
///
/// STATUS (audited 2026-08-07): **unfinished migration — currently dead code.**
/// Nothing under `lib/`, `test/`, `integration_test/` or `tool/` constructs
/// [PrefsImpl] or references [PrefsImpl.global]; every callsite still goes
/// through the static [Prefs] facade. The file is kept (not deleted) because
/// it is the declared migration target: see the class doc on [Prefs] in
/// `lib/util/prefs.dart` and TODOS.md item 7 ("`Prefs` god class — split into
/// focused services"), which names this file as the seam that split lands on.
///
/// Do NOT treat this as a working abstraction: it has no injection point (the
/// doc line below about passing `SharedPreferences` in tests was never
/// implemented — the constructor takes no arguments and everything re-delegates
/// to the static cache inside [Prefs]). Either finish TODOS.md item 7 or delete
/// this file together with `prefs_interfaces.dart`.
class PrefsImpl implements ICorePrefs, IFriendPrefs, IUIPrefs, INotificationPrefs {
  PrefsImpl();

  static PrefsImpl? _global;

  /// Global instance; uses [Prefs] under the hood (no stored SharedPreferences).
  static PrefsImpl get global => _global ??= PrefsImpl();

  @override
  Future<String?> getServerId() => Prefs.getServerId();
  @override
  Future<void> setServerId(String value) => Prefs.setServerId(value);
  @override
  Future<({String host, int port, String pubkey})?> getCurrentBootstrapNode() =>
      Prefs.getCurrentBootstrapNode();
  @override
  Future<void> setCurrentBootstrapNode(String host, int port, String pubkey) =>
      Prefs.setCurrentBootstrapNode(host, port, pubkey);
  @override
  Future<void> clearCurrentBootstrapNode() => Prefs.clearCurrentBootstrapNode();
  @override
  Future<String> getBootstrapNodeMode() => Prefs.getBootstrapNodeMode();
  @override
  Future<void> setBootstrapNodeMode(String mode) => Prefs.setBootstrapNodeMode(mode);
  @override
  Future<int> getLanBootstrapPort() => Prefs.getLanBootstrapPort();
  @override
  Future<void> setLanBootstrapPort(int port) => Prefs.setLanBootstrapPort(port);
  @override
  Future<bool> getLanBootstrapServiceRunning() => Prefs.getLanBootstrapServiceRunning();
  @override
  Future<void> setLanBootstrapServiceRunning(bool running) =>
      Prefs.setLanBootstrapServiceRunning(running);

  @override
  Future<Set<String>> getPinned() => Prefs.getPinned();
  @override
  Future<void> setPinned(Set<String> peers) => Prefs.setPinned(peers);
  @override
  Future<Set<String>> getMuted() => Prefs.getMuted();
  @override
  Future<void> setMuted(Set<String> peers) => Prefs.setMuted(peers);
  @override
  Future<Set<String>> getLocalFriends() => Prefs.getLocalFriends();
  @override
  Future<void> setLocalFriends(Set<String> ids) => Prefs.setLocalFriends(ids);
  @override
  Future<Set<String>> getGroups() => Prefs.getGroups();
  @override
  Future<void> setGroups(Set<String> groups) => Prefs.setGroups(groups);
  @override
  Future<Set<String>> getQuitGroups() => Prefs.getQuitGroups();
  @override
  Future<void> setQuitGroups(Set<String> groups) => Prefs.setQuitGroups(groups);
  @override
  Future<String?> getGroupName(String groupId) => Prefs.getGroupName(groupId);
  @override
  Future<void> setGroupName(String groupId, String name) => Prefs.setGroupName(groupId, name);
  @override
  Future<String?> getFriendNickname(String userId) => Prefs.getFriendNickname(userId);
  @override
  Future<void> setFriendNickname(String userId, String? nickname) =>
      Prefs.setFriendNickname(userId, nickname ?? '');
  @override
  Future<String?> getFriendAvatarPath(String userId) => Prefs.getFriendAvatarPath(userId);
  @override
  Future<void> setFriendAvatarPath(String userId, String? path) =>
      Prefs.setFriendAvatarPath(userId, path);

  @override
  Future<String> getThemeMode() => Prefs.getThemeMode();
  @override
  Future<void> setThemeMode(String mode) => Prefs.setThemeMode(mode);
  @override
  Future<String?> getLanguageCode() => Prefs.getLanguageCode();
  @override
  Future<void> setLanguageCode(String code) => Prefs.setLanguageCode(code);
  @override
  Future<Locale?> getLocale() => Prefs.getLocale();
  @override
  Future<void> setLocale(Locale locale) => Prefs.setLocale(locale);
  @override
  Future<String?> getNickname() => Prefs.getNickname();
  @override
  Future<void> setNickname(String value) => Prefs.setNickname(value);
  @override
  Future<String?> getStatusMessage() => Prefs.getStatusMessage();
  @override
  Future<void> setStatusMessage(String value) => Prefs.setStatusMessage(value);
  @override
  Future<String?> getAvatarPath() => Prefs.getAvatarPath();
  @override
  Future<void> setAvatarPath(String? path) => Prefs.setAvatarPath(path);
  @override
  Future<String?> getCardText() => Prefs.getCardText();
  @override
  Future<void> setCardText(String? text) => Prefs.setCardText(text);
  @override
  Future<String?> getDraft(String peerId) => Prefs.getDraft(peerId);
  @override
  Future<void> setDraft(String peerId, String text) => Prefs.setDraft(peerId, text);
  @override
  Future<Rect?> getWindowBounds() => Prefs.getWindowBounds();
  @override
  Future<void> setWindowBounds(Rect rect) => Prefs.setWindowBounds(rect);
  @override
  Future<bool> getWindowMaximized() => Prefs.getWindowMaximized();
  @override
  Future<void> setWindowMaximized(bool value) => Prefs.setWindowMaximized(value);
  @override
  Future<double?> getSplitterPosition() => Prefs.getSplitterPosition();
  @override
  Future<void> setSplitterPosition(double value) => Prefs.setSplitterPosition(value);
  @override
  Future<String?> getDownloadsDirectory() => Prefs.getDownloadsDirectory();
  @override
  Future<void> setDownloadsDirectory(String? path) => Prefs.setDownloadsDirectory(path);

  @override
  Future<bool> getNotificationSoundEnabled([String? toxId]) =>
      Prefs.getNotificationSoundEnabled(toxId);
  @override
  Future<void> setNotificationSoundEnabled(bool value, [String? toxId]) =>
      Prefs.setNotificationSoundEnabled(value, toxId);
  @override
  Future<bool> getAutoAcceptFriends([String? toxId]) => Prefs.getAutoAcceptFriends(toxId);
  @override
  Future<void> setAutoAcceptFriends(bool value, [String? toxId]) =>
      Prefs.setAutoAcceptFriends(value, toxId);
  @override
  Future<bool> getAutoAcceptGroupInvites([String? toxId]) =>
      Prefs.getAutoAcceptGroupInvites(toxId);
  @override
  Future<void> setAutoAcceptGroupInvites(bool value, [String? toxId]) =>
      Prefs.setAutoAcceptGroupInvites(value, toxId);
  @override
  Future<bool> getAutoLogin([String? toxId]) => Prefs.getAutoLogin(toxId);
  @override
  Future<void> setAutoLogin(bool value, [String? toxId]) => Prefs.setAutoLogin(value, toxId);
}
