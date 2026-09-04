// Shared full-mesh loopback bootstrap for Fixture-C two-process gates.
//
// WHY: same-host toxee instances bootstrap to the PUBLIC DHT but never to EACH
// OTHER, and macOS sandbox blocks local discovery (no multicast entitlement), so
// PUBLIC-group NGC peer discovery never converges — the founder's
// HandleGroupPeerJoin never fires and group messages don't roundtrip
// (root-caused live 2026-06-01). The tim2tox auto_tests avoid this with a
// full-mesh LOCAL bootstrap (`test_helper.dart` `configureLocalBootstrap`, whose
// comment names this exact "peer_join never fires on founder" symptom).
//
// This helper bootstraps every instance to every OTHER on 127.0.0.1 (BOTH
// directions — the founder needs a local DHT peer to learn from too), using the
// gated `l3_dht_info` + `l3_add_bootstrap_node` L3 tools, then settles briefly
// for the local DHT to converge. Call it once, after every instance is booted +
// connected, before any group activity.

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';

/// The L3 extensions a bootstrap target must expose. Each driver should
/// `waitForExtension` these (alongside its other waits) before bootstrapping.
const List<String> fixtureCBootstrapExtensions = <String>[
  'ext.mcp.toolkit.l3_dht_info',
  'ext.mcp.toolkit.l3_add_bootstrap_node',
];

/// A connected Fixture-C instance the bootstrap operates on. Drivers construct
/// these from their own `_PairDriver` fields (`name`, `vm`, `isolateId`).
///
/// [host] is the address at which THIS target's DHT endpoint is reachable BY THE
/// OTHER targets. Same-host pairs leave it '127.0.0.1' (loopback). A CROSS-HOST
/// pair (macOS-A ↔ Linux-VM-B) sets each side's real IP on the shared virtual
/// network (e.g. A=the Parallels host IP, B=10.211.55.6), so the mesh wires
/// `add_bootstrap_node(peer.host, peer.udpPort, peer.dhtId)` with a routable
/// address instead of loopback — the only thing that differs from same-host.
class BootstrapTarget {
  BootstrapTarget(
    this.name,
    this.vm,
    this.isolateId, {
    this.host = '127.0.0.1',
  });
  final String name;
  final VmService vm;
  final String isolateId;
  final String host;
}

/// The HOST-side TCP-relay port for TCP-only pairs (Android star): adb maps
/// it to A's guest relay. Mirrors RELAY_HOST_PORT in
/// launch_android_fixture_c_pair.sh — NOT 3389, which an unrelated host
/// listener can hijack silently (measured: a legacy qemu VM's hostfwd).
int fixtureCTcpRelayHostPort() =>
    int.tryParse(Platform.environment['TOXEE_ANDROID_RELAY_HOST_PORT'] ?? '') ??
    33390;

