import 'dart:async';
import 'dart:io';
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../adapters/shared_prefs_adapter.dart';
import '../adapters/logger_adapter.dart';
import 'app_paths.dart';
import 'prefs.dart';
import 'logger.dart';
import 'platform_utils.dart';

/// FfiChatPathResolver adapter that routes the file_recv / avatars fallbacks
/// through toxee's `AppPaths`. Used so `FfiChatService` does not need to call
/// `getApplicationSupportDirectory()` directly when toxee is the integrator
/// (X6 from the 2026-05-18 local-storage review). Tim2Tox standalone tests
/// can still omit a resolver and get the built-in defaults.
class _AppPathsFfiChatResolver implements FfiChatPathResolver {
  const _AppPathsFfiChatResolver();

  @override
  Future<String> resolveFileRecvDirectory() => AppPaths.fileRecvPath;

  @override
  Future<String> resolveAvatarsDirectory() => AppPaths.avatarsPath;
}

/// LAN Bootstrap Service information
class LanBootstrapService {
  final String ip;
  final int port;
  final String? publicKey; // If available
  final bool isAvailable; // Service availability

  LanBootstrapService({
    required this.ip,
    required this.port,
    this.publicKey,
    required this.isAvailable,
  });
}

/// Probe result for a single IP
class ProbeResult {
  final String ip;
  final LanBootstrapService? service; // null if no service found

  ProbeResult({
    required this.ip,
    this.service,
  });
}

/// LAN Bootstrap Service manager
class LanBootstrapServiceManager {
  static LanBootstrapServiceManager? _instance;
  static LanBootstrapServiceManager get instance {
    _instance ??= LanBootstrapServiceManager._();
    return _instance!;
  }

  LanBootstrapServiceManager._();

  int? _bootstrapInstanceHandle;
  FfiChatService? _bootstrapService;
  Timer? _bootstrapPollingTimer;
  String? _bootstrapServiceIP;
  int? _bootstrapServicePort;
  String? _bootstrapServicePubkey;

  /// Virtual/container interface name prefixes to filter out
  static const _virtualInterfacePrefixes = [
    'docker', 'veth', 'br-', 'virbr', 'vbox', 'vmnet',
  ];

  static bool _isVirtualInterface(String name) {
    final lower = name.toLowerCase();
    return _virtualInterfacePrefixes.any((p) => lower.startsWith(p));
  }

