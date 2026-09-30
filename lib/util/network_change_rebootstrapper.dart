import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'bootstrap_node_ensurer.dart';
import 'logger.dart';
import 'platform_utils.dart';

/// One report from the platform's default-network watcher.
///
/// [identity] names the effective default path (Android: network handle,
/// transports and link addresses; iOS: the preferred interface of the
/// satisfied `NWPath` and its addresses). It is only compared for equality.
@immutable
class NetworkPathSnapshot {
  const NetworkPathSnapshot({required this.available, this.identity});

  final bool available;
  final String? identity;

  static NetworkPathSnapshot? fromEvent(Object? event) {
    if (event is! Map) return null;
    final available = event['available'];
    if (available is! bool) return null;
    final identity = event['identity'];
    return NetworkPathSnapshot(
      available: available,
      identity: identity is String ? identity : null,
    );
  }
}

/// Re-bootstraps the running Tox session when the device's default network
/// path changes — Wi-Fi <-> cellular handover, or a new address on the same
/// interface (checklist N1).
///
/// toxcore recovers from an IP change on its own, but slowly: DHT entries
/// learned on the old path time out first, and TCP relays that died with the
/// old path are only re-added by a bootstrap call. `tox_self_get_connection_status`
/// can still read "connected" in that window, so unlike the resume path this
/// kick is NOT gated on `isConnected`. It is a best-effort, cheap nudge
/// (a few `tox_bootstrap` / `tox_add_tcp_relay` calls, no Tox restart); the
/// recovery-time gain is unmeasured.
///
/// Policy (agreed with codex review, 2026-09-29):
/// * the first snapshot after subscribing is the current path, not a change;
/// * only a change to an AVAILABLE path whose identity differs from the last
///   available one counts; going offline cancels pending work and forgets the
///   path, so coming back online counts as a change;
/// * changes are debounced ([debounce]) — a handover emits a burst;
/// * at most one kick runs at a time, and kicks are at least [minInterval]
///   apart; a change inside that window is not dropped but runs as a single
///   trailing kick when the window ends (if still online);
/// * [dispose] cancels everything.
class NetworkChangeReBootstrapper {
  NetworkChangeReBootstrapper({
    required Stream<NetworkPathSnapshot> snapshots,
    required Future<void> Function(bool Function() isLive) kick,
    this.debounce = const Duration(seconds: 3),
    this.minInterval = const Duration(seconds: 30),
  }) : _snapshots = snapshots,
       _kick = kick;

  final Stream<NetworkPathSnapshot> _snapshots;
  /// The re-bootstrap. It receives `isLive`, which turns false once this
  /// trigger is disposed (session teardown): a kick still awaiting the node
  /// list must stop before touching native, or it could apply the old
  /// session's nodes to the next account's instance.
  final Future<void> Function(bool Function() isLive) _kick;
  final Duration debounce;
  final Duration minInterval;

  StreamSubscription<NetworkPathSnapshot>? _sub;
  Timer? _debounceTimer;
  Timer? _cooldown;
  bool _seenFirst = false;
  bool _online = false;
  String? _lastIdentity;
  bool _inFlight = false;
  bool _trailing = false;
  bool _disposed = false;

  /// Number of kicks started so far (diagnostics / tests).
  int kicks = 0;

  void start() {
    if (_disposed || _sub != null) return;
    _sub = _snapshots.listen(
      _onSnapshot,
      onError: (Object e, StackTrace st) => AppLogger.logError(
        '[NetworkChangeReBootstrapper] network watcher error',
        e,
        st,
      ),
    );
  }

  void _onSnapshot(NetworkPathSnapshot s) {
    if (_disposed) return;
    if (!_seenFirst) {
      _seenFirst = true;
      _online = s.available;
      _lastIdentity = s.available ? s.identity : null;
      return;
    }
    if (!s.available) {
      // Nothing is reachable: drop pending work and forget the path so the
      // next available path (even the same one) counts as a change.
      _online = false;
      _lastIdentity = null;
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _trailing = false;
      return;
    }
    final wasOnline = _online;
    _online = true;
    if (wasOnline && s.identity == _lastIdentity) return;
    _lastIdentity = s.identity;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _request);
  }

  void _request() {
    _debounceTimer = null;
    if (_disposed || !_online) return;
    if (_inFlight || (_cooldown?.isActive ?? false)) {
      _trailing = true;
      return;
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    _inFlight = true;
    _trailing = false;
    kicks++;
    _cooldown?.cancel();
    _cooldown = Timer(minInterval, _onCooldownEnd);
    AppLogger.log(
      '[NetworkChangeReBootstrapper] default network path changed; re-applying bootstrap nodes',
    );
    try {
      await _kick(() => !_disposed);
    } catch (e, st) {
      AppLogger.logError(
        '[NetworkChangeReBootstrapper] re-bootstrap failed (non-fatal)',
        e,
        st,
      );
    } finally {
      _inFlight = false;
    }
    if (_trailing && !(_cooldown?.isActive ?? false)) _onCooldownEnd();
  }

  void _onCooldownEnd() {
    if (_disposed || _inFlight || !_trailing || !_online) return;
    unawaited(_run());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _cooldown?.cancel();
    await _sub?.cancel();
    _sub = null;
  }

  static const EventChannel _channel = EventChannel('toxee/network_path');

  /// Snapshots from the native default-network watcher
  /// (`NetworkPathChannel.kt` / `NetworkPathChannel.swift`). Empty on
  /// platforms without one (desktop: no handover to follow).
  static Stream<NetworkPathSnapshot> platformSnapshots() {
    if (!PlatformUtils.isMobile) return const Stream.empty();
    return _channel
        .receiveBroadcastStream()
        .map(NetworkPathSnapshot.fromEvent)
        .where((s) => s != null)
        .cast<NetworkPathSnapshot>();
  }

  /// Starts the watcher for a live session; returns its disposer (for the
  /// session's DisposableBag). A no-op disposer on desktop.
  static void Function() startForSession(FfiChatService service) {
    if (!PlatformUtils.isMobile) return () {};
    final r = NetworkChangeReBootstrapper(
      snapshots: platformSnapshots(),
      kick: (isLive) =>
          BootstrapNodeEnsurer.reapplyForNetworkChange(service, isLive: isLive),
    )..start();
    return () => unawaited(r.dispose());
  }
}
