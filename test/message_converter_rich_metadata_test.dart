import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_face_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_file_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_location_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/utils/message_converter.dart';

bool _ffiAvailable() {
  try {
    setNativeLibraryName('tim2tox_ffi');
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

V2TimMessage _message(int elemType) {
  return V2TimMessage(
    elemType: elemType,
    sender: 'peer',
    msgID: 'binary-message',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('MessageConverter binary-replacement metadata', () {
    test('encodes face as the shared text envelope', () {
      final source = _message(MessageElemType.V2TIM_ELEM_TYPE_FACE)
        ..faceElem = V2TimFaceElem(index: 7, data: 'smile');

      final converted = MessageConverter.v2TimMessageToChatMessage(
        source,
        'self',
      );

      expect(
        converted.text,
        '__face__:${jsonEncode({'index': 7, 'data': 'smile'})}',
      );
      expect(converted.mediaKind, isNull);
    }, skip: skipReason);

    test('encodes location as the shared text envelope', () {
      final source = _message(MessageElemType.V2TIM_ELEM_TYPE_LOCATION)
        ..locationElem = V2TimLocationElem(
          desc: 'park',
          longitude: 1.5,
          latitude: 2.5,
        );

      final converted = MessageConverter.v2TimMessageToChatMessage(
        source,
        'self',
      );

      expect(
        converted.text,
        '__location__:${jsonEncode({'desc': 'park', 'longitude': 1.5, 'latitude': 2.5})}',
      );
      expect(converted.mediaKind, isNull);
    }, skip: skipReason);

    test('preserves typed custom data without envelope parsing', () {
      const raw = '__face__:{"index":7,"data":"opaque"}';
      final source = _message(MessageElemType.V2TIM_ELEM_TYPE_CUSTOM)
        ..customElem = V2TimCustomElem(data: raw, desc: '', extension: '');

      final converted = MessageConverter.v2TimMessageToChatMessage(
        source,
        'self',
      );

      expect(converted.text, raw);
      expect(converted.mediaKind, 'custom');
    }, skip: skipReason);

    test('preserves cloud metadata and file size', () {
      const cloud = '{"messageReply":{"messageID":"quoted"}}';
      final source = _message(MessageElemType.V2TIM_ELEM_TYPE_FILE)
        ..fileElem = V2TimFileElem(
          path: '/tmp/file.bin',
          fileName: 'file.bin',
          fileSize: 123,
        )
        ..cloudCustomData = cloud;

      final converted = MessageConverter.v2TimMessageToChatMessage(
        source,
        'self',
      );

      expect(converted.fileSize, 123);
      expect(converted.cloudCustomData, cloud);
    }, skip: skipReason);
  });
}
