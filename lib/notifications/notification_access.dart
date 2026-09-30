import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import '../util/harness_environment.dart';
import '../util/logger.dart';
import 'notification_channels.dart';
import 'notification_service.dart';

/// How well Toxee can alert the user while it is in the background, worst
/// first. Tox has no push server, so these system notifications are the only
/// way a backgrounded session surfaces messages and calls.
enum NotificationAccess {
  /// App notifications are off (Android switch / iOS denied).
  appOff,

  /// Android: the incoming-call channel is off — calls cannot ring.
  callsChannelOff,

  /// Android 14+: full-screen intents are not allowed — calls still notify
  /// but cannot take over the lock screen.
  fullScreenIntentOff,

  /// Android: the message channel is off.
  messagesOff,

  /// Android: friend-request, group-invite or missed-call channel is off.
  otherChannelsOff,

  /// iOS: alerts are off; notifications land silently in Notification Center.
  alertsOff,

  /// iOS provisional authorization: delivered quietly until the user keeps them.
  provisional,

  ok,
}

/// Where the notice's settings button should take the user.
enum NotificationSettingsTarget { app, channel, fullScreenIntent }

/// Reads the platform state. Injected in tests.
typedef NotificationAccessProbe = Future<NotificationAccess> Function();

/// Watches [NotificationAccess] for the in-app notice (NotificationAccessBanner).
///
/// Refreshes when started, whenever the permission request settles (so a
/// denial is explained right away) and on every resume (returning from system
/// settings). On Android it also hands the app switch back to
/// [NotificationService], whose send gate would otherwise keep a denial for the
/// whole session.
class NotificationAccessMonitor {
  NotificationAccessMonitor({
    NotificationAccessProbe? probe,
    bool Function()? requestSettled,
    bool? isMobileOverride,
  }) : _probe = probe ?? probeNotificationAccess,
       _requestSettled =
           requestSettled ??
           (() => NotificationService.instance.permissionRequestSettled),
       _isMobile = isMobileOverride ?? (Platform.isAndroid || Platform.isIOS);

  static final NotificationAccessMonitor instance = NotificationAccessMonitor();

  final NotificationAccessProbe _probe;
  final bool Function() _requestSettled;
  final bool _isMobile;

  final ValueNotifier<NotificationAccess> access = ValueNotifier(
    NotificationAccess.ok,
  );

  AppLifecycleListener? _resumeListener;
  int _refreshSeq = 0;

  /// Idempotent; a no-op off mobile.
  void start() {
    if (!_isMobile || _resumeListener != null) return;
    _resumeListener = AppLifecycleListener(
      onResume: () => unawaited(refresh()),
    );
    NotificationService.instance.onPermissionSettled = () =>
        unawaited(refresh());
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!_isMobile) return;
    final seq = ++_refreshSeq;
    NotificationAccess next;
    try {
      next = await _probe();
    } catch (e) {
      AppLogger.warn('[NotificationAccessMonitor] probe failed: $e');
      return;
    }
    if (seq != _refreshSeq) return; // a newer refresh owns the result
    if (Platform.isAndroid || debugTreatAsAndroid) {
      NotificationService.instance.observeAndroidAppSwitch(
        enabled: next != NotificationAccess.appOff,
      );
    }
    // Before the first prompt is answered iOS reports an undecided state as
    // "not enabled"; the L3 harness never asks at all. Neither is "off".
    if (!_requestSettled() ||
        HarnessEnvironment.boolValue(
          HarnessEnvironment.disableNotificationPermissionKey,
        )) {
      next = NotificationAccess.ok;
    }
    access.value = next;
  }

  /// Test seam: route [refresh]'s Android hand-off on a non-Android host.
  @visibleForTesting
  bool debugTreatAsAndroid = false;

  @visibleForTesting
  void debugReset() {
    _resumeListener?.dispose();
    _resumeListener = null;
    _refreshSeq = 0;
    debugTreatAsAndroid = false;
    access.value = NotificationAccess.ok;
  }
}

const MethodChannel _nativeChannel = MethodChannel('toxee/notification_access');

/// The platform [NotificationAccessProbe].
Future<NotificationAccess> probeNotificationAccess() async {
  final plugin = FlutterLocalNotificationsPlugin();
  if (Platform.isAndroid) {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return NotificationAccess.ok;
    if (await android.areNotificationsEnabled() == false) {
      return NotificationAccess.appOff;
    }
    final sdkInt = await _nativeChannel.invokeMethod<int>('sdkInt') ?? 0;
    // Channels exist from API 26. A channel missing on 26+ means registration
    // has not happened yet (or failed): not "off" — the next refresh retries.
    final channels = sdkInt >= 26
        ? await android.getNotificationChannels() ?? const []
        : const <AndroidNotificationChannel>[];
    bool off(ToxeeNotificationChannel c) =>
        channels.any((ch) => ch.id == c.id && ch.importance == Importance.none);
    if (off(ToxeeNotificationChannel.incomingCalls)) {
      return NotificationAccess.callsChannelOff;
    }
    if (sdkInt >= 34 &&
        await _nativeChannel.invokeMethod<bool>('canUseFullScreenIntent') ==
            false) {
      return NotificationAccess.fullScreenIntentOff;
    }
    if (off(ToxeeNotificationChannel.messages)) {
      return NotificationAccess.messagesOff;
    }
    if (off(ToxeeNotificationChannel.friendRequests) ||
        off(ToxeeNotificationChannel.groupInvites) ||
        off(ToxeeNotificationChannel.missedCalls)) {
      return NotificationAccess.otherChannelsOff;
    }
    return NotificationAccess.ok;
  }
  if (Platform.isIOS) {
    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final options = await ios?.checkPermissions();
    if (options == null) return NotificationAccess.ok;
    if (options.isProvisionalEnabled) return NotificationAccess.provisional;
    if (!options.isEnabled) return NotificationAccess.appOff;
    if (!options.isAlertEnabled) return NotificationAccess.alertsOff;
  }
  return NotificationAccess.ok;
}

/// The settings page that fixes [access].
NotificationSettingsTarget settingsTargetFor(NotificationAccess access) =>
    switch (access) {
      NotificationAccess.callsChannelOff ||
      NotificationAccess.messagesOff => NotificationSettingsTarget.channel,
      NotificationAccess.fullScreenIntentOff =>
        NotificationSettingsTarget.fullScreenIntent,
      _ => NotificationSettingsTarget.app,
    };

/// Opens the settings page that fixes [access]. Android deep-links the exact
/// page (falls back to the app page natively); iOS has only the app page.
Future<void> openNotificationSettings(NotificationAccess access) async {
  final target = settingsTargetFor(access);
  final channelId = switch (access) {
    NotificationAccess.callsChannelOff =>
      ToxeeNotificationChannel.incomingCalls.id,
    NotificationAccess.messagesOff => ToxeeNotificationChannel.messages.id,
    _ => null,
  };
  try {
    await _nativeChannel.invokeMethod<void>('openSettings', {
      'target': target.name,
      'channelId': channelId,
    });
  } on MissingPluginException {
    // iOS / other: no native deep link — the generic app settings page.
    await _openAppSettingsFallback();
  } catch (e) {
    AppLogger.warn('[NotificationAccess] openSettings failed: $e');
    await _openAppSettingsFallback();
  }
}

Future<void> _openAppSettingsFallback() async {
  try {
    await openAppSettings();
  } catch (e) {
    AppLogger.warn('[NotificationAccess] openAppSettings failed: $e');
  }
}
