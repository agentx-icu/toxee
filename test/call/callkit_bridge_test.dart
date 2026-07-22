import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/callkit_bridge.dart';

/// Tests for the CallKit bridge. We focus on:
///  1. Method-channel encoding (Dart → native).
///  2. Native → Dart event decoding via `handleNativeMethodForTest`.
///  3. Short-circuit behaviour on non-iOS platforms.
///
/// Native (Swift) is not exercised here — that needs an XCTest target plus
/// running on a real device because CallKit is partially broken on iOS
/// simulators (see CallKitProvider.swift header comment).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallKitBridge — Dart → native', () {
    late MethodChannel channel;
    late List<MethodCall> calls;
    late CallKitBridge bridge;
    late TargetPlatform originalPlatform;

    setUp(() {
      originalPlatform =
          debugDefaultTargetPlatformOverride ?? TargetPlatform.android;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      channel = const MethodChannel('toxee/callkit_test');
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      bridge = CallKitBridge(channel: channel);
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = originalPlatform;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reportIncomingCall encodes callId, displayName, hasVideo', () async {
      final handled = await bridge.reportIncomingCall(
        callId: 'native_av_42',
        displayName: 'Alice',
        hasVideo: true,
      );
      expect(handled, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'reportIncomingCall');
      final args = calls.single.arguments as Map<dynamic, dynamic>;
      expect(args['callId'], 'native_av_42');
      expect(args['displayName'], 'Alice');
      expect(args['hasVideo'], isTrue);
    });

    test('reportOutgoingCall encodes call fields', () async {
      await bridge.reportOutgoingCall(
        callId: 'invite_abc',
        displayName: 'Bob',
        hasVideo: false,
      );
      expect(calls, hasLength(1));
      expect(calls.single.method, 'reportOutgoingCall');
      final args = calls.single.arguments as Map<dynamic, dynamic>;
      expect(args['callId'], 'invite_abc');
      expect(args['hasVideo'], isFalse);
    });

    test('reportCallConnected forwards callId', () async {
      await bridge.reportCallConnected(callId: 'native_av_7');
      expect(calls.single.method, 'reportCallConnected');
      final args = calls.single.arguments as Map<dynamic, dynamic>;
      expect(args['callId'], 'native_av_7');
    });

    test('reportCallEnded forwards callId and reason', () async {
      await bridge.reportCallEnded(
        callId: 'native_av_9',
        reason: CallKitEndReason.networkError,
      );
      expect(calls.single.method, 'reportCallEnded');
      final args = calls.single.arguments as Map<dynamic, dynamic>;
      expect(args['callId'], 'native_av_9');
      expect(args['reason'], 'network_error');
    });

    test('reportCallEnded defaults to hangup', () async {
      await bridge.reportCallEnded(callId: 'x');
      final args = calls.single.arguments as Map<dynamic, dynamic>;
      expect(args['reason'], 'hangup');
    });

    test('PlatformException from native does not throw to caller', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'REPORT_FAILED', message: 'denied');
          });
      // Should swallow PlatformException — the call layer needs to keep going
      // (e.g. fall back to in-app ringtone) when CallKit refuses to surface
      // the UI.
      final handled = await bridge.reportIncomingCall(
        callId: 'x',
        displayName: 'y',
        hasVideo: false,
      );
      expect(handled, isFalse);
    });
  });

  group('CallKitBridge — native → Dart', () {
    late TargetPlatform originalPlatform;
    late CallKitBridge bridge;

    setUp(() {
      originalPlatform =
          debugDefaultTargetPlatformOverride ?? TargetPlatform.android;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      bridge = CallKitBridge(
        channel: const MethodChannel('toxee/callkit_test_in'),
      );
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = originalPlatform;
    });

    test('decodes answer action and emits on userActions stream', () async {
      final actions = <CallKitAction>[];
      final sub = bridge.userActions.listen(actions.add);

      bridge.handleNativeMethodForTest(
        const MethodCall('onCallKitAction', <String, Object?>{
          'action': 'answer',
          'callId': 'native_av_3',
        }),
      );
      // Stream is broadcast/async; allow event-loop turn.
      await Future<void>.delayed(Duration.zero);

      expect(actions, hasLength(1));
      expect(actions.single.kind, CallKitActionKind.answer);
      expect(actions.single.callId, 'native_av_3');

      await sub.cancel();
    });

    test('decodes mute action with muted flag', () async {
      final actions = <CallKitAction>[];
      final sub = bridge.userActions.listen(actions.add);

      bridge.handleNativeMethodForTest(
        const MethodCall('onCallKitAction', <String, Object?>{
          'action': 'mute',
          'callId': 'native_av_5',
          'muted': true,
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(actions.single.kind, CallKitActionKind.mute);
      expect(actions.single.muted, isTrue);
      await sub.cancel();
    });

    test('unknown action is dropped', () async {
      final actions = <CallKitAction>[];
      final sub = bridge.userActions.listen(actions.add);

      bridge.handleNativeMethodForTest(
        const MethodCall('onCallKitAction', <String, Object?>{
          'action': 'wat',
          'callId': 'native_av_1',
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(actions, isEmpty);
      await sub.cancel();
    });

    test('CallKit reset surfaces synthetic end with empty callId', () async {
      final actions = <CallKitAction>[];
      final sub = bridge.userActions.listen(actions.add);

      bridge.handleNativeMethodForTest(
        const MethodCall('onCallKitReset', null),
      );
      await Future<void>.delayed(Duration.zero);

      expect(actions, hasLength(1));
      expect(actions.single.kind, CallKitActionKind.end);
      expect(actions.single.callId, isEmpty);
      await sub.cancel();
    });

    test('missing callId is dropped', () async {
      final actions = <CallKitAction>[];
      final sub = bridge.userActions.listen(actions.add);

      bridge.handleNativeMethodForTest(
        const MethodCall('onCallKitAction', <String, Object?>{
          'action': 'answer',
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(actions, isEmpty);
      await sub.cancel();
    });
  });

  group('CallKitBridge — non-iOS short-circuit', () {
    late TargetPlatform originalPlatform;

    setUp(() {
      originalPlatform =
          debugDefaultTargetPlatformOverride ?? TargetPlatform.android;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = originalPlatform;
    });

    test('isSupported is false on Android', () {
      final bridge = CallKitBridge(
        channel: const MethodChannel('toxee/callkit_noplatform'),
      );
      expect(bridge.isSupported, isFalse);
    });

    test(
      'methods short-circuit without hitting the channel on Android',
      () async {
        const channel = MethodChannel('toxee/callkit_noplatform_2');
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return null;
            });
        final bridge = CallKitBridge(channel: channel);

        final handled = await bridge.reportIncomingCall(
          callId: 'x',
          displayName: 'y',
          hasVideo: false,
        );
        expect(handled, isFalse);
        await bridge.reportOutgoingCall(
          callId: 'x',
          displayName: 'y',
          hasVideo: false,
        );
        await bridge.reportCallConnected(callId: 'x');
        await bridge.reportCallEnded(callId: 'x');

        expect(calls, isEmpty);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      },
    );
  });

  group('CallKitBridge.generateCallId', () {
    test('produces RFC4122-shape ids', () {
      final id = CallKitBridge.generateCallId();
      // 8-4-4-4-12 hex layout, version 4, variant 8/9/a/b.
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(pattern.hasMatch(id), isTrue, reason: 'id=$id');
    });

    test('produces unique ids across calls', () {
      final ids = <String>{
        for (var i = 0; i < 64; i++) CallKitBridge.generateCallId(),
      };
      expect(ids.length, 64);
    });
  });
}
