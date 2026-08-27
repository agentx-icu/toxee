import 'dart:async';
import 'dart:io';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart' as ffi_lib;
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import 'app_paths.dart';
import 'logger.dart';
import 'safe_diagnostics.dart';

/// Verdict of a **real** bootstrap-node reachability probe.
///
/// "Real" is load-bearing here. `FfiChatService.tryBootstrapNode` only reports
/// whether toxcore *accepted* the node descriptor (`tox_bootstrap` returning
/// true means "the arguments parsed and the host resolved", nothing more), so
/// on its own it cannot tell a live node from a dead one.
enum BootstrapProbeVerdict {
  /// The node answered a DHT nodes request. See [BootstrapNodeProbe] for why
  /// an answer on the isolated probe instance can only have come from the
  /// candidate.
  reachable,

  /// The descriptor was well-formed but nothing answered before the timeout —
  /// unresolvable host, dead node, wrong port, wrong public key, or UDP
  /// blocked on this network.
  unreachable,

  /// `host` / `port` / `publicKey` are not a well-formed Tox node descriptor.
  invalid,

  /// This device has no UDP socket bound, so the DHT probe cannot run at all
  /// (`tox_dht_send_nodes_request` fails with `UDP_DISABLED`), or no getnodes
  /// request could be sent during the probe window for a reason on THIS
  /// device (see [BootstrapNodeProbe.verdictFor] — an unresolvable host is
  /// [unreachable], not this).
  ///
  /// This is NOT [unreachable] and must never be rendered as one. A TCP-only
  /// client still USES bootstrap nodes — it reaches them through
  /// `tox_add_tcp_relay` — so reporting "node unreachable" here would blame a
  /// perfectly good node for a local network constraint, which is the same
  /// class of lie this whole probe exists to remove. Callers should report the
  /// constraint and leave the node selectable.
  udpUnavailable,
}

/// Raised when a probe could not be *performed* at all (as opposed to being
/// performed and coming back negative).
///
/// Deliberately distinct from [BootstrapProbeVerdict.unreachable]: a probe
/// instance that fails to start is an app/platform defect, and reporting it as
/// "node unreachable" would blame the user's node for our bug.
class BootstrapProbeUnavailable implements Exception {
  BootstrapProbeUnavailable(this.reason, [this.cause]);

  final String reason;
  final Object? cause;

  @override
  String toString() =>
      'BootstrapProbeUnavailable: $reason'
      '${cause == null ? '' : ' (${SafeDiagnostics.describeError(cause!)})'}';
}

/// Probes bootstrap nodes over the Tox DHT, with or without a logged-in
/// session.
///
/// ## Why the verdict is "any DHT nodes response", not "a response from this
/// public key"
///
/// The obvious design — send a `getnodes` request and wait for a response
/// *authenticated with the candidate's public key* — is not implementable on
/// toxcore's API, and an earlier version of this file that tried it reported
/// **every** node as unreachable, live ones included.
/// `tox_callback_dht_nodes_response` does not report the responder. toxcore
/// fires it once per node *contained in* a nodes response — i.e. the
/// responder's neighbours (`DHT.c: handle_nodes_response` loops over
/// `plain_nodes[i]`) — and a node never lists itself among its own close
/// nodes, so the candidate's key can never come back. Waiting for it waits
/// forever. `third_party/tim2tox/auto_tests/.../scenario_dht_nodes_response_api_test.dart`
/// pins this contract so it cannot be silently re-broken.
///
/// What toxcore *does* guarantee is attribution by construction: a nodes
/// response is only accepted when its sender public key, source address and
/// ping id match a request this instance actually sent
/// (`DHT.c: sent_nodes_request_to_node`). So on an instance that has queried
/// exactly one node, "a nodes response arrived" means "that node answered".
///
/// ## The isolation that makes it sound
///
/// Every probe runs on its own short-lived Tox instance, created through
/// `tim2tox_ffi_create_test_instance_ex` with:
///  * a **fresh scratch profile directory** — no saved DHT nodes, no saved
///    bootstrap node, none of the real account's data;
///  * **`local_discovery_enabled = 0`** — a LAN peer answering a discovery
///    broadcast is the one way an unsolicited response could reach us, and it
///    would make a dead candidate look alive. This is exactly the pollution
///    that made a connection-status-based verdict unacceptable;
///  * **no bootstrap call to anything but the candidate** — the candidate is
///    the only node this instance is ever told about.
///
/// The live session is never used for the verdict even when one exists: a
/// connected session crawls the DHT continuously, so "a nodes response
/// arrived" would be true for a dead node too. That would be the same lie in
/// the opposite direction.
///
/// Probes are serialised so two overlapping probes can never share an
/// instance and cross-attribute each other's answers.
class BootstrapNodeProbe {
  BootstrapNodeProbe._();

