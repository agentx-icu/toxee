import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:ffi/ffi.dart' as pkgffi;
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'app_paths.dart';
import 'prefs.dart';
import 'logger.dart';
import 'platform_utils.dart';

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

  ProbeResult({required this.ip, this.service});
}

class LanAddressCandidate {
  const LanAddressCandidate({
    required this.interfaceName,
    required this.address,
    required this.type,
    this.isLoopback = false,
  });

  final String interfaceName;
  final String address;
  final InternetAddressType type;
  final bool isLoopback;
}

/// LAN Bootstrap Service manager
class LanBootstrapServiceManager {
  static LanBootstrapServiceManager? _instance;
  static LanBootstrapServiceManager get instance {
    _instance ??= LanBootstrapServiceManager._();
    return _instance!;
  }

  LanBootstrapServiceManager._()
    : _localAddressProvider = getLocalIPAddress,
      _startupTimeout = const Duration(seconds: 30),
      _setCurrentBootstrapNode = Prefs.setCurrentBootstrapNode;

  @visibleForTesting
  LanBootstrapServiceManager.forTesting({
    required Future<String?> Function() localAddressProvider,
    Duration startupTimeout = const Duration(seconds: 30),
    Future<void> Function(String host, int port, String pubkey)?
    setCurrentBootstrapNode,
  }) : _localAddressProvider = localAddressProvider,
       _startupTimeout = startupTimeout,
       _setCurrentBootstrapNode =
           setCurrentBootstrapNode ?? Prefs.setCurrentBootstrapNode;

  final Future<String?> Function() _localAddressProvider;
  final Duration _startupTimeout;
  final Future<void> Function(String host, int port, String pubkey)
  _setCurrentBootstrapNode;

  int? _bootstrapInstanceHandle;
  String? _bootstrapServiceIP;
  int? _bootstrapServicePort;
  String? _bootstrapServicePubkey;

  @visibleForTesting
  int? get nativeInstanceHandle => _bootstrapInstanceHandle;

  /// Concurrent callers await the same native startup instead of racing into
  /// separate handle creation or receiving a false failure from a second tap.
  Future<bool>? _startFuture;
  Completer<bool>? _startResult;
  int _lifecycleGeneration = 0;

  /// Virtual/container interface name prefixes to filter out.
  /// Also covers VPN tunnels (tun*/tap*/utun*/wg*) — LAN bootstrap should
  /// advertise a real LAN address, not a VPN endpoint reachable from anywhere
  /// the VPN tunnels reach.
  static const _virtualInterfacePrefixes = [
    'docker',
    'veth',
    'br-',
    'virbr',
    'vbox',
    'vmnet',
    'tun',
    'tap',
    'utun',
    'wg',
  ];

  static bool _isVirtualInterface(String name) {
    final lower = name.toLowerCase();
    return _virtualInterfacePrefixes.any((p) => lower.startsWith(p));
  }

