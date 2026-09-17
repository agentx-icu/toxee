import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../util/app_l10n.dart';

/// The app's Android notification channels.
///
/// A channel's name and description are user-visible (system notification
/// settings), so they follow the app language instead of being English
/// constants. [registerAndroidNotificationChannels] runs at startup and again
/// whenever the language changes: re-registering an existing channel id only
/// updates its name and description. Importance, sound and vibration stay
/// whatever the channel was first created with — Android makes those immutable
/// once the channel exists; the values here are the defaults for fresh installs
/// (or after a clear-data).
enum ToxeeNotificationChannel {
  messages('toxee_messages'),
  friendRequests('toxee_friend_requests'),
  missedCalls('toxee_missed_calls'),
  incomingCalls('toxee_incoming_calls');

  const ToxeeNotificationChannel(this.id);

  final String id;

  /// Localized channel name (not the enum's own `name`).
  String get displayName {
    final l10n = currentAppL10n();
    return switch (this) {
      messages => l10n.channelMessagesName,
      friendRequests => l10n.channelFriendRequestsName,
      missedCalls => l10n.channelMissedCallsName,
      incomingCalls => l10n.channelIncomingCallsName,
    };
  }

  String get description {
    final l10n = currentAppL10n();
    return switch (this) {
      messages => l10n.channelMessagesDescription,
      friendRequests => l10n.channelFriendRequestsDescription,
      missedCalls => l10n.channelMissedCallsDescription,
      incomingCalls => l10n.channelIncomingCallsDescription,
    };
  }

  AndroidNotificationChannel get androidChannel {
    final isCall = this == incomingCalls;
    return AndroidNotificationChannel(
      id,
      displayName,
      description: description,
      importance: isCall ? Importance.max : Importance.high,
      // The live incoming-call surface stays silent: RingtonePlayer owns ring
      // sound/vibration and respects the device ringer mode.
      playSound: !isCall,
      enableVibration: !isCall,
      showBadge: !isCall,
    );
  }
}

/// Creates (or, when they already exist, renames) every app channel in the
/// current UI language.
Future<void> registerAndroidNotificationChannels(
  AndroidFlutterLocalNotificationsPlugin androidImpl,
) async {
  for (final channel in ToxeeNotificationChannel.values) {
    await androidImpl.createNotificationChannel(channel.androidChannel);
  }
}

/// Android policy for the live incoming-call surface.
///
/// Sound and vibration stay disabled here because [RingtonePlayer] owns those
/// effects and respects the device ringer mode. The notification exists to
/// make the Flutter accept/decline surface visible over background/lock state.
AndroidNotificationDetails buildAndroidIncomingCallNotificationDetails() {
  const channel = ToxeeNotificationChannel.incomingCalls;
  return AndroidNotificationDetails(
    channel.id,
    channel.displayName,
    channelDescription: channel.description,
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    fullScreenIntent: true,
    ongoing: true,
    autoCancel: false,
    playSound: false,
    enableVibration: false,
    visibility: NotificationVisibility.public,
  );
}
