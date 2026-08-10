import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/util/bootstrap_node_ensurer.dart';
import 'package:toxee/util/bootstrap_nodes.dart';
import 'package:toxee/util/prefs.dart';

/// Records the bootstrap nodes applied to the live instance, and lets the test
/// dictate `isConnected`, without touching the native Tox core.
class _RecordingService extends FfiChatService {
  _RecordingService({bool connected = false}) : _connected = connected, super();

  final bool _connected;
  final List<({String host, int port, String pubkey})> added = [];

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> addBootstrapNode(String host, int port, String publicKey) async {
    added.add((host: host, port: port, pubkey: publicKey));
    return true;
  }

  @override
  Future<bool> tryBootstrapNode(String host, int port, String publicKey) async {
    added.add((host: host, port: port, pubkey: publicKey));
    return true;
  }
}

bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

/// Returns `true` when the calling test must stop because libtim2tox_ffi is not
/// loadable here, after reporting a real SKIP.
///
/// Every case below used to open with a bare `if (!_ffiAvailable()) return;`,
/// which reported a silent **PASS** on any machine where the native library had
/// not been built — a green run that had asserted nothing. `markTestSkipped`
/// makes the gap visible in the test report instead.
bool _skipWithoutFfi() {
  if (_ffiAvailable()) return false;
  markTestSkipped(
    'libtim2tox_ffi is not loadable in this environment — build it with '
    './build_all.sh to exercise the bootstrap-node paths',
  );
  return true;
}

BootstrapNode _node(String ip, {String status = 'ONLINE'}) => BootstrapNode(
  ipv4: ip,
  port: 33445,
  // 64 hex chars — a structurally valid Tox public key.
  publicKey: 'A' * 64,
  status: status,
);

Future<void> _resetPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    BootstrapNodeEnsurer.debugNodeFetcher = null;
  });

  test('fresh auto-mode account applies built-in fallback nodes and seeds prefs '
      'with no network', () async {
    if (_skipWithoutFfi()) return; // needs libtim2tox_ffi (built in CI)
    await _resetPrefs();
    // Background live refresh returns nothing so the assertion is deterministic
    // — we are testing the synchronous first-run fallback path here.
    BootstrapNodeEnsurer.debugNodeFetcher = () async => const <BootstrapNode>[];

    final service = _RecordingService();
    await BootstrapNodeEnsurer.ensureForSession(service);

    final fallback = BootstrapNodesService.fallbackNodes;
    // Up to maxAutoNodes fallback nodes applied immediately, no HTTP wait.
    expect(service.added, hasLength(BootstrapNodeEnsurer.maxAutoNodes));
    expect(service.added.first.host, fallback.first.ipv4);
    // And prefs is seeded so settings / resume have a current node.
    final saved = await Prefs.getCurrentBootstrapNode();
    expect(saved?.host, fallback.first.ipv4);
  });

  test(
    'auto mode applies at most maxAutoNodes nodes from the live list',
    () async {
      if (_skipWithoutFfi()) return;
      await _resetPrefs();
      // A saved node exists, so ensureForSession skips the fallback seed and goes
      // straight to the (background) live refresh — exercised deterministically
      // here via refreshIfDisconnected which awaits it.
      BootstrapNodeEnsurer.debugNodeFetcher = () async =>
          List.generate(8, (i) => _node('10.0.0.$i'));

      final service = _RecordingService(connected: false);
      await BootstrapNodeEnsurer.refreshIfDisconnected(service);

      expect(service.added.length, BootstrapNodeEnsurer.maxAutoNodes);
    },
  );

  test('manual mode applies only the saved node and never fetches', () async {
    if (_skipWithoutFfi()) return;
    await _resetPrefs();
    await Prefs.setBootstrapNodeMode('manual');
    await Prefs.setCurrentBootstrapNode('manual.example', 12345, 'B' * 64);
    BootstrapNodeEnsurer.debugNodeFetcher = () async =>
        throw StateError('manual mode must not hit the node list');

    final service = _RecordingService();
    await BootstrapNodeEnsurer.ensureForSession(service);

    expect(service.added, hasLength(1));
    expect(service.added.single.host, 'manual.example');
    expect(service.added.single.port, 12345);
  });

  test('refreshIfDisconnected is a no-op when already connected', () async {
    if (_skipWithoutFfi()) return;
    await _resetPrefs();
    BootstrapNodeEnsurer.debugNodeFetcher = () async =>
        throw StateError('must not fetch when connected');

    final service = _RecordingService(connected: true);
    await BootstrapNodeEnsurer.refreshIfDisconnected(service);

    expect(service.added, isEmpty);
  });

  test('auto mode falls back to status-agnostic nodes when the API flags all '
      'OFFLINE', () async {
    if (_skipWithoutFfi()) return;
    await _resetPrefs();
    // API reachable, valid nodes, but every one marked OFFLINE (stale status).
    // Regression guard for the gap Codex flagged: filtering strictly on ONLINE
    // would apply nothing and leave the session with no DHT entry point.
    BootstrapNodeEnsurer.debugNodeFetcher = () async => [
      _node('5.5.5.5', status: 'OFFLINE'),
      _node('6.6.6.6', status: 'OFFLINE'),
    ];

    final service = _RecordingService(connected: false);
    await BootstrapNodeEnsurer.refreshIfDisconnected(service);

    expect(
      service.added.map((n) => n.host),
      containsAll(<String>['5.5.5.5', '6.6.6.6']),
    );
  });

  test('auto mode applies an IPv6-only node with its raw host', () async {
    if (_skipWithoutFfi()) return;
    await _resetPrefs();
    await Prefs.setCurrentBootstrapNode('seed.example', 33445, 'B' * 64);
    BootstrapNodeEnsurer.debugNodeFetcher = () async => [
      BootstrapNode(
        ipv4: '',
        ipv6: '2001:db8::20',
        port: 33445,
        publicKey: 'A' * 64,
        status: 'ONLINE',
      ),
    ];

    final service = _RecordingService(connected: false);
    await BootstrapNodeEnsurer.refreshIfDisconnected(service);

    expect(service.added, hasLength(1));
    expect(service.added.single.host, '2001:db8::20');
  });
}
