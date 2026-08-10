// L1 — the Prefs "do-not-disturb / muted" storage family, which had ZERO test
// coverage despite being the persistence layer behind a directly user-visible
// regression class: "I muted this peer and still got a banner."
//
// WHY THIS FILE EXISTS
// --------------------
// `lib/util/prefs.dart` is the widest-blast-radius file in the repo (75
// importers). Four of its public methods in this family were never touched by
// any test:
//
//   * `Prefs.getMuted` / `Prefs.setMuted`               — the per-account muted
//     conversation SET (key `muted_peers_<first16>`)
//   * `Prefs.getDoNotDisturb` / `Prefs.setDoNotDisturb` — the per-FRIEND DND
//     boolean (key `do_not_disturb_<friendId>_<first16>`)
//
// Both are account-scoped through `Prefs._scopedKey` (16-char Tox-ID prefix +
// the shared `scopedPrefsKey` helper), so the regression that matters most is
// account BLEED: account A muting a peer must never mute that peer for account
// B on the same device, and deleting account A must take A's mute state with
// it.
//
// WHAT THIS FILE LOCKS
// --------------------
//   1. Defaults: unset == "not muted" / "not DND" (an accidental default flip
//      would silence every notification in the app).
//   2. Round-trip through the real SharedPreferences mock store.
//   3. The exact on-disk key strings — these are the migration/compat contract
//      shared with `SharedPreferencesAdapter` and with the account-teardown
//      sweep, which matches on the `_<first16>` SUFFIX.
//   4. Per-account isolation in both directions (A does not leak into B, and
//      switching back to A still sees A's state).
//   5. `Prefs.clearScopedKeysForAccount` — deleting an account removes that
//      account's mute/DND keys and leaves the other account's alone.
//   6. The no-active-account guard, which BOTH APIs now share. `setDoNotDisturb`
//      used to fall through to an unscoped `do_not_disturb_<friendId>` key —
//      cross-account visible AND permanently un-collectable, since every
//      teardown path matches on the `_<first16>` suffix. It now early-returns
//      like `setMuted`, and the getters return the "not muted" default instead
//      of reading that global slot.
//
// WHAT THIS FILE DOES NOT COVER (and why)
// ---------------------------------------
//   * The C2C / group `recvOpt` family (`get/setC2CReceiveMessageOpt`,
//     `get/setGroupReceiveMessageOpt`) — covered by the sibling
//     `prefs_receive_message_opt_test.dart`, which also links them to the
//     notification-suppression consumer. Note that recvOpt, not this family,
//     is what `NotificationMessageListener._shouldSuppress` actually reads;
//     see that sibling file's header for the consumer chain.
//   * Whether anything in the app still CALLS `get/setMuted` or
//     `get/setDoNotDisturb`. A repo-wide search (re-run 2026-08-08 over `lib/`,
//     `third_party/tim2tox/dart` and `third_party/chat-uikit-flutter`) finds no
//     production consumer outside `PrefsImpl`/`prefs_interfaces` (which merely
//     re-export `getMuted`/`setMuted` and are themselves uncalled). The four
//     methods are kept only so pre-existing on-disk state stays reachable —
//     see the status note on `Prefs.getMuted`. These tests therefore pin the
//     STORAGE contract only; they cannot prove a UI surface honours it.
//   * Legacy unscoped-key migration (there is none for these keys — unlike
//     `getGroupOwner`/`getGroupMemberNameCard`, neither getter falls back to an
//     unscoped key when the scoped one is missing).
//
// Mobile parity: pure Dart over SharedPreferences with no platform branch, so
// iOS/Android/desktop all execute exactly this code.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Two 76-char Tox IDs whose FIRST 16 CHARS DIFFER — that prefix is the whole
  // scoping mechanism, so ids that only differ past char 16 would share a key.
  final String toxIdA = '${'A' * 16}${'1' * 60}';
  final String toxIdB = '${'B' * 16}${'2' * 60}';
  final String prefixA = 'A' * 16;
  final String prefixB = 'B' * 16;

  // 64-char (public-key form) peer ids. Deliberately NOT ending in the account
  // prefix, so the suffix-matching account sweep can't match them by accident.
  final String friend1 = 'D' * 64;
  final String friend2 = 'E' * 64;

  late SharedPreferences store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await SharedPreferences.getInstance();
    await Prefs.initialize(store);
    // Start with NO implicit current account so scope is only what a test sets.
    await Prefs.setCurrentAccountToxId(null);
  });

  tearDown(() async {
    // `Prefs` caches the active account in a static field; leaving it set would
    // silently rescope every later test in this process.
    await Prefs.setCurrentAccountToxId(null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Set<String> keysStartingWith(String prefix) =>
      store.getKeys().where((k) => k.startsWith(prefix)).toSet();

  group('Prefs.getMuted / setMuted — account-scoped muted conversation set', () {
    test('unset reads back as the EMPTY set, never a mute-all', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      expect(
        await Prefs.getMuted(),
        isEmpty,
        reason:
            'a fresh account must have nothing muted; a non-empty default would '
            'silence conversations the user never touched',
      );
    });

    test('round-trips and writes exactly the scoped key', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setMuted(<String>{friend1, friend2});

      expect(await Prefs.getMuted(), <String>{friend1, friend2});
      expect(
        keysStartingWith('muted_peers'),
        <String>{'muted_peers_$prefixA'},
        reason:
            'setMuted must write one account-scoped key of the form '
            'muted_peers_<first16 of toxId>',
      );
      expect(
        store.getStringList('muted_peers_$prefixA')?.toSet(),
        <String>{friend1, friend2},
      );
    });

    test('overwriting replaces the whole set (it is not additive)', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setMuted(<String>{friend1, friend2});
      await Prefs.setMuted(<String>{friend2});

      expect(
        await Prefs.getMuted(),
        <String>{friend2},
        reason: 'setMuted is a full replace; friend1 must be un-muted',
      );
    });

    test('account A muting a peer does NOT mute it for account B', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setMuted(<String>{friend1});

      await Prefs.setCurrentAccountToxId(toxIdB);
      expect(
        await Prefs.getMuted(),
        isEmpty,
        reason: "account B must not inherit account A's mutes",
      );

      await Prefs.setMuted(<String>{friend2});

      await Prefs.setCurrentAccountToxId(toxIdA);
      expect(
        await Prefs.getMuted(),
        <String>{friend1},
        reason: "switching back to A must restore A's own mute set, not B's",
      );
      expect(
        keysStartingWith('muted_peers'),
        <String>{'muted_peers_$prefixA', 'muted_peers_$prefixB'},
        reason: 'the two accounts must occupy two independent keys',
      );
    });

    test('with NO active account setMuted writes nothing at all', () async {
      // Contract: both getMuted and setMuted early-return on a null/empty
      // current account, so a mute performed before login is DROPPED rather
      // than landing on a global key that every account would then share.
      await Prefs.setMuted(<String>{friend1});

      expect(keysStartingWith('muted_peers'), isEmpty);
      expect(await Prefs.getMuted(), isEmpty);
    });

    test(
      'clearScopedKeysForAccount removes only the deleted account mute set',
      () async {
        await Prefs.setCurrentAccountToxId(toxIdA);
        await Prefs.setMuted(<String>{friend1});
        await Prefs.setCurrentAccountToxId(toxIdB);
        await Prefs.setMuted(<String>{friend2});

        await Prefs.clearScopedKeysForAccount(toxIdA);

        expect(
          keysStartingWith('muted_peers'),
          <String>{'muted_peers_$prefixB'},
          reason: "deleting account A must take A's mute set and nothing else",
        );
        expect(await Prefs.getMuted(), <String>{friend2},
            reason: 'B is still the current account and keeps its mutes');
      },
    );
  });

  group('Prefs.getDoNotDisturb / setDoNotDisturb — per-friend DND flag', () {
    test('unset reads back as FALSE', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      expect(
        await Prefs.getDoNotDisturb(friend1),
        isFalse,
        reason:
            'the default must be "notify"; a true default would silence every '
            'friend on first run',
      );
    });

    test('round-trips true and writes exactly the scoped key', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setDoNotDisturb(friend1, true);

      expect(await Prefs.getDoNotDisturb(friend1), isTrue);
      expect(
        keysStartingWith('do_not_disturb_'),
        <String>{'do_not_disturb_${friend1}_$prefixA'},
      );
      expect(store.getBool('do_not_disturb_${friend1}_$prefixA'), isTrue);
    });

    test('setting false PERSISTS false rather than deleting the key', () async {
      // Distinct from the recvOpt setters, which delete the key for opt == 0.
      // Here the entry stays with an explicit `false`. Worth pinning: a future
      // "optimisation" that switched to remove() would be behaviourally
      // equivalent for reads but would change what the account-export /
      // teardown sweeps see.
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setDoNotDisturb(friend1, true);
      await Prefs.setDoNotDisturb(friend1, false);

      expect(await Prefs.getDoNotDisturb(friend1), isFalse);
      expect(
        store.getBool('do_not_disturb_${friend1}_$prefixA'),
        isFalse,
        reason: 'false is stored explicitly, not represented by key absence',
      );
    });

    test('the flag is per friend, not per account', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setDoNotDisturb(friend1, true);

      expect(await Prefs.getDoNotDisturb(friend1), isTrue);
      expect(
        await Prefs.getDoNotDisturb(friend2),
        isFalse,
        reason: 'muting one friend must not mute a different friend',
      );
    });

    test('account A DND does NOT leak into account B', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setDoNotDisturb(friend1, true);

      await Prefs.setCurrentAccountToxId(toxIdB);
      expect(
        await Prefs.getDoNotDisturb(friend1),
        isFalse,
        reason:
            'the same friend can be a contact of both accounts; DND is a '
            'per-account decision',
      );

      await Prefs.setCurrentAccountToxId(toxIdA);
      expect(await Prefs.getDoNotDisturb(friend1), isTrue);
    });

    test(
      'with NO active account setDoNotDisturb writes nothing at all '
      '(same guard as setMuted)',
      () async {
        // Regression guard. This used to fall through to `_scopedKey(base,
        // null)` == the raw `do_not_disturb_<friendId>` key: visible to EVERY
        // account, and invisible to `clearScopedKeysForAccount` /
        // `clearAccountData`, which only sweep the `_<first16>` suffix. A
        // pre-login toggle therefore leaked a permanent, un-deletable entry.
        await Prefs.setDoNotDisturb(friend1, true);

        expect(
          keysStartingWith('do_not_disturb_'),
          isEmpty,
          reason:
              'a DND write with no account must be DROPPED, never parked on an '
              'unscoped key no teardown path can reach',
        );
        expect(await Prefs.getDoNotDisturb(friend1), isFalse);
      },
    );

    test(
      'a legacy UNSCOPED entry is not read back while logged out',
      () async {
        // Older builds could leave `do_not_disturb_<friendId>` behind. The
        // getter must not resurrect it as a cross-account default — and it
        // must not be mistaken for account A's state either. (Deleting it is
        // a separate concern, owned by the one-shot PrefsUpgrader v2→v3 sweep;
        // see test/prefs_migration_registry_test.dart. This test asserts the
        // READ contract, so the entry is deliberately still present here.)
        SharedPreferences.setMockInitialValues(<String, Object>{
          'do_not_disturb_$friend1': true,
        });
        store = await SharedPreferences.getInstance();
        await Prefs.initialize(store);
        await Prefs.setCurrentAccountToxId(null);

        expect(
          await Prefs.getDoNotDisturb(friend1),
          isFalse,
          reason: 'no account => no scope => the legacy global slot is ignored',
        );

        await Prefs.setCurrentAccountToxId(toxIdA);
        expect(
          await Prefs.getDoNotDisturb(friend1),
          isFalse,
          reason:
              'account A reads `do_not_disturb_<friend>_<prefixA>`; the legacy '
              'unscoped entry was never A\'s and must not be adopted',
        );
      },
    );

    test(
      'clearScopedKeysForAccount removes only the deleted account DND flags',
      () async {
        await Prefs.setCurrentAccountToxId(toxIdA);
        await Prefs.setDoNotDisturb(friend1, true);
        await Prefs.setCurrentAccountToxId(toxIdB);
        await Prefs.setDoNotDisturb(friend2, true);

        await Prefs.clearScopedKeysForAccount(toxIdA);

        expect(
          keysStartingWith('do_not_disturb_'),
          <String>{'do_not_disturb_${friend2}_$prefixB'},
          reason:
              'the sweep matches on the `_<first16>` suffix, so only A-scoped '
              'DND flags may disappear',
        );
        expect(await Prefs.getDoNotDisturb(friend2), isTrue);
      },
    );
  });
}
