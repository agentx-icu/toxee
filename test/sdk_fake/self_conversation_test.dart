// The self conversation ("note to self", `c2c_<own public key>`) in toxee:
// listed in the conversation list, and never deleted — not through the SDK
// platform (single, batch, friend deletion), not through the host conversation
// manager. Runs over the real FfiChatService on a binding stub (no native
// library), the way tim2tox's own tests do.

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as pkgffi;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimConversationListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimFriendshipListener.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';
import 'package:toxee/sdk_fake/self_conversation.dart';
import 'package:toxee/util/prefs.dart';

const _selfKey =
    'ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB';
const _selfToxId = '${_selfKey}0000000012EF';
const _selfConv = 'c2c_$_selfKey';
const _friendKey =
    'CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCD';

/// Answers the identity; counts native friend deletions; nothing else is
/// reachable from these tests.
class _SelfFfi extends Tim2ToxFfi {
  _SelfFfi({this.selfToxId = _selfToxId}) : super.forTesting();

  final String? selfToxId;
  final List<String> deletedFriends = [];

  @override
  int Function() get getCurrentInstanceId => () => 0;

  @override
  void Function() get uninit => () {};

  @override
  int Function(ffi.Pointer<ffi.Int8>, int) get getSelfToxId => (buf, cap) {
        final id = selfToxId;
        if (id == null) return 0;
        final bytes = utf8.encode(id);
        final out = buf.cast<ffi.Uint8>().asTypedList(bytes.length + 1);
        out.setAll(0, bytes);
        out[bytes.length] = 0;
        return bytes.length;
      };

  @override
  int Function(ffi.Pointer<ffi.Int8>, int) get getFriendList => (buf, cap) {
        buf.cast<ffi.Uint8>()[0] = 0;
        return 0;
      };

  @override
  int Function(ffi.Pointer<pkgffi.Utf8>) get deleteFriend => (key) {
        deletedFriends.add(key.toDartString());
        return 1;
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late _SelfFfi stub;
  late FfiChatService service;

  FfiChatService open(_SelfFfi binding) => FfiChatService(
        ffiForTesting: binding,
        historyDirectory: '${root.path}/history',
        queueFilePath: '${root.path}/offline_queue.json',
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('toxee_self_conv_');
    await Directory('${root.path}/history').create();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
    stub = _SelfFfi();
    service = open(stub);
    service.debugSetSelfId('FlutterUIKitClient'); // toxee's login alias
  });

