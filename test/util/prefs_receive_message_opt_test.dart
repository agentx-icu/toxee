// L1 — the `recvOpt` (receive-message-option / mute) persistence family in
// `lib/util/prefs.dart`, which had ZERO test coverage:
//
//   * `Prefs.getC2CReceiveMessageOpt`   / `Prefs.setC2CReceiveMessageOpt`
//   * `Prefs.getGroupReceiveMessageOpt` / `Prefs.setGroupReceiveMessageOpt`
//
// WHY THIS FILE EXISTS
// --------------------
// This is the DURABLE half of "the user muted a conversation". The consumer
// chain that makes it user-visible is:
//
//   Prefs (durable)                                     <- this file
//     -> C2CRecvOptCache.hydrateFromPrefs / setAndPersist  (runtime projection)
//        -> NotificationMessageListener._shouldSuppress    (banner or no banner)
//
// `_shouldSuppress` (lib/notifications/notification_message_listener.dart)
// returns true — i.e. NO OS notification — when `C2CRecvOptCache.isMuted(sender)`
// is true, and `isMuted` is `optFor(sender) != 0`. `optFor` is seeded from
// `Prefs.getC2CReceiveMessageOpt`, so a regression in these four methods shows
// up to the user as "I muted them and the banner still fired" (or, worse,
// "everything went silent"). The group side is the same idea: Tox has no native
// group recv-opt, so `Prefs.get/setGroupReceiveMessageOpt` IS the source of
// truth, projected onto `conv.recvOpt` in `FakeChatDataProvider`
// (lib/sdk_fake/fake_provider.dart), which `_shouldSuppress` also consults.
//
// Value semantics (from `ReceiveMsgOptEnum`, tencent_cloud_chat_sdk):
//   0 = V2TIM_RECEIVE_MESSAGE            (notify; the default)
//   1 = V2TIM_NOT_RECEIVE_MESSAGE
//   2 = V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE (what the DND switch writes = "mute")
// Everything non-zero counts as muted for suppression purposes.
//
// WHAT THIS FILE LOCKS
// --------------------
//   1. Default 0 when unset — a non-zero default would mute the whole app.
//   2. Round-trip of 1 and 2, and the "opt == 0 DELETES the key" contract
//      (the setters remove instead of writing 0, which is what keeps the
//      account-teardown sweep and prefs exports free of no-op entries).
//   3. The exact key strings, plus BYTE-FOR-BYTE PARITY with
//      `SharedPreferencesAdapter`. Two writers, one on-disk slot: the platform
//      write path goes through the adapter while several read paths go through
//      `Prefs`, so a divergence would make a mute invisible to the reader.
//      (Same class of tripwire as `friend_remark_key_parity_test.dart`.)
//      Both now delegate to ONE builder — `c2cRecvOptPrefsKey` /
//      `groupRecvOptPrefsKey` in `lib/util/prefs/scoped_key.dart` — so the
//      parity is structural rather than maintained by hand; the tests below
//      stay as the tripwire for anyone who "optimises" that back into two
//      local string concatenations.
//   4. Per-account isolation via the explicit `userToxId` argument, AND the
//      scope ladder both implementations follow when it is omitted.
//   5. `Prefs.clearScopedKeysForAccount` takes the deleted account's recvOpt
//      entries and leaves the other account's.
//   6. The CONSUMER link: a value persisted here is what
//      `C2CRecvOptCache.hydrateFromPrefs` returns and what
//      `C2CRecvOptCache.isMuted` reports — the exact boolean
//      `_shouldSuppress` branches on.
//
// SCOPING AND ID-REPRESENTATION CONTRACT
// --------------------------------------
//   * `userToxId` stays OPTIONAL (it mirrors the tim2tox
//     `ExtendedPreferencesService` signature), but omitting it no longer mints
//     an unscoped, cross-account key. BOTH implementations run the same
//     ladder — explicit `userToxId`, else "the active account", else refuse:
//       - `Prefs._recvOptScope` resolves the active account from
//         `current_account_tox_id`;
//       - `SharedPreferencesAdapter._recvOptScope` resolves it from its own
//         `_accountPrefix` (the adapter is constructed per account, or has the
//         prefix injected once login resolves selfId), because as an injected
//         `ExtendedPreferencesService` it has no other notion of "active".
//     When neither resolves, the getter returns 0 and the setter is a no-op.
//     The unscoped key was doubly bad — every account shared it AND
//     `clearScopedKeysForAccount`'s `_<first16>` suffix sweep could never
//     collect it. Entries older builds already minted are swept once by
//     `PrefsUpgrader` v2→v3 (see `test/prefs_migration_registry_test.dart`).
//   * The id is embedded VERBATIM. No normalisation, deliberately:
//       - No case folding. Every producer feeding these keys emits UPPERCASE
//         hex (`%02X` in `V2TIMFriendshipManagerImpl`,
//         `V2TIMConversationManagerImpl`, `ToxUtil.h`); the handful of `%02x`
//         sites in the C++ tree encode custom-elem payload bytes, DHT node
//         keys, and an internal group chat-id compared with `strncasecmp` —
//         none of them ever becomes a `userID` or `groupID` here. Folding case
//         would orphan every existing entry to fix a split that does not exist.
//       - No 64-char truncation. The C2C and group builders share one shape,
//         and a group id is NOT a Tox public key — truncating it could collapse
//         two distinct groups onto one mute slot.
//     Normalisation therefore lives one layer up, in `C2CRecvOptCache`, which
//     truncates to the 64-char public key (case preserved — the same
//     `length >= 64 ? substring(0, 64) : id` the platform applies when it
//     builds `c2c_<key>` conversation IDs) before touching Prefs, and falls
//     back to the un-truncated key once, migrating it forward. Both halves are
//     pinned below.
//
// WHAT THIS FILE DOES NOT COVER (and why)
// ---------------------------------------
//   * `C2CRecvOptCache.hydrateFromPrefs`'s native re-push side effect. It is
//     fired via `unawaited(...)` and, with the SDK uninitialised in a unit
//     test, `TIMMessageManager.setC2CReceiveMessageOpt` short-circuits on
//     `isInitSDK() == false` before touching any FFI binding. So the tests
//     below are safe to run without the native library, but they assert
//     nothing about the re-push (`_repushPending` / `needsHydration`), which is
//     inherently racy from a test's point of view.
//   * `NotificationMessageListener._shouldSuppress` end-to-end — that decision
//     is already covered in `test/ui/notification_mute_suppression_test.dart`
//     (which drives the cache directly). This file covers the persistence hop
//     that feeds it.
//   * The UI toggle itself (`user_profile_conversation_mute_switch`) — covered
//     by `test/ui/contact/friend_profile_ops_real_ui_test.dart` (S114).
//
// Mobile parity: pure Dart over SharedPreferences, no platform branch — the
// same code runs on iOS/Android/desktop.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/adapters/shared_prefs_adapter.dart';
import 'package:toxee/sdk_fake/c2c_recv_opt_cache.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 76-char Tox IDs differing in their first 16 chars (the scoping prefix).
  final String toxIdA = '${'a' * 16}${'1' * 60}';
  final String toxIdB = '${'b' * 16}${'2' * 60}';
  final String prefixA = 'a' * 16;
  final String prefixB = 'b' * 16;

  // 64-char public-key form, already lower-cased so `toToxPublicKey(peer)`
  // is the identity and the Prefs key and the cache key agree.
  final String peer = 'ab' * 32;
  final String peer2 = 'cd' * 32;
  const String groupId = 'group-42';
  const String groupId2 = 'group-43';

  late SharedPreferences store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await SharedPreferences.getInstance();
    await Prefs.initialize(store);
    await Prefs.setCurrentAccountToxId(null);
    C2CRecvOptCache.debugClear();
  });

  tearDown(() async {
    // Both `Prefs` (static account cache) and `C2CRecvOptCache` (static map)
    // are process-global; leaving either dirty would poison later tests.
    C2CRecvOptCache.debugClear();
    await Prefs.setCurrentAccountToxId(null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Set<String> keysStartingWith(String p) =>
      store.getKeys().where((k) => k.startsWith(p)).toSet();

  group('C2C recvOpt storage', () {
    test('unset reads back as 0 (= notify)', () async {
      expect(
        await Prefs.getC2CReceiveMessageOpt(peer, toxIdA),
        0,
        reason:
            'the default MUST be 0; any non-zero default is read as "muted" by '
            'C2CRecvOptCache.isMuted and would silence every conversation',
      );
    });

    test('mute (2) round-trips and writes exactly the scoped key', () async {
      await Prefs.setC2CReceiveMessageOpt(peer, 2, toxIdA);

      expect(await Prefs.getC2CReceiveMessageOpt(peer, toxIdA), 2);
      expect(
        keysStartingWith('c2c_recv_opt_'),
        <String>{'c2c_recv_opt_${peer}_$prefixA'},
      );
      expect(store.getInt('c2c_recv_opt_${peer}_$prefixA'), 2);
    });

    test('opt 1 is stored verbatim, not collapsed onto 2', () async {
      await Prefs.setC2CReceiveMessageOpt(peer, 1, toxIdA);
      expect(
        await Prefs.getC2CReceiveMessageOpt(peer, toxIdA),
        1,
        reason:
            'V2TIM_NOT_RECEIVE_MESSAGE (1) and V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE '
            '(2) are different options; the store must not normalise them',
      );
    });

    test('setting 0 DELETES the key instead of storing a zero', () async {
      await Prefs.setC2CReceiveMessageOpt(peer, 2, toxIdA);
      expect(keysStartingWith('c2c_recv_opt_'), isNotEmpty);

      await Prefs.setC2CReceiveMessageOpt(peer, 0, toxIdA);

      expect(
        keysStartingWith('c2c_recv_opt_'),
        isEmpty,
        reason: 'un-muting must remove the entry, not persist an explicit 0',
      );
      expect(await Prefs.getC2CReceiveMessageOpt(peer, toxIdA), 0);
    });

    test('a mute under account A is invisible to account B', () async {
      await Prefs.setC2CReceiveMessageOpt(peer, 2, toxIdA);

      expect(
        await Prefs.getC2CReceiveMessageOpt(peer, toxIdB),
        0,
        reason:
            'the same peer can be a contact of both local accounts; muting for '
            'one must not mute for the other',
      );
      expect(await Prefs.getC2CReceiveMessageOpt(peer, toxIdA), 2);
    });

    test('different peers of the same account are independent', () async {
      await Prefs.setC2CReceiveMessageOpt(peer, 2, toxIdA);

      expect(await Prefs.getC2CReceiveMessageOpt(peer2, toxIdA), 0);
      expect(
        keysStartingWith('c2c_recv_opt_'),
        <String>{'c2c_recv_opt_${peer}_$prefixA'},
      );
    });
  });

  group('group recvOpt storage', () {
    test('unset reads back as 0 (= notify)', () async {
      expect(await Prefs.getGroupReceiveMessageOpt(groupId, toxIdA), 0);
    });

    test('mute (2) round-trips and writes exactly the scoped key', () async {
      await Prefs.setGroupReceiveMessageOpt(groupId, 2, toxIdA);

      expect(await Prefs.getGroupReceiveMessageOpt(groupId, toxIdA), 2);
      expect(
        keysStartingWith('group_recv_opt_'),
        <String>{'group_recv_opt_${groupId}_$prefixA'},
      );
      expect(store.getInt('group_recv_opt_${groupId}_$prefixA'), 2);
    });

    test('setting 0 DELETES the key', () async {
      await Prefs.setGroupReceiveMessageOpt(groupId, 2, toxIdA);
      await Prefs.setGroupReceiveMessageOpt(groupId, 0, toxIdA);

      expect(keysStartingWith('group_recv_opt_'), isEmpty);
      expect(await Prefs.getGroupReceiveMessageOpt(groupId, toxIdA), 0);
    });

    test('a muted group under A is not muted under B', () async {
      await Prefs.setGroupReceiveMessageOpt(groupId, 2, toxIdA);

      expect(await Prefs.getGroupReceiveMessageOpt(groupId, toxIdB), 0);
      expect(await Prefs.getGroupReceiveMessageOpt(groupId, toxIdA), 2);
    });

    test('the group and C2C namespaces do not collide', () async {
      // Same trailing id in both namespaces: the key PREFIXES must keep them
      // apart, otherwise muting a group would mute a same-named peer.
      await Prefs.setC2CReceiveMessageOpt(groupId, 2, toxIdA);

      expect(
        await Prefs.getGroupReceiveMessageOpt(groupId, toxIdA),
        0,
        reason: 'a C2C mute must not surface as a group mute',
      );
      expect(await Prefs.getC2CReceiveMessageOpt(groupId, toxIdA), 2);
    });
  });

  group('account scoping (how the key prefix is resolved)', () {
    test(
      'omitting userToxId scopes to the ACTIVE account, not to a global key',
      () async {
        // Regression guard. `scopedPrefsKey` returns the raw key for a null
        // prefix, so passing null straight through used to create one global
        // mute slot: visible to every account AND invisible to
        // `clearScopedKeysForAccount`'s `_<first16>` suffix sweep, hence
        // un-deletable. `_recvOptScope` now resolves the active account first.
        await Prefs.setCurrentAccountToxId(toxIdA);
        await Prefs.setC2CReceiveMessageOpt(peer, 2);

        expect(keysStartingWith('c2c_recv_opt_'), <String>{
          'c2c_recv_opt_${peer}_$prefixA',
        });
        expect(
          await Prefs.getC2CReceiveMessageOpt(peer, toxIdA),
          2,
          reason:
              'the implicit-scope write and the explicit-scope read must land '
              'on the same entry',
        );
        expect(
          await Prefs.getC2CReceiveMessageOpt(peer, toxIdB),
          0,
          reason: 'account B must still be unaffected',
        );

        await Prefs.clearScopedKeysForAccount(toxIdA);
        expect(
          keysStartingWith('c2c_recv_opt_'),
          isEmpty,
          reason:
              'because the entry is now suffix-scoped, account deletion can '
              'actually collect it',
        );
      },
    );

    test(
      'with NO active account and no userToxId, reads are 0 and writes are '
      'dropped',
      () async {
        // The remaining hole would be a mute persisted before login. There is
        // no honest key for it, so the write is dropped rather than parked on
        // a slot every account would inherit.
        await Prefs.setC2CReceiveMessageOpt(peer, 2);
        await Prefs.setGroupReceiveMessageOpt(groupId, 2);

        expect(keysStartingWith('c2c_recv_opt_'), isEmpty);
        expect(keysStartingWith('group_recv_opt_'), isEmpty);
        expect(await Prefs.getC2CReceiveMessageOpt(peer), 0);
        expect(await Prefs.getGroupReceiveMessageOpt(groupId), 0);
      },
    );

    test(
      'a legacy UNSCOPED entry is not adopted by any account',
      () async {
        // Entries an older build left at `c2c_recv_opt_<peer>` must not read
        // back as a mute for whichever account happens to be active.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'c2c_recv_opt_$peer': 2,
        });
        store = await SharedPreferences.getInstance();
        await Prefs.initialize(store);
        await Prefs.setCurrentAccountToxId(toxIdA);

        expect(
          await Prefs.getC2CReceiveMessageOpt(peer),
          0,
          reason:
              'the implicit scope is account A, and A has no entry — the '
              'global slot stays orphaned rather than becoming everyone\'s mute',
        );
        expect(
          store.getInt('c2c_recv_opt_$peer'),
          2,
          reason:
              'the READ path must not delete it either — collecting the orphan '
              'is the job of the one-shot PrefsUpgrader v2→v3 sweep (covered in '
              'test/prefs_migration_registry_test.dart), which runs once at '
              'startup with the full account registry in hand. A read-path '
              'side effect would fire per lookup and could not tell an orphan '
              'from another account\'s key',
        );
      },
    );

    test(
      'an explicit empty userToxId also falls back to the active account',
      () async {
        // `ffiService.selfId` is the empty string before login; treating '' as
        // "unscoped" would reopen the same hole as null.
        await Prefs.setCurrentAccountToxId(toxIdA);
        await Prefs.setC2CReceiveMessageOpt(peer, 2, '');

        expect(keysStartingWith('c2c_recv_opt_'), <String>{
          'c2c_recv_opt_${peer}_$prefixA',
        });
      },
    );

    test('a toxId shorter than 16 chars is used verbatim as the prefix',
        () async {
      // `scopedPrefsAccountPrefix` only truncates when length >= 16. Short ids (16-char
      // profile prefixes, test fixtures) therefore scope on the whole string.
      await Prefs.setC2CReceiveMessageOpt(peer, 2, 'short-id');

      expect(keysStartingWith('c2c_recv_opt_'), <String>{
        'c2c_recv_opt_${peer}_short-id',
      });
      expect(await Prefs.getC2CReceiveMessageOpt(peer, 'short-id'), 2);
    });

    test(
      'the Prefs key stays id-representation sensitive (76-char write != '
      '64-char read)',
      () async {
        // This is the LAYERING contract, not a bug report. `Prefs` is the raw
        // slot: it embeds whatever id it is handed, byte-for-byte with
        // `SharedPreferencesAdapter` (they share `c2cRecvOptPrefsKey`).
        // Callers that need 76-vs-64 to agree go through `C2CRecvOptCache`,
        // which normalises before it gets here (see the 'id normalisation'
        // group below). Adding truncation to the shared builder would ALSO
        // truncate `groupRecvOptPrefsKey`, whose id is not a Tox public key,
        // and would strand every entry an older build wrote under a longer id.
        final String peer76 = '$peer${'0' * 12}';
        expect(peer76.length, 76); // guard the fixture itself

        await Prefs.setC2CReceiveMessageOpt(peer76, 2, toxIdA);

        expect(
          await Prefs.getC2CReceiveMessageOpt(peer, toxIdA),
          0,
          reason:
              'no normalisation happens in Prefs — if you add some, update this '
              'test AND re-check every hydrate/persist call site pairs up',
        );
        expect(await Prefs.getC2CReceiveMessageOpt(peer76, toxIdA), 2);
      },
    );
  });

  group('key parity with SharedPreferencesAdapter', () {
    test('C2C: what Prefs writes, the adapter reads (and vice versa)',
        () async {
      final adapter = SharedPreferencesAdapter(store);

      await Prefs.setC2CReceiveMessageOpt(peer, 2, toxIdA);
      expect(
        await adapter.getC2CReceiveMessageOpt(peer, toxIdA),
        2,
        reason:
            'the adapter is the PLATFORM write path and Prefs is a read path; '
            'they must address the same SharedPreferences entry',
      );

      await Prefs.setC2CReceiveMessageOpt(peer, 0, toxIdA);
      await adapter.setC2CReceiveMessageOpt(peer2, 2, toxIdA);
      expect(await Prefs.getC2CReceiveMessageOpt(peer2, toxIdA), 2);
      expect(
        keysStartingWith('c2c_recv_opt_'),
        <String>{'c2c_recv_opt_${peer2}_$prefixA'},
        reason: 'both implementations must produce the identical key string',
      );
    });

    test('group: what Prefs writes, the adapter reads (and vice versa)',
        () async {
      final adapter = SharedPreferencesAdapter(store);

      await Prefs.setGroupReceiveMessageOpt(groupId, 2, toxIdA);
      expect(await adapter.getGroupReceiveMessageOpt(groupId, toxIdA), 2);

      await Prefs.setGroupReceiveMessageOpt(groupId, 0, toxIdA);
      await adapter.setGroupReceiveMessageOpt(groupId2, 2, toxIdA);
      expect(await Prefs.getGroupReceiveMessageOpt(groupId2, toxIdA), 2);
      expect(
        keysStartingWith('group_recv_opt_'),
        <String>{'group_recv_opt_${groupId2}_$prefixA'},
      );
    });

    test('the adapter agrees with Prefs that 0 deletes the entry', () async {
      final adapter = SharedPreferencesAdapter(store);

      await adapter.setC2CReceiveMessageOpt(peer, 2, toxIdA);
      await adapter.setC2CReceiveMessageOpt(peer, 0, toxIdA);

      expect(keysStartingWith('c2c_recv_opt_'), isEmpty);
      expect(await Prefs.getC2CReceiveMessageOpt(peer, toxIdA), 0);
    });

    test('a full 76-char toxId is truncated to the same 16-char scope', () async {
      // Both sides must apply the SAME truncation, otherwise the platform
      // (which passes the full `ffiService.selfId`) and the UI would key on
      // different suffixes.
      final adapter = SharedPreferencesAdapter(store);

      await adapter.setC2CReceiveMessageOpt(peer, 2, toxIdA);

      expect(keysStartingWith('c2c_recv_opt_'), <String>{
        'c2c_recv_opt_${peer}_$prefixA',
      });
    });
  });

  group('adapter scope ladder (the tim2tox-injected write path)', () {
    // The adapter is toxee's `ExtendedPreferencesService`. tim2tox calls it
    // with `ffiService.selfId`, which is the EMPTY STRING before login —
    // `tim2tox_sdk_platform_converters._mapConv` and
    // `Tim2ToxSdkPlatform.getGroupsInfo` both pass it straight through. It
    // therefore needs the same "explicit id -> active account -> refuse"
    // ladder `Prefs` has, with `_accountPrefix` standing in for "active
    // account" (an injected service has no other handle on it).

    test('no accountPrefix and no userToxId: reads 0, writes nothing',
        () async {
      final adapter = SharedPreferencesAdapter(store);

      await adapter.setC2CReceiveMessageOpt(peer, 2);
      await adapter.setGroupReceiveMessageOpt(groupId, 2);

      expect(
        keysStartingWith('c2c_recv_opt_'),
        isEmpty,
        reason:
            'the unscoped `c2c_recv_opt_<peer>` key is visible to every local '
            'account and no teardown path (clearScopedKeysForAccount, '
            'clearAccountData, adapter.clear) can ever collect it',
      );
      expect(keysStartingWith('group_recv_opt_'), isEmpty);
      expect(await adapter.getC2CReceiveMessageOpt(peer), 0);
      expect(await adapter.getGroupReceiveMessageOpt(groupId), 0);
    });

    test('an EMPTY userToxId is treated as "no scope", not as "unscoped"',
        () async {
      // This is the exact value tim2tox passes before login.
      final adapter = SharedPreferencesAdapter(store);

      await adapter.setC2CReceiveMessageOpt(peer, 2, '');
      await adapter.setGroupReceiveMessageOpt(groupId, 2, '');

      expect(keysStartingWith('c2c_recv_opt_'), isEmpty);
      expect(keysStartingWith('group_recv_opt_'), isEmpty);
      expect(await adapter.getC2CReceiveMessageOpt(peer, ''), 0);
    });

    test('a pre-existing unscoped entry is not read back by the adapter',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'c2c_recv_opt_$peer': 2,
        'group_recv_opt_$groupId': 2,
      });
      store = await SharedPreferences.getInstance();
      final adapter = SharedPreferencesAdapter(store);

      expect(
        await adapter.getC2CReceiveMessageOpt(peer),
        0,
        reason: 'an un-attributable entry must not become everyone\'s mute',
      );
      expect(await adapter.getGroupReceiveMessageOpt(groupId), 0);
    });

    test('an omitted userToxId falls back to the adapter accountPrefix',
        () async {
      final adapter = SharedPreferencesAdapter(store, accountPrefix: prefixA);

      await adapter.setC2CReceiveMessageOpt(peer, 2);
      await adapter.setGroupReceiveMessageOpt(groupId, 2);

      expect(keysStartingWith('c2c_recv_opt_'), <String>{
        'c2c_recv_opt_${peer}_$prefixA',
      });
      expect(keysStartingWith('group_recv_opt_'), <String>{
        'group_recv_opt_${groupId}_$prefixA',
      });
      expect(await adapter.getC2CReceiveMessageOpt(peer), 2);
      expect(await adapter.getGroupReceiveMessageOpt(groupId), 2);
    });

    test(
      'the implicit-scope key is byte-identical across adapter and Prefs',
      () async {
        // The tripwire that matters most: adapter scopes via _accountPrefix,
        // Prefs via current_account_tox_id. Different inputs, one key.
        final adapter = SharedPreferencesAdapter(store, accountPrefix: prefixA);
        await Prefs.setCurrentAccountToxId(toxIdA);

        await adapter.setC2CReceiveMessageOpt(peer, 2);
        expect(await Prefs.getC2CReceiveMessageOpt(peer), 2);

        await adapter.setGroupReceiveMessageOpt(groupId, 2);
        expect(await Prefs.getGroupReceiveMessageOpt(groupId), 2);

        await Prefs.setC2CReceiveMessageOpt(peer2, 1);
        expect(await adapter.getC2CReceiveMessageOpt(peer2), 1);

        expect(keysStartingWith('c2c_recv_opt_'), <String>{
          'c2c_recv_opt_${peer}_$prefixA',
          'c2c_recv_opt_${peer2}_$prefixA',
        });
      },
    );

    test('an explicit userToxId overrides the adapter accountPrefix', () async {
      // The explicit argument wins — otherwise a multi-account tool driving
      // the adapter for account B would write into account A's slot.
      final adapter = SharedPreferencesAdapter(store, accountPrefix: prefixA);

      await adapter.setC2CReceiveMessageOpt(peer, 2, toxIdB);

      expect(keysStartingWith('c2c_recv_opt_'), <String>{
        'c2c_recv_opt_${peer}_$prefixB',
      });
      expect(await adapter.getC2CReceiveMessageOpt(peer), 0);
      expect(await adapter.getC2CReceiveMessageOpt(peer, toxIdB), 2);
    });

    test('setAccountPrefix retroactively supplies the scope', () async {
      // The legacy login path constructs the adapter before `login()` resolves
      // selfId, then injects the prefix. Writes before that point are dropped
      // (there is no honest key); writes after it are scoped.
      final adapter = SharedPreferencesAdapter(store);

      await adapter.setC2CReceiveMessageOpt(peer, 2);
      expect(keysStartingWith('c2c_recv_opt_'), isEmpty);

      adapter.setAccountPrefix(prefixA);
      await adapter.setC2CReceiveMessageOpt(peer, 2);

      expect(keysStartingWith('c2c_recv_opt_'), <String>{
        'c2c_recv_opt_${peer}_$prefixA',
      });
    });
  });

  group('account teardown', () {
    test(
      'clearScopedKeysForAccount drops only the deleted account recvOpt state',
      () async {
        await Prefs.setC2CReceiveMessageOpt(peer, 2, toxIdA);
        await Prefs.setGroupReceiveMessageOpt(groupId, 2, toxIdA);
        await Prefs.setC2CReceiveMessageOpt(peer2, 2, toxIdB);
        await Prefs.setGroupReceiveMessageOpt(groupId2, 2, toxIdB);

        await Prefs.clearScopedKeysForAccount(toxIdA);

        expect(
          keysStartingWith('c2c_recv_opt_'),
          <String>{'c2c_recv_opt_${peer2}_$prefixB'},
        );
        expect(
          keysStartingWith('group_recv_opt_'),
          <String>{'group_recv_opt_${groupId2}_$prefixB'},
        );
        expect(await Prefs.getC2CReceiveMessageOpt(peer, toxIdA), 0);
        expect(await Prefs.getGroupReceiveMessageOpt(groupId, toxIdA), 0);
        expect(
          await Prefs.getC2CReceiveMessageOpt(peer2, toxIdB),
          2,
          reason: "deleting account A must not disturb account B's mutes",
        );
      },
    );
  });

  group('consumer projection — C2CRecvOptCache reads what Prefs persisted', () {
    test(
      'a persisted mute hydrates into the cache as isMuted == true',
      () async {
        // This is the exact boolean `NotificationMessageListener._shouldSuppress`
        // branches on, so it is the shortest honest statement of "muted last
        // session => no banner this session".
        await Prefs.setC2CReceiveMessageOpt(peer, 2, toxIdA);

        expect(
          C2CRecvOptCache.isMuted(peer),
          isFalse,
          reason: 'nothing hydrated yet — the cache starts empty',
        );

        final hydrated = await C2CRecvOptCache.hydrateFromPrefs(peer, toxIdA);

        expect(hydrated, 2);
        expect(C2CRecvOptCache.optFor(peer), 2);
        expect(
          C2CRecvOptCache.isMuted(peer),
          isTrue,
          reason:
              'the persisted mute must survive a restart and reach the '
              'notification suppression check',
        );
      },
    );

    test('no persisted entry hydrates as un-muted', () async {
      final hydrated = await C2CRecvOptCache.hydrateFromPrefs(peer, toxIdA);

      expect(hydrated, 0);
      expect(C2CRecvOptCache.isMuted(peer), isFalse);
      expect(
        C2CRecvOptCache.contains(peer),
        isTrue,
        reason:
            'hydration records the 0 so the lazy re-hydration paths stop '
            'treating this peer as a cache miss',
      );
    });

    test("account A's mute does not hydrate into account B's session",
        () async {
      await Prefs.setC2CReceiveMessageOpt(peer, 2, toxIdA);

      final hydratedForB = await C2CRecvOptCache.hydrateFromPrefs(peer, toxIdB);

      expect(hydratedForB, 0);
      expect(
        C2CRecvOptCache.isMuted(peer),
        isFalse,
        reason:
            'after switching accounts the peer must be audible again for the '
            'account that never muted them',
      );
    });
  });

  group('id normalisation — the durable key C2CRecvOptCache addresses', () {
    // `peer` is the 64-char public key; `peer76` the full Tox address that
    // carries the extra nospam + checksum. Both denote the same contact.
    final String peer76 = '$peer${'0' * 12}';

    test('fixtures denote the same peer in two widths', () {
      expect(peer.length, 64);
      expect(peer76.length, 76);
      expect(peer76.startsWith(peer), isTrue);
    });

    test(
      'setAndPersist truncates to the 64-char key the platform read path uses',
      () async {
        // `tim2tox_sdk_platform_converters` reads
        // `conversationID.replaceFirst('c2c_', '')`, i.e. the platform's own
        // 64-char truncation. Persisting under the 76-char address would put
        // the mute somewhere that reader can never see.
        await C2CRecvOptCache.setAndPersist(peer76, 2, toxIdA);

        expect(keysStartingWith('c2c_recv_opt_'), <String>{
          'c2c_recv_opt_${peer}_$prefixA',
        });
        expect(await Prefs.getC2CReceiveMessageOpt(peer, toxIdA), 2);
      },
    );

    test('a 76-char persist survives a restart read with the 64-char id',
        () async {
      await C2CRecvOptCache.setAndPersist(peer76, 2, toxIdA);
      C2CRecvOptCache.debugClear(); // simulate the next process launch

      expect(await C2CRecvOptCache.hydrateFromPrefs(peer, toxIdA), 2);
      expect(C2CRecvOptCache.isMuted(peer), isTrue);
    });

    test('the durable key keeps the id CASE (it is not lower-cased)', () async {
      // Deliberate: `SharedPreferencesAdapter` and the tim2tox converters build
      // the same key from the raw id, so lower-casing only here would address a
      // different SharedPreferences entry than the platform write path does.
      // The in-memory projection still normalises case, so `optFor` agrees.
      final String peerUpper = peer.toUpperCase();

      await C2CRecvOptCache.setAndPersist(peerUpper, 2, toxIdA);

      expect(keysStartingWith('c2c_recv_opt_'), <String>{
        'c2c_recv_opt_${peerUpper}_$prefixA',
      });
      expect(
        C2CRecvOptCache.optFor(peer),
        2,
        reason: 'the runtime projection is case-insensitive even though the '
            'durable key is not',
      );
    });

    test(
      'a legacy entry parked under the 76-char key is adopted AND migrated',
      () async {
        // What a pre-normalisation build left behind. Hydration must find it
        // once, then move it onto the canonical key so the platform reader and
        // any later un-mute both address the same entry.
        await Prefs.setC2CReceiveMessageOpt(peer76, 2, toxIdA);

        final hydrated = await C2CRecvOptCache.hydrateFromPrefs(peer76, toxIdA);

        expect(hydrated, 2);
        expect(C2CRecvOptCache.isMuted(peer), isTrue);
        expect(
          keysStartingWith('c2c_recv_opt_'),
          <String>{'c2c_recv_opt_${peer}_$prefixA'},
          reason:
              'the long key must be gone, not merely shadowed — two entries '
              'for one peer is how an un-mute gets resurrected',
        );
      },
    );

    test('un-muting through a 76-char id clears both representations',
        () async {
      await Prefs.setC2CReceiveMessageOpt(peer76, 2, toxIdA); // legacy leftover
      await Prefs.setC2CReceiveMessageOpt(peer, 2, toxIdA); // canonical

      await C2CRecvOptCache.setAndPersist(peer76, 0, toxIdA);

      expect(
        keysStartingWith('c2c_recv_opt_'),
        isEmpty,
        reason:
            'a leftover long-key entry would re-mute the peer on the next '
            'hydration',
      );
      expect(C2CRecvOptCache.isMuted(peer), isFalse);
    });
  });

  group('C2CRecvOptCache.debugClear', () {
    test(
      'resets the native re-push backlog, not just the projection',
      () async {
        await Prefs.setC2CReceiveMessageOpt(peer, 2, toxIdA);
        await C2CRecvOptCache.hydrateFromPrefs(peer, toxIdA);
        // The re-push is fired unawaited; let it settle. With the SDK
        // uninitialised, TIMMessageManager.setC2CReceiveMessageOpt returns
        // ERR_SDK_NOT_INITIALIZED synchronously-ish, so the peer lands in the
        // backlog deterministically.
        await pumpEventQueue();

        expect(
          C2CRecvOptCache.needsHydration(peer),
          isTrue,
          reason:
              'the projection has an entry, so this can only be true because '
              'the failed native re-push parked the peer in _repushPending',
        );

        C2CRecvOptCache.debugClear();
        // Repopulate the projection ONLY — setLocal never touches the backlog,
        // so anything left in it still shows up through needsHydration.
        C2CRecvOptCache.setLocal(peer, 0);

        expect(
          C2CRecvOptCache.needsHydration(peer),
          isFalse,
          reason:
              'debugClear must clear _repushPending too; otherwise the backlog '
              'leaks into every later test in the process',
        );
      },
    );
  });
}
