// Notification copy has no BuildContext, so it resolves the app language via
// currentAppL10n() (AppLocale.locale). These strings — Android channel names in
// system settings, banner titles, the incoming-call surface — were English
// constants in every language before.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/notifications/notification_channels.dart';
import 'package:toxee/util/app_l10n.dart';
import 'package:toxee/util/locale_controller.dart';

void main() {
  tearDown(() => AppLocale.locale.value = const Locale('en'));

  test('channel names and descriptions follow the app language', () {
    AppLocale.locale.value = const Locale('en');
    expect(ToxeeNotificationChannel.messages.displayName, 'Messages');
    expect(
      ToxeeNotificationChannel.incomingCalls.displayName,
      'Incoming calls',
    );

    AppLocale.locale.value = const Locale('ja');
    final ja = currentAppL10n();
    for (final channel in ToxeeNotificationChannel.values) {
      expect(
        channel.displayName,
        isNot(contains(RegExp('[A-Za-z]{3,}'))),
        reason: '${channel.id} name is still English in ja',
      );
      expect(channel.androidChannel.name, channel.displayName);
      expect(channel.androidChannel.description, channel.description);
    }
    expect(
      ToxeeNotificationChannel.missedCalls.displayName,
      ja.channelMissedCallsName,
    );

    final details = buildAndroidIncomingCallNotificationDetails();
    expect(details.channelId, 'toxee_incoming_calls');
    expect(details.channelName, ja.channelIncomingCallsName);
  });

  test('channel ids and call-surface policy do not depend on the language', () {
    for (final locale in const [
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      Locale('ar'),
    ]) {
      AppLocale.locale.value = locale;
      expect(ToxeeNotificationChannel.values.map((c) => c.id), [
        'toxee_messages',
        'toxee_friend_requests',
        'toxee_missed_calls',
        'toxee_incoming_calls',
      ]);
      final call = ToxeeNotificationChannel.incomingCalls.androidChannel;
      expect(call.playSound, isFalse);
      expect(call.enableVibration, isFalse);
      expect(call.showBadge, isFalse);
      expect(
        ToxeeNotificationChannel.messages.androidChannel.playSound,
        isTrue,
      );
    }
  });

  test('context-free lookup resolves script-qualified Chinese', () {
    AppLocale.locale.value = const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    );
    expect(currentAppL10n().notificationMissedCall, '未接來電');
    AppLocale.locale.value = const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
    );
    expect(currentAppL10n().notificationMissedCall, '未接来电');
  });
}