  /// Get local LAN IP address. Filters out virtual/container interfaces.
  /// Supports 169.254.x.x (link-local/APIPA) as last-resort fallback.
  static Future<String?> getLocalIPAddress() async {
    try {
      final List<String> physicalCandidates = [];
      String? linkLocal;

      for (var interface in await NetworkInterface.list()) {
        if (_isVirtualInterface(interface.name)) continue;

        for (var addr in interface.addresses) {
          if (addr.type != InternetAddressType.IPv4 || addr.isLoopback) continue;

          final ip = addr.address;

          if (ip.startsWith('169.254.')) {
            linkLocal ??= ip;
            continue;
          }

          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              (ip.startsWith('172.') &&
                  int.tryParse(ip.split('.')[1]) != null &&
                  int.parse(ip.split('.')[1]) >= 16 &&
                  int.parse(ip.split('.')[1]) <= 31)) {
            physicalCandidates.add(ip);
          }
        }
      }

      if (physicalCandidates.isNotEmpty) {
        if (physicalCandidates.length > 1) {
          AppLogger.log(
            '[LanBootstrapService] Multiple LAN interfaces: ${physicalCandidates.join(", ")}, using ${physicalCandidates.first}',
          );
        }
        return physicalCandidates.first;
      }

      if (linkLocal != null) {
        AppLogger.log(
          '[LanBootstrapService] Using link-local/APIPA address $linkLocal (no other LAN interface found)',
        );
        return linkLocal;
      }
    } catch (e) {
      AppLogger.logError('Failed to get local IP address', e, null);
    }
    return null;
  }

  /// Get current Tox instance's bootstrap info (UDP port and public key)
  /// Returns null if the service is not initialized or info is not available
  static Future<({String ip, int port, String pubkey})?> getToxBootstrapInfo(
    FfiChatService service,
  ) async {
    try {
      final localIP = await getLocalIPAddress();
      if (localIP == null) return null;

      final udpPort = service.getUdpPort();
      if (udpPort == 0) return null;

      final dhtId = service.getDhtId();
      if (dhtId == null || dhtId.isEmpty) return null;

      return (
        ip: localIP,
        port: udpPort,
        pubkey: dhtId,
      );
    } catch (e) {
      AppLogger.logError('Failed to get Tox bootstrap info', e, null);
      return null;
    }
  }

  /// Probe a single IP for bootstrap service
  static Future<LanBootstrapService?> probeBootstrapService(
    String ip,
    int port,
  ) async {
    try {
      // Try to connect to the port
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 2),
      ).timeout(const Duration(seconds: 2));
      
      // If connection succeeds, assume service exists
      // Note: We can't easily get the public key without proper Tox protocol
      // For now, we'll just check if the port is open
      await socket.close();
      
      return LanBootstrapService(
        ip: ip,
        port: port,
        isAvailable: true,
      );
    } catch (e) {
      return null;
    }
  }

  /// Start local bootstrap service. Desktop only; startup is limited to 30 seconds.
  Future<bool> startLocalBootstrapService(int port) async {
    if (!PlatformUtils.isDesktop) {
      AppLogger.log('[LanBootstrapService] LAN bootstrap is only supported on desktop');
      return false;
    }
    if (_bootstrapInstanceHandle != null) {
      AppLogger.log('[LanBootstrapService] Bootstrap service already running');
      return true;
    }

    try {
      final result = await _startLocalBootstrapServiceImpl(port)
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Bootstrap service startup timed out after 30 seconds');
      });
      return result;
    } on TimeoutException catch (e) {
      AppLogger.logError('Bootstrap service startup timeout', e, null);
      await stopLocalBootstrapService();
      return false;
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to start bootstrap service', e, stackTrace);
      await stopLocalBootstrapService();
      return false;
    }
  }

  Future<bool> _startLocalBootstrapServiceImpl(int port) async {
    final ffi = Tim2ToxFfi.open();

    final localIP = await getLocalIPAddress();
    if (localIP == null) {
      AppLogger.logError('Failed to get local IP address', null, null);
      return false;
    }

    // X6: route through the central path authority instead of constructing
    // the bootstrap profile path inline. AppPaths.lanBootstrapProfilePath is
    // the single source of truth for this location.
    final profilePath = await AppPaths.lanBootstrapProfilePath;
    final profileDir = p.dirname(profilePath);
    final profileDirFile = Directory(profileDir);
    if (!await profileDirFile.exists()) {
      await profileDirFile.create(recursive: true);
    }

    final profilePathPtr = profilePath.toNativeUtf8();
    final instanceHandle = ffi.createTestInstanceNative(profilePathPtr);
    pkgffi.malloc.free(profilePathPtr);

    if (instanceHandle == 0) {
      AppLogger.logError('Failed to create bootstrap service instance', null, null);
      return false;
    }

    final setResult = ffi.setCurrentInstance(instanceHandle);
    if (setResult == 0) {
      AppLogger.logError('Failed to set bootstrap service instance', null, null);
      ffi.destroyTestInstance(instanceHandle);
      return false;
    }

    _bootstrapInstanceHandle = instanceHandle;

    final prefs = await SharedPreferences.getInstance();
    _bootstrapService = FfiChatService(
      preferencesService: SharedPreferencesAdapter(prefs),
      loggerService: AppLoggerAdapter(),
      bootstrapService: null,
      pathResolver: const _AppPathsFfiChatResolver(),
    );

    await _bootstrapService!.init();

    ffi.setCurrentInstance(instanceHandle);

    await _bootstrapService!.login(
      userId: 'BootstrapService',
      userSig: 'dummy_sig',
    );

    final udpPort = _bootstrapService!.getUdpPort();
    final dhtId = _bootstrapService!.getDhtId();

    if (udpPort == 0 || dhtId == null) {
      AppLogger.logError('Failed to get bootstrap service info', null, null);
      await stopLocalBootstrapService();
      return false;
    }

    _bootstrapServiceIP = localIP;
    _bootstrapServicePort = udpPort;
    _bootstrapServicePubkey = dhtId;

    ffi.setCurrentInstance(instanceHandle);
    await _bootstrapService!.startPolling();

    await Prefs.setLanBootstrapServiceRunning(true);

    AppLogger.log('[LanBootstrapService] Bootstrap service started at $localIP:$udpPort');
    return true;
  }

  /// Stop local bootstrap service
  Future<void> stopLocalBootstrapService() async {
    _bootstrapPollingTimer?.cancel();
    _bootstrapPollingTimer = null;

    if (_bootstrapInstanceHandle != null) {
      try {
        final ffi = Tim2ToxFfi.open();
        ffi.destroyTestInstance(_bootstrapInstanceHandle!);
        _bootstrapInstanceHandle = null;
      } catch (e) {
        AppLogger.logError('Error destroying bootstrap instance', e, null);
      }
    }

    if (_bootstrapService != null) {
      try {
        await _bootstrapService!.dispose();
        _bootstrapService = null;
      } catch (e) {
        AppLogger.logError('Error disposing bootstrap service', e, null);
      }
    }

    _bootstrapServiceIP = null;
    _bootstrapServicePort = null;
    _bootstrapServicePubkey = null;

    await Prefs.setLanBootstrapServiceRunning(false);
    AppLogger.log('[LanBootstrapService] Bootstrap service stopped');
  }

  /// Get bootstrap service info
  Future<({String ip, int port, String pubkey})?> getBootstrapServiceInfo() async {
    if (_bootstrapServiceIP == null || 
        _bootstrapServicePort == null || 
        _bootstrapServicePubkey == null) {
      return null;
    }

    return (
      ip: _bootstrapServiceIP!,
      port: _bootstrapServicePort!,
      pubkey: _bootstrapServicePubkey!,
    );
  }

  /// Check if bootstrap service is running
  bool isBootstrapServiceRunning() {
    return _bootstrapInstanceHandle != null;
  }
}
