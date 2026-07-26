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

    test('stale running-flag + NO saved pre-LAN node → clears the flag and '
        'leaves the current bootstrap node UNTOUCHED', () async {
      await Prefs.setLanBootstrapServiceRunning(true);
      // The user's normal current node is present; NO pre-LAN node was stashed
      // (e.g. the crash happened before it was). Recovery must clear the flag
      // WITHOUT clobbering the current node (codex: assert it, not just the flag).
      await Prefs.setCurrentBootstrapNode('9.9.9.9', 33445, 'USERNODE');

      await mgr.recoverFromCrashedSession();

      expect(await Prefs.getLanBootstrapServiceRunning(), isFalse);
      final cur = await Prefs.getCurrentBootstrapNode();
      expect(
        cur?.host,
        '9.9.9.9',
        reason: 'with no pre-LAN node, recovery must NOT touch current node',
      );
      expect(cur?.port, 33445);
      expect(cur?.pubkey, 'USERNODE');
    });

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
