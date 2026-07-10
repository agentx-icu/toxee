import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'ffi_chat_service_account_key.dart';
import 'prefs.dart';
import 'dart:io';
import 'logger.dart';

/// Outcome of [IrcAppManager.addChannel]. Distinguishes "the channel/group was
/// created" from "the live IRC connection was actually initiated", so the UI can
/// tell the user the honest state instead of always reporting plain success.
class IrcAddChannelResult {
  const IrcAddChannelResult({
    required this.added,
    required this.connected,
    this.groupId,
  });

  /// The channel exists locally (its Tox group was created / already present).
  final bool added;

  /// The native IRC connect was successfully initiated. False when the IRC
  /// library isn't loaded (e.g. unsupported platform) or the FFI rejected it.
  final bool connected;

  /// The mapped Tox group id, when [added].
  final String? groupId;
}

/// How the chats-tab "+" → join-IRC flow reacts to an [IrcAddChannelResult].
/// Pure classification of the three honest outcomes, extracted so the mapping
/// is unit-testable without pumping a HomePage. Success here REQUIRES a
/// [IrcAddChannelResult.groupId] because that entry point opens the group via
/// `_handleGroupChanged(groupId)`. (The Applications page has equivalent inline
/// messaging but doesn't consume the groupId — it refreshes from a state
/// snapshot — so it keys off `added` alone rather than reusing this helper.)
enum IrcAddChannelUiOutcome {
  /// Channel + group created AND the live IRC connection came up.
  addedConnected,

  /// Channel + group created but the live connection did not start (e.g. IRC
  /// unavailable on this platform). Report honestly, not as plain success.
  addedNotConnected,

  /// The channel/group could not be created at all — a hard failure.
  failed,
}

IrcAddChannelUiOutcome classifyIrcAddChannelResult(IrcAddChannelResult result) {
  if (!result.added || result.groupId == null) {
    return IrcAddChannelUiOutcome.failed;
  }
  return result.connected
      ? IrcAddChannelUiOutcome.addedConnected
      : IrcAddChannelUiOutcome.addedNotConnected;
}

/// Manages IRC application state and channels
class IrcAppManager {
  static final IrcAppManager _instance = IrcAppManager._internal();
  factory IrcAppManager() => _instance;
  IrcAppManager._internal();

  bool _isInstalled = false;
  List<String> _channels = [];
  final Map<String, String> _channelToGroupId = {}; // Map channel name to group ID

  /// Initialize from persisted data
  Future<void> init() async {
    _isInstalled = await Prefs.getIrcAppInstalled();
    _channels = await Prefs.getIrcChannels();
  }

  /// Check if IRC app is installed
  bool get isInstalled => _isInstalled;

  /// Get list of IRC channels
  List<String> get channels => List.unmodifiable(_channels);

  /// Get group ID for a channel
  String? getGroupIdForChannel(String channel) {
    return _channelToGroupId[channel];
  }

  /// Install the IRC app (loads dynamic library).
  ///
  /// Returns whether the native IRC client library loaded. Installation itself
  /// always succeeds (the app concept can exist without a live connection — the
  /// pure-Dart group flow and tests rely on that), but the return lets the UI
  /// warn honestly when live IRC is unavailable on this platform instead of
  /// showing an unqualified "Installed" with silently-broken connections.
  Future<bool> install(FfiChatService service) async {
    _isInstalled = true;
    await Prefs.setIrcAppInstalled(true);

    // Load IRC dynamic library (platform-aware: .dll/.so/.dylib).
    final libraryPath = _ircLibraryPath();

    final success = await service.loadIrcLibrary(libraryPath);
    if (!success) {
      AppLogger.log('[IRC] Failed to load IRC dynamic library from: $libraryPath');
      // Don't fail installation, but log the error
    } else {
      AppLogger.log('[IRC] IRC dynamic library loaded successfully');
    }
    return success;
  }

