import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'ffi_chat_service_account_key.dart';
import 'prefs.dart';
import 'dart:io';
import 'logger.dart';

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

  /// Install the IRC app (loads dynamic library)
  Future<void> install(FfiChatService service) async {
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

  /// Add an IRC channel and create/join the corresponding group
  /// [password] is optional and will be stored for future IRC synchronization
  Future<String?> addChannel(
    String channel,
    FfiChatService service, {
    String? password,
    String? customNickname,
  }) async {
    if (_channels.contains(channel)) {
      // Channel already exists, update password if provided
      if (password != null) {
        await Prefs.setIrcChannelPassword(channel, password);
      }
      return _channelToGroupId[channel];
    }

    // Create a group for this IRC channel
    // Use channel name as group name, prefixed with "IRC: "
    final groupName = 'IRC: $channel';
    final groupId = await service.createGroup(groupName);
    
    if (groupId != null && groupId.isNotEmpty) {
      _channels.add(channel);
      _channelToGroupId[channel] = groupId;
      await Prefs.addIrcChannel(channel);
      // Store the mapping in Prefs (we can use group_name_ prefix)
      await Prefs.setGroupName(groupId, groupName);
      // Store password if provided
      if (password != null && password.isNotEmpty) {
        await Prefs.setIrcChannelPassword(channel, password);
      }
      
      // Connect to IRC server
      final ircServer = await Prefs.getIrcServer();
      final ircPort = await Prefs.getIrcPort();
      final passwordStr = password ?? '';
      final useSasl = await Prefs.getIrcUseSasl();
      
      // Get Tox nickname for SASL authentication if enabled
      String? saslUsername;
      String? saslPassword;
      if (useSasl) {
        // Use Tox nickname as SASL username (default)
        // If nickname is not available, fall back to Tox public key
        final nickname = await Prefs.getNickname();
        if (nickname != null && nickname.isNotEmpty) {
          saslUsername = nickname;
        } else {
          // Fall back to Tox public key if nickname is not set. Use
          // `accountKey` so the 64-char-length check actually fires —
          // `selfId` is the V2TIM placeholder ("FlutterUIKitClient", 18
          // chars), so the previous form silently skipped the fallback.
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
      
      final success = await service.connectIrcChannel(
        ircServer,
        ircPort,
        channel,
        passwordStr.isEmpty ? null : passwordStr,
        groupId,
        saslUsername: saslUsername,
        saslPassword: saslPassword,
        useSsl: useSsl,
        customNickname: customNickname,
      );
      
      if (!success) {
        // Log error but don't fail - group is already created
        AppLogger.log('[IRC] Failed to connect to IRC server for channel $channel');
      }
      
      return groupId;
    }
    return null;
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
    // If IRC app is installed, ensure the library is loaded first
    if (_isInstalled) {
      final isLoaded = await service.isIrcLibraryLoaded();
      if (!isLoaded) {
        // Try to load the library (platform-aware: .dll/.so/.dylib).
        final libraryPath = _ircLibraryPath();

        final loadSuccess = await service.loadIrcLibrary(libraryPath);
        if (!loadSuccess) {
          AppLogger.log('[IRC] Failed to load IRC library during restoreChannelMappings');
          return; // Can't proceed without the library
        } else {
          AppLogger.log('[IRC] IRC library loaded successfully during restoreChannelMappings');
        }
      }
    }
    
    final knownGroups = service.knownGroups;
    for (final groupId in knownGroups) {
      final groupName = await Prefs.getGroupName(groupId);
      if (groupName != null && groupName.startsWith('IRC: ')) {
        final channel = groupName.substring(5); // Remove "IRC: " prefix
        if (_channels.contains(channel)) {
          _channelToGroupId[channel] = groupId;
          
          // Only reconnect if IRC app is installed and library is loaded
          if (_isInstalled) {
          // Reconnect to IRC channel on startup
          final password = await getChannelPassword(channel);
          final ircServer = await Prefs.getIrcServer();
          final ircPort = await Prefs.getIrcPort();
          final useSasl = await Prefs.getIrcUseSasl();
          
          // Get Tox nickname for SASL authentication if enabled
          String? saslUsername;
          String? saslPassword;
          if (useSasl) {
            // Use Tox nickname as SASL username (default)
            // If nickname is not available, fall back to Tox public key
            final nickname = await Prefs.getNickname();
            if (nickname != null && nickname.isNotEmpty) {
              saslUsername = nickname;
            } else {
              // Fall back to Tox public key if nickname is not set. Use
              // `accountKey` (real Tox address); `selfId` is the V2TIM
              // login placeholder so the 64-char-length check would
              // silently skip otherwise.
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
          
          final success = await service.connectIrcChannel(
            ircServer,
            ircPort,
            channel,
            password,
            groupId,
            saslUsername: saslUsername,
            saslPassword: saslPassword,
            useSsl: useSsl,
            customNickname: null, // TODO: Allow user to set custom nickname
          );
            
            if (!success) {
              AppLogger.log('[IRC] Failed to reconnect to IRC server for channel $channel on startup');
            } else {
              AppLogger.log('[IRC] Reconnected to IRC channel $channel on startup');
            }
          }
        }
      }
    }
  }
}

