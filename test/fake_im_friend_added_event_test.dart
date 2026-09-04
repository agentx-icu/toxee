// FakeIM must emit FakeFriendAdded when a friend (re)appears in the Tox friend
// list — including the SOLE friend being deleted and re-added, which empties
// the previous-friends set (an "is it cold start?" heuristic based on that set
// being empty would swallow the event). The event lifts the conversation
// tombstone FakeChatDataProvider keeps after FakeFriendDeleted; without it a
// re-added friend's entry is skipped by every 5 s rebuild.
//
// Same scaffold as fake_im_pending_friend_adds_test.dart: skips when the
// tim2tox FFI library isn't loadable.

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

class _RecordingFfiChatService extends FfiChatService {
  _RecordingFfiChatService() : super();

  List<({String userId, String nickName, String status, bool online})>
      friendsToReturn = const [];

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
      getFriendList() async => friendsToReturn;

  @override
  Future<List<({String userId, String wording})>> getFriendApplications() async =>
      const [];

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
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('FakeIM FakeFriendAdded', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      await Prefs.setCurrentAccountToxId(
          '00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF');
    });

    tearDown(() async {
      await env.dispose();
    });

    test('sole friend deleted then re-added emits FakeFriendAdded', () async {
      const friendId =
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final ffi = _RecordingFfiChatService();
      final bus = FakeEventBus();
      final im = FakeIM(ffi, bus);
      final added = <String>[];
      final deleted = <String>[];
      final addedSub = bus
          .on<FakeFriendAdded>(FakeIM.topicFriendAdded)
          .listen((e) => added.add(e.userID));
      final deletedSub = bus
          .on<FakeFriendDeleted>(FakeIM.topicFriendDeleted)
          .listen((e) => deleted.add(e.userID));

      // Baseline poll: the friend is known; no "added" event for a cold start.
      ffi.friendsToReturn = [
        (userId: friendId, nickName: 'Alice', status: '', online: true),
      ];
      await im.refreshContacts();
      await Future<void>.delayed(Duration.zero);
      expect(added, isEmpty, reason: 'first poll is the baseline');

      // Tox drops the only friend: deletion detected, previous set now EMPTY.
      ffi.friendsToReturn = const [];
      await im.refreshContacts();
      await Future<void>.delayed(Duration.zero);
      expect(deleted, contains(friendId));

      // Re-add: must still be reported as added.
      ffi.friendsToReturn = [
        (userId: friendId, nickName: 'Alice', status: '', online: true),
      ];
      await im.refreshContacts();
      await Future<void>.delayed(Duration.zero);
      expect(added, contains(friendId),
          reason: 'a re-add after deleting the sole friend must emit');

      await addedSub.cancel();
      await deletedSub.cancel();
      im.dispose();
      bus.dispose();
    }, skip: skipReason);
  });
}
