// "Jump to a specific message" (search hit, "@me" mention) over >1 page of
// history, end to end through the fork's data layer and Tim2ToxSdkPlatform.
//
// The fork (like upstream UIKit) loads the target's window in two calls:
//   1. getHistoryMessageListV2(getType: CLOUD_NEWER, lastMsgID: target)
//      and `.reversed` the result, relying on the V2TIM contract that a
//      NEWER page is in ascending time order (tencent_cloud_chat_sdk
//      V2TIMMessageListGetOption: "当 getType 设置为拉取更新的消息时，消息列表按照
//      时间顺序，也即消息按照时间戳从小往大的顺序排序"), so `.last` is the message
//      right after the target;
//   2. getHistoryMessageListV2(OLDER, lastMsgID: that message), which then
//      starts AT the target.
// Tim2ToxSdkPlatform used to return NEWER pages newest-first, so `.last` was
// the NEWEST message of the window and step 2 re-fetched the whole window:
// every message between the target and the window top appeared twice and the
// target ended up at the very bottom edge with no older context.
//
// FFI dependency: `Tim2ToxSdkPlatform`'s constructor requires a real
// `FfiChatService`, which opens the tim2tox FFI library. History reads use
// Dart persistence directly and do not require init, login, or polling.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_common/data/message/tencent_cloud_chat_message_data.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform_converters.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

// A 64-char hex peer id so the normalizer treats it as a C2C id.
const _peerId =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _groupId = 'tox_group_jump_target';
const _total = 60;

List<String> _ids(Iterable<V2TimMessage> messages) =>
    messages.map((m) => m.msgID ?? '').toList();

