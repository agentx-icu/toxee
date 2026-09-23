// GT-4: the native ReceiveNewMessage fan-out must apply the text-control-
// envelope contract before it reaches UIKit listeners.
//
// In the product every native globalCallback carries `instance_id` (0 for the
// default instance; json_parser.cpp BuildGlobalCallbackJson), so
// NativeLibraryManager._handleGlobalCallback always hands it to
// Tim2ToxSdkPlatform.dispatchInstanceGlobalCallback first, whose
// ReceiveNewMessage branch feeds the platform's advanced-message listeners —
// the ones the UIKit registers (V2TIMMessageManager.addAdvancedMsgListener is
// platform-routed). This drives that exact entry point with the native JSON
// shape (`message_elem_array` / `text_elem_content`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_imsdk_bindings_generated.dart'
    show GlobalCallbackType;
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

Map<String, dynamic> _nativeTextCallback(String text) => <String, dynamic>{
      'callback': 'globalCallback',
      'callbackType': GlobalCallbackType.ReceiveNewMessage.value,
      'instance_id': 0,
      'json_msg_array': [
        <String, dynamic>{
          'message_msg_id': 'native-1',
          'message_sender': 'peer',
          'message_conv_id': 'peer',
          'message_conv_type': 1,
          'message_is_from_self': false,
          'message_elem_array': [
            <String, dynamic>{'elem_type': 0, 'text_elem_content': text},
          ],
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('native ReceiveNewMessage fan-out', () {
    late Directory tempRoot;
    late FfiChatService service;
    late Tim2ToxSdkPlatform platform;
    late List<V2TimMessage> received;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('native_fanout_env_');
      service = FfiChatService(
        historyDirectory: '${tempRoot.path}/history',
        queueFilePath: '${tempRoot.path}/offline_queue.json',
      );
      platform = Tim2ToxSdkPlatform(ffiService: service);
      received = <V2TimMessage>[];
      await platform.addAdvancedMsgListener(
        listener: V2TimAdvancedMsgListener(onRecvNewMessage: received.add),
      );
    });

    tearDown(() async {
      platform.dispose();
      await service.dispose();
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    Future<void> dispatch(String text) async {
      platform.dispatchInstanceGlobalCallback(
        0,
        GlobalCallbackType.ReceiveNewMessage.value,
        _nativeTextCallback(text),
      );
      await pumpEventQueue();
    }

    test('a __revoke__ command reaches no listener', () async {
      await dispatch('__revoke__:{"msgID":"x","textPrefix":"secret","textLen":6}');
      expect(received, isEmpty);
    }, skip: skipReason);

    test('a __face__ envelope arrives as a FACE element, not raw text',
        () async {
      await dispatch('__face__:{"index":7,"data":"smile"}');
      expect(received, hasLength(1));
      final msg = received.single;
      expect(msg.elemType, MessageElemType.V2TIM_ELEM_TYPE_FACE);
      expect(msg.faceElem?.index, 7);
      expect(msg.faceElem?.data, 'smile');
      expect(msg.textElem, isNull);
      expect(msg.elemList.first, same(msg.faceElem));
    }, skip: skipReason);

    test('a __location__ envelope arrives as a LOCATION element', () async {
      await dispatch(
          '__location__:{"desc":"park","longitude":1.5,"latitude":2.5}');
      expect(received, hasLength(1));
      expect(received.single.elemType,
          MessageElemType.V2TIM_ELEM_TYPE_LOCATION);
      expect(received.single.locationElem?.desc, 'park');
      expect(received.single.textElem, isNull);
    }, skip: skipReason);

    test('a __custom__ envelope arrives as a CUSTOM element', () async {
      await dispatch('__custom__:opaque-v1');
      expect(received, hasLength(1));
      expect(received.single.elemType, MessageElemType.V2TIM_ELEM_TYPE_CUSTOM);
      expect(received.single.customElem?.data, 'opaque-v1');
    }, skip: skipReason);

    test('plain text is delivered unchanged', () async {
      await dispatch('hello');
      expect(received, hasLength(1));
      expect(received.single.elemType, MessageElemType.V2TIM_ELEM_TYPE_TEXT);
      expect(received.single.textElem?.text, 'hello');
    }, skip: skipReason);
  });
}
