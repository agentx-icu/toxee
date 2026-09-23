// Group-review 2026-09-17 GH-4 / GH-6 / GH-9 across the two inbound paths.
//
// Native contract: an inbound NGC group message delivered to the advanced
// listener carries `message_custom_str` (-> V2TimMessage.localCustomData)
// `{"toxGroupMsgId":<uint32>}`, the same value the polled `gtext:` header
// carries as `|m<id>`. MessageConverter stamps the resulting
// `gmid:<gid>|<SENDER>|<id>` alias, so the hook, appendHistory and the
// FfiChatService poll dedupe all match the two copies EXACTLY, and two
// genuine identical messages ("ok", "ok" 500 ms apart) stay two rows.
//
// FFI dependency: `V2TimMessage`'s constructor and `FfiChatService` reach the
// native library; skipped when it is not loadable (same as
// `tim2tox_binary_replacement_hook_generation_test.dart`).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/utils/binary_replacement_history_hook.dart';
import 'package:tim2tox_dart/utils/message_converter.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

const _gid = '1122334455667788990011223344556677889900112233445566778899001122';
// Per-group peer key as the native layer hex-encodes it (both the V2TIM
// sender and the gtext header use the same string).
const _peer =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _self = 'SELF';

bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

V2TimMessage _groupText({
  required String msgID,
  required String text,
  int? toxGroupMsgId,
  int? seconds,
}) {
  final msg = V2TimMessage(
    msgID: msgID,
    groupID: _gid,
    userID: _peer,
    sender: _peer,
    isSelf: false,
    elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    timestamp: seconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    localCustomData:
        toxGroupMsgId == null ? '' : '{"toxGroupMsgId":$toxGroupMsgId}',
  );
  msg.textElem = V2TimTextElem(text: text);
  return msg;
}

