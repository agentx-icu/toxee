import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../i18n/app_localizations.dart';
import '../../sdk_fake/c2c_send_guard.dart';
import '../../sdk_fake/fake_uikit_core.dart';
import '../../util/ffi_chat_service_account_key.dart';
import '../../util/logger.dart';
import '../../util/tox_utils.dart';

/// The desktop composer's attachment toolbar (File, personal card, and —
/// while the account's Location switch is on — Location). Moved out of
/// HomePage so the toolbar's error handling no longer counts against the
/// page's complexity pin; HomePage supplies the callbacks.
List<TencentCloudChatMessageGeneralOptionItem> buildToxeeDesktopInputOptions(
  BuildContext context, {
  String? userID,
  String? groupID,
  required FfiChatService service,
  required Future<void> Function(BuildContext context,
      {String? userId, String? groupId})
  pickAndSendFile,
  required void Function(String message) showSnackBar,
  required Future<String> Function() createSelfQrCardImage,
  String? locationLabel,
  Future<void> Function()? onSendLocation,
}) {
    final appL10n = AppLocalizations.of(context)!;
    final fileLabel = appL10n.file;
    final personalCardLabel = appL10n.personalCard;
    final personalCardGroupLabel = appL10n.sendPersonalCardToGroup;
    final sentSnack = appL10n.personalCardSent;
    final sentGroupSnack = appL10n.sentPersonalCardToGroup;
    // toxee: desktop composer merges File / Photo / Video into a single "file"
    // button. `_sendMedia(type: file)` opens the OS picker with FileType.any, so
    // it already sends images, videos and every other file type — the separate
    // photo/video buttons were removed to declutter the desktop toolbar. Mobile
    // exposes File plus Camera, with camera results routed back through
    // [_sendMedia] so both surfaces share the same send/offline behavior.
    final options = <TencentCloudChatMessageGeneralOptionItem>[
      TencentCloudChatMessageGeneralOptionItem(
        icon: Icons.attach_file,
        label: fileLabel,
        onTap: ({Offset? offset}) async {
          await pickAndSendFile(context, userId: userID, groupId: groupID);
        },
      ),
    ];
    if (onSendLocation != null && locationLabel != null) {
      options.add(
        TencentCloudChatMessageGeneralOptionItem(
          icon: Icons.location_on_outlined,
          label: locationLabel,
          onTap: ({Offset? offset}) => onSendLocation(),
        ),
      );
    }
    if (userID != null) {
      options.add(
        TencentCloudChatMessageGeneralOptionItem(
          icon: Icons.qr_code_2,
          label: personalCardLabel,
          onTap: ({Offset? offset}) async {
            try {
              // Check if friend is online before sending
              final friends = await service.getFriendList();
              final friend = friends.firstWhere(
                (f) => f.userId == userID,
                orElse: () =>
                    (userId: userID, nickName: '', online: false, status: ''),
              );
              if (!friends.any((f) => f.userId == normalizeToxId(userID))) {
                showSnackBar(appL10n.userNotInFriendList);
                return;
              }
              if (!friend.online) {
                // Send a text message to chat window indicating failure (two lines: error + file path)
                final qrPath = await createSelfQrCardImage();
                final twoLineMsg =
                    '${appL10n.friendOfflineSendCardFailed}\n$qrPath';
                final mgr = FakeUIKit.instance.messageManager;
                await sendFailureNotice(mgr, 'c2c_$userID', twoLineMsg);
                return;
              }
              final qrPath = await createSelfQrCardImage();
              await service.sendFile(userID, qrPath);
              showSnackBar(sentSnack);
            } catch (e) {
              // Provide more user-friendly error messages
              final errorMsg = e.toString();
              String userMsg;
              if (errorMsg.contains('offline') ||
                  errorMsg.contains('not connected')) {
                // Send a text message to chat window indicating failure (two lines: error + file path)
                // Try to get the file path from the error or use a default message
                try {
                  final qrPath = await createSelfQrCardImage();
                  final twoLineMsg =
                      '${appL10n.friendOfflineSendCardFailed}\n$qrPath';
                  final mgr = FakeUIKit.instance.messageManager;
                  await sendFailureNotice(mgr, 'c2c_$userID', twoLineMsg);
                } catch (e, st) {
                  AppLogger.logError(
                    '[HomePage] Failed to create self QR card image for offline fallback',
                    e,
                    st,
                  );
                  await sendFailureNotice(
                    FakeUIKit.instance.messageManager,
                    'c2c_$userID',
                    appL10n.friendOfflineSendCardFailed,
                  );
                }
                userMsg = appL10n.friendOfflineCannotSendFile;
              } else if (errorMsg.contains('not in your friend list')) {
                userMsg = appL10n.userNotInFriendList;
              } else {
                // Extract error message without file path
                String errorText = e.toString();
                // Remove file path from error message if present
                if (errorText.contains('File does not exist')) {
                  errorText = appL10n.fileDoesNotExist;
                } else if (errorText.contains('File is empty')) {
                  errorText = appL10n.fileIsEmpty;
                } else if (errorText.contains(':')) {
                  // Remove path after colon (e.g., "Exception: /path/to/file")
                  final colonIndex = errorText.indexOf(':');
                  if (colonIndex > 0) {
                    final beforeColon = errorText.substring(0, colonIndex);
                    final afterColon = errorText
                        .substring(colonIndex + 1)
                        .trim();
                    // Check if after colon looks like a file path
                    if (afterColon.startsWith('/') ||
                        afterColon.contains('\\')) {
                      errorText = beforeColon;
                    }
                  }
                }
                userMsg = appL10n.sendFailed(errorText);
              }
              showSnackBar(userMsg);
            }
          },
        ),
      );
    } else if (groupID != null) {
      options.add(
        TencentCloudChatMessageGeneralOptionItem(
          icon: Icons.qr_code,
          label: personalCardGroupLabel,
          onTap: ({Offset? offset}) async {
            final appL10n = AppLocalizations.of(context)!;
            final text = '${appL10n.myId}: ${service.accountKey}';
            await service.sendGroupText(groupID, text);
            showSnackBar(sentGroupSnack);
          },
        ),
      );
    }
    return options;
  }
