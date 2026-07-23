// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_camera.dart';
import 'package:toxee/ui/home/mobile_attachment_policy.dart';
import 'package:toxee/ui/home/tim2tox_plugin_policy.dart';

void main() {
  test(
    'toxee mobile attachments replace Album/Photo/Video with File/Camera',
    () {
      final config = buildToxeeMessageAttachmentConfig();
      expect(config.enableSendMediaFromMobileGallery, isFalse);
      expect(config.enableSendImage, isFalse);
      expect(config.enableSendVideo, isFalse);
      expect(config.enableSendFile, isFalse);

      final invoked = <String>[];
      final options = buildToxeeMobileAttachmentOptions(
        fileLabel: 'File',
        cameraLabel: 'Camera',
        onFile: () async => invoked.add('file'),
        onCamera: () async => invoked.add('camera'),
      );

      expect(options.map((option) => option.label), ['File', 'Camera']);
      expect(options.map((option) => option.icon), [
        Icons.attach_file,
        Icons.camera_alt_outlined,
      ]);

      options[0].onTap();
      options[1].onTap();
      expect(invoked, ['file', 'camera']);
    },
  );

  test('camera picker cancellation never dispatches an empty send path', () {
    final images = <String>[];
    final videos = <String>[];

    dispatchCameraPickerResult(
      path: null,
      isVideo: false,
      onSendImage: ({required imagePath}) => images.add(imagePath),
      onSendVideo: ({required videoPath}) => videos.add(videoPath),
    );
    dispatchCameraPickerResult(
      path: '',
      isVideo: true,
      onSendImage: ({required imagePath}) => images.add(imagePath),
      onSendVideo: ({required videoPath}) => videos.add(videoPath),
    );

    expect(images, isEmpty);
    expect(videos, isEmpty);

    dispatchCameraPickerResult(
      path: '/tmp/photo.jpg',
      isVideo: false,
      onSendImage: ({required imagePath}) => images.add(imagePath),
      onSendVideo: ({required videoPath}) => videos.add(videoPath),
    );
    dispatchCameraPickerResult(
      path: '/tmp/video.mp4',
      isVideo: true,
      onSendImage: ({required imagePath}) => images.add(imagePath),
      onSendVideo: ({required videoPath}) => videos.add(videoPath),
    );

    expect(images, ['/tmp/photo.jpg']);
    expect(videos, ['/tmp/video.mp4']);
  });

  test('tim2tox without an STT backend never registers soundToText', () {
    var addCalls = 0;

    final handled = registerTim2toxSoundToTextIfSupported(
      backendSupported: false,
      alreadyRegistered: false,
      pluginExists: false,
      addPlugin: () => addCalls++,
    );

    expect(handled, isFalse);
    expect(addCalls, 0);
  });
}
