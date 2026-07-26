import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message diagnostics exclude payloads and local media paths', () {
    final sources = <String>[
      'lib/sdk_fake/fake_im.dart',
      'lib/sdk_fake/fake_managers.dart',
      'lib/sdk_fake/fake_msg_provider.dart',
      'lib/sdk_fake/fake_provider.dart',
      'lib/sdk_fake/fake_msg_provider_mapping.dart',
      'lib/sdk_fake/fake_msg_provider_routing.dart',
      'lib/sdk_fake/fake_msg_provider_file_progress.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    for (final leak in <String>[
      r'filePath=${m.filePath}',
      r'fileName=${m.fileName}',
      r'customElem.data=${msg.customElem?.data',
      r'path=${mappedImageElem.path}',
      r'localUrl=$effectiveLocalUrl',
      r'imageElem.path=${msg.imageElem!.path}',
      r'progress.path=${progress.path}',
      r'localUrl=${progress.path}',
      r'peer=${req.peerId}',
      r'for ${req.fileName}',
      r'path=$imagePath',
      r'path=$filePath',
      r'path=$videoPath',
      r'path=$soundPath',
      r'localUrl=${updatedMsg',
      r'msgID=${mappedMsg.msgID}',
      r'fromUser=${m.fromUser}',
      r'userID=$userID',
      r'local messages for $normalizedId',
      r'image attachment failed: $e',
      r'Error sending messageNeedUpdate: $e',
    ]) {
      expect(sources, isNot(contains(leak)), reason: leak);
    }

    final uikitUtils = File(
      'third_party/chat-uikit-flutter/tencent_cloud_chat_common/lib/utils/tencent_cloud_chat_utils.dart',
    ).readAsStringSync();
    expect(
      uikitUtils,
      isNot(contains('debugPrint(message.customElem!.toJson().toString())')),
    );
  });
}
