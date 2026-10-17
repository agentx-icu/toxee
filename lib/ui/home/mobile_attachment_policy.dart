import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';

import '../../i18n/app_localizations.dart';

TencentCloudChatMessageAttachmentConfig buildToxeeMessageAttachmentConfig() {
  return TencentCloudChatMessageAttachmentConfig(
    enableSendMediaFromMobileGallery: false,
    enableSendImage: false,
    enableSendVideo: false,
    enableSendFile: false,
    enableSearch: false,
    mediaSendGuard: toxeeMediaSendGuard,
  );
}

/// Tox has no file transfer for groups (`tox_file_send` is friend-only), so
/// every media send into a group fails. The attach and camera buttons already
/// refuse up front (HomePage `_sendMedia`); this covers the entry points that
/// are not buttons — hold-to-record on mobile, drag & drop and clipboard paste
/// on desktop — which used to ask for the microphone / show a "send to
/// <group>?" confirmation and only then fail, leaving a red bubble and an
/// orphaned recording or scratch file behind.
bool toxeeMediaSendGuard(
  BuildContext context, {
  required String kind,
  String? userID,
  String? groupID,
}) {
  if (groupID == null || groupID.isEmpty) return true;
  final l10n = AppLocalizations.of(context);
  if (l10n != null) {
    final label = switch (kind) {
      'voice' => l10n.audio,
      'image' => l10n.photo,
      _ => l10n.file,
    };
    // Replace rather than queue: a forward to several groups asks once per
    // group, and N identical toasts would play back one after another.
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.sendingToGroupsNotSupported(label))),
      );
  }
  return false;
}

List<TencentCloudChatMessageGeneralOptionItem>
buildToxeeMobileAttachmentOptions({
  required String fileLabel,
  required String cameraLabel,
  required Future<void> Function() onFile,
  required Future<void> Function() onCamera,
  // Location message (F1): present only while the account's Location switch
  // is on, so nothing reads the position otherwise.
  String? locationLabel,
  Future<void> Function()? onLocation,
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
    if (onLocation != null && locationLabel != null)
      TencentCloudChatMessageGeneralOptionItem(
        icon: Icons.location_on_outlined,
        label: locationLabel,
        onTap: ({Offset? offset}) => onLocation(),
      ),
  ];
}

/// Message-list sender-name policy: group chats need sender attribution above
/// incoming bubbles — without it a multi-party thread is unreadable (avatars
/// alone don't identify the sender). 1:1 chats keep the name row off: the
/// header already names the only possible peer. The UIKit name row hides
/// itself for self-sent messages, so this only labels others' messages.
bool showSenderNameInGroupsOnly({
  String? userID,
  String? groupID,
  String? topicID,
}) => (groupID ?? '').isNotEmpty;

typedef ToxeeMobileAttachmentOptionsBuilder =
    List<TencentCloudChatMessageGeneralOptionItem> Function({
      String? userID,
      String? groupID,
      String? topicID,
    });

/// The `additionalAttachmentOptionsForMobile` closure HomePage installs into
/// the GLOBAL UIKit config. It outlives the HomePage, so every callback is
/// guarded at invocation time through [isMounted] / [contextOf] (a stale chat
/// rebuild once hit a defunct State.context: red screen on Android). The
/// Location option exists only while the account's Location switch is on.
ToxeeMobileAttachmentOptionsBuilder buildToxeeMobileAttachmentOptionsBuilder({
  required bool Function() isMounted,
  required BuildContext Function() contextOf,
  required bool Function() locationEnabled,
  required Future<void> Function(BuildContext context,
      {String? userId, String? groupId})
  onFile,
  required Future<void> Function(BuildContext context,
      {String? userId, String? groupId})
  onCamera,
  required Future<void> Function({String? userId, String? groupId}) onLocation,
}) {
  return ({String? userID, String? groupID, String? topicID}) {
    if (!isMounted()) return const [];
    final context = contextOf();
    final appL10n = AppLocalizations.of(context)!;
    final cameraLabel =
        TencentCloudChatLocalizations.of(context)?.camera ?? 'Camera';
    final withLocation = locationEnabled();
    return buildToxeeMobileAttachmentOptions(
      fileLabel: appL10n.file,
      cameraLabel: cameraLabel,
      onFile: () async {
        if (!isMounted()) return;
        await onFile(contextOf(), userId: userID, groupId: groupID);
      },
      onCamera: () async {
        if (!isMounted()) return;
        await onCamera(contextOf(), userId: userID, groupId: groupID);
      },
      locationLabel: withLocation ? appL10n.locationMessageLabel : null,
      onLocation: withLocation
          ? () async {
              if (!isMounted()) return;
              await onLocation(userId: userID, groupId: groupID);
            }
          : null,
    );
  };
}