  tearDown(() async {
    await service.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('conversation list', () {
    test('the builder lists the self conversation with its own title/avatar',
        () async {
      final list = await buildConversationsFromFriends(
        friends: const [
          (userId: _friendKey, nickName: 'Bob', online: true),
        ],
        groupIds: const [],
        pinned: const <String>{},
        quitGroups: const <String>{},
        pendingFriendIds: const <String>{},
        sortingMode: 'name',
        getUnreadOf: (_) => 3,
        self: (
          key: _selfKey,
          title: 'Ann',
          faceUrl: '/avatars/ann.png',
          activity: null,
        ),
      );
      final self = list.singleWhere((c) => c.conversationID == _selfConv);
      expect(self.title, 'Ann');
      expect(self.faceUrl, '/avatars/ann.png');
      expect(self.isGroup, isFalse);
      expect(self.unreadCount, 0, reason: 'nothing inbound in a notebook');
      expect(list.map((c) => c.conversationID), contains('c2c_$_friendKey'));
    });

    test('pinned and activity-sorted like any C2C; absent without identity',
        () async {
      Future<List<String>> ids({required bool pin, DateTime? activity}) async =>
          (await buildConversationsFromFriends(
            friends: const [
              (userId: _friendKey, nickName: 'Bob', online: true),
            ],
            groupIds: const [],
            pinned: pin ? {_selfKey} : const <String>{},
            quitGroups: const <String>{},
            pendingFriendIds: const <String>{},
            sortingMode: 'activity',
            getUnreadOf: (_) => 0,
            self: (key: _selfKey, title: 'Zed', faceUrl: null, activity: activity),
          ))
              .map((c) => c.conversationID)
              .toList();

      expect((await ids(pin: true)).first, _selfConv);
      expect(
        (await ids(pin: false, activity: DateTime(2030))).first,
        _selfConv,
        reason: 'the newest activity sorts first',
      );
      final none = await buildConversationsFromFriends(
        friends: const [],
        groupIds: const [],
        pinned: const <String>{},
        quitGroups: const <String>{},
        pendingFriendIds: const <String>{},
        sortingMode: 'name',
        getUnreadOf: (_) => 0,
      );
      expect(none, isEmpty);
    });

    test('resolveSelfConversation: own key, nickname, last note time', () async {
      await Prefs.setNickname('Ann');
      final row = await service.sendTextWithResult(_selfKey, 'note');
      final self = (await resolveSelfConversation(service))!;
      expect(self.key, _selfKey);
      expect(self.title, 'Ann');
      expect(self.activity, row.timestamp);

      await Prefs.setNickname('');
      expect((await resolveSelfConversation(service))!.title, 'ABABABAB');

      final anonymous = open(_SelfFfi(selfToxId: null));
      addTearDown(anonymous.dispose);
      expect(await resolveSelfConversation(anonymous), isNull);
    });

    test('isSelfConversationId: c2c with the own key only', () {
      expect(isSelfConversationId(service, _selfConv), isTrue);
      expect(isSelfConversationId(service, 'c2c_${_selfKey.toLowerCase()}'),
          isTrue);
      expect(isSelfConversationId(service, 'c2c_$_friendKey'), isFalse);
      expect(isSelfConversationId(service, 'group_tox_1'), isFalse);
      expect(isSelfConversationId(service, 'c2c_FlutterUIKitClient'), isFalse);
      expect(isSelfConversationId(null, _selfConv), isFalse);
    });
  });

  test('a note to self routes to the self conversation, not the open chat',
      () async {
    final bus = FakeEventBus();
    final im = FakeIM(service, bus);
    final routed = <String>[];
    final sub = bus
        .on<FakeMessage>(FakeIM.topicMessage)
        .listen((m) => routed.add(m.conversationID));
    im.start();
    addTearDown(() async {
      await sub.cancel();
      im.dispose();
    });
    // Another chat is open (a forward into self is sent from there too).
    service.setActivePeer('c2c_$_friendKey');
    await service.sendTextWithResult(_selfKey, 'note while Bob is open');
    await pumpEventQueue();
    expect(routed, [_selfConv]);
  });

  group('never deleted', () {
    late Tim2ToxSdkPlatform platform;
    late List<String> deletedConversations;
    late List<String> deletedFriends;

    setUp(() async {
      // Seeded BEFORE the platform listens: it turns every emitted message
      // into a V2TimMessage, which reads the server time from the native IM
      // library that unit tests do not load.
      await service.sendTextWithResult(_selfKey, 'keep me');
      platform = Tim2ToxSdkPlatform(ffiService: service);
      deletedConversations = [];
      deletedFriends = [];
      await platform.addConversationListener(
        listener: V2TimConversationListener(
          onConversationDeleted: deletedConversations.addAll,
        ),
      );
      await platform.addFriendListener(
        listener: V2TimFriendshipListener(
          onFriendListDeleted: deletedFriends.addAll,
        ),
      );
    });

    tearDown(() => platform.dispose());

    List<String> notes() =>
        service.getHistory(_selfKey).map((m) => m.text).toList();

    test('deleteConversation(self) is refused before anything happens',
        () async {
      final result = await platform.deleteConversation(conversationID: _selfConv);
      expect(result.code, 6017);
      expect(result.desc, FfiChatService.selfConversationUndeletable);
      expect(deletedConversations, isEmpty,
          reason: 'a deletion event would make hosts suppress the row');
      expect(notes(), ['keep me']);
    });

    test('a mixed batch refuses only the self conversation', () async {
      for (final clearMessage in [true, false]) {
        deletedConversations.clear();
        final result = await platform.deleteConversationList(
          conversationIDList: [_selfConv, 'c2c_$_friendKey'],
          clearMessage: clearMessage,
        );
        expect(result.code, 0, reason: 'batch semantics are unchanged');
        final byId = {for (final r in result.data!) r.conversationID: r};
        expect(byId[_selfConv]!.resultCode, 6017);
        expect(byId['c2c_$_friendKey']!.resultCode, 0);
        expect(deletedConversations, ['c2c_$_friendKey']);
        expect(notes(), ['keep me']);
      }
    });

    test('friend deletion refuses self and does not report it', () async {
      final result = await platform.deleteFromFriendList(
        userIDList: [_selfKey, _friendKey],
        deleteType: 2,
      );
      final byId = {for (final r in result.data!) r.userID: r};
      expect(byId[_selfKey]!.resultCode, 6017);
      expect(byId[_friendKey]!.resultCode, 0);
      expect(stub.deletedFriends, [_friendKey], reason: 'self never native');
      expect(deletedFriends, [_friendKey]);
      expect(notes(), ['keep me']);
    });

    test('the host conversation manager refuses it too', () async {
      final manager = FakeConversationManager(
        FakeUIKit.instance.eventBusInstance,
        service,
      );
      await manager.deleteConversation(_selfConv);
      expect(notes(), ['keep me']);
    });

    test('explicit clear still empties it', () async {
      final result = await platform.clearC2CHistoryMessage(userID: _selfKey);
      expect(result.code, 0);
      expect(notes(), isEmpty);
    });
  });
}
