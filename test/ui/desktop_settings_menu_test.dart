import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/home/desktop_settings_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('toxee/desktop_menu');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<int?> owners;
  setUp(() {
    owners = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setSettingsOwner');
      owners.add(call.arguments as int?);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> activate(int? owner) async {
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('openSettings', owner)),
      (_) {},
    );
  }

  testWidgets(
    'ready route receives action once; not-ready and disposed routes cannot',
    (tester) async {
      var calls = 0;
      Widget page(bool ready) => MaterialApp(
        home: DesktopSettingsMenu(
          ready: ready,
          onOpenSettings: () => calls++,
          child: const Text('Home'),
        ),
      );
      await tester.pumpWidget(page(false));
      expect(owners, isEmpty);
      await tester.pumpWidget(page(true));
      await tester.pump();
      final owner = owners.last;
      expect(owner, isNotNull);
      await activate(owner);
      expect(calls, 1);
      await tester.pumpWidget(page(false));
      await tester.pump();
      expect(owners.last, isNull);
      await activate(owner);
      expect(calls, 1);
      await tester.pumpWidget(page(true));
      await tester.pump();
      final next = owners.last;
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await activate(next);
      expect(calls, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'covered routes disable Preferences and stale commands cannot cross account replacement',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      var oldCalls = 0;
      var newCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: DesktopSettingsMenu(
            ready: true,
            onOpenSettings: () => oldCalls++,
            child: const Text('Account A'),
          ),
        ),
      );
      await tester.pump();
      final old = owners.last;
      final covered = navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Text('Cover')),
      );
      await tester.pumpAndSettle();
      expect(owners.last, isNull);
      await activate(old);
      expect(oldCalls, 0);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await covered;
      final resumed = owners.last;
      expect(resumed, isNot(old));
      await activate(old);
      expect(oldCalls, 0);
      await activate(resumed);
      expect(oldCalls, 1);
      unawaited(
        navigator.currentState!.pushReplacement<void, void>(
          MaterialPageRoute(
            builder: (_) => DesktopSettingsMenu(
              ready: true,
              onOpenSettings: () => newCalls++,
              child: const Text('Account B'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final next = owners.last;
      expect(next, isNotNull);
      expect(next, isNot(resumed));
      await activate(resumed);
      expect(newCalls, 0);
      await activate(next);
      expect(newCalls, 1);
      expect(oldCalls, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  test('old account disposer cannot clear a newer owner', () async {
    final commands = DesktopSettingsMenuCommands(channel: channel);
    var calls = 0;
    final oldRelease = commands.bind(() => fail('stale account received menu'));
    final release = commands.bind(() => calls++);
    oldRelease();
    await Future<void>.delayed(Duration.zero);
    expect(owners.last, isNotNull);
    await activate(owners.last);
    expect(calls, 1);
    release();
    release();
    await Future<void>.delayed(Duration.zero);
    expect(owners.where((owner) => owner == null), hasLength(1));
  });

  testWidgets(
    'non-macOS hosts never publish native Preferences',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopSettingsMenu(
            ready: true,
            onOpenSettings: () => fail('unexpected native action'),
            child: const Text('Home'),
          ),
        ),
      );
      await tester.pump();
      expect(owners, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
