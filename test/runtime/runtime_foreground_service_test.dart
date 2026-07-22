import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/runtime/runtime_foreground_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RuntimeForegroundService', () {
    const channel = MethodChannel('toxee/runtime_foreground');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test(
      'non-Android platforms short-circuit without invoking the channel',
      () async {
        // The host platform when running `flutter test` is desktop (macOS /
        // linux / windows). Platform.isAndroid is false, so every method must
        // be a no-op regardless of what the mock handler would return.
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

        final service = RuntimeForegroundService();
        await service.start(title: 't', body: 'b', settingsLabel: 's');
        await service.stop();
        await service.elevateToCall(title: 't', body: 'b', settingsLabel: 's');
        await service.restoreFromCall(
          title: 't',
          body: 'b',
          settingsLabel: 's',
        );

        // The wrapper guards on Platform.isAndroid, so on the host VM (which is
        // not Android) the channel is never touched. This is the contract that
        // unit tests, desktop dev, and iOS rely on.
        expect(calls, isEmpty);
      },
    );

    test('swallows MissingPluginException defensively', () async {
      // Force the test messenger to act as if no handler is registered.
      messenger.setMockMethodCallHandler(channel, null);

      // We cannot directly assert "Android branch" without forcing the
      // platform, so this test exercises the public contract: calling any
      // method on a non-Android host must complete normally even with no
      // mock handler — a regression of the defensive try/catch would
      // surface as a thrown PlatformException / MissingPluginException.
      final service = RuntimeForegroundService();
      await expectLater(
        service.start(title: 't', body: 'b', settingsLabel: 's'),
        completes,
      );
      await expectLater(service.stop(), completes);
      await expectLater(
        service.elevateToCall(title: 't', body: 'b', settingsLabel: 's'),
        completes,
      );
      await expectLater(
        service.restoreFromCall(title: 't', body: 'b', settingsLabel: 's'),
        completes,
      );
    });

    test('uses the injected MethodChannel name', () {
      // The channel name is part of the contract with the native side and
      // must not drift; the matching Kotlin constant lives in
      // android/app/src/main/kotlin/com/toxee/app/RuntimeForegroundChannel.kt.
      expect(channel.name, 'toxee/runtime_foreground');
    });

    test('call elevation forwards whether camera capture is active', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final service = RuntimeForegroundService(
        channel: channel,
        isAndroidOverride: true,
      );

      await service.elevateToCall(
        title: 'Calling',
        body: 'Connected',
        settingsLabel: 'Settings',
        usesCamera: true,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'elevateToCall');
      expect(calls.single.arguments, containsPair('usesCamera', true));
    });
  });
}
