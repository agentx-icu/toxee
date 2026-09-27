// B5 + S2 (doc/reference/MOBILE_DEVICE_FEATURES.md): Settings > Background &
// notifications. The hide-content switch persists through
// NotificationPrivacy; on Android the battery-optimization row reflects
// `toxee/notification_access` and re-reads it when the app resumes from the
// system dialog.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/notifications/notification_privacy.dart';
import 'package:toxee/ui/settings/background_settings_section.dart';
import 'package:toxee/ui/testing/ui_keys_settings.dart';

void main() {
  const channel = MethodChannel('test/background_settings');
  late bool exempt;
  late List<String> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationPrivacy.debugReset();
    exempt = false;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'isIgnoringBatteryOptimizations') return exempt;
      return null;
    });
  });

  tearDown(() {
    NotificationPrivacy.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pump(WidgetTester tester, {required bool android}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BackgroundSettingsSection(
            isAndroidOverride: android,
            channel: channel,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hide-content switch persists the choice', (tester) async {
    await pump(tester, android: false);
    final finder = find.byKey(SettingsUiKeys.hideNotificationContentSwitch);
    expect(tester.widget<SwitchListTile>(finder).value, isFalse);

    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(finder).value, isTrue);
    NotificationPrivacy.debugReset();
    expect(await NotificationPrivacy.hidesContent(), isTrue);
  });

  testWidgets('no battery row off Android', (tester) async {
    await pump(tester, android: false);
    expect(find.text('Background running'), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('Android: restricted → Allow asks the system; resume re-reads', (
    tester,
  ) async {
    await pump(tester, android: true);
    expect(find.textContaining('Restricted by battery'), findsOneWidget);

    await tester.tap(find.byKey(SettingsUiKeys.backgroundRunningAllowButton));
    await tester.pumpAndSettle();
    expect(calls, contains('requestIgnoreBatteryOptimizations'));

    // The user allowed it in the system dialog and came back.
    exempt = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.textContaining('Allowed.'), findsOneWidget);
    expect(
      find.byKey(SettingsUiKeys.backgroundRunningAllowButton),
      findsNothing,
    );
  });
}