  /// Uninstall the IRC app (removes all channels and quits groups, unloads library)
  Future<void> uninstall(FfiChatService service) async {
    // Disconnect all IRC channels first
    for (final channel in _channels) {
      await service.disconnectIrcChannel(channel);
    }
    
    // Quit all IRC groups
    for (final channel in _channels) {
      final groupId = _channelToGroupId[channel];
      if (groupId != null) {
        await service.quitGroup(groupId);
      }
    }
    // Clear channels
    _channels.clear();
    _channelToGroupId.clear();
    await Prefs.setIrcChannels([]);
    
    // Unload IRC dynamic library
    final success = await service.unloadIrcLibrary();
    if (!success) {
      AppLogger.log('[IRC] Failed to unload IRC dynamic library');
    } else {
      AppLogger.log('[IRC] IRC dynamic library unloaded successfully');
    }
    
    // Mark as uninstalled
    _isInstalled = false;
    await Prefs.setIrcAppInstalled(false);
  }

  /// Reset in-memory cache without performing IRC disconnection or library unloading.
  /// Called during account teardown when the FfiChatService is about to be disposed.
  void resetCache() {
    _isInstalled = false;
    _channels = [];
    _channelToGroupId.clear();
  }

  /// Tear down LIVE native IRC state for the account being logged out, WITHOUT
  /// touching persisted channels (they belong to that account and must survive
  /// for its next login).
  ///
  /// Why this exists: [resetCache] only clears Dart memory. The native
  /// `IrcClientManager` keeps its own channel threads + sockets, and inbound IRC
  /// messages forward to whatever the *current* Tox instance is, using the old
  /// channel's stored group id. If we only reset the Dart cache on account
  /// switch, account A's IRC sockets keep running and can bleed A's channel
  /// traffic into account B's Tox instance. So we disconnect every live channel
  /// (graceful QUIT + stop threads) here.
  ///
  /// We deliberately do NOT unload the library here — only disconnect the
  /// channels. Disconnecting already empties the native channel table (so
  /// there's no cross-account bleed), and the next account's boot re-registers
  /// its own IRC callbacks against the still-loaded library. Unloading would be
  /// wasted work on every switch (the next account just reloads it), and the
  /// native library is never actually unmapped anyway (`unload` is a logical
  /// unload that leaves the image mapped so in-flight DNS resolver threads can
  /// finish safely).
  ///
  /// Must run while [service] is still alive (before `service.dispose()`).
  /// Best-effort: teardown must never throw.
  Future<void> shutdownSession(FfiChatService service) async {
    try {
      if (await service.isIrcLibraryLoaded()) {
        for (final channel in _channels) {
          await service.disconnectIrcChannel(channel);
        }
      }
    } catch (e, st) {
      AppLogger.log('[IRC] shutdownSession error (non-fatal): $e\n$st');
    } finally {
      resetCache();
    }
  }