List<String> _range(int from, int to, {bool descending = false}) {
  final ids = [for (var i = from; i <= to; i++) 'msgid_$i'];
  return descending ? ids.reversed.toList() : ids;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');
  final ffiAvailable = _ffiAvailable();
  final previousCustomCallbackHandler =
      NativeLibraryManager.customCallbackHandler;
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  test('historyTimeRange follows the V2TIM direction rules', () {
    expect(historyTimeRange(newer: true), isNull);
    expect(historyTimeRange(newer: false, timeBegin: 0, timePeriod: 0),
        isNull);
    expect(historyTimeRange(newer: true, timeBegin: 100),
        (from: 100, to: null));
    expect(historyTimeRange(newer: true, timeBegin: 100, timePeriod: 10),
        (from: 100, to: 110));
    expect(historyTimeRange(newer: false, timeBegin: 100),
        (from: null, to: 100));
    expect(historyTimeRange(newer: false, timeBegin: 100, timePeriod: 10),
        (from: 90, to: 100));
    // timeBegin 0 = "now".
    expect(
        historyTimeRange(
            newer: false, timePeriod: 10, nowSeconds: 1000),
        (from: 990, to: null));
  });

  group('jump to a specific message over >1 page of history', skip: skipReason,
      () {
    Directory? tempRoot;
    MessageHistoryPersistence? persistence;
    FfiChatService? service;
    Tim2ToxSdkPlatform? platform;
    TencentCloudChatSdkPlatform? previousPlatform;

    setUp(() async {
      final root = await Directory.systemTemp
          .createTemp('tim2tox_load_to_specific_message_');
      tempRoot = root;
      final historyPersistence = MessageHistoryPersistence(
          historyDirectory: p.join(root.path, 'history'));
      persistence = historyPersistence;
      final ffiService =
          FfiChatService(messageHistoryPersistence: historyPersistence);
      service = ffiService;
      platform = Tim2ToxSdkPlatform(ffiService: ffiService);
      previousPlatform = TencentCloudChatSdkPlatform.instance;
      TencentCloudChatSdkPlatform.instance = platform!;
      TencentCloudChat.instance.dataInstance.messageData.messageListMap = {};
    });

    tearDown(() async {
      final messageData = TencentCloudChat.instance.dataInstance.messageData;
      messageData.messageListMap = {};
      messageData.clearMessageListStatus(userID: _peerId);
      messageData.clearMessageListStatus(groupID: _groupId);
      if (previousPlatform != null) {
        TencentCloudChatSdkPlatform.instance = previousPlatform!;
      }
      platform?.dispose();
      NativeLibraryManager.customCallbackHandler =
          previousCustomCallbackHandler;
      final ffiService = service;
      if (ffiService != null) {
        await ffiService.dispose();
      } else {
        await persistence?.dispose();
      }
      final root = tempRoot;
      if (root != null && await root.exists()) {
        await root.delete(recursive: true);
      }
      tempRoot = null;
      persistence = null;
      service = null;
      platform = null;
      previousPlatform = null;
    });

    ChatMessage msg(int i, {String? groupId}) => ChatMessage(
          text: 'msg $i',
          fromUserId: _peerId,
          isSelf: false,
          // 1 s apart so second-granular V2TimMessage timestamps stay distinct.
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 1000),
          groupId: groupId,
          msgID: 'msgid_$i',
        );

    Future<List<ChatMessage>> seed(String conversationId,
        {String? groupId}) async {
      final messages = List.generate(_total, (i) => msg(i, groupId: groupId));
      final historyPersistence = persistence!;
      await historyPersistence.saveHistory(conversationId, messages);
      historyPersistence.clearAllCached();
      final reloaded = await historyPersistence.loadHistory(conversationId);
      expect(reloaded.map((m) => m.msgID).toList(), _range(0, _total - 1));
      return messages;
    }

    group('Tim2ToxSdkPlatform honours the V2TIM paging order contract', () {
      for (final conv in ['c2c', 'group']) {
        final isGroup = conv == 'group';
        String? uid() => isGroup ? null : _peerId;
        String? gid() => isGroup ? _groupId : null;

        for (final getType in [
          HistoryMessageGetType.V2TIM_GET_CLOUD_NEWER_MSG,
          HistoryMessageGetType.V2TIM_GET_LOCAL_NEWER_MSG,
        ]) {
          test('$conv getType=$getType: NEWER page is ascending and starts '
              'right after the anchor', () async {
            await seed(isGroup ? _groupId : _peerId,
                groupId: isGroup ? _groupId : null);

            final mid = await platform!.getHistoryMessageListV2(
              getType: getType,
              userID: uid(),
              groupID: gid(),
              count: 20,
              lastMsgID: 'msgid_10',
            );
            expect(mid.code, 0);
            expect(_ids(mid.data!.messageList), _range(11, 30));
            expect(mid.data!.isFinished, isFalse);

            final top = await platform!.getHistoryMessageListV2(
              getType: getType,
              userID: uid(),
              groupID: gid(),
              count: 20,
              lastMsgID: 'msgid_50',
            );
            expect(_ids(top.data!.messageList), _range(51, 59));
            expect(top.data!.isFinished, isTrue);

            final none = await platform!.getHistoryMessageListV2(
              getType: getType,
              userID: uid(),
              groupID: gid(),
              count: 20,
              lastMsgID: 'msgid_59',
            );
            expect(none.data!.messageList, isEmpty);
            expect(none.data!.isFinished, isTrue);
          });
        }

        test('$conv: OLDER page stays descending and excludes the anchor',
            () async {
          await seed(isGroup ? _groupId : _peerId,
              groupId: isGroup ? _groupId : null);
          final res = await platform!.getHistoryMessageListV2(
            getType: HistoryMessageGetType.V2TIM_GET_CLOUD_OLDER_MSG,
            userID: uid(),
            groupID: gid(),
            count: 20,
            lastMsgID: 'msgid_31',
          );
          expect(_ids(res.data!.messageList), _range(11, 30, descending: true));
          expect(res.data!.isFinished, isFalse);
        });

        test('$conv: NEWER with only timeBegin starts at timeBegin, ascending',
            () async {
          await seed(isGroup ? _groupId : _peerId,
              groupId: isGroup ? _groupId : null);
          // msgid_10's second; closed interval, open-ended (timePeriod 0).
          final res = await platform!.getHistoryMessageListV2(
            getType: HistoryMessageGetType.V2TIM_GET_CLOUD_NEWER_MSG,
            userID: uid(),
            groupID: gid(),
            count: 20,
            timeBegin: 1700000000 + 10,
          );
          expect(_ids(res.data!.messageList), _range(10, 29));
          expect(res.data!.isFinished, isFalse);
        });
      }
    });

    group('fork loadToSpecificMessage over the platform', () {
      final messageData = TencentCloudChat.instance.dataInstance.messageData;

      void expectContiguousWindow(List<V2TimMessage> list,
          {required int oldest, required int newest}) {
        final ids = _ids(list);
        expect(ids.toSet().length, ids.length,
            reason: 'duplicate rows in the store: $ids');
        expect(ids, _range(oldest, newest, descending: true),
            reason: 'store must be newest-first and contiguous');
      }

      test('C2C search-hit jump to msgid_10 (outside the newest page)',
          () async {
        await seed(_peerId);
        await messageData.loadMessageList(
          userID: _peerId,
          direction: TencentCloudChatMessageLoadDirection.previous,
          count: 20,
        );
        expectContiguousWindow(messageData.getMessageList(key: _peerId),
            oldest: 40, newest: 59);

        final res = await messageData.loadToSpecificMessage(
            userID: _peerId, msgID: 'msgid_10');

        expect(res.targetMessage?.msgID, 'msgid_10');
        // 20 newer than the target + the target + the 10 older ones.
        expectContiguousWindow(messageData.getMessageList(key: _peerId),
            oldest: 0, newest: 30);
        expect(res.haveMoreLatestData, isTrue);
        expect(res.haveMorePreviousData, isFalse);
      });

      test('group "@me" jump: seq-resolved row, then jump by its msgID',
          () async {
        final rows = await seed(_groupId, groupId: _groupId);
        await messageData.loadMessageList(
          groupID: _groupId,
          direction: TencentCloudChatMessageLoadDirection.previous,
          count: 20,
        );

        // What separate_data._loadMentionedMessages does with groupAtInfoList.
        final mentioned = await TencentCloudChat
            .instance.chatSDKInstance.messageSDK
            .getHistoryMessageList(
          count: 1,
          groupID: _groupId,
          messageSeqList: [groupAtSeqOf(rows[12])],
        );
        expect(_ids(mentioned.messageList), ['msgid_12']);
        final target = mentioned.messageList.single;

        final res = await messageData.loadToSpecificMessage(
          groupID: _groupId,
          msgID: target.msgID,
          timeStamp: target.timestamp,
          seq: int.tryParse(target.seq ?? ''),
        );

        expect(res.targetMessage?.msgID, 'msgid_12');
        expectContiguousWindow(messageData.getMessageList(key: _groupId),
            oldest: 0, newest: 32);
        expect(res.haveMoreLatestData, isTrue);
        expect(res.haveMorePreviousData, isFalse);
      });

      test('deep target keeps older context and pages both ways', () async {
        await seed(_peerId);
        final res = await messageData.loadToSpecificMessage(
            userID: _peerId, msgID: 'msgid_30');
        expect(res.targetMessage?.msgID, 'msgid_30');
        expectContiguousWindow(messageData.getMessageList(key: _peerId),
            oldest: 11, newest: 50);
        expect(res.haveMoreLatestData, isTrue);
        expect(res.haveMorePreviousData, isTrue);
      });

      test('C2C jump to the read position (timestamp only)', () async {
        await seed(_peerId);
        await messageData.loadMessageList(
          userID: _peerId,
          direction: TencentCloudChatMessageLoadDirection.previous,
          count: 20,
        );
        // onLoadToLatestReadMessage: timeStamp = c2cReadTimestamp (msgid_10's
        // second); the target is the first message after it.
        final res = await messageData.loadToSpecificMessage(
            userID: _peerId, timeStamp: 1700000000 + 10);
        expect(res.targetMessage?.msgID, 'msgid_11');
        expectContiguousWindow(messageData.getMessageList(key: _peerId),
            oldest: 0, newest: 29);
        expect(res.haveMoreLatestData, isTrue);
      });

      test('jump to the newest message into an unloaded conversation',
          () async {
        // A search hit opens the chat with `targetMessage` set, which calls
        // loadToSpecificMessage INSTEAD of the initial page load; an empty
        // NEWER page must not leave the chat blank.
        await seed(_peerId);
        final res = await messageData.loadToSpecificMessage(
            userID: _peerId, msgID: 'msgid_59');
        expect(res.targetMessage?.msgID, 'msgid_59');
        expectContiguousWindow(messageData.getMessageList(key: _peerId),
            oldest: 40, newest: 59);
        expect(res.haveMoreLatestData, isFalse);
        expect(res.haveMorePreviousData, isTrue);
      });
    });
  });
}