  /// How long to wait for a DHT response.
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// UDP is lossy and a single `getnodes` can simply evaporate, so the request
  /// is repeated until the timeout rather than sent once and hoped over.
  static const Duration _retryInterval = Duration(seconds: 1);

  static final RegExp _pubkeyPattern = RegExp(r'^[0-9A-Fa-f]{64}$');

  /// Serialises probes; see the class docs.
  static Future<void> _queue = Future<void>.value();

  /// Test seam: when set, [probe] delegates here instead of touching the FFI.
  @visibleForTesting
  static Future<BootstrapProbeVerdict> Function({
    required String host,
    required int port,
    required String publicKey,
    FfiChatService? service,
  })?
  debugProbeOverride;

  /// Validates the descriptor the same way toxcore will.
  static bool isWellFormed(String host, int port, String publicKey) {
    if (port < 1 || port > 65535) return false;
    if (host.isEmpty || host.length > 255 || host != host.trim()) return false;
    if (host.codeUnits.any((c) => c <= 0x20 || c == 0x7F)) return false;
    return _pubkeyPattern.hasMatch(publicKey);
  }

  /// Probe [host]:[port]/[publicKey] and return a real verdict.
  ///
  /// [service], when supplied, is only used to prime the *live* session's DHT
  /// with a node the user is asking about; it never decides the verdict.
  /// Throws [BootstrapProbeUnavailable] only when the probe could not be run.
  static Future<BootstrapProbeVerdict> probe({
    required String host,
    required int port,
    required String publicKey,
    FfiChatService? service,
    Duration timeout = defaultTimeout,
  }) async {
    if (!isWellFormed(host, port, publicKey)) {
      return BootstrapProbeVerdict.invalid;
    }

    final override = debugProbeOverride;
    if (override != null) {
      return override(
        host: host,
        port: port,
        publicKey: publicKey,
        service: service,
      );
    }

    // Priming the real session is a side effect the user is asking for
    // ("try this node"), not evidence. Its boolean is deliberately discarded.
    if (service != null) {
      try {
        await service.tryBootstrapNode(host, port, publicKey);
      } catch (e) {
        SafeDiagnostics.logFailure(
          '[BootstrapNodeProbe] priming the live session failed',
          e,
        );
      }
    }

    final completer = Completer<BootstrapProbeVerdict>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(
          await _runIsolatedProbe(
            host: host,
            port: port,
            publicKey: publicKey,
            timeout: timeout,
          ),
        );
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Force-release probe resources. Kept for widget `dispose()`; each probe
  /// already owns and tears down its own instance, so this only waits for an
  /// in-flight probe to finish releasing.
  static Future<void> shutdown() => _queue;

  // ---- probe mechanics ----------------------------------------------------

  static Future<BootstrapProbeVerdict> _runIsolatedProbe({
    required String host,
    required int port,
    required String publicKey,
    required Duration timeout,
  }) async {
    final session = await _ProbeSession.start();
    try {
      // A DHT getnodes request is UDP-only. With no UDP socket bound (a
      // UDP-blocked network, or TOX_FORCE_TCP_ONLY) the probe can prove
      // nothing about the node, so say exactly that instead of returning a
      // false negative for every node the user tries.
      if (session.udpPort == 0) return BootstrapProbeVerdict.udpUnavailable;
      final answered = await session.awaitAnyResponse(
        host: host,
        port: port,
        publicKey: publicKey,
        timeout: timeout,
      );
      final verdict = verdictFor(
        answered: answered,
        sendCount: session.sendCount,
        sendErrors: session.sendErrors,
      );
      AppLogger.log(
        '[BootstrapNodeProbe] $host:$port -> ${verdict.name} '
        '(probeUdp=${session.udpPort} sent=${session.sendCount} '
        'responses=${session.responseCount} '
        'sendErrors=${session.sendErrors.map((e) => e.name).join(',')})',
      );
      return verdict;
    } finally {
      session.dispose();
    }
  }

  /// Name the verdict from what the probe window actually observed.
  ///
  /// `sendCount == 0` means NOT ONE getnodes request left this device across
  /// the whole window — see [_ProbeSession.sendCount] — and WHY decides whose
  /// fault that is:
  ///
  /// * every refusal described the descriptor ([DhtSendNodesRequestError
  ///   .isDescriptorProblem]: an unresolvable host, a bad port) — the node was
  ///   asked for and could not even be addressed, which is exactly the
  ///   "unresolvable host" [BootstrapProbeVerdict.unreachable] documents;
  /// * anything else (UDP disabled, no usable instance, a send that failed on
  ///   this device) — nothing was ever asked of the node, so "unreachable"
  ///   would be a verdict about our own socket wearing the node's name. That
  ///   is the same lie [BootstrapProbeVerdict.udpUnavailable] exists to
  ///   prevent (a TCP-only client still reaches bootstrap nodes through
  ///   `tox_add_tcp_relay`), so it takes the same verdict: report the local
  ///   constraint and leave the node selectable.
  ///
  /// Before this split a UDP-capable desktop probing `tox.example.org` was
  /// told "this device is running TCP-only" — false, and it hid the real
  /// answer (the host does not resolve).
  @visibleForTesting
  static BootstrapProbeVerdict verdictFor({
    required bool answered,
    required int sendCount,
    required Set<DhtSendNodesRequestError> sendErrors,
  }) {
    if (answered) return BootstrapProbeVerdict.reachable;
    if (sendCount > 0) return BootstrapProbeVerdict.unreachable;
    final descriptorOnly =
        sendErrors.isNotEmpty && sendErrors.every((e) => e.isDescriptorProblem);
    return descriptorOnly
        ? BootstrapProbeVerdict.unreachable
        : BootstrapProbeVerdict.udpUnavailable;
  }
}

/// One short-lived, fully isolated Tox instance used for exactly one probe.
class _ProbeSession {
  _ProbeSession._(this._ffi, this._handle, this._dir, this._svc, this.udpPort);