/// Full-mesh loopback bootstrap across [targets]: each instance bootstraps to
/// every OTHER on 127.0.0.1 + the peer's `l3_dht_info` endpoint, then settles.
/// Tolerant — logs but does NOT throw on a missing endpoint (the downstream
/// scenario assertion is the authoritative gate). [log] defaults to `print`.
///
/// TCP-only pairs report udpPort=0; when [tcpRelayFallbackPort] is given,
/// those peers get a TCP-RELAY fallback add instead (given-port
/// tox_add_tcp_relay via add_bootstrap_node). OPT-IN because the port is
/// TOPOLOGY-specific (Android star = fixtureCTcpRelayHostPort; iOS pairs use
/// their own fixed listeners) — before 2026-08-31 TCP-only peers were
/// silently skipped and the "local star" actually rode PUBLIC relays.
Future<void> wireFullMeshBootstrap(
  List<BootstrapTarget> targets, {
  void Function(String)? log,
  Duration settle = const Duration(seconds: 6),
  int? tcpRelayFallbackPort,
}) async {
  final emit = log ?? print;
  // Desktop TCP-only pairs (TOXEE_PAIR_TCP_ONLY=1: Windows/Linux real-UI) have
  // NO UDP endpoint, so every re-wire — not just the launch one — must add the
  // relay; callers that re-seed after a relaunch used to omit it and the peer
  // never came back (sweep_p1_relaunch on Windows, 2026-09-04).
  // Precedence: an EXPLICIT port (topology-aware, e.g. the adb-reverse host
  // port on Android) > the peer's own relay from pair.json > the desktop env
  // default — see the fallback below.
  final envRelayPort = desktopTcpRelayFallbackPortFromEnv();
  // 1. Gather each instance's local DHT endpoint. A FRESH instance can race
  // this with its tox bring-up and report an empty dhtId — retry briefly, or
  // its peers get no wiring at all (seen live: attempt-1 A->B/A->C missing).
  final endpoints = <String, ({int port, String dhtId})>{};
  for (final t in targets) {
    var port = 0;
    var dhtId = '';
    for (var i = 0; i < 12 && dhtId.isEmpty; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(seconds: 1));
      final resp = await t.vm.callServiceExtension(
        'ext.mcp.toolkit.l3_dht_info',
        isolateId: t.isolateId,
        args: const <String, String>{},
      );
      final j = (resp.json ?? const <String, dynamic>{})
          .cast<String, dynamic>();
      port = (j['udpPort'] as num?)?.toInt() ?? 0;
      dhtId = (j['dhtId']?.toString() ?? '').trim();
    }
    endpoints[t.name] = (port: port, dhtId: dhtId);
    emit('[fixture-c-bootstrap] ${t.name} DHT endpoint ${t.host}:$port');
  }
  final hostByName = {for (final t in targets) t.name: t.host};
  // 2. Full mesh: every instance bootstraps to every OTHER (both directions).
  for (final target in targets) {
    for (final peer in targets) {
      if (identical(target, peer)) continue;
      final ep = endpoints[peer.name]!;
      if (ep.dhtId.isEmpty) {
        emit('[fixture-c-bootstrap] WARN ${peer.name} has no DHT id');
        continue;
      }
      final relayFallback = ep.port <= 0;
      // Without an explicit port, prefer the PEER's own relay (recorded per
      // instance in pair.json by the launchers) over the env default: with one
      // shared port this dialed 127.0.0.1:<A's relay> carrying B's DHT key — a
      // handshake against the wrong server key — so A never got a working
      // relay from the pair and reached "connected" only through the public
      // bootstrap list (minutes, or never on a slow VM).
      final resolvedRelayPort = tcpRelayFallbackPort ??
          (relayFallback ? pairInstanceTcpRelayPort(peer.name) : null) ??
          envRelayPort;
      if (relayFallback && resolvedRelayPort == null) {
        emit(
          '[fixture-c-bootstrap] WARN ${peer.name} has no UDP endpoint and '
          'no TCP-relay fallback port was given',
        );
        continue;
      }
      final port = relayFallback ? resolvedRelayPort! : ep.port;
      if (relayFallback) {
        emit(
          '[fixture-c-bootstrap] ${target.name} -> ${peer.name} TCP-relay '
          'fallback :$port (peer has no UDP endpoint)',
        );
      }
      final resp = await target.vm.callServiceExtension(
        'ext.mcp.toolkit.l3_add_bootstrap_node',
        isolateId: target.isolateId,
        args: <String, String>{
          'host': hostByName[peer.name] ?? '127.0.0.1',
          'port': '$port',
          'pubkey': ep.dhtId,
        },
      );
      final ok =
          ((resp.json ?? const <String, dynamic>{})
              .cast<String, dynamic>())['ok'] ==
          true;
      emit(
        '[fixture-c-bootstrap] ${target.name} -> ${peer.name} '
        '@${hostByName[peer.name] ?? '127.0.0.1'} bootstrap ok=$ok',
      );
    }
  }
  emit(
    '[fixture-c-bootstrap] full-mesh wired; settling '
    '${settle.inSeconds}s for local DHT',
  );
  await Future<void>.delayed(settle);
}

/// The pair's localhost TCP-relay port when the desktop pair runs TCP-only
/// (`TOXEE_PAIR_TCP_ONLY=1`), else null. `TOXEE_PAIR_TCP_RELAY_PORT` overrides;
/// the Windows launcher defaults to 33390 (3389 is RDP there), others 3389.
int? desktopTcpRelayFallbackPortFromEnv() {
  final env = Platform.environment;
  final tcpOnly = env['TOXEE_PAIR_TCP_ONLY'];
  if (tcpOnly != '1' && tcpOnly != 'true') return null;
  return int.tryParse(env['TOXEE_PAIR_TCP_RELAY_PORT'] ?? '') ??
      ((env['TOXEE_REAL_UI_PLATFORM'] ?? '') == 'windows' || Platform.isWindows
          ? 33390
          : 3389);
}

/// The localhost TCP-relay port instance [name] HOSTS, from the launcher's
/// pair.json (`instances.<name>.tcp_relay_port`, TOXEE_REAL_UI_PAIR_JSON or
/// the desktop default path); null when unknown or not a TCP-only pair.
int? pairInstanceTcpRelayPort(String name) {
  final path = Platform.environment['TOXEE_REAL_UI_PAIR_JSON'] ??
      (Platform.isWindows
          ? 'build/windows_runtime/pair.json'
          : Platform.isLinux
              ? 'build/linux_runtime/pair.json'
              : 'tool/mcp_test/.multi_instance_runtime/pair.json');
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final doc = jsonDecode(file.readAsStringSync());
    final inst = (doc as Map)['instances']?[name];
    final raw = inst is Map ? inst['tcp_relay_port'] : null;
    return int.tryParse('${raw ?? ''}');
  } on Object {
    return null;
  }
}
