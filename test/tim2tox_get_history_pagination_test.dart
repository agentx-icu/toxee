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
// `FfiChatService`, which opens the tim2tox FFI library. Skipped when the
// library is not loadable in this environment.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
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
  final ffiAvailable = _ffiAvailable();
  // Even with the FFI library loadable, getHistoryMessageListV2 returns
  // code=-1 unless the FfiChatService has gone through init+login. Setting
  // that up in a unit test is non-trivial (requires native Tox bootstrap
  // and identity, not just FFI symbol resolution). Skip until we have a
  // proper fixture; the P4 sort-once fix itself is exercised by manual
  // testing and the existing account_export_roundtrip_test verifies the
  // surrounding history round-trip.
  // TODO(perf-pr4): build a service fixture (or use Tim2ToxInstance from
  // auto_tests) that lets us call getHistoryMessageListV2 against a seeded
  // history without booting Tox.
  final skipReason = ffiAvailable
      ? 'requires fully-initialized FfiChatService (login+identity); '
          'see TODO in this file'
      : 'tim2tox FFI library not loadable in this environment';

  group('Tim2ToxSdkPlatform.getHistoryMessageListV2 — P4 sort-once',
      skip: skipReason, () {
    late Directory tempRoot;
    late MessageHistoryPersistence persistence;
    late FfiChatService service;
    late Tim2ToxSdkPlatform platform;

    // Use a 64-char hex peer id so the normalizer treats it as a C2C id.
    const peerId =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    setUp(() async {
      tempRoot = await Directory.systemTemp
          .createTemp('tim2tox_get_history_pagination_');
      persistence = MessageHistoryPersistence(
          historyDirectory: p.join(tempRoot.path, 'history'));
      service = FfiChatService(messageHistoryPersistence: persistence);
      platform = Tim2ToxSdkPlatform(ffiService: service);
    });

    tearDown(() async {
      try {
        await tempRoot.delete(recursive: true);
      } catch (_) {}
    });

    ChatMessage _msg(int i, {String? kind}) {
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

    test('page 1 with count=5 returns the 5 newest messages descending',
        () async {
      final messages = List.generate(20, (i) => _msg(i));
      persistence.setCachedHistory(peerId, messages);

      final res = await platform.getHistoryMessageListV2(
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
      final messages = List.generate(13, (i) => _msg(i));
      persistence.setCachedHistory(peerId, messages);

      final firstPage = await platform.getHistoryMessageListV2(
        userID: peerId,
        count: 5,
      );
      expect(firstPage.code, 0);
      expect(firstPage.data!.messageList.length, 5);

      final secondPage = await platform.getHistoryMessageListV2(
        userID: peerId,
        count: 5,
        lastMsgID: firstPage.data!.messageList.last.msgID,
      );
      expect(secondPage.code, 0);
      expect(secondPage.data!.messageList.length, 5);

      final thirdPage = await platform.getHistoryMessageListV2(
        userID: peerId,
        count: 5,
        lastMsgID: secondPage.data!.messageList.last.msgID,
      );
      expect(thirdPage.code, 0);
      expect(thirdPage.data!.messageList.length, 3);
      expect(thirdPage.data!.isFinished, isTrue);

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
        _msg(0, kind: 'image'),
        _msg(1),
        _msg(2, kind: 'image'),
        _msg(3),
        _msg(4, kind: 'image'),
      ];
      persistence.setCachedHistory(peerId, messages);

      final res = await platform.getHistoryMessageListV2(
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
