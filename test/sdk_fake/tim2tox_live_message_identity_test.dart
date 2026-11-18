import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform_converters.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

const _peer =
    'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

class _MessageStreamService extends FfiChatService {
  _MessageStreamService({
    required super.historyDirectory,
    required this.inboundRows,
  });

  final StreamController<ChatMessage>? inboundRows;

  @override
  Stream<ChatMessage> get messages => inboundRows?.stream ?? super.messages;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');
  final nativePath = Platform.environment['TOXEE_TEST_LOG_LIBRARY'];
  if (nativePath != null) setNativeLibraryPath(nativePath);
  bool nativeAvailable() {
    try {
      Tim2ToxFfi.open();
      return true;
    } catch (_) {
      return false;
    }
  }

  group('Platform live message identity', skip: !nativeAvailable(), () {
    final data = TencentCloudChat.instance.dataInstance.messageData;
    late _MessageStreamService service;
    late StreamController<V2TimMessage> events;

    Future<Tim2ToxSdkPlatform> connect({
      StreamController<ChatMessage>? inboundRows,
      void Function(FfiChatService)? beforeListening,
    }) async {
      final dir = await Directory.systemTemp.createTemp('live_msg_identity_');
      addTearDown(() => dir.delete(recursive: true));
      events = StreamController<V2TimMessage>.broadcast();
      addTearDown(events.close);
      final previousHandler = NativeLibraryManager.customCallbackHandler;
      service = _MessageStreamService(
        historyDirectory: dir.path,
        inboundRows: inboundRows,
      );
      beforeListening?.call(service);
      final platform = Tim2ToxSdkPlatform(ffiService: service);
      addTearDown(() async {
        platform.dispose();
        NativeLibraryManager.customCallbackHandler = previousHandler;
        data.messageListMap = {};
        await service.dispose();
      });
      await platform.addAdvancedMsgListener(
        listener: V2TimAdvancedMsgListener(
          onRecvNewMessage: (message) {
            data.onReceiveNewMessage(message);
            events.add(message);
          },
          onRecvMessageModified: (message) {
            data.onReceiveMessageModified(message);
            events.add(message);
          },
        ),
      );
      return platform;
    }

    Future<V2TimMessage> nextEvent() =>
        events.stream.first.timeout(const Duration(seconds: 5));

    test(
      'a receipt updates the older of two identical sent messages',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final platform = await connect(
          beforeListening: (service) {
            for (final timestamp in [now - 1000, now]) {
              service.ingestC2cText(
                peer: _peer,
                text: 'hello',
                isSelf: true,
                epochMs: timestamp,
              );
            }
          },
        );
        final sent = service.getHistory(_peer);
        final firstId = sent.first.msgID;
        final secondId = sent.last.msgID;
        data.updateMessageList(
          userID: _peer,
          messageList: [
            for (final row in sent)
              platform.chatMessageToV2TimMessage(
                row,
                '',
                forwardTargetUserID: _peer,
              ),
          ],
        );

        final receipt = jsonEncode({
          'type': 'receipt',
          'msgID': firstId,
          'receiptType': 'read',
          'sender': _peer,
        });
        final bytes = [
          1,
          ...utf8.encode(receipt),
        ].map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
        final receiptEcho = nextEvent();
        expect(service.ingestC2cBinaryEvent('c2cbin:$_peer:$bytes'), isTrue);
        expect((await receiptEcho).msgID, firstId);
        final rows = data.getMessageList(key: _peer);
        expect(rows.map((m) => m.msgID), [secondId, firstId]);
        expect(rows.first.isPeerRead, isNot(true));
        expect(rows.last.isPeerRead, isTrue);

        final thirdEcho = nextEvent();
        service.ingestC2cText(
          peer: _peer,
          text: 'hello',
          isSelf: true,
          epochMs: now + 1000,
        );
        final thirdId = (await thirdEcho).msgID;
        expect(data.getMessageList(key: _peer).map((m) => m.msgID), [
          thirdId,
          secondId,
          firstId,
        ]);
      },
    );

    test(
      'same-name incoming files keep separate callback identities',
      () async {
        final input = StreamController<ChatMessage>();
        addTearDown(input.close);
        await connect(inboundRows: input);
        final now = DateTime.now();
        ChatMessage file(int n, {bool completed = false}) => ChatMessage(
          text: '',
          fromUserId: _peer,
          isSelf: false,
          timestamp: now,
          msgID: '${now.millisecondsSinceEpoch}_${n}_$_peer',
          mediaKind: 'file',
          fileName: 'report.pdf',
          filePath: completed
              ? '/completed/$n/report.pdf'
              : '/tmp/receiving_$n',
          isPending: !completed,
        );
        for (final row in [file(1), file(2), file(1, completed: true)]) {
          final echo = nextEvent();
          input.add(row);
          expect((await echo).msgID, row.msgID);
        }
        final rows = data.getMessageList(key: _peer);
        expect(rows, hasLength(2));
        final byId = {for (final row in rows) row.msgID: row};
        expect(byId.keys, unorderedEquals([file(1).msgID, file(2).msgID]));
        expect(byId[file(1).msgID]?.fileElem?.path, '/completed/1/report.pdf');
        expect(byId[file(2).msgID]?.fileElem?.path, '/tmp/receiving_2');
      },
    );

    test('a native callback and its matching poll copy reconcile', () async {
      final input = StreamController<ChatMessage>();
      addTearDown(input.close);
      final platform = await connect(inboundRows: input);
      final now = DateTime.now();
      final row = ChatMessage(
        text: 'hello',
        fromUserId: _peer,
        isSelf: false,
        timestamp: now,
        msgID: '${now.millisecondsSinceEpoch}_1_$_peer',
      );
      data.onReceiveNewMessage(
        platform.chatMessageToV2TimMessage(row, '')
          ..msgID = 'msg_1_10_1'
          ..id = 'msg_1_10_1',
      );

      final echo = nextEvent();
      input.add(row);
      expect((await echo).msgID, row.msgID);
      expect(data.getMessageList(key: _peer).map((m) => m.msgID), [row.msgID]);
    });
  });
}