  /// Resolve the IRC client native library path for the CURRENT platform. The
  /// library is named per-platform — `libirc_client.dll` (Windows),
  /// `libirc_client.so` (Android/Linux), `libirc_client.dylib` (macOS/iOS) — so
  /// the loader must NOT hardcode `.dylib` (that made `loadIrcLibrary` fail on
  /// Windows/Android even when the matching library was bundled). On desktop the
  /// library is bundled next to the executable; on Android the bundled `.so` is
  /// resolved by bare name from the APK's native-lib dir.
  String _ircLibraryPath() {
    final String fileName;
    if (Platform.isWindows) {
      fileName = 'libirc_client.dll';
    } else if (Platform.isMacOS || Platform.isIOS) {
      fileName = 'libirc_client.dylib';
    } else {
      fileName = 'libirc_client.so'; // Android + Linux
    }
    if (Platform.isAndroid) {
      return fileName;
    }
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final candidate = File('${exeDir.path}/$fileName');
      if (candidate.existsSync()) return candidate.path;
    } catch (_) {
      // Fall through to the bare name (let the dynamic loader search).
    }
    return fileName;
  }

  /// Add an IRC channel and create/join the corresponding group.
  /// [password] is optional and will be stored for future IRC synchronization.
  /// [customNickname] is persisted so it is reused on reconnect/restart.
  Future<IrcAddChannelResult> addChannel(
    String channel,
    FfiChatService service, {
    String? password,
    String? customNickname,
  }) async {
    if (_channels.contains(channel)) {
      // Channel already exists, update password / nickname if provided
      if (password != null) {
        await Prefs.setIrcChannelPassword(channel, password);
      }
      if (customNickname != null) {
        await Prefs.setIrcChannelNickname(channel, customNickname);
      }
      // Resolve the group mapping if it wasn't restored yet. The home "Join
      // IRC" flow calls init() (which loads _channels) WITHOUT
      // restoreChannelMappings(), so a channel persisted from a previous
      // session is in _channels but not _channelToGroupId — returning a null
      // groupId there made the caller report a false "add failed".
      var groupId = _channelToGroupId[channel];
      groupId ??= await _resolveGroupIdForChannel(channel, service);
      if (groupId != null) {
        _channelToGroupId[channel] = groupId;
      }
      // Report the honest live-connection state rather than assuming connected.
      final connected = await service.isIrcChannelConnected(channel);
      return IrcAddChannelResult(
        added: groupId != null,
        connected: connected,
        groupId: groupId,
      );
    }

    // Create a group for this IRC channel
    // Use channel name as group name, prefixed with "IRC: "
    final groupName = 'IRC: $channel';
    final groupId = await service.createGroup(groupName);

    if (groupId == null || groupId.isEmpty) {
      return const IrcAddChannelResult(added: false, connected: false);
    }

    _channels.add(channel);
    _channelToGroupId[channel] = groupId;
    await Prefs.addIrcChannel(channel);
    // Store the mapping in Prefs (we can use group_name_ prefix)
    await Prefs.setGroupName(groupId, groupName);
    // Store password / custom nickname if provided
    if (password != null && password.isNotEmpty) {
      await Prefs.setIrcChannelPassword(channel, password);
    }
    if (customNickname != null && customNickname.isNotEmpty) {
      await Prefs.setIrcChannelNickname(channel, customNickname);
    }

    final connected = await _connectChannelToIrc(
      service,
      channel,
      groupId,
      password: password,
      customNickname: customNickname,
    );
    if (!connected) {
      // Log error but don't fail - group is already created
      AppLogger.log('[IRC] Failed to connect to IRC server for channel $channel');
    }

    return IrcAddChannelResult(
      added: true,
      connected: connected,
      groupId: groupId,
    );
  }

  /// Resolve the Tox group id backing [channel] by scanning known groups for
  /// the `IRC: <channel>` group name. Used to repair the in-memory mapping when
  /// it wasn't restored (e.g. the home flow calls init() without
  /// restoreChannelMappings()). Returns null if no matching group exists.
  Future<String?> _resolveGroupIdForChannel(
    String channel,
    FfiChatService service,
  ) async {
    final targetName = 'IRC: $channel';
    for (final groupId in service.knownGroups) {
      final groupName = await Prefs.getGroupName(groupId);
      if (groupName == targetName) return groupId;
    }
    return null;
  }

  /// Shared connect path used by both [addChannel] and [restoreChannelMappings].
  /// Resolves server/port/SASL/SSL from prefs and initiates the native connect.
  /// Returns whether the connect was successfully initiated (the actual
  /// connection result arrives asynchronously via the status stream).
  Future<bool> _connectChannelToIrc(
    FfiChatService service,
    String channel,
    String groupId, {
    required String? password,
    required String? customNickname,
  }) async {
    final ircServer = await Prefs.getIrcServer();
    final ircPort = await Prefs.getIrcPort();
    final useSasl = await Prefs.getIrcUseSasl();

    // Get Tox nickname for SASL authentication if enabled
    String? saslUsername;
    String? saslPassword;
    if (useSasl) {
      // Use Tox nickname as SASL username (default). If nickname is not
      // available, fall back to Tox public key. Use `accountKey` so the
      // 64-char-length check actually fires — `selfId` is the V2TIM placeholder
      // ("FlutterUIKitClient", 18 chars), so the previous form silently skipped
      // the fallback.
      final nickname = await Prefs.getNickname();
      if (nickname != null && nickname.isNotEmpty) {
        saslUsername = nickname;
      } else {
        final selfId = service.accountKey;
        if (selfId.isNotEmpty && selfId.length >= 64) {
          saslUsername = selfId.substring(0, 64);
        }
      }
      // For now, use empty password - user needs to register with NickServ
      saslPassword = '';
    }

    // Determine if we should use SSL (port 6697 typically uses SSL)
    final useSsl = ircPort == 6697;
    final normalizedPassword =
        (password == null || password.isEmpty) ? null : password;

    return service.connectIrcChannel(
      ircServer,
      ircPort,
      channel,
      normalizedPassword,
      groupId,
      saslUsername: saslUsername,
      saslPassword: saslPassword,
      useSsl: useSsl,
      customNickname: customNickname,
    );
  }

  /// Get password for a channel
  Future<String?> getChannelPassword(String channel) async {
    return await Prefs.getIrcChannelPassword(channel);
  }

  /// Remove an IRC channel and quit the corresponding group
  Future<void> removeChannel(
    String channel,
    FfiChatService service,
  ) async {
    // Disconnect from IRC first
    await service.disconnectIrcChannel(channel);
    
    final groupId = _channelToGroupId[channel];
    if (groupId != null) {
      await service.quitGroup(groupId);
    }
    _channels.remove(channel);
    _channelToGroupId.remove(channel);
    await Prefs.removeIrcChannel(channel);
  }

  /// Load channel to group ID mappings from existing groups
  /// This is called on startup to restore mappings and reconnect to IRC
  Future<void> restoreChannelMappings(FfiChatService service) async {
    // Determine whether live IRC is available (native library loads). Mapping
    // reconstruction below must happen REGARDLESS so local IRC groups stay
    // manageable (e.g. removable) even on platforms where the library can't
    // load — install/addChannel intentionally allow local IRC groups without a
    // live connection. Only the actual reconnect is gated on availability.
    bool libraryAvailable = false;
    if (_isInstalled) {
      libraryAvailable = await service.isIrcLibraryLoaded();
      if (!libraryAvailable) {
        // Try to load the library (platform-aware: .dll/.so/.dylib).
        final loadSuccess = await service.loadIrcLibrary(_ircLibraryPath());
        if (loadSuccess) {
          libraryAvailable = true;
          AppLogger.log('[IRC] IRC library loaded successfully during restoreChannelMappings');
        } else {
          AppLogger.log(
              '[IRC] IRC library unavailable; restoring mappings without live reconnect');
        }
      }
    }

    final knownGroups = service.knownGroups;
    for (final groupId in knownGroups) {
      final groupName = await Prefs.getGroupName(groupId);
      if (groupName == null || !groupName.startsWith('IRC: ')) continue;
      final channel = groupName.substring(5); // Remove "IRC: " prefix
      if (!_channels.contains(channel)) continue;
      _channelToGroupId[channel] = groupId;

      // Reconnect only when installed AND the native library is available.
      if (!_isInstalled || !libraryAvailable) continue;

      // Guard each channel independently: a throw from one connect (e.g. a
      // native FFI error) must not become an uncaught zone error nor abort
      // restoring the remaining channels.
      try {
        final password = await getChannelPassword(channel);
        final customNickname = await Prefs.getIrcChannelNickname(channel);
        final success = await _connectChannelToIrc(
          service,
          channel,
          groupId,
          password: password,
          customNickname: customNickname,
        );
        if (!success) {
          AppLogger.log(
              '[IRC] Failed to reconnect to IRC server for channel $channel on startup');
        } else {
          AppLogger.log('[IRC] Reconnected to IRC channel $channel on startup');
        }
      } catch (e, st) {
        AppLogger.log(
            '[IRC] Exception reconnecting to channel $channel on startup: $e\n$st');
      }
    }
  }
}

