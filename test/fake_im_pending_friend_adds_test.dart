// X9 (local-storage review 2026-05-18): pending-friend-adds buffer in FakeIM.
//
// `Prefs.localFriends` plays two conflicting roles — cold-start cache and
// authoritative mirror overwritten every 5s by Tox polling. Without a
// dedicated buffer, an accept that lands between two poll cycles is wiped
// when Tox hasn't propagated yet. We added `_pendingFriendAdds` with TTL.
//
// This test exercises the public surface:
//   1. `registerPendingFriendAdd` records the entry.
//   2. After a Tox poll that includes the friend, the entry is dropped.
//   3. After a Tox poll that does NOT include the friend, the entry is
//      preserved AND `Prefs.localFriends` is NOT wiped of that friend.
//   4. Expired entries are evicted on the next access.
//
// Uses a `_RecordingFfiChatService` subclass to control `getFriendList()` /
// `getFriendApplications()`. Skips when the tim2tox FFI library isn't
// loadable (no dylib in this environment).

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

/// Subclass that lets the test choose what Tox "returns" on a poll without
/// running real FFI. The base ctor still touches FFI (Tim2ToxFfi.open in
/// some envs) so we gate on `_ffiAvailable` like the neighbouring tests.
class _RecordingFfiChatService extends FfiChatService {
  _RecordingFfiChatService() : super();

  List<({String userId, String nickName, String status, bool online})>
      friendsToReturn = const [];
  List<({String userId, String wording})> appsToReturn = const [];

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
      getFriendList() async {
    return friendsToReturn;
  }

  @override
  Future<List<({String userId, String wording})>> getFriendApplications() async {
    return appsToReturn;
  }

  @override
  int getUnreadOf(String peerId) => 0;
}

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('FakeIM pending friend adds (X9)', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      await Prefs.setCurrentAccountToxId(
          '00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF');
    });

    tearDown(() async {
      await env.dispose();
    });

    test('register → Tox poll confirms → pending entry removed',
        () async {
      const friendId =
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

      final ffi = _RecordingFfiChatService();
      final bus = FakeEventBus();
      final im = FakeIM(ffi, bus);

      // Simulate the app-side accept by calling the public hook.
      im.registerPendingFriendAdd(friendId);
      expect(im.debugPendingFriendAdds.keys, contains(friendId),
          reason: 'register must record the friend ID');

      // Now Tox finally confirms — the next poll includes the friend.
      ffi.friendsToReturn = [
        (userId: friendId, nickName: 'Alice', status: '', online: true),
      ];
      await im.refreshContacts();

      expect(im.debugPendingFriendAdds.keys, isNot(contains(friendId)),
          reason:
              'Tox confirmation must drop the entry from the pending buffer');

      // localFriends should reflect the confirmed friend.
      final stored = await Prefs.getLocalFriends();
      expect(stored, contains(friendId));

      im.dispose();
      bus.dispose();
    }, skip: skipReason);

    test(
        'register → Tox poll does NOT include the friend → pending preserved and merged into localFriends',
        () async {
      const friendId =
          'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

      final ffi = _RecordingFfiChatService();
      final bus = FakeEventBus();
      final im = FakeIM(ffi, bus);

      im.registerPendingFriendAdd(friendId);

      // Tox hasn't yet propagated — friendList is empty. We still need the
      // poll to take the "Tox returned a non-empty list at some point" path,
      // so include a different friend Tox already knows about.
      const other =
          'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
      ffi.friendsToReturn = [
        (userId: other, nickName: 'Other', status: '', online: false),
      ];
      await im.refreshContacts();

      // Pending entry must survive.
      expect(im.debugPendingFriendAdds.keys, contains(friendId),
          reason:
              'pending entry must survive a Tox poll that has not yet confirmed it');

      // localFriends must include the pending friend even though Tox does not.
      final stored = await Prefs.getLocalFriends();
      expect(stored, contains(friendId),
          reason: 'X9: pending friend must be merged into localFriends');
      expect(stored, contains(other));

      im.dispose();
      bus.dispose();
    }, skip: skipReason);

    test(
        'within-TTL entry survives poll; already-expired entry is evicted and not merged',
        () async {
      const liveId =
          'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
      const expiredId =
          'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';

      final ffi = _RecordingFfiChatService();
      final bus = FakeEventBus();
      final im = FakeIM(ffi, bus);

      // Live: long TTL so it survives the first poll's eviction pass.
      im.registerPendingFriendAdd(liveId,
          ttlOverride: const Duration(seconds: 30));
      // Expired: TTL already in the past — must be dropped by `_livePendingFriendAdds`.
      im.registerPendingFriendAdd(expiredId,
          ttlOverride: const Duration(milliseconds: -1));

      expect(im.debugPendingFriendAdds.keys,
          containsAll([liveId, expiredId]),
          reason: 'both entries should be present before any poll runs');

      // Tox returns nothing related to either pending entry. We still need
      // the "non-empty Tox returned at some point" path, so include an
      // unrelated friend so the impl exits the cold-start branch.
      const unrelated =
          '9999999999999999999999999999999999999999999999999999999999999999';
      ffi.friendsToReturn = [
        (userId: unrelated, nickName: 'Other', status: '', online: false),
      ];
      await im.refreshContacts();

      expect(im.debugPendingFriendAdds.keys, contains(liveId),
          reason: 'within-TTL entry must survive the eviction pass');
      expect(im.debugPendingFriendAdds.keys, isNot(contains(expiredId)),
          reason:
              'already-expired entry must be evicted on the next poll cycle');

      final stored = await Prefs.getLocalFriends();
      expect(stored, contains(liveId),
          reason: 'live pending entry must be merged into localFriends');
      expect(stored, isNot(contains(expiredId)),
          reason:
              'expired pending entry must not haunt localFriends (TTL contract)');

      im.dispose();
      bus.dispose();
    }, skip: skipReason);

    test('registering an empty or whitespace ID is a no-op', () async {
      final ffi = _RecordingFfiChatService();
      final bus = FakeEventBus();
      final im = FakeIM(ffi, bus);

      im.registerPendingFriendAdd('');
      im.registerPendingFriendAdd('   ');
      expect(im.debugPendingFriendAdds, isEmpty);

      im.dispose();
      bus.dispose();
    }, skip: skipReason);

    test(
        '76-char address normalizes to 64-char pubkey before storage',
        () async {
      const pubkey =
          'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';
      const fullAddr = '${pubkey}AABBCCDD1234'; // 76 chars
      expect(fullAddr.length, 76);

      final ffi = _RecordingFfiChatService();
      final bus = FakeEventBus();
      final im = FakeIM(ffi, bus);
      im.registerPendingFriendAdd(fullAddr);
      // Storage key must be the normalized 64-char pubkey, so Tox poll
      // matching works against the FFI's pubkey-shaped friend list.
      expect(im.debugPendingFriendAdds.keys, equals({pubkey}));

      im.dispose();
      bus.dispose();
    }, skip: skipReason);
  });
}
