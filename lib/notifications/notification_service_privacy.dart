part of 'notification_service.dart';

/// S2: turning "hide message content" on must also take back what is already
/// on screen — lock-screen and Notification Center entries posted before the
/// switch still show the sender and the text.
extension NotificationServicePrivacy on NotificationService {
  /// Withdraws every posted message notification, including ones a previous
  /// process posted, and drops the grouped lines. Friend requests, invites
  /// and calls stay. Android reports no payload for active notifications, so
  /// it is matched by group / channel; iOS and macOS by payload (`c2c_…` /
  /// `group_…`, the conversation id).
  Future<void> withdrawMessageNotifications() async {
    final ids = <int>{
      for (final conversationId in _grouped.keys) _idFor(conversationId),
    };
    _grouped.clear();
    if (!_initialized || !_platformSupported) return;
    try {
      for (final active in await _plugin.getActiveNotifications()) {
        final payload = active.payload ?? '';
        final id = active.id;
        final isMessage =
            (active.groupKey ?? '').startsWith('toxee.messages.') ||
            active.channelId == ToxeeNotificationChannel.messages.id ||
            payload.startsWith('c2c_') ||
            payload.startsWith('group_');
        if (id != null && isMessage) ids.add(id);
      }
    } catch (e) {
      // Linux / Windows have no active list; this session's ids still go.
      AppLogger.debug('[NotificationService] no active notifications: $e');
    }
    for (final id in ids) {
      try {
        await _plugin.cancel(id);
      } catch (e) {
        AppLogger.debug('[NotificationService] withdraw $id failed: $e');
      }
    }
  }
}
