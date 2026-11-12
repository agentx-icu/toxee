import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_data_tools.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

import '../i18n/app_localizations.dart';
import '../util/prefs.dart';
import 'location_permission_helper.dart';
import 'location_source.dart';

enum LocationSendOutcome { sent, disabled, permissionDenied, noFix, failed }

/// F1 — send my current position as a location message, to a friend or a
/// group. Its own path: it does not go through the media helper (whose group
/// guard stays). Order: master switch → permission → one fix → the SDK's own
/// `createLocationMessage` (pure Dart on native) → the UIKit
/// `TencentCloudChatMessageDataTools.sendMessage`, which inserts the
/// optimistic row and calls the platform `sendMessage(id, …)` where the
/// existing `__location__:` envelope is serialised.
class LocationSender {
  LocationSender({
    required LocationSource source,
    required Future<String?> Function() currentToxId,
    required bool Function() isSessionCurrent,
    LocationPermissionHelper? permissions,
    Future<LocationSendOutcome> Function(
      LocationFix fix,
      String? userID,
      String? groupID,
    )?
    dispatch,
  }) : _source = source,
       _currentToxId = currentToxId,
       _isSessionCurrent = isSessionCurrent,
       _permissions = permissions ?? LocationPermissionHelper(source),
       _dispatch = dispatch;

  final LocationSource _source;
  final Future<String?> Function() _currentToxId;
  final bool Function() _isSessionCurrent;
  final LocationPermissionHelper _permissions;

  /// The actual send (test seam; production goes through the UIKit).
  final Future<LocationSendOutcome> Function(
    LocationFix fix,
    String? userID,
    String? groupID,
  )?
  _dispatch;

  /// Formats a fix for the bubble label: `39.9042, 116.4074`.
  static String describe(LocationFix fix) =>
      '${fix.latitude.toStringAsFixed(4)}, ${fix.longitude.toStringAsFixed(4)}';

  Future<LocationSendOutcome> send(
    BuildContext context, {
    String? userID,
    String? groupID,
  }) async {
    if ((userID == null || userID.isEmpty) &&
        (groupID == null || groupID.isEmpty)) {
      return LocationSendOutcome.failed;
    }
    bool isCurrent() => context.mounted && _isSessionCurrent();
    if (!isCurrent()) return LocationSendOutcome.failed;
    final account = await _currentToxId();
    if (!isCurrent() || account == null || account.isEmpty) {
      return LocationSendOutcome.failed;
    }

    Future<LocationSendOutcome?> validate() async {
      final current = await _currentToxId();
      if (!isCurrent() || current != account) return LocationSendOutcome.failed;
      final enabled = await LocationPrefs.getLocationEnabled(account);
      if (!isCurrent()) return LocationSendOutcome.failed;
      return enabled ? null : LocationSendOutcome.disabled;
    }

    var blocked = await validate();
    if (!context.mounted || !_isSessionCurrent()) {
      return LocationSendOutcome.failed;
    }
    if (blocked != null) return blocked;
    final allowed = await _permissions.ensure(context);
    if (!isCurrent()) return LocationSendOutcome.failed;
    if (!allowed) return LocationSendOutcome.permissionDenied;
    blocked = await validate();
    if (!isCurrent()) return LocationSendOutcome.failed;
    if (blocked != null) return blocked;
    final fix = await _source.currentFix();
    if (!isCurrent()) return LocationSendOutcome.failed;
    if (fix == null) return LocationSendOutcome.noFix;
    blocked = await validate();
    if (!isCurrent()) return LocationSendOutcome.failed;
    if (blocked != null) return blocked;
    final dispatch = _dispatch;
    if (dispatch != null) return dispatch(fix, userID, groupID);
    return _sendThroughUiKit(fix, userID, groupID, isCurrent);
  }

  static Future<LocationSendOutcome> _sendThroughUiKit(
    LocationFix fix,
    String? userID,
    String? groupID,
    bool Function() isCurrent,
  ) async {
    // Message creation and the UIKit's profile lookup can both suspend. Do
    // not let either resume into another account's global SDK instance.
    if (!isCurrent()) return LocationSendOutcome.failed;
    final created = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createLocationMessage(
          desc: describe(fix),
          longitude: fix.longitude,
          latitude: fix.latitude,
        );
    if (!isCurrent()) return LocationSendOutcome.failed;
    final info = created.data;
    if (created.code != 0 || info == null) return LocationSendOutcome.failed;
    var cancelled = false;
    final result = await TencentCloudChatMessageDataTools.sendMessage(
      createdMessage: info,
      userID: (userID != null && userID.isNotEmpty) ? userID : null,
      groupID: (groupID != null && groupID.isNotEmpty) ? groupID : null,
      beforeMessageSendingHook:
          ({
            required createdMessage,
            repliedMessage,
            userID,
            groupID,
            topicID,
          }) {
            if (!isCurrent()) {
              cancelled = true;
              return null;
            }
            return createdMessage;
          },
    );
    if (cancelled) return LocationSendOutcome.failed;
    if (result == null) return LocationSendOutcome.sent; // optimistic row shown
    return result.code == 0
        ? LocationSendOutcome.sent
        : LocationSendOutcome.failed;
  }

  /// A user-facing line for a non-sent outcome (null for [LocationSendOutcome.sent]).
  static String? describeOutcome(BuildContext context, LocationSendOutcome o) {
    final l10n = AppLocalizations.of(context)!;
    switch (o) {
      case LocationSendOutcome.sent:
        return null;
      case LocationSendOutcome.disabled:
        return l10n.locationDisabledHint;
      case LocationSendOutcome.permissionDenied:
        return l10n.locationPermissionDenied;
      case LocationSendOutcome.noFix:
        return l10n.locationUnavailable;
      case LocationSendOutcome.failed:
        return l10n.locationSendFailed;
    }
  }
}
