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
  BootstrapTarget(this.name, this.vm, this.isolateId, {this.host = '127.0.0.1'});
  final String name;
  final VmService vm;
  final String isolateId;
  final String host;
}

/// Full-mesh loopback bootstrap across [targets]: each instance bootstraps to
/// every OTHER on 127.0.0.1 + the peer's `l3_dht_info` endpoint, then settles.
/// Tolerant — logs but does NOT throw on a missing endpoint (the downstream
/// scenario assertion is the authoritative gate). [log] defaults to `print`.
Future<void> wireFullMeshBootstrap(
  List<BootstrapTarget> targets, {
  void Function(String)? log,
  Duration settle = const Duration(seconds: 6),
}) async {
  final emit = log ?? print;
  // 1. Gather each instance's local DHT endpoint.
  final endpoints = <String, ({int port, String dhtId})>{};
  for (final t in targets) {
    final resp = await t.vm.callServiceExtension(
      'ext.mcp.toolkit.l3_dht_info',
      isolateId: t.isolateId,
      args: const <String, String>{},
    );
    final j = (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
    final port = (j['udpPort'] as num?)?.toInt() ?? 0;
    final dhtId = (j['dhtId']?.toString() ?? '').trim();
    endpoints[t.name] = (port: port, dhtId: dhtId);
    emit('[fixture-c-bootstrap] ${t.name} DHT endpoint ${t.host}:$port');
  }
  final hostByName = {for (final t in targets) t.name: t.host};
  // 2. Full mesh: every instance bootstraps to every OTHER (both directions).
  for (final target in targets) {
    for (final peer in targets) {
      if (identical(target, peer)) continue;
      final ep = endpoints[peer.name]!;
      if (ep.port <= 0 || ep.dhtId.isEmpty) {
        emit('[fixture-c-bootstrap] WARN ${peer.name} has no usable DHT endpoint');
        continue;
      }
      final resp = await target.vm.callServiceExtension(
        'ext.mcp.toolkit.l3_add_bootstrap_node',
        isolateId: target.isolateId,
        args: <String, String>{
          'host': hostByName[peer.name] ?? '127.0.0.1',
          'port': '${ep.port}',
          'pubkey': ep.dhtId,
        },
      );
      final ok = ((resp.json ?? const <String, dynamic>{})
              .cast<String, dynamic>())['ok'] ==
          true;
      emit('[fixture-c-bootstrap] ${target.name} -> ${peer.name} '
          '@${hostByName[peer.name] ?? '127.0.0.1'} bootstrap ok=$ok');
    }
  }
  emit('[fixture-c-bootstrap] full-mesh wired; settling '
      '${settle.inSeconds}s for local DHT');
  await Future<void>.delayed(settle);
}
