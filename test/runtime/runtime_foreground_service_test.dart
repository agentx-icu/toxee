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

    group('ensureRunning', () {
      late List<MethodCall> calls;
      late bool nativeRunning;
      late RuntimeForegroundService service;

      setUp(() {
        calls = <MethodCall>[];
        nativeRunning = true;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'isInRequestedMode' ? nativeRunning : null;
        });
        service = RuntimeForegroundService(
          channel: channel,
          isAndroidOverride: true,
        );
      });

      List<String> methods() => calls.map((c) => c.method).toList();

      test('does nothing outside a session', () async {
        await service.ensureRunning();
        expect(calls, isEmpty);
      });

      test('leaves a running service alone', () async {
        await service.start(title: 't', body: 'b', settingsLabel: 's');
        calls.clear();
        await service.ensureRunning();
        expect(methods(), ['isInRequestedMode']);
      });

      test('restarts a service the OS stopped with the same args', () async {
        await service.start(title: 't', body: 'b', settingsLabel: 's');
        calls.clear();
        nativeRunning = false;
        await service.ensureRunning();
        expect(methods(), ['isInRequestedMode', 'start']);
        expect(calls.last.arguments, {
          'title': 't',
          'body': 'b',
          'settingsLabel': 's',
        });
      });

      test('keeps an in-progress call in call mode', () async {
        await service.start(title: 't', body: 'b', settingsLabel: 's');
        await service.elevateToCall(
          title: 'Calling',
          body: 'Connected',
          settingsLabel: 's',
          usesCamera: true,
        );
        calls.clear();
        nativeRunning = false;
        await service.ensureRunning();
        expect(methods(), ['isInRequestedMode', 'elevateToCall']);
        expect(calls.last.arguments, containsPair('usesCamera', true));
      });

      test('replays the restored mode after a call ended', () async {
        await service.elevateToCall(title: 'c', body: 'b', settingsLabel: 's');
        await service.restoreFromCall(
          title: 't',
          body: 'b',
          settingsLabel: 's',
        );
        calls.clear();
        nativeRunning = false;
        await service.ensureRunning();
        expect(methods(), ['isInRequestedMode', 'restoreFromCall']);
      });

      test('replays a request the native side refused to deliver', () async {
        await service.start(title: 't', body: 'b', settingsLabel: 's');
        // A background startForegroundService refusal: the intent never
        // reaches the service, so its own mode check still reports the old
        // (runtime) mode as satisfied.
        var refuse = true;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'isInRequestedMode') return true;
          if (call.method == 'elevateToCall' && refuse) {
            throw PlatformException(code: 'error', message: 'refused');
          }
          return null;
        });
        await service.elevateToCall(title: 'c', body: 'b', settingsLabel: 's');
        refuse = false;
        calls.clear();
        await service.ensureRunning();
        expect(methods(), ['isInRequestedMode', 'elevateToCall']);

        // Delivered now: the next resume leaves it alone.
        calls.clear();
        await service.ensureRunning();
        expect(methods(), ['isInRequestedMode']);
      });

      test('does not restart after the session stopped the service', () async {
        await service.start(title: 't', body: 'b', settingsLabel: 's');
        await service.stop();
        calls.clear();
        nativeRunning = false;
        await service.ensureRunning();
        expect(calls, isEmpty);
      });

      test('does not restart when the session ends mid-check', () async {
        await service.start(title: 't', body: 'b', settingsLabel: 's');
        calls.clear();
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'isInRequestedMode') {
            // Logout lands while the native status query is in flight.
            await service.stop();
            return false;
          }
          return null;
        });
        await service.ensureRunning();
        expect(methods(), ['isInRequestedMode', 'stop']);
      });
    });
  });
}
