import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';

TencentCloudChatMessageAttachmentConfig buildToxeeMessageAttachmentConfig() {
  return TencentCloudChatMessageAttachmentConfig(
    enableSendMediaFromMobileGallery: false,
    enableSendImage: false,
    enableSendVideo: false,
    enableSendFile: false,
    enableSearch: false,
  );
}

List<TencentCloudChatMessageGeneralOptionItem>
buildToxeeMobileAttachmentOptions({
  required String fileLabel,
  required String cameraLabel,
  required Future<void> Function() onFile,
  required Future<void> Function() onCamera,
}) {
  return <TencentCloudChatMessageGeneralOptionItem>[
    TencentCloudChatMessageGeneralOptionItem(
      icon: Icons.attach_file,
      label: fileLabel,
      onTap: ({Offset? offset}) => onFile(),
    ),
    TencentCloudChatMessageGeneralOptionItem(
      icon: Icons.camera_alt_outlined,
      label: cameraLabel,
      onTap: ({Offset? offset}) => onCamera(),
    ),
  ];
}
