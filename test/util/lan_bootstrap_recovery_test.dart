// L1 gate for the HERMETIC half of S92 — LAN bootstrap crash-recovery + guards.
// The start/stop path binds a real native UDP socket (FFI
// `createTestInstanceNative`) and stays native-bound (see the S92 spec), but the
// crash-RECOVERY hook is pure Prefs logic with no native dependency, and the
// "is it running / what's its info" state is observable on a fresh manager.
// These are real behaviours (a crash between start and stop must restore the
// user's pre-LAN bootstrap node on the next cold start) and are gated here with
// zero production-code change.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/lan_bootstrap_node_ownership.dart';
import 'package:toxee/util/lan_bootstrap_service.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mgr = LanBootstrapServiceManager.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // `Prefs` caches its own SharedPreferences instance (prefs.dart `_cachedPrefs`),
    // so `setMockInitialValues` alone does NOT give Prefs a fresh store between
    // tests. Re-`initialize` it with a fresh instance so each case is isolated
    // (codex — otherwise a later case inherits an earlier case's restored node).
    await Prefs.initialize(await SharedPreferences.getInstance());
  });

  group('S92 LAN bootstrap — recoverFromCrashedSession (pure Prefs)', () {
    test('no stale running-flag → no-op (nothing to recover)', () async {
      // Default: running flag unset → recover returns early, touches nothing.
      await mgr.recoverFromCrashedSession();
      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
      expect(await Prefs.getCurrentBootstrapNode(), isNull);
      expect(await Prefs.getPreLanBootstrapNode(), isNull);
    });

    test('stale running-flag + saved pre-LAN node → restores the node as current, '
        'clears the pre-LAN node, clears the flag', () async {
      // Simulate a process that crashed between start and stop: the LAN-running
      // flag is set, the user's ORIGINAL bootstrap node was saved aside, and the
      // current node points at the now-dead LAN bootstrap instance.
      await Prefs.setLanBootstrapServiceRunning(true);
      await Prefs.setPreLanBootstrapNode('1.2.3.4', 33445, 'PRELANPUBKEY');
      await Prefs.setCurrentBootstrapNode('192.168.1.9', 40000, 'DEADLANKEY');

      await mgr.recoverFromCrashedSession();

      final cur = await Prefs.getCurrentBootstrapNode();
      expect(cur?.host, '1.2.3.4', reason: 'the pre-LAN node is restored');
      expect(cur?.port, 33445);
      expect(cur?.pubkey, 'PRELANPUBKEY');
      expect(
        await Prefs.getPreLanBootstrapNode(),
        isNull,
        reason: 'the saved-aside node is consumed/cleared',
      );
      expect(
        await Prefs.getLanBootstrapServiceRunning(),
        isFalse,
        reason: 'the stale running flag is cleared',
      );
    });

    test('stale running-flag + NO saved pre-LAN node → clears the flag AND the '
        'dead LAN node', () async {
      await Prefs.setLanBootstrapServiceRunning(true);
      // With the LAN service running and NO pre-LAN snapshot, the current node
      // can only be the LAN node the crashed run set on start (a manual/auto
      // node would have been snapshotted). That address is dead, so recovery
      // clears it rather than leaving a dead node for init() to apply —
      // symmetric with the interactive stop path (LAN review 2026-09-15, F4).
      await Prefs.setCurrentBootstrapNode('192.168.1.9', 40000, 'DEADLANKEY');

      await mgr.recoverFromCrashedSession();

      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
      expect(
        await Prefs.getCurrentBootstrapNode(),
        isNull,
        reason: 'the dead LAN node must be cleared when no pre-LAN node exists',
      );
    });

    // Recovery clears the running flag BEFORE it drops the snapshot, so a crash
    // between the two leaves this state (never "running, no snapshot", which
    // would delete the node just restored). The next cold start must sweep
    // the stale snapshot and leave the restored current node alone.
    test('no running-flag + stale snapshot → snapshot swept, current kept',
        () async {
      await Prefs.setPreLanBootstrapNode('1.2.3.4', 33445, 'PRELANPUBKEY');
      await Prefs.setCurrentBootstrapNode('1.2.3.4', 33445, 'PRELANPUBKEY');

      await mgr.recoverFromCrashedSession();

      expect(await Prefs.getPreLanBootstrapNode(), isNull);
      expect((await Prefs.getCurrentBootstrapNode())?.host, '1.2.3.4');
      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
    });

    test('the restore runs while flag and snapshot are both still set, so a '
        'failed restore loses nothing', () async {
      await Prefs.setLanBootstrapServiceRunning(true);
      await Prefs.setPreLanBootstrapNode('203.0.113.7', 33445, 'PRELANKEY');
      await Prefs.setCurrentBootstrapNode('192.168.1.9', 40000, 'DEADLANKEY');
      final seen = <String>[];
      final recordingManager = LanBootstrapServiceManager.forTesting(
        localAddressProvider: () async => null,
        setCurrentBootstrapNode: (host, port, pubkey) async {
          seen.add('running=${await Prefs.getLanBootstrapServiceRunning()} '
              'snapshot=${(await Prefs.getPreLanBootstrapNode())?.host}');
          await Prefs.setCurrentBootstrapNode(host, port, pubkey);
        },
      );

      await recordingManager.recoverFromCrashedSession();

      expect(seen, ['running=true snapshot=203.0.113.7']);
      expect((await Prefs.getCurrentBootstrapNode())?.host, '203.0.113.7');
      expect(await Prefs.getPreLanBootstrapNode(), isNull);
      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
    });

    // Recovery runs on the cold-start path before runApp: a store that refuses
    // the snapshot write must be logged, never thrown into startup.
    for (final running in [false, true]) {
      test('a failing snapshot drop does not escape recovery '
          '(running flag ${running ? 'set' : 'clear'})', () async {
        await Prefs.setLanBootstrapServiceRunning(running);
        await Prefs.setPreLanBootstrapNode('203.0.113.7', 33445, 'PRELANKEY');
        await Prefs.setCurrentBootstrapNode('203.0.113.7', 33445, 'PRELANKEY');

        await recoverLanBootstrapCrash(
          serviceAlive: false,
          setCurrentNode: Prefs.setCurrentBootstrapNode,
          clearSnapshot: () async => throw StateError('simulated store failure'),
        );

        expect((await Prefs.getCurrentBootstrapNode())?.host, '203.0.113.7');
        expect(
          await Prefs.getLanBootstrapServiceRunning(),
          isFalse,
          reason: 'the flag clears first, so the leftover snapshot is inert',
        );
      });
    }

    test(
      'failed pre-LAN restore preserves snapshot and running flag for retry',
      () async {
        await Prefs.setLanBootstrapServiceRunning(true);
        await Prefs.setPreLanBootstrapNode('203.0.113.7', 33445, 'PRELANKEY');
        await Prefs.setCurrentBootstrapNode('192.168.1.9', 40000, 'DEADLANKEY');
        final failingManager = LanBootstrapServiceManager.forTesting(
          localAddressProvider: () async => null,
          setCurrentBootstrapNode: (_, _, _) async {
            throw StateError('simulated preference write failure');
          },
        );

        await failingManager.recoverFromCrashedSession();

        final current = await Prefs.getCurrentBootstrapNode();
        final snapshot = await Prefs.getPreLanBootstrapNode();
        expect(current?.host, '192.168.1.9');
        expect(snapshot?.host, '203.0.113.7');
        expect(await Prefs.getLanBootstrapServiceRunning(), isTrue);
      },
    );
  });

  group(
    'S92 LAN bootstrap — observable state on a fresh (un-started) manager',
    () {
      test('isBootstrapServiceRunning() is false with no live instance', () {
        expect(mgr.isBootstrapServiceRunning(), isFalse);
      });

      test(
        'getBootstrapServiceInfo() is null when nothing is running',
        () async {
          expect(await mgr.getBootstrapServiceInfo(), isNull);
        },
      );
    },
  );
}