  static String? selectPreferredAddress(
    Iterable<LanAddressCandidate> candidates,
  ) {
    final usable = <({LanAddressCandidate candidate, int rank})>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      final address = candidate.address.trim();
      if (address.isEmpty ||
          candidate.isLoopback ||
          _isVirtualInterface(candidate.interfaceName)) {
        continue;
      }
      final key = '${candidate.interfaceName}\u0000$address';
      if (!seen.add(key)) continue;
      final rank = _addressRank(candidate.type, address);
      if (rank == null) continue;
      usable.add((
        candidate: LanAddressCandidate(
          interfaceName: candidate.interfaceName,
          address: address,
          type: candidate.type,
        ),
        rank: rank,
      ));
    }
    usable.sort((left, right) {
      final rankOrder = left.rank.compareTo(right.rank);
      if (rankOrder != 0) return rankOrder;
      final interfaceOrder = left.candidate.interfaceName.compareTo(
        right.candidate.interfaceName,
      );
      if (interfaceOrder != 0) return interfaceOrder;
      return left.candidate.address.compareTo(right.candidate.address);
    });
    return usable.isEmpty ? null : usable.first.candidate.address;
  }

  static int? _addressRank(InternetAddressType type, String address) {
    final lower = address.toLowerCase();
    if (type == InternetAddressType.IPv4) {
      if (lower == '127.0.0.1') return null;
      if (lower.startsWith('169.254.')) return 4;
      if (_isPrivateIpv4(lower)) return 0;
      return 1;
    }
    if (lower == '::1' || lower.startsWith('fe80:')) return null;
    if (lower.startsWith('fc') || lower.startsWith('fd')) return 2;
    if (lower.startsWith('2') || lower.startsWith('3')) return 3;
    return null;
  }

  static bool _isPrivateIpv4(String address) {
    if (address.startsWith('10.') || address.startsWith('192.168.')) {
      return true;
    }
    if (!address.startsWith('172.')) return false;
    final parts = address.split('.');
    if (parts.length != 4) return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }

  /// Get local LAN IP address. Filters out virtual/container interfaces.
  /// Supports 169.254.x.x (link-local/APIPA) as last-resort fallback.
  static Future<String?> getLocalIPAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      final candidates = interfaces.expand(
        (interface) => interface.addresses.map(
          (address) => LanAddressCandidate(
            interfaceName: interface.name,
            address: address.address,
            type: address.type,
            isLoopback: address.isLoopback,
          ),
        ),
      );
      return selectPreferredAddress(candidates);
    } catch (e) {
      AppLogger.logError('Failed to get local IP address', e, null);
    }
    return null;
  }

  /// Start local bootstrap service. Desktop only; startup is limited to 30 seconds.
  Future<bool> startLocalBootstrapService(int port) async {
    if (!PlatformUtils.isDesktop) {
      AppLogger.log(
        '[LanBootstrapService] LAN bootstrap is only supported on desktop',
      );
      return false;
    }
    if (_bootstrapInstanceHandle != null) {
      AppLogger.log('[LanBootstrapService] Bootstrap service already running');
      return true;
    }
    final inFlight = _startResult;
    if (inFlight != null) {
      return inFlight.future;
    }

    final generation = ++_lifecycleGeneration;
    final result = Completer<bool>();
    final startFuture = _runStart(port, generation);
    _startResult = result;
    _startFuture = startFuture;
    unawaited(
      startFuture
          .then((value) {
            if (!result.isCompleted) result.complete(value);
          })
          .whenComplete(() {
            if (identical(_startFuture, startFuture)) _startFuture = null;
            if (identical(_startResult, result)) _startResult = null;
          }),
    );
    return result.future;
  }

  Future<bool> _runStart(int port, int generation) async {
    try {
      return await _startLocalBootstrapServiceImpl(port, generation);
    } on TimeoutException catch (e) {
      AppLogger.logError('Bootstrap service startup timeout', e, null);
      if (generation == _lifecycleGeneration) {
        await stopLocalBootstrapService();
      }
      return false;
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to start bootstrap service', e, stackTrace);
      if (generation == _lifecycleGeneration) {
        await stopLocalBootstrapService();
      }
      return false;
    }
  }

  Future<bool> _startLocalBootstrapServiceImpl(int port, int generation) async {
    final ffi = Tim2ToxFfi.open();

    final localIP = await _localAddressProvider().timeout(
      _startupTimeout,
      onTimeout: () {
        throw TimeoutException(
          'LAN address lookup timed out after $_startupTimeout',
        );
      },
    );
    if (generation != _lifecycleGeneration) return false;
    if (localIP == null) {
      AppLogger.logError('Failed to get local IP address', null, null);
      return false;
    }

    // X6: route through the central path authority instead of constructing
    // the bootstrap profile path inline. AppPaths.lanBootstrapProfilePath is
    // the single source of truth for this location.
    final profilePath = await AppPaths.lanBootstrapProfilePath;
    if (generation != _lifecycleGeneration) return false;
    final profileDir = p.dirname(profilePath);
    final profileDirFile = Directory(profileDir);
    if (!await profileDirFile.exists()) {
      await profileDirFile.create(recursive: true);
    }
    if (generation != _lifecycleGeneration) return false;

    final profilePathPtr = profilePath.toNativeUtf8();
    final int instanceHandle;
    try {
      instanceHandle = ffi.createTestInstanceNative(profilePathPtr);
    } finally {
      pkgffi.malloc.free(profilePathPtr);
    }

    if (instanceHandle == 0) {
      AppLogger.logError(
        'Failed to create bootstrap service instance',
        null,
        null,
      );
      return false;
    }

    _bootstrapInstanceHandle = instanceHandle;

    if (ffi.isInstanceInitialized(instanceHandle) != 1) {
      throw StateError('Bootstrap service instance was not initialized');
    }

    final udpPort = ffi.getUdpPort(instanceHandle);
    final dhtId = _readDhtIdForInstance(ffi, instanceHandle);

    if (udpPort == 0 || dhtId == null || dhtId.isEmpty) {
      throw StateError('Failed to get bootstrap service info');
    }

    _bootstrapServiceIP = localIP;
    _bootstrapServicePort = udpPort;
    _bootstrapServicePubkey = dhtId;

    await Prefs.setLanBootstrapServiceRunning(true);
    if (generation != _lifecycleGeneration) {
      await _discardCancelledStart(ffi, instanceHandle);
      return false;
    }

    AppLogger.log(
      '[LanBootstrapService] Bootstrap service started at '
      '$localIP:$udpPort (requested port: $port)',
    );
    return true;
  }

  /// Stop local bootstrap service
  Future<bool> stopLocalBootstrapService() async {
    _lifecycleGeneration += 1;
    final pendingResult = _startResult;
    if (pendingResult != null && !pendingResult.isCompleted) {
      pendingResult.complete(false);
    }
    if (identical(_startResult, pendingResult)) _startResult = null;
    _startFuture = null;
    final ffi = Tim2ToxFfi.open();
    final bootstrapHandle = _bootstrapInstanceHandle;
    final previousInstance = ffi.getCurrentInstanceId();
    final restoreTarget = previousInstance == bootstrapHandle
        ? 0
        : previousInstance;

    if (bootstrapHandle != null) {
      try {
        final destroyed = ffi.destroyTestInstance(bootstrapHandle);
        if (destroyed == 0) {
          if (ffi.isInstanceInitialized(bootstrapHandle) == 1) {
            throw StateError('Native bootstrap instance was not destroyed');
          }
          AppLogger.warn(
            '[LanBootstrapService] Native bootstrap handle was already gone; '
            'clearing stale Dart state',
          );
        }
      } catch (e) {
        AppLogger.logError('Error destroying bootstrap instance', e, null);
        ffi.setCurrentInstance(restoreTarget);
        return false;
      }
      _bootstrapInstanceHandle = null;
    }

    try {
      ffi.setCurrentInstance(restoreTarget);
    } catch (e) {
      AppLogger.logError('Error restoring previous instance', e, null);
    }

    _bootstrapServiceIP = null;
    _bootstrapServicePort = null;
    _bootstrapServicePubkey = null;

    await Prefs.setLanBootstrapServiceRunning(false);
    AppLogger.log('[LanBootstrapService] Bootstrap service stopped');
    return true;
  }

  Future<void> _discardCancelledStart(
    Tim2ToxFfi ffiLibrary,
    int instanceHandle,
  ) async {
    if (_bootstrapInstanceHandle != instanceHandle) {
      if (_bootstrapInstanceHandle == null) {
        await Prefs.setLanBootstrapServiceRunning(false);
      }
      return;
    }

    final destroyed = ffiLibrary.destroyTestInstance(instanceHandle);
    if (destroyed == 0 &&
        ffiLibrary.isInstanceInitialized(instanceHandle) == 1) {
      return;
    }
    _bootstrapInstanceHandle = null;
    _bootstrapServiceIP = null;
    _bootstrapServicePort = null;
    _bootstrapServicePubkey = null;
    await Prefs.setLanBootstrapServiceRunning(false);
  }

  static String? _readDhtIdForInstance(Tim2ToxFfi ffiLibrary, int instanceId) {
    final buffer = pkgffi.malloc.allocate<ffi.Int8>(65);
    try {
      final length = ffiLibrary.getDhtIdForInstanceNative(
        instanceId,
        buffer,
        65,
      );
      if (length <= 0 || length > 64) return null;
      return buffer.cast<pkgffi.Utf8>().toDartString(length: length);
    } finally {
      pkgffi.malloc.free(buffer);
    }
  }

  /// Get bootstrap service info
  Future<({String ip, int port, String pubkey})?>
  getBootstrapServiceInfo() async {
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

  /// Crash-recovery hook. If a previous run set the LAN-bootstrap-running
  /// flag but this process has no live instance (because the previous process
  /// crashed between `start` and `stop`), restore the saved pre-LAN bootstrap
  /// node and clear the stale flags. Safe to call on every cold start.
  Future<void> recoverFromCrashedSession() async {
    if (_bootstrapInstanceHandle != null) return; // service is alive now
    final wasRunning = await Prefs.getLanBootstrapServiceRunning();
    if (!wasRunning) return;
    AppLogger.warn(
      '[LanBootstrapService] Detected stale LAN-running flag with no live instance — recovering',
    );
    final priorNode = await Prefs.getPreLanBootstrapNode();
    if (priorNode != null) {
      try {
        await _setCurrentBootstrapNode(
          priorNode.host,
          priorNode.port,
          priorNode.pubkey,
        );
        await Prefs.clearPreLanBootstrapNode();
      } catch (e, st) {
        AppLogger.logError(
          '[LanBootstrapService] recovery: failed to restore pre-LAN node',
          e,
          st,
        );
        return;
      }
    }
    await Prefs.setLanBootstrapServiceRunning(false);
  }
}