String _alias(int id) =>
    FfiChatService.groupMessageAlias(groupId: _gid, senderPk: _peer, pseudoMsgId: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('t2t_group_identity_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      switch (call.method) {
        case 'getApplicationSupportDirectory':
        case 'getApplicationDocumentsDirectory':
          return tempRoot.path;
        case 'getApplicationCacheDirectory':
          return '${tempRoot.path}/cache';
        case 'getTemporaryDirectory':
          return '${tempRoot.path}/temp';
        case 'getDownloadsDirectory':
          return '${tempRoot.path}/downloads';
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    await BinaryReplacementHistoryHook.uninstallStandalone();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  MessageHistoryPersistence newPersistence() {
    final persistence = MessageHistoryPersistence(
        historyDirectory: '${tempRoot.path}/history');
    addTearDown(persistence.dispose);
    return persistence;
  }

  FfiChatService newService(MessageHistoryPersistence persistence) {
    final service = FfiChatService(messageHistoryPersistence: persistence);
    service.debugSetSelfId(_self);
    addTearDown(service.dispose);
    return service;
  }

  group('MessageConverter', skip: skipReason, () {
    test('stamps the group alias from localCustomData (native contract)', () {
      final chat = MessageConverter.v2TimMessageToChatMessage(
          _groupText(msgID: 'msg_0_1_1', text: 'ok', toxGroupMsgId: 77), _self);
      expect(chat.altMsgIds, [_alias(77)]);
      expect(chat.altMsgIds.single, startsWith('gmid:$_gid|EEEE'),
          reason: 'sender key upper-cased exactly like the poll path');

      final legacy = MessageConverter.v2TimMessageToChatMessage(
          _groupText(msgID: 'msg_0_1_2', text: 'ok'), _self);
      expect(legacy.altMsgIds, isEmpty);

      final c2c = V2TimMessage(
        msgID: 'msg_0_1_3',
        userID: _peer,
        sender: _peer,
        elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        localCustomData: '{"toxGroupMsgId":5}',
      )..textElem = V2TimTextElem(text: 'x');
      expect(MessageConverter.v2TimMessageToChatMessage(c2c, _self).altMsgIds,
          isEmpty,
          reason: 'only group messages carry a group identity');
    });

    test('GH-6: whole-second native stamp refined to the receive instant', () {
      final msg = _groupText(msgID: 'm', text: 't', seconds: 1700000000);
      DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);
      expect(MessageConverter.timestampOf(msg, at(1700000000700)),
          at(1700000000700));
      expect(MessageConverter.timestampOf(msg, at(1700000001400)),
          at(1700000000999),
          reason: 'clamped into the native second');
      expect(MessageConverter.timestampOf(msg, at(1700000090000)),
          at(1700000000000),
          reason: 'not a live delivery: keep the native second');
    });

    test('GH-6: self (ms) + inbound (s) in the same second keep order on reload',
        () async {
      final persistence = newPersistence();
      final expected = <String>[];
      for (var i = 0; i < 40; i++) {
        final second = 1700000000 + i ~/ 10;
        if (i.isEven) {
          final self = ChatMessage(
            text: 'self $i',
            fromUserId: _self,
            isSelf: true,
            groupId: _gid,
            timestamp:
                DateTime.fromMillisecondsSinceEpoch(second * 1000 + i * 10),
            msgID: 'self_$i',
          );
          expected.add(self.msgID!);
          // ignore: unawaited_futures
          persistence.appendHistory(_gid, self);
        } else {
          final inbound = MessageConverter.v2TimMessageToChatMessage(
            _groupText(
                msgID: 'msg_0_9_$i',
                text: 'in $i',
                toxGroupMsgId: 1000 + i,
                seconds: second),
            _self,
            receivedAt:
                DateTime.fromMillisecondsSinceEpoch(second * 1000 + i * 10 + 5),
          );
          expected.add(inbound.msgID!);
          // ignore: unawaited_futures
          persistence.appendHistory(_gid, inbound);
        }
      }
      await persistence.flushPendingSaves();
      final reloaded = MessageHistoryPersistence(
          historyDirectory: '${tempRoot.path}/history');
      addTearDown(reloaded.dispose);
      expect((await reloaded.loadHistory(_gid)).map((m) => m.msgID), expected);
    });
  });

  group('BinaryReplacementHistoryHook identity dedupe', skip: skipReason, () {
    test('"ok" twice 500 ms apart with distinct ids -> 2 rows; cross-path '
        'copy of the first -> still 2 rows', () async {
      final persistence = newPersistence();
      BinaryReplacementHistoryHook.initialize(persistence, _self);
      await BinaryReplacementHistoryHook.saveMessage(
          _groupText(msgID: 'msg_0_1_1', text: 'ok', toxGroupMsgId: 1));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await BinaryReplacementHistoryHook.saveMessage(
          _groupText(msgID: 'msg_0_1_2', text: 'ok', toxGroupMsgId: 2));
      expect(persistence.getHistory(_gid).map((m) => m.msgID),
          ['msg_0_1_1', 'msg_0_1_2']);

      // A second delivery of message 1 under another id (the other path).
      await BinaryReplacementHistoryHook.saveMessage(
          _groupText(msgID: 'msg_0_1_9', text: 'ok', toxGroupMsgId: 1));
      final rows = persistence.getHistory(_gid);
      expect(rows, hasLength(2));
      expect(rows.first.altMsgIds, contains('msg_0_1_9'),
          reason: 'GH-9: the dropped copy id stays resolvable');
    });

    test('alias-less legacy delivery keeps the 2 s content window', () async {
      final persistence = newPersistence();
      BinaryReplacementHistoryHook.initialize(persistence, _self);
      // Pinned timestamps: taking them from the clock made this depend on the
      // two saves landing inside the 2s window, which a loaded full-suite run
      // does not guarantee.
      const sentAt = 1700000000;
      await BinaryReplacementHistoryHook.saveMessage(
          _groupText(msgID: 'msg_0_2_1', text: 'ok', seconds: sentAt));
      await BinaryReplacementHistoryHook.saveMessage(
          _groupText(msgID: 'msg_0_2_2', text: 'ok', seconds: sentAt + 1));
      expect(persistence.getHistory(_gid), hasLength(1));
    });
  });

  group('FfiChatService poll path identity dedupe', skip: skipReason, () {
    test('distinct pseudo ids -> 2 rows and 2 unread; same id twice -> 1 row',
        () async {
      final persistence = newPersistence();
      final service = newService(persistence);
      await service.registerJoinedGroupState(_gid);
      expect(
          service.ingestInboundGroupText(
              gid: _gid, from: _peer, text: 'ok', pseudoMsgId: 11),
          isTrue);
      expect(
          service.ingestInboundGroupText(
              gid: _gid, from: _peer, text: 'ok', pseudoMsgId: 12),
          isTrue);
      service.ingestInboundGroupText(
          gid: _gid, from: _peer, text: 'ok', pseudoMsgId: 11);
      final rows = persistence.getHistory(_gid);
      expect(rows, hasLength(2));
      expect(rows.map(toxGroupMessageAliasOf), [_alias(11), _alias(12)]);
      expect(service.getUnreadOf(_gid), 2);
    });

    test('hook first, then poll: exact merge, both "ok" rows counted',
        () async {
      final persistence = newPersistence();
      final service = newService(persistence);
      await service.registerJoinedGroupState(_gid);
      BinaryReplacementHistoryHook.initialize(persistence, _self);

      await BinaryReplacementHistoryHook.saveMessage(
          _groupText(msgID: 'msg_0_3_1', text: 'ok', toxGroupMsgId: 21));
      service.ingestInboundGroupText(
          gid: _gid, from: _peer, text: 'ok', pseudoMsgId: 21);
      await BinaryReplacementHistoryHook.saveMessage(
          _groupText(msgID: 'msg_0_3_2', text: 'ok', toxGroupMsgId: 22));
      service.ingestInboundGroupText(
          gid: _gid, from: _peer, text: 'ok', pseudoMsgId: 22);

      expect(persistence.getHistory(_gid).map((m) => m.msgID),
          ['msg_0_3_1', 'msg_0_3_2']);
      expect(service.getUnreadOf(_gid), 2,
          reason: 'the second genuine "ok" was treated as already reflected');
    });

    test('GH-9: poll first, then hook; markRead + delete by the native id',
        () async {
      final persistence = newPersistence();
      final service = newService(persistence);
      await service.registerJoinedGroupState(_gid);
      BinaryReplacementHistoryHook.initialize(persistence, _self);

      service.ingestInboundGroupText(
          gid: _gid, from: _peer, text: 'hi', pseudoMsgId: 31);
      await BinaryReplacementHistoryHook.saveMessage(
          _groupText(msgID: 'msg_native_31', text: 'hi', toxGroupMsgId: 31));

      var rows = persistence.getHistory(_gid);
      expect(rows, hasLength(1));
      expect(rows.single.altMsgIds, containsAll(['msg_native_31', _alias(31)]));
      expect(rows.single.isRead, isFalse);

      await service.markMessageAsRead(_peer, 'msg_native_31', groupID: _gid);
      rows = persistence.getHistory(_gid);
      expect(rows.single.isRead, isTrue,
          reason: 'markMessageAsRead must resolve the absorbed native id');

      expect(await persistence.removeMessage(_gid, 'msg_native_31'), isTrue);
      expect(persistence.getHistory(_gid), isEmpty);
    });
  });
}