  final ffi_lib.Tim2ToxFfi _ffi;
  final int _handle;
  final Directory _dir;
  final FfiChatService _svc;

  /// The probe instance's own UDP port; 0 means this device has no UDP.
  final int udpPort;

  /// Diagnostics: how many getnodes requests toxcore accepted, and how many
  /// DHT nodes responses came back. `sent > 0 && responses == 0` is the
  /// signature of a genuinely unreachable node; `sent == 0` means no request
  /// ever left, and [sendErrors] says whether that was the descriptor's fault
  /// (unresolvable host, bad port) or this device's — see
  /// [BootstrapNodeProbe.verdictFor].
  int sendCount = 0;
  int responseCount = 0;

  /// Every distinct reason toxcore refused a send during the window. Read
  /// together with [sendCount] by [BootstrapNodeProbe.verdictFor].
  final Set<DhtSendNodesRequestError> sendErrors = <DhtSendNodesRequestError>{};

  static Future<_ProbeSession> start() async {
    final root = await AppPaths.getProfileStorageRoot();
    final dir = Directory(
      p.join(root, '.tmp_node_probe_${DateTime.now().microsecondsSinceEpoch}'),
    );
    await dir.create(recursive: true);

    final ffi = ffi_lib.Tim2ToxFfi.open();
    final pathPtr = dir.path.toNativeUtf8();
    final int handle;
    try {
      // localDiscovery = 0, ipv6 = 1. Disabling local discovery is what keeps
      // a LAN peer from answering on a dead candidate's behalf.
      handle = ffi.createTestInstanceExNative(pathPtr, 0, 1);
    } finally {
      pkgffi.malloc.free(pathPtr);
    }
    if (handle == 0) {
      await _deleteQuietly(dir);
      throw BootstrapProbeUnavailable('probe Tox instance failed to start');
    }
    // `create_test_instance_ex` already ran InitSDK, which builds the Tox
    // instance and starts its native iterate thread — no login and no
    // `startPolling()` are needed, and the DHT response arrives on a direct
    // native callback rather than through the polled event queue.
    //
    // `g_current_instance_id` is a PROCESS-GLOBAL, so it is switched only
    // around synchronous FFI calls and restored immediately; it must never
    // stay switched across an await or the live session's calls would be
    // routed into the probe instance.
    //
    // Everything from here on runs with a LIVE handle that no caller owns yet:
    // if `getUdpPort` / `FfiChatService()` / `AppLogger.log` throws, `start()`
    // unwinds without ever returning a session, so nobody can call `dispose()`
    // and BOTH the Tox instance and its scratch directory would leak for the
    // rest of the process. Tear them down here and rethrow.
    try {
      final session = _ProbeSession._(
        ffi,
        handle,
        dir,
        FfiChatService(),
        ffi.getUdpPort(handle),
      );
      AppLogger.log(
        '[BootstrapNodeProbe] probe instance ready '
        '(handle=$handle udp=${session.udpPort})',
      );
      return session;
    } catch (_) {
      _destroyQuietly(ffi, handle);
      await _deleteQuietly(dir);
      rethrow;
    }
  }

