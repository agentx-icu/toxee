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
    final binding = WidgetsBinding.instance;
    var leftForeground = _isOutsideForeground(binding.lifecycleState);
    bool isCurrent() =>
        !leftForeground && context.mounted && _isSessionCurrent();
    if (!isCurrent()) return LocationSendOutcome.failed;
    final lifecycle = AppLifecycleListener(
      binding: binding,
      onStateChange: (state) {
        if (_isOutsideForeground(state)) leftForeground = true;
      },
    );

    try {
      final account = await _currentToxId();
      if (!isCurrent() || account == null || account.isEmpty) {
        return LocationSendOutcome.failed;
      }
      final isLocationEnabled = await LocationPrefs.locationEnabledReader(
        account,
      );

      LocationSendOutcome? blockedNow() {
        if (!isCurrent()) return LocationSendOutcome.failed;
        return isLocationEnabled() ? null : LocationSendOutcome.disabled;
      }

      if (!context.mounted || leftForeground || !_isSessionCurrent()) {
        return LocationSendOutcome.failed;
      }
      if (!isLocationEnabled()) return LocationSendOutcome.disabled;
      final allowed = await _permissions.ensure(context);
      if (!isCurrent() || await _currentToxId() != account) {
        return LocationSendOutcome.failed;
      }
      var blocked = blockedNow();
      if (blocked != null) return blocked;
      if (!allowed) return LocationSendOutcome.permissionDenied;
      final fix = await _source.currentFix();
      if (!isCurrent() || await _currentToxId() != account) {
        return LocationSendOutcome.failed;
      }
      blocked = blockedNow();
      if (blocked != null) return blocked;
      if (fix == null) return LocationSendOutcome.noFix;
      final dispatch = _dispatch;
      if (dispatch != null) return await dispatch(fix, userID, groupID);
      return await _sendThroughUiKit(fix, userID, groupID, blockedNow);
    } finally {
      lifecycle.dispose();
    }
  }

  // Permission prompts and loss of window focus also produce inactive.
  static bool _isOutsideForeground(AppLifecycleState? state) =>
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;

  static Future<LocationSendOutcome> _sendThroughUiKit(
    LocationFix fix,
    String? userID,
    String? groupID,
    LocationSendOutcome? Function() blockedNow,
  ) async {
    // Message creation and the UIKit's profile lookup can both suspend. The
    // hook rechecks consent before UIKit inserts a row or calls the SDK.
    final created = await TencentImSDKPlugin.v2TIMManager
        .getMessageManager()
        .createLocationMessage(
          desc: describe(fix),
          longitude: fix.longitude,
          latitude: fix.latitude,
        );
    final blocked = blockedNow();
    if (blocked != null) return blocked;
    final info = created.data;
    if (created.code != 0 || info == null) return LocationSendOutcome.failed;
    LocationSendOutcome? cancelled;
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
            cancelled = blockedNow();
            return cancelled == null ? createdMessage : null;
          },
    );
    if (result == null) return cancelled ?? LocationSendOutcome.sent;
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
