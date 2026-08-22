import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';

import 'friend_request_display_name.dart';

class ContactApplicationItemContentOverride extends StatelessWidget {
  const ContactApplicationItemContentOverride({
    super.key,
    required this.application,
  });

  final V2TimFriendApplication application;

  bool get _hasNickname {
    return _displayName != application.userID;
  }

  String get _displayName {
    return resolveFriendRequestDisplayName(
      userId: application.userID,
      nickname: application.nickname,
      wording: application.addWording,
    );
  }

  String get _addWording => application.addWording?.trim() ?? '';

  /// A Tox public key is 64 hex chars; printed raw under the name it dominates
  /// the row and wraps mid-token on phones. Show a fingerprint (first 8 + last
  /// 6) — enough to match against the key the requester shared out-of-band —
  /// and keep the full key one hover/long-press away in a tooltip.
  static String abbreviateUserId(String id) {
    final trimmed = id.trim();
    if (trimmed.length <= 20) return trimmed;
    return '${trimmed.substring(0, 8)}…${trimmed.substring(trimmed.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: textStyle.fontsize_14,
                  fontWeight: FontWeight.w600,
                  color: colorTheme.contactItemFriendNameColor,
                ),
              ),
              if (_hasNickname) ...[
                const SizedBox(height: 2),
                Tooltip(
                  message: application.userID,
                  waitDuration: const Duration(milliseconds: 400),
                  child: Text(
                    abbreviateUserId(application.userID),
                    key: ValueKey(
                      'contact_application_userid:${application.userID}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: textStyle.fontsize_12,
                      fontFamily: 'monospace',
                      color: colorTheme.secondaryTextColor,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
              if (_addWording.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _addWording,
                  key: ValueKey(
                    'contact_application_addwording:${application.userID}',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorTheme.contactItemTabItemNameColor,
                    fontSize: textStyle.fontsize_12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
