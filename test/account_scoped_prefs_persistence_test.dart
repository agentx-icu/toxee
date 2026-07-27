// L1 — locks ROUND-TRIP + per-account scoping for the remaining persisted
// per-account / per-friend state that `account_toggle_persistence_test.dart`
// does NOT cover. That sibling file owns the boolean toggles (autoLogin /
// autoAcceptFriends / autoAcceptGroupInvites / notificationSound) and the
// `<const>_<first16>` scoped-key form; this file covers the *content*-shaped
// state:
//
//   * Friend remark / alias        (S30)  — getFriendRemark/setFriendRemark
//   * Blocklist                    (S29)  — getBlackList/set/add/removeFromBlackList
//   * Local friends list                  — getLocalFriends/setLocalFriends
//   * Pinned conversations                — getPinned/setPinned
//   * Groups list + quit groups           — getGroups/setGroups, add/removeQuitGroup
//   * Per-peer draft messages             — getDraft/setDraft
//
// Two distinct scoping shapes are exercised on purpose:
//   * Friend-remark / pinned / groups / local-friends scope on the
//     CURRENT account's 16-char prefix via `_scopedKey` (key = `<base>_<first16>`).
//     There is no toxId argument; the active account is read from
//     getCurrentAccountToxId(), so we control scope with setCurrentAccountToxId.
//   * Blocklist scopes on the FULL toxId passed explicitly
//     (key = `black_list_<userToxId>`, falling back to `black_list_default`
//     when omitted) — a different code path worth its own isolation check.
//
// Pure Prefs: no FfiChatService, no FFI, no skip-guard. Prefs.initialize only
// needs a SharedPreferences instance, so no path_provider mock is required.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Two toxIds whose first 16 chars DIFFER, so current-account-scoped state
  // must land on independent keys.
  const toxIdA =
      'AAAAAAAAAAAAAAAA111111111111111111111111111111111111111111111111111111111111';
  const toxIdB =
      'BBBBBBBBBBBBBBBB222222222222222222222222222222222222222222222222222222222222';

  const friend1 = 'FRIEND00000000000000000000000000000000000000000000000000000001';
  const friend2 = 'FRIEND00000000000000000000000000000000000000000000000000000002';

  Future<void> resetPrefs() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.initialize(await SharedPreferences.getInstance());
    // Start each test with no implicit current account so that scope is only
    // whatever the test sets explicitly.
    await Prefs.setCurrentAccountToxId(null);
  }

  setUp(resetPrefs);

  group('friend remark per-account round-trip (S30)', () {
    test('unset returns null', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      expect(await Prefs.getFriendRemark(friend1), isNull,
          reason: 'a friend with no remark set must read back as null');
    });

    test('set then read returns the same remark', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setFriendRemark(friend1, 'Alice (work)');
      expect(await Prefs.getFriendRemark(friend1), equals('Alice (work)'),
          reason: 'remark must round-trip for the same friend under the same account');
    });

    test('empty remark removes the stored value (back to null)', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setFriendRemark(friend1, 'temp');
      await Prefs.setFriendRemark(friend1, '');
      expect(await Prefs.getFriendRemark(friend1), isNull,
          reason: 'setting an empty remark must clear it, not store ""');
    });

    test('remark is isolated per friend', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setFriendRemark(friend1, 'one');
      await Prefs.setFriendRemark(friend2, 'two');
      expect(await Prefs.getFriendRemark(friend1), equals('one'),
          reason: 'friend1 remark is independent of friend2');
      expect(await Prefs.getFriendRemark(friend2), equals('two'),
          reason: 'friend2 remark is independent of friend1');
    });

    test('remark is isolated per account (different first-16 prefixes)', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setFriendRemark(friend1, 'remark-from-A');

      await Prefs.setCurrentAccountToxId(toxIdB);
      expect(await Prefs.getFriendRemark(friend1), isNull,
          reason: 'account B must not see the remark account A set for the same friend');

      await Prefs.setFriendRemark(friend1, 'remark-from-B');
      await Prefs.setCurrentAccountToxId(toxIdA);
      expect(await Prefs.getFriendRemark(friend1), equals('remark-from-A'),
          reason: 'switching back to account A still reads A\'s remark, not B\'s');
    });

    test('persists under the scoped key form friend_remark_<friend>_<first16>',
        () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setFriendRemark(friend1, 'scoped-check');

      final raw = await SharedPreferences.getInstance();
      // LITERAL key assertion (not via scopedPrefsKey, which is the SAME helper
      // Prefs._scopedKey delegates to — a regression there must not pass here).
      // friend1 + first-16 of toxIdA ('AAAAAAAAAAAAAAAA').
      const expectedKey =
          'friend_remark_FRIEND00000000000000000000000000000000000000000000000000000001_AAAAAAAAAAAAAAAA';
      expect(raw.getString(expectedKey), equals('scoped-check'),
          reason: 'remark must persist under <friend_remark_id>_<first-16-of-toxId>');
    });
  });

  group('blocklist round-trip (S29) — scoped on full toxId', () {
    test('unset returns empty set', () async {
      expect(await Prefs.getBlackList(toxIdA), isEmpty,
          reason: 'a never-populated blocklist must read back as an empty set');
    });

    test('setBlackList round-trips the whole set', () async {
      await Prefs.setBlackList({friend1, friend2}, toxIdA);
      expect(await Prefs.getBlackList(toxIdA), equals({friend1, friend2}),
          reason: 'the exact set written must round-trip for the same owner toxId');
    });

    test('addToBlackList appends; removeFromBlackList removes', () async {
      await Prefs.addToBlackList([friend1], toxIdA);
      expect(await Prefs.getBlackList(toxIdA), equals({friend1}),
          reason: 'addToBlackList on an empty list yields a one-element set');

      await Prefs.addToBlackList([friend2], toxIdA);
      expect(await Prefs.getBlackList(toxIdA), equals({friend1, friend2}),
          reason: 'addToBlackList must union, not replace');

      await Prefs.removeFromBlackList([friend1], toxIdA);
      expect(await Prefs.getBlackList(toxIdA), equals({friend2}),
          reason: 'removeFromBlackList must drop exactly the requested id');
    });

    test('blocklist is isolated per owner toxId', () async {
      await Prefs.setBlackList({friend1}, toxIdA);
      await Prefs.setBlackList({friend2}, toxIdB);
      expect(await Prefs.getBlackList(toxIdA), equals({friend1}),
          reason: 'owner A blocklist is independent of owner B');
      expect(await Prefs.getBlackList(toxIdB), equals({friend2}),
          reason: 'owner B blocklist is independent of owner A');
    });

    test('persists under the full-toxId key form black_list_<toxId>', () async {
      await Prefs.setBlackList({friend1}, toxIdA);
      final raw = await SharedPreferences.getInstance();
      expect(raw.getStringList('black_list_$toxIdA'), equals([friend1]),
          reason: 'blocklist scopes on the FULL toxId (black_list_<toxId>), '
              'not on the 16-char prefix used by other scoped state');
    });

    test('omitting toxId falls back to the black_list_default key', () async {
      // No userToxId arg: _blackListKey substitutes 'default', so storage
      // lands on the literal 'black_list_default' key.
      await Prefs.setBlackList({friend1, friend2});
      // (a) round-trip works with the same no-arg call.
      expect(await Prefs.getBlackList(), equals({friend1, friend2}),
          reason: 'the no-toxId blocklist must round-trip via the default key');

      // (b) raw on-disk key is literally 'black_list_default'.
      final raw = await SharedPreferences.getInstance();
      expect(raw.getStringList('black_list_default'), equals([friend1, friend2]),
          reason: 'omitting userToxId must persist under the literal '
              'black_list_default fallback key');
    });
  });

  group('local friends list round-trip', () {
    test('unset (no current account) returns empty set', () async {
      // No current account set in setUp; getLocalFriends short-circuits to {}.
      expect(await Prefs.getLocalFriends(), isEmpty,
          reason: 'with no active account, local friends must be empty');
    });

    test('set then read round-trips the set under the current account', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setLocalFriends({friend1, friend2});
      expect(await Prefs.getLocalFriends(), equals({friend1, friend2}),
          reason: 'the local friends set must round-trip for the active account');
    });

    test('add a friend then remove it via read-modify-write', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);

      final afterAdd = await Prefs.getLocalFriends()..add(friend1);
      await Prefs.setLocalFriends(afterAdd);
      expect(await Prefs.getLocalFriends(), equals({friend1}),
          reason: 'adding friend1 to the empty local list yields {friend1}');

      final afterRemove = await Prefs.getLocalFriends()..remove(friend1);
      await Prefs.setLocalFriends(afterRemove);
      expect(await Prefs.getLocalFriends(), isEmpty,
          reason: 'removing the only friend yields an empty local list');
    });

    test('isolated per account (different first-16 prefixes)', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setLocalFriends({friend1});

      await Prefs.setCurrentAccountToxId(toxIdB);
      expect(await Prefs.getLocalFriends(), isEmpty,
          reason: 'account B must not see account A\'s local friends');
      await Prefs.setLocalFriends({friend2});

      await Prefs.setCurrentAccountToxId(toxIdA);
      expect(await Prefs.getLocalFriends(), equals({friend1}),
          reason: 'switching back to A still reads A\'s local friends only');
    });
  });

  group('pinned conversations round-trip', () {
    test('unset (no current account) returns empty set', () async {
      expect(await Prefs.getPinned(), isEmpty,
          reason: 'with no active account, pinned set must be empty');
    });

    test('set then read round-trips under the current account', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setPinned({friend1, friend2});
      expect(await Prefs.getPinned(), equals({friend1, friend2}),
          reason: 'pinned set must round-trip for the active account');
    });

    test('pin then unpin via read-modify-write', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setPinned({friend1});
      expect(await Prefs.getPinned(), equals({friend1}),
          reason: 'pinning friend1 stores it');

      final unpinned = await Prefs.getPinned()..remove(friend1);
      await Prefs.setPinned(unpinned);
      expect(await Prefs.getPinned(), isEmpty,
          reason: 'unpinning the only pinned peer yields an empty set');
    });

    test('isolated per account (different first-16 prefixes)', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setPinned({friend1});

      await Prefs.setCurrentAccountToxId(toxIdB);
      expect(await Prefs.getPinned(), isEmpty,
          reason: 'account B must not inherit account A\'s pinned conversations');
    });
  });

  group('groups list round-trip', () {
    test('unset (no current account) returns empty set', () async {
      expect(await Prefs.getGroups(), isEmpty,
          reason: 'with no active account, groups set must be empty');
    });

    test('set then read round-trips under the current account', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setGroups({'g1', 'g2'});
      expect(await Prefs.getGroups(), equals({'g1', 'g2'}),
          reason: 'groups set must round-trip for the active account');
    });

    test('isolated per account (different first-16 prefixes)', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setGroups({'g1'});

      await Prefs.setCurrentAccountToxId(toxIdB);
      expect(await Prefs.getGroups(), isEmpty,
          reason: 'account B must not see account A\'s groups');
    });
  });

  group('quit-groups add/remove (RMW) round-trip', () {
    test('unset (no current account) returns empty set', () async {
      expect(await Prefs.getQuitGroups(), isEmpty,
          reason: 'with no active account, quit-groups set must be empty');
    });

    test('addQuitGroup then removeQuitGroup under the current account', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);

      await Prefs.addQuitGroup('g1');
      expect(await Prefs.getQuitGroups(), equals({'g1'}),
          reason: 'addQuitGroup must persist the group id');

      await Prefs.addQuitGroup('g2');
      expect(await Prefs.getQuitGroups(), equals({'g1', 'g2'}),
          reason: 'addQuitGroup must union, not replace');

      await Prefs.removeQuitGroup('g1');
      expect(await Prefs.getQuitGroups(), equals({'g2'}),
          reason: 'removeQuitGroup must drop exactly the requested group id');
    });

    test('concurrent addQuitGroup calls do not lose writes (RMW serialization)',
        () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      // Fire several adds without awaiting between them; the internal RMW tail
      // must serialize them so no read-modify-write snapshot clobbers another.
      await Future.wait([
        Prefs.addQuitGroup('g1'),
        Prefs.addQuitGroup('g2'),
        Prefs.addQuitGroup('g3'),
      ]);
      expect(await Prefs.getQuitGroups(), equals({'g1', 'g2', 'g3'}),
          reason: 'all concurrent quit-group adds must survive the RMW serialization');
    });

    test('isolated per account (different first-16 prefixes)', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.addQuitGroup('g1');

      await Prefs.setCurrentAccountToxId(toxIdB);
      expect(await Prefs.getQuitGroups(), isEmpty,
          reason: 'account B must not see account A\'s quit groups');
    });
  });

  group('per-peer draft messages round-trip', () {
    test('unset returns null', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      expect(await Prefs.getDraft(friend1), isNull,
          reason: 'a peer with no draft must read back null');
    });

    test('set then read returns the same draft text', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setDraft(friend1, 'half-typed message');
      expect(await Prefs.getDraft(friend1), equals('half-typed message'),
          reason: 'draft text must round-trip for the same peer');
    });

    test('empty draft clears the stored value (back to null)', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setDraft(friend1, 'something');
      await Prefs.setDraft(friend1, '');
      expect(await Prefs.getDraft(friend1), isNull,
          reason: 'setting an empty draft must clear it, not store ""');
    });

    test('draft is isolated per peer', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setDraft(friend1, 'to friend1');
      await Prefs.setDraft(friend2, 'to friend2');
      expect(await Prefs.getDraft(friend1), equals('to friend1'),
          reason: 'friend1 draft is independent of friend2');
      expect(await Prefs.getDraft(friend2), equals('to friend2'),
          reason: 'friend2 draft is independent of friend1');
    });

    test('draft is isolated per account (different first-16 prefixes)', () async {
      await Prefs.setCurrentAccountToxId(toxIdA);
      await Prefs.setDraft(friend1, 'draft-from-A');

      await Prefs.setCurrentAccountToxId(toxIdB);
      expect(await Prefs.getDraft(friend1), isNull,
          reason: 'account B must not see account A\'s draft for the same peer');
    });
  });
}
