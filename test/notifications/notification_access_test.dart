import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/notifications/notification_access.dart';
import 'package:toxee/notifications/notification_service.dart';
import 'package:toxee/ui/home/notification_access_banner.dart';
import 'package:toxee/ui/testing/ui_keys_home.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationAccessMonitor', () {
    test(
      'reports the probed state once the permission request settled',
      () async {
        final monitor = NotificationAccessMonitor(
          probe: () async => NotificationAccess.messagesOff,
          requestSettled: () => true,
          isMobileOverride: true,
        );
        await monitor.refresh();
        expect(monitor.access.value, NotificationAccess.messagesOff);
      },
    );

    test('an unanswered prompt is not "off"', () async {
      // iOS reports an undecided prompt as not enabled.
      final monitor = NotificationAccessMonitor(
        probe: () async => NotificationAccess.appOff,
        requestSettled: () => false,
        isMobileOverride: true,
      );
      await monitor.refresh();
      expect(monitor.access.value, NotificationAccess.ok);
    });

    test('only the newest refresh decides', () async {
      final slow = Completer<NotificationAccess>();
      var calls = 0;
      final monitor = NotificationAccessMonitor(
        probe: () {
          calls++;
          return calls == 1 ? slow.future : Future.value(NotificationAccess.ok);
        },
        requestSettled: () => true,
        isMobileOverride: true,
      );
      final first = monitor.refresh();
      await monitor.refresh(); // newer: ok
      slow.complete(NotificationAccess.appOff); // stale answer arrives late
      await first;
      expect(monitor.access.value, NotificationAccess.ok);
    });

    test('a settled permission request refreshes right away', () async {
      var access = NotificationAccess.ok;
      final monitor = NotificationAccessMonitor(
        probe: () async => access,
        requestSettled: () => true,
        isMobileOverride: true,
      );
      addTearDown(monitor.debugReset);
      addTearDown(
        () => NotificationService.instance.onPermissionSettled = null,
      );
      monitor.start();
      await pumpEventQueue();
      access = NotificationAccess.appOff; // the user just denied
      NotificationService.instance.onPermissionSettled!();
      await pumpEventQueue();
      expect(monitor.access.value, NotificationAccess.appOff);
    });

    test('desktops never report a problem', () async {
      final monitor = NotificationAccessMonitor(
        probe: () async => NotificationAccess.appOff,
        requestSettled: () => true,
        isMobileOverride: false,
      );
      await monitor.refresh();
      expect(monitor.access.value, NotificationAccess.ok);
    });

    test('Android: the observed app switch lifts the send gate', () async {
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final captured = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured.add(call.method);
            return call.method == 'initialize' ? true : null;
          });
      addTearDown(() {
        NotificationService.debugForceIsAndroid = null;
        NotificationService.instance.debugAndroidPermissionGranted = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final svc = NotificationService.instance;
      await svc.init();
      NotificationService.debugForceIsAndroid = true;
      svc.debugAndroidPermissionGranted = false; // denied earlier

      final monitor = NotificationAccessMonitor(
        probe: () async => NotificationAccess.ok, // enabled in settings since
        requestSettled: () => true,
        isMobileOverride: true,
      )..debugTreatAsAndroid = true;
      await monitor.refresh();

      captured.clear();
      await svc.showMessageNotification(
        conversationId: 'c2c_peer',
        senderName: 'Alice',
        preview: 'hello',
      );
      expect(captured, contains('show'));
    });

    test('each problem opens the page that fixes it', () {
      expect(
        settingsTargetFor(NotificationAccess.callsChannelOff),
        NotificationSettingsTarget.channel,
      );
      expect(
        settingsTargetFor(NotificationAccess.messagesOff),
        NotificationSettingsTarget.channel,
      );
      expect(
        settingsTargetFor(NotificationAccess.fullScreenIntentOff),
        NotificationSettingsTarget.fullScreenIntent,
      );
      for (final access in [
        NotificationAccess.appOff,
        NotificationAccess.otherChannelsOff,
        NotificationAccess.alertsOff,
        NotificationAccess.provisional,
      ]) {
        expect(settingsTargetFor(access), NotificationSettingsTarget.app);
      }
    });
  });

  group('NotificationAccessBanner', () {
    Future<(NotificationAccessMonitor, List<NotificationAccess>)> pumpBanner(
      WidgetTester tester, {
      Widget child = const SizedBox.expand(),
    }) async {
      final monitor = NotificationAccessMonitor(
        probe: () async => NotificationAccess.ok,
        requestSettled: () => true,
        isMobileOverride: false, // start() is a no-op; tests drive access
      );
      final opened = <NotificationAccess>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NotificationAccessBanner(
              monitor: monitor,
              openSettings: (access) async => opened.add(access),
              child: child,
            ),
          ),
        ),
      );
      return (monitor, opened);
    }

    testWidgets('hidden while notifications work', (tester) async {
      await pumpBanner(tester);
      expect(find.byKey(HomeUiKeys.notificationAccessBanner), findsNothing);
    });

    testWidgets('explains each problem and opens its settings', (tester) async {
      final (monitor, opened) = await pumpBanner(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final expected = {
        NotificationAccess.appOff: l10n.notificationAccessAppOff,
        NotificationAccess.callsChannelOff: l10n.notificationAccessCallsOff,
        NotificationAccess.fullScreenIntentOff:
            l10n.notificationAccessFullScreenOff,
        NotificationAccess.messagesOff: l10n.notificationAccessMessagesOff,
        NotificationAccess.otherChannelsOff: l10n.notificationAccessOtherOff,
        NotificationAccess.alertsOff: l10n.notificationAccessAlertsOff,
        NotificationAccess.provisional: l10n.notificationAccessProvisional,
      };
      for (final entry in expected.entries) {
        monitor.access.value = entry.key;
        await tester.pump();
        expect(find.byKey(HomeUiKeys.notificationAccessBanner), findsOneWidget);
        expect(find.text(entry.value), findsOneWidget);
        await tester.tap(find.byKey(HomeUiKeys.notificationAccessSettings));
        await tester.pump();
        expect(opened.last, entry.key);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('showing or hiding the notice keeps the tab alive', (
      tester,
    ) async {
      var inits = 0;
      final (monitor, _) = await pumpBanner(
        tester,
        child: _InitCounter(onInit: () => inits++),
      );
      monitor.access.value = NotificationAccess.appOff;
      await tester.pump();
      monitor.access.value = NotificationAccess.ok;
      await tester.pump();
      expect(
        inits,
        1,
        reason: 'the Chats tab must not be rebuilt from scratch',
      );
    });
  });
}

class _InitCounter extends StatefulWidget {
  const _InitCounter({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_InitCounter> createState() => _InitCounterState();
}

class _InitCounterState extends State<_InitCounter> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
