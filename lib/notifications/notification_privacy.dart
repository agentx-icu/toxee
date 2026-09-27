import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/app_l10n.dart';
import '../util/logger.dart';
import '../util/serialized_async_tail.dart';
import 'notification_service.dart';

/// "Hide message content in notifications": message notifications then show
/// only the app name and a generic "New message", on the lock screen and in
/// banners alike, instead of the sender and text.
///
/// A device-level choice (who can see this screen), not per account. Off by
/// default so existing notifications do not change.
class NotificationPrivacy {
  NotificationPrivacy._();

  static const _key = 'notification_hide_content';

  /// The current setting; null until first read.
  static final ValueNotifier<bool?> hideContent = ValueNotifier(null);

  /// An unreadable setting hides content (the switch may be on), uncached so
  /// the next notification reads again.
  static Future<bool> hidesContent() async {
    final cached = hideContent.value;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      // `??=`: a setHideContent that landed during the read is newer.
      return hideContent.value ??= prefs.getBool(_key) ?? false;
    } catch (e) {
      AppLogger.warn('[NotificationPrivacy] read failed, hiding content: $e');
      return true;
    }
  }

  /// Created on first use, so it lives in the zone that saves.
  static SerializedAsyncTail? _writes;
  static SerializedAsyncTail _newTail() => SerializedAsyncTail(
    logError: (e, _) => AppLogger.warn('[NotificationPrivacy] save: $e'),
  );

  /// Saves one at a time, in call order, so the last choice wins. A failed
  /// save keeps the previous choice in effect (shared_preferences has already
  /// cached the new value by then, so the cache here is pinned) and throws.
  /// Turning it on also withdraws message notifications already on screen.
  static Future<void> setHideContent(bool value) =>
      (_writes ??= _newTail()).enqueue(() => _save(value));

  static Future<void> _save(bool value) async {
    final previous = await hidesContent();
    var saved = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = await prefs.setBool(_key, value);
    } catch (e) {
      AppLogger.warn('[NotificationPrivacy] write failed: $e');
    }
    if (!saved) {
      hideContent.value = previous;
      throw StateError('notification privacy setting was not saved');
    }
    hideContent.value = value;
    if (value) {
      await NotificationService.instance.withdrawMessageNotifications();
    }
  }

  /// The sender, preview and avatar a hidden notification shows instead.
  static (String, String, String?) redacted() =>
      ('Toxee', currentAppL10n().notificationContentHidden, null);

  @visibleForTesting
  static void debugReset() {
    hideContent.value = null;
    _writes = null;
  }
}
