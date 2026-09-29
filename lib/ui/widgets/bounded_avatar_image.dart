import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_bounded_image.dart';

/// An avatar file decoded at the circle's physical size, keeping its aspect
/// ratio for `BoxFit.cover` (checklist M6).
///
/// Avatars are untrusted in size — a friend's avatar is auto-accepted up to
/// 10 MiB — and a full-resolution decode per row / per call screen is what
/// gets a low-memory phone killed. `ResizeImage` with both cacheWidth and
/// cacheHeight would bound memory too, but squashes a non-square image before
/// the cover crop; see [TencentCloudChatBoundedImage].
ImageProvider boundedAvatarImage(
  BuildContext context,
  String path,
  double logicalSize,
) => TencentCloudChatBoundedImage.file(
  path,
  logicalWidth: logicalSize,
  logicalHeight: logicalSize,
  devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
);