  /// Send `getnodes` to [host]:[port] until any DHT nodes response arrives or
  /// [timeout] elapses. See [BootstrapNodeProbe] for why any response counts.
  ///
  /// Returns `true` only when a response arrived. A `false` here means "no
  /// answer within the window" — it does NOT distinguish a dead node from a
  /// probe that never got off the ground; [sendCount] and [sendErrors] do, and
  /// [BootstrapNodeProbe.verdictFor] reads them before naming a verdict.
  Future<bool> awaitAnyResponse({
    required String host,
    required int port,
    required String publicKey,
    required Duration timeout,
  }) async {
    final answered = Completer<void>();
    _run(() {
      _svc.setDhtNodesResponseCallback((_, _, _) {
        responseCount++;
        if (!answered.isCompleted) answered.complete();
      });
    });

    Timer? retry;
    try {
      // `targetPublicKey` is the candidate's own key: we are asking the node
      // for its neighbours, and any reply at all is the signal.
      //
      // A failed FIRST send is NOT fatal any more. It used to `return false`
      // immediately, which (a) blamed the node for a local send failure and
      // (b) meant the very first send was the only one never retried — the 1 s
      // `Timer.periodic` below only started once a send had already succeeded,
      // so one transient local hiccup permanently read as "Node unreachable" in
      // Settings for a node that was fine. The retry timer now starts
      // unconditionally and keeps trying for the whole window; if EVERY attempt
      // fails, `sendCount` stays 0 and [BootstrapNodeProbe.verdictFor] decides
      // from the recorded refusal reasons whether that is the descriptor's
      // fault (unresolvable host) or this device's.
      _send(host, port, publicKey);
      retry = Timer.periodic(BootstrapNodeProbe._retryInterval, (_) {
        if (answered.isCompleted) return;
        _send(host, port, publicKey);
      });
      await answered.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      retry?.cancel();
    }
  }

  bool _send(String host, int port, String publicKey) {
    try {
      final refusal = _run(
        () => _svc.dhtSendNodesRequestChecked(publicKey, host, port, publicKey),
      );
      if (refusal == null) {
        sendCount++;
        return true;
      }
      sendErrors.add(refusal);
      return false;
    } catch (e) {
      SafeDiagnostics.logFailure(
        '[BootstrapNodeProbe] getnodes send failed',
        e,
      );
      return false;
    }
  }

  /// Run [action] with the probe instance as the current FFI instance.
  ///
  /// [action] MUST be synchronous — see the note in [start].
  ///
  /// The instance to restore is read HERE, on entry, rather than snapshotted
  /// once in [start]: `g_current_instance_id` is a process global, a probe
  /// lives for up to [BootstrapNodeProbe.defaultTimeout], and `_run` is
  /// re-entered from the retry [Timer]. Restoring a construction-time snapshot
  /// would clobber whatever instance the rest of the app had made current in
  /// the meantime. (toxee's singleton flow never changes it, so this is a
  /// latent race rather than a live bug — but it is inherent to the pattern.)
  T _run<T>(T Function() action) {
    final previous = _ffi.getCurrentInstanceId();
    _ffi.setCurrentInstance(_handle);
    try {
      return action();
    } finally {
      _ffi.setCurrentInstance(previous);
    }
  }

  void dispose() {
    try {
      _run(_svc.clearDhtNodesResponseCallback);
    } catch (e) {
      SafeDiagnostics.logFailure(
        '[BootstrapNodeProbe] failed to clear DHT callback',
        e,
      );
    }
    _destroyQuietly(_ffi, _handle);
    unawaited(_deleteQuietly(_dir));
  }

  /// Destroy a probe instance and hand the process-global current instance back
  /// to whatever it was on entry (same "read it now, not at construction time"
  /// rule as [_run]). Never throws — teardown must not mask the original error
  /// on the [start] failure path.
  static void _destroyQuietly(ffi_lib.Tim2ToxFfi ffi, int handle) {
    try {
      final previous = ffi.getCurrentInstanceId();
      try {
        // destroy_test_instance refuses to run on the current instance's
        // behalf, so hand the global back to the default first.
        ffi.setCurrentInstance(0);
        ffi.destroyTestInstance(handle);
      } finally {
        // Never restore a handle we just destroyed.
        ffi.setCurrentInstance(previous == handle ? 0 : previous);
      }
    } catch (e) {
      SafeDiagnostics.logFailure(
        '[BootstrapNodeProbe] probe instance teardown failed',
        e,
      );
    }
  }

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      SafeDiagnostics.logFailure(
        '[BootstrapNodeProbe] probe profile cleanup failed',
        e,
      );
    }
  }
}
