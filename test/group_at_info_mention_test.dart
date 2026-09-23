// Group "@me" marker (V2TimConversation.groupAtInfoList) contracts.
//
//  * The marker CLEARS once the mention is read. UIKit merges conversation
//    updates as `incoming.groupAtInfoList ?? existing.groupAtInfoList`, so a
//    group conversation must always carry an explicit list — the old
//    producers left it null when nothing was unread and "[@me]" stuck until
//    restart.
//  * The @me JUMP lands on the mentioning message. UIKit resolves the marker
//    with getHistoryMessageListV2(messageSeqList: [seq]); Tim2Tox used to
//    ignore the list and return the newest message, and every marker carried
//    seq '0'. The seq now identifies the mentioning row and the platform
//    resolves it back to exactly that row (or to nothing — never to another
//    message).
//
// These drive the real FfiChatService ingest seam and Tim2ToxSdkPlatform.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_common/data/conversation/tencent_cloud_chat_conversation_data.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_builders.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/interfaces/conversation_manager_provider.dart';
import 'package:tim2tox_dart/models/fake_models.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform_converters.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

const _gid = '1122334455667788990011223344556677889900112233445566778899001122';
const _peer =
    'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';
const _self = 'FlutterUIKitClient';
const _t0 = 1700000000000;

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('group @me marker', skip: skipReason, () {
    late Directory tempRoot;
    late FfiChatService service;
    late Tim2ToxSdkPlatform platform;
    late TencentCloudChatSdkPlatform previousPlatform;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('group_at_info_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
            return call.method.startsWith('get') ? tempRoot.path : null;
          });
      final persistence = MessageHistoryPersistence(
        historyDirectory: p.join(tempRoot.path, 'history'),
      );
      service = FfiChatService(messageHistoryPersistence: persistence)
        ..debugSetSelfId(_self);
      await service.updateSelfProfile(nickname: 'Ann', statusMessage: '');
      await service.registerJoinedGroupState(_gid);
      platform = Tim2ToxSdkPlatform(
        ffiService: service,
        conversationManagerProvider: _OneGroupConversations(service),
      );
      // Installed, as in the app: the SDK facade UIKit calls routes here.
      previousPlatform = TencentCloudChatSdkPlatform.instance;
      TencentCloudChatSdkPlatform.instance = platform;
    });

    tearDown(() async {
      TencentCloudChatSdkPlatform.instance = previousPlatform;
      platform.dispose();
      await service.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    void ingest(String text, int offsetMs) {
      expect(
        service.ingestInboundGroupText(
          gid: _gid,
          from: _peer,
          text: text,
          epochMs: _t0 + offsetMs,
        ),
        isTrue,
      );
    }

    String msgIdOf(String text) =>
        service.getHistory(_gid).singleWhere((m) => m.text == text).msgID!;

    Future<V2TimConversation> mapConv() =>
        platform.fakeConversationToV2TimConversation(
          FakeConversation(
            conversationID: 'group_$_gid',
            title: 'G',
            faceUrl: null,
            unreadCount: service.getUnreadOf(_gid),
            isGroup: true,
          ),
        );

    test('a group with no unread mention carries an explicit empty list',
        () async {
      ingest('hello', 0);
      expect(groupAtInfoListFor(service, _gid), isEmpty);
      final conv = await mapConv();
      expect(conv.groupAtInfoList, isNotNull,
          reason: 'null means "unchanged" to the UIKit merge');
      expect(conv.groupAtInfoList, isEmpty);
    });

    test('the marker clears in the UIKit conversation list once read',
        () async {
      ingest('hello', 0);
      ingest('@Ann look here', 1000);
      ingest('later 1', 2000);

      final data = TencentCloudChatConversationData<dynamic>(
        TencentCloudChatConversationDataKeys.conversationList,
      );
      data.buildConversationList([await mapConv()], 'test_unread');
      expect(data.conversationList.single.groupAtInfoList, hasLength(1));
      expect(data.conversationList.single.groupAtInfoList!.single!.atType, 1);

      // Opening the chat reads it.
      service.setActivePeer('group_$_gid');
      data.buildConversationList([await mapConv()], 'test_read');
      expect(
        data.conversationList.single.groupAtInfoList,
        isEmpty,
        reason: 'Regression: the read conversation carried a null '
            'groupAtInfoList, so `incoming ?? existing` kept "[@me]" forever',
      );
    });

    test('each unread mention gets a seq that resolves to its own row',
        () async {
      ingest('@Ann first', 0);
      ingest('chatter', 1000);
      ingest('hey @Ann second', 2000);
      ingest('newest, no mention', 3000);

      final infos = groupAtInfoListFor(service, _gid);
      expect(infos, hasLength(2));
      final seqs = infos.map((i) => int.parse(i.seq)).toList();
      expect(seqs, isNot(contains(unresolvedGroupAtSeq)));
      final rows = chatMessagesForGroupAtSeqs(service.getHistory(_gid), seqs);
      expect(rows.map((m) => m.text), ['hey @Ann second', '@Ann first'],
          reason: 'newest first, and only the mentioning rows');
    });

    test('the @me jump returns the mention message, not the newest one',
        () async {
      ingest('@Ann look here', 0);
      ingest('later 1', 1000);
      ingest('later 2 (newest)', 2000);

      final seq = int.parse(groupAtInfoListFor(service, _gid).single.seq);
      // Exactly what the fork's _loadMentionedMessages sends.
      final res = await platform.getHistoryMessageListV2(
        groupID: _gid,
        count: 1,
        messageSeqList: [seq],
      );
      expect(res.code, 0);
      final list = res.data!.messageList;
      expect(list, hasLength(1));
      expect(list.single.msgID, msgIdOf('@Ann look here'),
          reason: 'Regression: messageSeqList was ignored and the newest '
              'message came back, so the jump landed on the wrong bubble');
      expect(list.single.groupID, _gid);
      expect(list.single.textElem?.text, '@Ann look here');
    });

    test('an unresolvable seq jumps nowhere instead of to another message',
        () async {
      ingest('@Ann look here', 0);
      ingest('later (newest)', 1000);

      for (final seqs in [
        [unresolvedGroupAtSeq],
        [424242],
      ]) {
        final res = await platform.getHistoryMessageListV2(
          groupID: _gid,
          count: seqs.length,
          messageSeqList: seqs,
        );
        expect(res.code, 0);
        expect(res.data!.messageList, isEmpty, reason: 'seqs=$seqs');
        expect(res.data!.isFinished, isTrue);
      }
    });

    // The real row-tap order: onTapConversationItem calls setActivePeer (which
    // reads the group) BEFORE the chat page loads its conversation, so the
    // open chat used to see an empty groupAtInfoList and never offered the
    // "@me" jump.
    Future<List<int>> openChatSeqs() async {
      final res = await platform.getConversation(conversationID: 'group_$_gid');
      expect(res.code, 0);
      return res.data!.groupAtInfoList!.map((i) => int.parse(i!.seq)).toList();
    }

    test('a row tap keeps the @me jump target for the open chat only',
        () async {
      ingest('@Ann look here', 0);
      ingest('later (newest)', 1000);
      expect((await mapConv()).groupAtInfoList, hasLength(1));

      service.setActivePeer('group_$_gid'); // the tap
      expect(service.getUnreadOf(_gid), 0);
      expect((await mapConv()).groupAtInfoList, isEmpty,
          reason: 'the conversation-list marker still clears once read');

      final seqs = await openChatSeqs();
      expect(seqs, hasLength(1),
          reason: 'Regression: the open chat loaded its conversation after '
              'the tap had read the mention, so the jump list was empty');
      final res = await platform.getHistoryMessageListV2(
        groupID: _gid,
        count: 1,
        messageSeqList: seqs,
      );
      expect(res.data!.messageList.single.msgID, msgIdOf('@Ann look here'));

      // A second bind of the same chat (bindActiveConversation after the row
      // handler) keeps the targets.
      service.setActivePeer('group_$_gid');
      expect(await openChatSeqs(), seqs);

      // Leaving the chat drops them; reopening finds nothing unread.
      service.setActivePeer(null);
      expect(await openChatSeqs(), isEmpty);
      service.setActivePeer('group_$_gid');
      expect(await openChatSeqs(), isEmpty);
    });

    test('switching to another conversation drops the jump target', () async {
      ingest('@Ann look here', 0);
      service.setActivePeer('group_$_gid');
      expect(await openChatSeqs(), hasLength(1));
      service.setActivePeer('c2c_$_peer');
      expect(await openChatSeqs(), isEmpty);
    });

    test('the UIKit chat page opened after the tap offers the @me jump',
        () async {
      ingest('hello', 0);
      ingest('@Ann look here', 1000);
      ingest('later (newest)', 2000);

      service.setActivePeer('group_$_gid'); // onTapConversationItem
      final page = TencentCloudChatMessageSeparateDataProvider();
      addTearDown(page.dispose);
      page.init(groupID: _gid, builders: TencentCloudChatMessageBuilders());
      for (var i = 0; i < 200 && page.messagesMentionedMe.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(page.messagesMentionedMe.map((m) => m.msgID),
          [msgIdOf('@Ann look here')]);
    });

    test('plain pagination is unaffected', () async {
      ingest('a', 0);
      ingest('b', 1000);
      final res = await platform.getHistoryMessageListV2(
        groupID: _gid,
        count: 1,
      );
      expect(res.data!.messageList.single.msgID, msgIdOf('b'));
    });
  });
}

/// The conversation list the app's FakeConversationManager would serve: the
/// one test group, with the service's live unread count.
class _OneGroupConversations implements ConversationManagerProvider {
  _OneGroupConversations(this.service);

  final FfiChatService service;

  @override
  Future<List<FakeConversation>> getConversationList() async => [
        FakeConversation(
          conversationID: 'group_$_gid',
          title: 'G',
          faceUrl: null,
          unreadCount: service.getUnreadOf(_gid),
          isGroup: true,
        ),
      ];

  @override
  Future<void> setPinned(String conversationID, bool isPinned) async {}

  @override
  Future<void> deleteConversation(String conversationID) async {}

  @override
  Future<int> getTotalUnreadCount() async => service.getUnreadOf(_gid);
}
