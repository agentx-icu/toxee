part of 'notification_service.dart';

const windowsInitializationSettings = WindowsInitializationSettings(
  appName: 'Toxee',
  appUserModelId: 'com.toxee.app',
  guid: '44a386ab-a16c-4d33-ac63-e7acb8f1ce11',
);

extension NotificationServiceWindows on NotificationService {
  Future<IncomingCallNotificationOutcome> _showWindowsIncomingCall(
    int generation,
    String callId,
    String displayName,
    bool isVideo,
  ) async {
    if (!_initialized) await init();
    if (!_incomingCallLease.isCurrent(generation, callId)) {
      return IncomingCallNotificationOutcome.cancelled;
    }
    final l10n = currentAppL10n();
    await _plugin.show(
      _androidIncomingCallNotificationId,
      isVideo
          ? l10n.notificationIncomingVideoCall
          : l10n.notificationIncomingCall,
      displayName.isEmpty ? l10n.notificationUnknownCaller : displayName,
      NotificationDetails(
        windows: WindowsNotificationDetails(
          scenario: WindowsNotificationScenario.incomingCall,
          audio: WindowsNotificationAudio.silent(),
        ),
      ),
      payload: 'incoming_call:$callId',
    );
    return IncomingCallNotificationOutcome.shown;
  }
}
