// P4 regression test: `Tim2ToxSdkPlatform.getHistoryMessageListV2` used to
// call `sort()` three times per request — once before filtering and once
// after each filter step. The sort key was always the same descending
// timestamp comparison, so the post-filter sorts were redundant. We removed
// the redundancy by sorting exactly once after both filters run.
//
// This test seeds a known history, walks several page boundaries with a mix
// of filters, and asserts pagination is unchanged.
//
// FFI dependency: `Tim2ToxSdkPlatform`'s constructor requires a real
// `FfiChatService`, which opens the tim2tox FFI library. History reads use
// Dart persistence directly and do not require init, login, or polling.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');
  final ffiAvailable = _ffiAvailable();
  final previousCustomCallbackHandler =
      NativeLibraryManager.customCallbackHandler;
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('Tim2ToxSdkPlatform.getHistoryMessageListV2 — P4 sort-once',
      skip: skipReason, () {
    Directory? tempRoot;
    MessageHistoryPersistence? persistence;
    FfiChatService? service;
    Tim2ToxSdkPlatform? platform;

    // Use a 64-char hex peer id so the normalizer treats it as a C2C id.
    const peerId =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    setUp(() async {
      final root = await Directory.systemTemp
          .createTemp('tim2tox_get_history_pagination_');
      tempRoot = root;
      final historyPersistence = MessageHistoryPersistence(
          historyDirectory: p.join(root.path, 'history'));
      persistence = historyPersistence;
      final ffiService =
          FfiChatService(messageHistoryPersistence: historyPersistence);
      service = ffiService;
      platform = Tim2ToxSdkPlatform(ffiService: ffiService);
    });

    tearDown(() async {
      platform?.dispose();
      NativeLibraryManager.customCallbackHandler =
          previousCustomCallbackHandler;
      final ffiService = service;
      if (ffiService != null) {
        await ffiService.dispose();
      } else {
        final historyPersistence = persistence;
        if (historyPersistence != null) {
          await historyPersistence.dispose();
        }
      }
      final root = tempRoot;
      if (root != null && await root.exists()) {
        await root.delete(recursive: true);
      }
      tempRoot = null;
      persistence = null;
      service = null;
      platform = null;
    });

    ChatMessage msg(int i, {String? kind}) {
      // Spread messages 1s apart so timestamps are stable.
      final ts = DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 1000);
      return ChatMessage(
        text: 'msg $i',
        fromUserId: peerId,
        isSelf: false,
        timestamp: ts,
        msgID: 'msgid_$i',
        mediaKind: kind,
      );
    }

    Future<void> seedHistory(List<ChatMessage> messages) async {
      final historyPersistence = persistence!;
      await historyPersistence.saveHistory(peerId, messages);
      historyPersistence.clearAllCached();
      final reloaded = await historyPersistence.loadHistory(peerId);
      expect(
        reloaded.map((message) => message.msgID),
        messages.map((message) => message.msgID),
      );
    }

    test('page 1 with count=5 returns the 5 newest messages descending',
        () async {
      final messages = List.generate(20, (i) => msg(i));
      await seedHistory(messages);

      final res = await platform!.getHistoryMessageListV2(
        userID: peerId,
        count: 5,
      );

      expect(res.code, 0);
      final list = res.data!.messageList;
      expect(list.length, 5);
      // Newest first: msg 19, 18, 17, 16, 15.
      for (var i = 0; i < 5; i++) {
        expect(list[i].msgID, 'msgid_${19 - i}');
      }
      expect(res.data!.isFinished, isFalse);
    });

    test(
        'pages stitched together with lastMsgID cover every message exactly '
        'once', () async {
      final messages = List.generate(13, (i) => msg(i));
      await seedHistory(messages);

      final firstPage = await platform!.getHistoryMessageListV2(
        userID: peerId,
        count: 5,
      );
      expect(firstPage.code, 0);
      expect(firstPage.data!.messageList.length, 5);

      final secondPage = await platform!.getHistoryMessageListV2(
        userID: peerId,
        count: 5,
        lastMsgID: firstPage.data!.messageList.last.msgID,
      );
      expect(secondPage.code, 0);
      expect(secondPage.data!.messageList.length, 5);

      final thirdPage = await platform!.getHistoryMessageListV2(
        userID: peerId,
        count: 5,
        lastMsgID: secondPage.data!.messageList.last.msgID,
      );
      expect(thirdPage.code, 0);
      expect(thirdPage.data!.messageList.length, 3);
      expect(thirdPage.data!.isFinished, isTrue);

      expect(
        firstPage.data!.messageList.map((message) => message.msgID).toList(),
        ['msgid_12', 'msgid_11', 'msgid_10', 'msgid_9', 'msgid_8'],
      );
      expect(
        secondPage.data!.messageList.map((message) => message.msgID).toList(),
        ['msgid_7', 'msgid_6', 'msgid_5', 'msgid_4', 'msgid_3'],
      );
      expect(
        thirdPage.data!.messageList.map((message) => message.msgID).toList(),
        ['msgid_2', 'msgid_1', 'msgid_0'],
      );

      final ids = <String?>{
        ...firstPage.data!.messageList.map((m) => m.msgID),
        ...secondPage.data!.messageList.map((m) => m.msgID),
        ...thirdPage.data!.messageList.map((m) => m.msgID),
      };
      expect(ids.length, 13);
      for (var i = 0; i < 13; i++) {
        expect(ids.contains('msgid_$i'), isTrue, reason: 'msgid_$i missing');
      }
    });

    test('filtering by message type still returns descending order',
        () async {
      // Mix of text and image; assert image-only page is sorted newest first.
      final messages = <ChatMessage>[
        msg(0, kind: 'image'),
        msg(1),
        msg(2, kind: 'image'),
        msg(3),
        msg(4, kind: 'image'),
      ];
      await seedHistory(messages);

      final res = await platform!.getHistoryMessageListV2(
        userID: peerId,
        count: 10,
        messageTypeList: [MessageElemType.V2TIM_ELEM_TYPE_IMAGE],
      );

      expect(res.code, 0);
      final list = res.data!.messageList;
      expect(list.length, 3);
      expect(list[0].msgID, 'msgid_4');
      expect(list[1].msgID, 'msgid_2');
      expect(list[2].msgID, 'msgid_0');
      expect(res.data!.isFinished, isTrue);
    });
  });
}
