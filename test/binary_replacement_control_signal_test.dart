// Control signals on the BINARY-REPLACEMENT inbound path.
//
// In the product a C2C message reaches the app through the native
// binary-replacement listener, NOT through `FfiChatService.messages`. The only
// `__revoke__:` handler used to live on the latter, so on the real path the
// signal was persisted as a literal `__revoke__:{…}` history row and the
// recalled message was never deleted on the receiver. That was reproduced live:
// the raw row was found verbatim in the peer's chat_history JSON while the
// real-UI `chat_recall_message` case reported `bGone=false`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/utils/binary_replacement_history_hook.dart';
import 'package:tim2tox_dart/utils/message_history_persistence.dart';

const _peer =
    'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
const _self =
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF';

V2TimMessage _textMessage(String text) {
  final m = V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT);
  m.msgID = 'binrep-${text.hashCode}';
  m.userID = _peer;
  m.sender = _peer;
  m.textElem = V2TimTextElem(text: text);
  m.timestamp = 1700000000;
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // V2TimMessage's constructor reaches into TIMManager.getServerTime(), which
  // dlopens the native SDK; point it at the tim2tox replacement like the other
  // SDK-touching unit tests do.
  setUpAll(() => setNativeLibraryName('tim2tox_ffi'));
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempRoot;
  late MessageHistoryPersistence persistence;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('binrep_control_');
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
    persistence = MessageHistoryPersistence(instanceId: 999401);
    BinaryReplacementHistoryHook.initialize(persistence, _self);
  });

  tearDown(() async {
    BinaryReplacementHistoryHook.applyInboundControlSignal = null;
    await BinaryReplacementHistoryHook.uninstallStandalone();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('a __revoke__ signal is routed to the applier, never persisted', () async {
    final applied = <({String text, String fromUserId, String? groupId})>[];
    BinaryReplacementHistoryHook.applyInboundControlSignal =
        ({
          required String text,
          required String fromUserId,
          String? groupId,
          bool isSelf = false,
        }) async {
          applied.add((text: text, fromUserId: fromUserId, groupId: groupId));
        };

    const signal = '__revoke__:{"msgID":"m1","textPrefix":"hi","textLen":2}';
    await BinaryReplacementHistoryHook.saveMessage(_textMessage(signal));

    expect(
      applied.map((a) => a.text),
      [signal],
      reason:
          'Regression: the binary-replacement path had no control-signal '
          'handler at all, so a recall arriving there was silently dropped.',
    );
    expect(applied.single.fromUserId, _peer);
    expect(
      persistence.getHistory(_peer).map((m) => m.text),
      isNot(contains(signal)),
      reason:
          'Regression: the raw control signal was persisted as displayable '
          'chat history — it was found verbatim in the peer chat_history JSON.',
    );
  });

  test('an ordinary text message is still persisted normally', () async {
    BinaryReplacementHistoryHook.applyInboundControlSignal =
        ({
          required String text,
          required String fromUserId,
          String? groupId,
          bool isSelf = false,
        }) async {
          fail('an ordinary message must not be treated as a control signal');
        };

    await BinaryReplacementHistoryHook.saveMessage(_textMessage('hello there'));

    expect(
      persistence.getHistory(_peer).map((m) => m.text),
      contains('hello there'),
      reason: 'the control-signal guard must not swallow real chat content',
    );
  });

  test(
    'a control signal is dropped, not persisted, when no applier is set',
    () async {
      BinaryReplacementHistoryHook.applyInboundControlSignal = null;
      const signal = '__revoke__:{"msgID":"m2"}';

      await BinaryReplacementHistoryHook.saveMessage(_textMessage(signal));

      expect(
        persistence.getHistory(_peer).map((m) => m.text),
        isNot(contains(signal)),
        reason: 'a missing handler must never degrade into showing raw JSON',
      );
    },
  );
}
