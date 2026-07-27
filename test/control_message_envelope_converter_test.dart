import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform_converters.dart';
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

ChatMessage _historyMessage(String text, {String? mediaKind}) {
  return ChatMessage(
    text: text,
    fromUserId: 'peer',
    isSelf: false,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    msgID: 'history-message',
    mediaKind: mediaKind,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('control envelope cold-history conversion', () {
    late Directory tempRoot;
    late FfiChatService service;
    late Tim2ToxSdkPlatform platform;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'control_message_envelope_converter_test_',
      );
      service = FfiChatService(
        historyDirectory: '${tempRoot.path}/history',
        queueFilePath: '${tempRoot.path}/offline_queue.json',
      );
      platform = Tim2ToxSdkPlatform(ffiService: service);
    });

    tearDown(() async {
      platform.dispose();
      await service.dispose();
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('restores face envelope as a face element', () {
      final converted = platform.chatMessageToV2TimMessage(
        _historyMessage('__face__:{"index":7,"data":"smile"}'),
        'self',
      );

      expect(converted.elemType, MessageElemType.V2TIM_ELEM_TYPE_FACE);
      expect(converted.faceElem?.index, 7);
      expect(converted.faceElem?.data, 'smile');
      expect(converted.textElem, isNull);
    }, skip: skipReason);

    test('restores location envelope as a location element', () {
      final converted = platform.chatMessageToV2TimMessage(
        _historyMessage(
          '__location__:{"desc":"park","longitude":1.5,"latitude":2.5}',
        ),
        'self',
      );

      expect(converted.elemType, MessageElemType.V2TIM_ELEM_TYPE_LOCATION);
      expect(converted.locationElem?.desc, 'park');
      expect(converted.locationElem?.longitude, 1.5);
      expect(converted.locationElem?.latitude, 2.5);
      expect(converted.textElem, isNull);
    }, skip: skipReason);

    test('preserves opaque custom suffix as custom element data', () {
      final converted = platform.chatMessageToV2TimMessage(
        _historyMessage('__custom__:opaque-v1:AAECAw=='),
        'self',
      );

      expect(converted.elemType, MessageElemType.V2TIM_ELEM_TYPE_CUSTOM);
      expect(converted.customElem?.data, 'opaque-v1:AAECAw==');
      expect(converted.textElem, isNull);
    }, skip: skipReason);

    test('keeps malformed structured envelope as plain text', () {
      const original = '__face__:not-json';
      final converted = platform.chatMessageToV2TimMessage(
        _historyMessage(original),
        'self',
      );

      expect(converted.elemType, MessageElemType.V2TIM_ELEM_TYPE_TEXT);
      expect(converted.textElem?.text, original);
      expect(converted.faceElem, isNull);
    }, skip: skipReason);

    test(
      'preserves direct custom media payloads without envelope parsing',
      () {
        final converted = platform.chatMessageToV2TimMessage(
          _historyMessage('direct-custom-data', mediaKind: 'custom'),
          'self',
        );

        expect(converted.elemType, MessageElemType.V2TIM_ELEM_TYPE_CUSTOM);
        expect(converted.customElem?.data, 'direct-custom-data');
      },
      skip: skipReason,
    );

    test('does not parse envelope-looking direct custom media data', () {
      const rawCustomData = '__face__:{"index":7,"data":"not-an-envelope"}';
      final converted = platform.chatMessageToV2TimMessage(
        _historyMessage(rawCustomData, mediaKind: 'custom'),
        'self',
      );

      expect(converted.elemType, MessageElemType.V2TIM_ELEM_TYPE_CUSTOM);
      expect(converted.customElem?.data, rawCustomData);
      expect(converted.faceElem, isNull);
    }, skip: skipReason);
  });

  group('control envelope live conversion', () {
    late Directory tempRoot;
    late FfiChatService service;
    late Tim2ToxSdkPlatform platform;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'control_message_envelope_live_test_',
      );
      service = FfiChatService(
        historyDirectory: '${tempRoot.path}/history',
        queueFilePath: '${tempRoot.path}/offline_queue.json',
      );
      platform = Tim2ToxSdkPlatform(ffiService: service);
    });

    tearDown(() async {
      platform.dispose();
      await service.dispose();
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    Future<V2TimMessage> ingest(String text) async {
      final received = Completer<V2TimMessage>();
      final listener = V2TimAdvancedMsgListener(
        onRecvNewMessage: (message) {
          if (!received.isCompleted) {
            received.complete(message);
          }
        },
      );
      await platform.addAdvancedMsgListener(listener: listener);
      final accepted = service.ingestInboundGroupText(
        gid: 'live-group',
        from: 'peer',
        text: text,
      );
      expect(accepted, isTrue);
      return received.future.timeout(const Duration(seconds: 2));
    }

    test('emits face without legacy placeholder elements', () async {
      final converted = await ingest('__face__:{"index":7,"data":"smile"}');

      expect(converted.elemType, MessageElemType.V2TIM_ELEM_TYPE_FACE);
      expect(converted.faceElem?.index, 7);
      expect(converted.faceElem?.data, 'smile');
      expect(converted.textElem, isNull);
      expect(converted.customElem, isNull);
    }, skip: skipReason);

    test('emits location without legacy placeholder elements', () async {
      final converted = await ingest(
        '__location__:{"desc":"park","longitude":1.5,"latitude":2.5}',
      );

      expect(converted.elemType, MessageElemType.V2TIM_ELEM_TYPE_LOCATION);
      expect(converted.locationElem?.desc, 'park');
      expect(converted.locationElem?.longitude, 1.5);
      expect(converted.locationElem?.latitude, 2.5);
      expect(converted.textElem, isNull);
      expect(converted.customElem, isNull);
    }, skip: skipReason);

    test('emits opaque custom suffix as custom data', () async {
      final converted = await ingest('__custom__:opaque-v1:AAECAw==');

      expect(converted.elemType, MessageElemType.V2TIM_ELEM_TYPE_CUSTOM);
      expect(converted.customElem?.data, 'opaque-v1:AAECAw==');
      expect(converted.textElem, isNull);
    }, skip: skipReason);
  });
}
