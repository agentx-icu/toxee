// X5 (local-storage review 2026-05-18): single conversation-list builder.
//
// `FakeConversationManager.getConversationList()` and
// `FakeIM._refreshConversationsWithFriends()` used to construct the
// conversation list independently, with subtly different normalization /
// pinned check / group filter logic. Drift between them caused real bugs
// (A6: pinned flag dropped on bus emit). This test exercises the shared
// builder directly with synthetic inputs to lock the contract.
//
// The builder is pure (only reads through `Prefs.*`), so this test can run
// without the tim2tox FFI library — unlike the manager-level tests it
// neighbours.

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

void main() {
  group('buildConversationsFromFriends (X5)', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      // Scoped Prefs reads (avatar, nickname, activity) require a current
      // account so they don't fall through to the global namespace.
      await Prefs.setCurrentAccountToxId(
          'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899');
    });

    tearDown(() async {
      await env.dispose();
    });

    // Helper: builds a friend record matching ConvBuilderFriend's shape.
    ConvBuilderFriend friend(String id, String nick, {bool online = false}) =>
        (userId: id, nickName: nick, online: online);

    // Helper: unread always returns zero so we don't have to wire a fake ffi.
    int zeroUnread(String _) => 0;

    test('pinned friend is reported as isPinned across both call paths',
        () async {
      const alice =
          'FFEEDDCCBBAA99887766554433221100FFEEDDCCBBAA99887766554433221100';
      const bob =
          '1122334455667788AABBCCDDEEFF00001122334455667788AABBCCDDEEFF0000';

      // Build with the bus-emit path's flags (Tox-authoritative, groupType on).
      final emitList = await buildConversationsFromFriends(
        friends: [friend(alice, 'Alice'), friend(bob, 'Bob')],
        groupIds: const <String>{},
        pinned: {alice},
        quitGroups: const <String>{},
        pendingFriendIds: const <String>{},
        sortingMode: 'name',
        getUnreadOf: zeroUnread,
        mergeLocalFriendsAsOffline: false,
        emitGroupType: true,
      );
      final emitAlice = emitList.firstWhere((c) => c.conversationID == 'c2c_$alice');
      expect(emitAlice.isPinned, isTrue,
          reason: 'pinned flag must survive the bus-emit builder path');
      expect(
          emitList.firstWhere((c) => c.conversationID == 'c2c_$bob').isPinned,
          isFalse);

      // Build with the sync getConversationList()'s flags (local merge, no groupType).
      final syncList = await buildConversationsFromFriends(
        friends: [friend(alice, 'Alice'), friend(bob, 'Bob')],
        groupIds: const <String>{},
        pinned: {alice},
        quitGroups: const <String>{},
        pendingFriendIds: const <String>{},
        sortingMode: 'name',
        getUnreadOf: zeroUnread,
        mergeLocalFriendsAsOffline: true,
        emitGroupType: false,
      );
      final syncAlice = syncList.firstWhere((c) => c.conversationID == 'c2c_$alice');
      expect(syncAlice.isPinned, isTrue,
          reason: 'pinned flag must also survive the sync builder path');
    });

    test('pinned group matches the "group_<normalizedGid>" key shape',
        () async {
      const gid = 'tox_42';
      final list = await buildConversationsFromFriends(
        friends: const <ConvBuilderFriend>[],
        groupIds: const ['tox_42', 'tox_conf_77'],
        pinned: {'group_$gid'},
        quitGroups: const <String>{},
        pendingFriendIds: const <String>{},
        sortingMode: 'name',
        getUnreadOf: zeroUnread,
        emitGroupType: true,
      );
      expect(list, hasLength(2));
      final pinned = list.firstWhere((c) => c.conversationID == 'group_$gid');
      expect(pinned.isPinned, isTrue);
      expect(pinned.groupType, 'group');
      final conf = list.firstWhere((c) => c.conversationID == 'group_tox_conf_77');
      expect(conf.groupType, 'conference',
          reason: 'tox_conf_* groups are conferences');
    });

    test('quit groups are filtered out', () async {
      final list = await buildConversationsFromFriends(
        friends: const <ConvBuilderFriend>[],
        groupIds: const ['tox_1', 'tox_2', 'tox_3'],
        pinned: const <String>{},
        quitGroups: const {'tox_2'},
        pendingFriendIds: const <String>{},
        sortingMode: 'name',
        getUnreadOf: zeroUnread,
      );
      expect(list.map((c) => c.conversationID),
          unorderedEquals(['group_tox_1', 'group_tox_3']));
    });

    test(
        'pending-but-not-accepted friend is suppressed; accepted-pending is emitted',
        () async {
      const sentNotAccepted =
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      const sentAndAccepted =
          'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
      final list = await buildConversationsFromFriends(
        // Tox has confirmed `sentAndAccepted` only.
        friends: [friend(sentAndAccepted, 'Bob')],
        groupIds: const <String>{},
        pinned: const <String>{},
        quitGroups: const <String>{},
        pendingFriendIds: {sentNotAccepted, sentAndAccepted},
        sortingMode: 'name',
        getUnreadOf: zeroUnread,
      );
      expect(list.map((c) => c.conversationID),
          equals(['c2c_$sentAndAccepted']));
    });

    test(
        'mergeLocalFriendsAsOffline pulls in cached friends absent from the Tox list',
        () async {
      const tox =
          '1111111111111111111111111111111111111111111111111111111111111111';
      const cached =
          '2222222222222222222222222222222222222222222222222222222222222222';
      await Prefs.setLocalFriends({cached});
      await Prefs.setFriendNickname(cached, 'CachedFriend');

      final list = await buildConversationsFromFriends(
        friends: [friend(tox, 'Tox')],
        groupIds: const <String>{},
        pinned: const <String>{},
        quitGroups: const <String>{},
        pendingFriendIds: const <String>{},
        sortingMode: 'name',
        getUnreadOf: zeroUnread,
        mergeLocalFriendsAsOffline: true,
      );
      final ids = list.map((c) => c.conversationID).toSet();
      expect(ids, containsAll(['c2c_$tox', 'c2c_$cached']));
      final cachedConv = list.firstWhere((c) => c.conversationID == 'c2c_$cached');
      expect(cachedConv.title, 'CachedFriend',
          reason: 'offline-merged friend uses cached nickname for title');
    });

    test(
        'mergeLocalFriendsAsOffline=false ignores cached friends (Tox-authoritative)',
        () async {
      const tox =
          '3333333333333333333333333333333333333333333333333333333333333333';
      const cached =
          '4444444444444444444444444444444444444444444444444444444444444444';
      await Prefs.setLocalFriends({cached});
      await Prefs.setFriendNickname(cached, 'Stale');

      final list = await buildConversationsFromFriends(
        friends: [friend(tox, 'Tox')],
        groupIds: const <String>{},
        pinned: const <String>{},
        quitGroups: const <String>{},
        pendingFriendIds: const <String>{},
        sortingMode: 'name',
        getUnreadOf: zeroUnread,
        mergeLocalFriendsAsOffline: false,
      );
      final ids = list.map((c) => c.conversationID).toSet();
      expect(ids, equals({'c2c_$tox'}),
          reason:
              'steady-state poll path must not pull in stale local-cache friends');
    });

    test('sort puts pinned first, then C2C by activity desc', () async {
      const a =
          '5555555555555555555555555555555555555555555555555555555555555555';
      const b =
          '6666666666666666666666666666666666666666666666666666666666666666';
      const c =
          '7777777777777777777777777777777777777777777777777777777777777777';
      // a has the most recent activity, b is older, c is older still.
      await Prefs.setFriendActivity(
          a, DateTime.fromMillisecondsSinceEpoch(3000));
      await Prefs.setFriendActivity(
          b, DateTime.fromMillisecondsSinceEpoch(2000));
      await Prefs.setFriendActivity(
          c, DateTime.fromMillisecondsSinceEpoch(1000));

      final list = await buildConversationsFromFriends(
        friends: [friend(a, 'A'), friend(b, 'B'), friend(c, 'C')],
        groupIds: const <String>{},
        pinned: {b}, // pin B
        quitGroups: const <String>{},
        pendingFriendIds: const <String>{},
        sortingMode: 'activity',
        getUnreadOf: zeroUnread,
      );
      // B pinned → first. Then A (newer activity) before C.
      expect(list.map((c) => c.conversationID).toList(),
          equals(['c2c_$b', 'c2c_$a', 'c2c_$c']));
    });

    test('normalizes 76-char Tox addresses to the 64-char pubkey', () async {
      const pubkey =
          '8888888888888888888888888888888888888888888888888888888888888888';
      const fullAddr = '${pubkey}AABBCCDD1234'; // 64 + 12 = 76 chars (pubkey + nospam + checksum stand-in)
      expect(fullAddr.length, 76);

      // The friend record carries the 76-char form, but the pinned set was
      // stored as the 64-char pubkey (matches FakeConversationManager.setPinned).
      final list = await buildConversationsFromFriends(
        friends: [friend(fullAddr, 'AddrFriend')],
        groupIds: const <String>{},
        pinned: {pubkey},
        quitGroups: const <String>{},
        pendingFriendIds: const <String>{},
        sortingMode: 'name',
        getUnreadOf: zeroUnread,
      );
      expect(list, hasLength(1));
      expect(list.first.isPinned, isTrue,
          reason:
              'pinned check must normalize the friend ID so 76-char addresses match the 64-char pubkey stored in Prefs.getPinned()');
    });
  });
}
