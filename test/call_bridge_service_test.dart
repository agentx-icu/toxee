// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimSignalingListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tim2tox_dart/interfaces/logger_service.dart';
import 'package:tim2tox_dart/service/call_bridge_service.dart';
import 'package:tim2tox_dart/service/tuicallkit_adapter.dart';

void main() {
  tearDown(() {
    getTUICallKitAdapter()?.dispose();
  });

  test(
    'registers outgoing signaling calls so they can be looked up and canceled',
    () async {
      final sdk = _FakeSdkPlatform();
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av);

      bridge.registerOutgoingCall(
        inviteID: 'invite-1',
        inviter: 'self',
        invitee: 'friend-1',
        data: '{"type":"audio","audio":true,"video":false}',
        friendNumber: 7,
      );
      // Model the adapter marking the media leg started after startCall()
      // succeeds, so endCall() tears the ToxAV leg down (not just signaling).
      bridge.markAvLegStarted('invite-1');

      final info = bridge.getCallInfo('invite-1');
      expect(info, isNotNull);
      expect(info!.inviter, 'self');
      expect(info.inviteeList, const ['friend-1']);
      expect(info.friendNumber, 7);
      expect(info.state, CallState.calling);

      await bridge.endCall('invite-1');

      expect(sdk.cancelledInviteIds, const ['invite-1']);
      expect(av.endedFriendNumbers, const [7]);
      expect(bridge.getCallInfo('invite-1'), isNull);
    },
  );

  test(
    'does not send signaling invite when outgoing call preflight denies',
    () async {
      final sdk = _FakeSdkPlatform();
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av);
      final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);

      adapter.onBeforeOutgoingCall = (_, __) async => false;

      final handled = await adapter.handleCall(
        type: TYPE_VIDEO,
        userids: const ['friend-1'],
      );

      expect(handled, isFalse);
      expect(sdk.inviteCallCount, 0);
      expect(bridge.getCallInfo('invite-1'), isNull);
    },
  );

  test('outgoing accept does not start the ToxAV leg twice', () async {
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend();
    final bridge = CallBridgeService(sdk, av);
    final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);
    final changes = <_CallChange>[];
    bridge.onCallStateChanged = (inviteID, state, {endReason}) {
      changes.add(_CallChange(inviteID, state, endReason));
    };

    final handled = await adapter.handleCall(
      type: TYPE_AUDIO,
      userids: const ['friend-1'],
    );
    sdk.listener!.onInviteeAccepted('invite-1', 'friend-1', '{}');

    expect(handled, isTrue);
    expect(av.startedFriendNumbers, const [7]);
    expect(bridge.getCallInfo('invite-1')?.state, CallState.inCall);
    expect(changes.single.state, CallState.inCall);
  });

  test('duplicate outgoing accept does not re-fire inCall', () async {
    // The signaling transport can redeliver an accept for an already
    // established call. The idempotency guard in onInviteeAccepted must skip
    // the second transition so the UI does not re-run enterCall / media
    // capture on a live call.
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend();
    final bridge = CallBridgeService(sdk, av);
    final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);
    final changes = <_CallChange>[];
    bridge.onCallStateChanged = (inviteID, state, {endReason}) {
      changes.add(_CallChange(inviteID, state, endReason));
    };

    await adapter.handleCall(type: TYPE_AUDIO, userids: const ['friend-1']);
    sdk.listener!.onInviteeAccepted('invite-1', 'friend-1', '{}');
    sdk.listener!.onInviteeAccepted('invite-1', 'friend-1', '{}');

    expect(
      changes.where((c) => c.state == CallState.inCall).length,
      1,
      reason: 'a redelivered accept must not re-fire the inCall callback',
    );
    expect(bridge.getCallInfo('invite-1')?.state, CallState.inCall);
  });

  test('outgoing call cancels signaling when ToxAV start fails', () async {
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend()..startResult = false;
    final bridge = CallBridgeService(sdk, av);
    final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);

    final handled = await adapter.handleCall(
      type: TYPE_AUDIO,
      userids: const ['friend-1'],
    );

    expect(handled, isFalse);
    expect(av.startedFriendNumbers, const [7]);
    expect(sdk.cancelledInviteIds, const ['invite-1']);
    expect(bridge.getCallInfo('invite-1'), isNull);
  });

  test('replacement outgoing call clears a stale tracked media leg', () async {
    final sdk = _FakeSdkPlatform()..inviteIDs.add('invite-2');
    final av = _FakeAvBackend();
    final bridge = CallBridgeService(sdk, av);
    final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);
    adapter.isCallIdle = () => true;

    expect(
      await adapter.handleCall(type: TYPE_AUDIO, userids: const ['friend-1']),
      isTrue,
    );
    final endsBeforeReplacement = av.endedFriendNumbers.length;
    expect(endsBeforeReplacement, 0);
    expect(
      await adapter.handleCall(type: TYPE_AUDIO, userids: const ['friend-1']),
      isTrue,
    );

    expect(av.endedFriendNumbers.length, greaterThan(endsBeforeReplacement));
    expect(bridge.getCallInfo('invite-1'), isNull);
    expect(bridge.getCallInfo('invite-2'), isNotNull);
  });

  test(
    'out-of-order duplicate setup cannot replace the newer invite',
    () async {
      final sdk = _FakeSdkPlatform();
      final firstInvite = Completer<V2TimValueCallback<String>>();
      final secondInvite = Completer<V2TimValueCallback<String>>();
      sdk.inviteCompleters.addAll([firstInvite, secondInvite]);
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av);
      final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);

      final first = adapter.handleCall(
        type: TYPE_AUDIO,
        userids: const ['friend-1'],
      );
      final second = adapter.handleCall(
        type: TYPE_AUDIO,
        userids: const ['friend-1'],
      );
      secondInvite.complete(
        V2TimValueCallback<String>(code: 0, desc: 'ok', data: 'invite-2'),
      );
      expect(await second, isTrue);
      firstInvite.complete(
        V2TimValueCallback<String>(code: 0, desc: 'ok', data: 'invite-1'),
      );

      expect(await first, isFalse);
      expect(sdk.cancelledInviteIds, contains('invite-1'));
      expect(bridge.getCallInfo('invite-1'), isNull);
      expect(bridge.getCallInfo('invite-2'), isNotNull);
    },
  );

  test(
    'replacement teardown continuation cannot overwrite a newer call',
    () async {
      final sdk = _FakeSdkPlatform()
        ..inviteIDs.addAll(['invite-2', 'invite-3']);
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av);
      final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);
      adapter.isCallIdle = () => true;

      expect(
        await adapter.handleCall(type: TYPE_AUDIO, userids: const ['friend-1']),
        isTrue,
      );
      Future<bool>? newest;
      var launchedNewest = false;
      bridge.onCallStateChanged = (inviteID, state, {endReason}) {
        if (!launchedNewest &&
            inviteID == 'invite-1' &&
            state == CallState.ended) {
          launchedNewest = true;
          newest = adapter.handleCall(
            type: TYPE_AUDIO,
            userids: const ['friend-1'],
          );
        }
      };

      final staleReplacement = adapter.handleCall(
        type: TYPE_AUDIO,
        userids: const ['friend-1'],
      );
      expect(await staleReplacement, isFalse);
      expect(await newest, isTrue);
      expect(sdk.cancelledInviteIds, contains('invite-2'));
      expect(bridge.getCallInfo('invite-2'), isNull);
      expect(bridge.getCallInfo('invite-3'), isNotNull);
    },
  );

  test('stale startCall completion cannot claim a newer call', () async {
    final sdk = _FakeSdkPlatform()..inviteIDs.add('invite-2');
    final av = _FakeAvBackend();
    final firstStart = Completer<bool>();
    final secondStart = Completer<bool>();
    av.startCompleters.addAll([firstStart, secondStart]);
    final firstStartCalled = Completer<void>();
    final secondStartCalled = Completer<void>();
    av.startCallSignals.addAll([firstStartCalled, secondStartCalled]);
    final bridge = CallBridgeService(sdk, av);
    final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);
    adapter.isCallIdle = () => true;

    final first = adapter.handleCall(
      type: TYPE_AUDIO,
      userids: const ['friend-1'],
    );
    await firstStartCalled.future;
    final second = adapter.handleCall(
      type: TYPE_AUDIO,
      userids: const ['friend-1'],
    );
    firstStart.complete(true);
    expect(await first, isFalse);
    await secondStartCalled.future;
    secondStart.complete(true);
    expect(await second, isTrue);
    expect(av.endedFriendNumbers, const [7]);
    expect(bridge.getCallInfo('invite-1'), isNull);
    expect(bridge.getCallInfo('invite-2'), isNotNull);
  });

  test('stale failed start cleans up before replacement start', () async {
    final sdk = _FakeSdkPlatform()..inviteIDs.add('invite-2');
    final av = _FakeAvBackend();
    final firstStart = Completer<bool>();
    final secondStart = Completer<bool>();
    av.startCompleters.addAll([firstStart, secondStart]);
    final firstStartCalled = Completer<void>();
    final secondStartCalled = Completer<void>();
    av.startCallSignals.addAll([firstStartCalled, secondStartCalled]);
    final bridge = CallBridgeService(sdk, av);
    final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);

    final first = adapter.handleCall(
      type: TYPE_AUDIO,
      userids: const ['friend-1'],
    );
    await firstStartCalled.future;
    final second = adapter.handleCall(
      type: TYPE_AUDIO,
      userids: const ['friend-1'],
    );
    firstStart.complete(false);

    expect(await first, isFalse);
    await secondStartCalled.future;
    secondStart.complete(true);
    expect(await second, isTrue);
    expect(sdk.cancelledInviteIds, contains('invite-1'));
    expect(bridge.getCallInfo('invite-1'), isNull);
    expect(bridge.getCallInfo('invite-2'), isNotNull);
  });

  test('native start exception cleans up its owned invite', () async {
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend()
      ..startOutcomes.add(_ThrowingOutcome(StateError('start failed')));
    final bridge = CallBridgeService(sdk, av);
    final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);
    final handled = await adapter.handleCall(
      type: TYPE_AUDIO,
      userids: const ['friend-1'],
    );

    expect(handled, isFalse);
    expect(sdk.cancelledInviteIds, const ['invite-1']);
    expect(bridge.getCallInfo('invite-1'), isNull);
  });

  group('onCallSetupFailed surfacing (failures must not be silent)', () {
    Future<(bool, List<CallSetupFailureReason>)> runCall({
      required _FakeSdkPlatform sdk,
      required _FakeAvBackend av,
      List<String> userids = const ['friend-1'],
      OutgoingCallPreflight? preflight,
    }) async {
      final bridge = CallBridgeService(sdk, av);
      final adapter = await TUICallKitAdapter.initialize(sdk, av, bridge);
      final reasons = <CallSetupFailureReason>[];
      adapter.onCallSetupFailed = (reason, _) => reasons.add(reason);
      if (preflight != null) adapter.onBeforeOutgoingCall = preflight;
      final handled = await adapter.handleCall(
        type: TYPE_AUDIO,
        userids: userids,
      );
      return (handled, reasons);
    }

    test('multiple invitees reports groupCallsUnsupported', () async {
      final (handled, reasons) = await runCall(
        sdk: _FakeSdkPlatform(),
        av: _FakeAvBackend(),
        userids: const ['friend-1', 'friend-2'],
      );
      expect(handled, isFalse);
      expect(reasons, const [CallSetupFailureReason.groupCallsUnsupported]);
    });

    test('preflight denial reports preflightDenied (embedder-owned, so the '
        'embedder can skip double-notifying)', () async {
      final (handled, reasons) = await runCall(
        sdk: _FakeSdkPlatform(),
        av: _FakeAvBackend(),
        preflight: (_, __) async => false,
      );
      expect(handled, isFalse);
      expect(reasons, const [CallSetupFailureReason.preflightDenied]);
    });

    test('signaling invite failure reports inviteFailed', () async {
      final (handled, reasons) = await runCall(
        sdk: _FakeSdkPlatform()..inviteCode = 6014,
        av: _FakeAvBackend(),
      );
      expect(handled, isFalse);
      expect(reasons, const [CallSetupFailureReason.inviteFailed]);
    });

    test('ToxAV start failure reports avStartFailed', () async {
      final (handled, reasons) = await runCall(
        sdk: _FakeSdkPlatform(),
        av: _FakeAvBackend()..startResult = false,
      );
      expect(handled, isFalse);
      expect(reasons, const [CallSetupFailureReason.avStartFailed]);
    });

    test('successful call fires no failure callback', () async {
      final (handled, reasons) = await runCall(
        sdk: _FakeSdkPlatform(),
        av: _FakeAvBackend(),
      );
      expect(handled, isTrue);
      expect(reasons, isEmpty);
    });
  });

  test(
    'acceptInvitation returns false when SDK accept returns non-zero code',
    () async {
      final sdk = _FakeSdkPlatform()..acceptCode = 7000;
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av);
      bridge.registerOutgoingCall(
        inviteID: 'invite-A',
        inviter: 'peer',
        invitee: 'self',
        data: '{"type":"audio"}',
        friendNumber: 3,
      );

      final ok = await bridge.acceptInvitation('invite-A');

      expect(
        ok,
        isFalse,
        reason:
            'SDK accept failed; the async result must propagate to the caller. '
            'Pre-fix the void contract silently dropped this branch.',
      );
      expect(
        av.answeredFriendNumbers,
        isEmpty,
        reason: 'ToxAV answer must not be issued when signaling accept fails',
      );
    },
  );

  test(
    'acceptInvitation rejects unresolved friend before SDK accept or AV answer',
    () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform();
        final av = _FakeAvBackend()
          ..friendNumber = 0xFFFFFFFF
          ..answerResult = false;
        final bridge = CallBridgeService(sdk, av);
        final changes = <_CallChange>[];
        bridge.onCallStateChanged = (inviteID, state, {endReason}) {
          changes.add(_CallChange(inviteID, state, endReason));
        };
        _receiveIncomingInvite(sdk, inviteID: 'invite-unresolved-friend');

        final ok = _expectFutureValue(
          asyncZone,
          bridge.acceptInvitation('invite-unresolved-friend'),
        );

        expect(ok, isFalse);
        expect(
          sdk.acceptCallCount,
          0,
          reason: 'unresolved Tox friend must fail before signaling accept',
        );
        expect(
          av.answeredFriendNumbers,
          isEmpty,
          reason: 'unresolved Tox friend must fail before ToxAV answer',
        );
        expect(sdk.rejectedInviteIds, const ['invite-unresolved-friend']);
        expect(bridge.getCallInfo('invite-unresolved-friend'), isNull);
        expect(changes.last.state, CallState.ended);
        expect(changes.last.endReason, 'cancel');
      });
    },
  );

  test('acceptInvitation returns false when ToxAV answer fails', () async {
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend()..answerResult = false;
    final bridge = CallBridgeService(sdk, av);
    bridge.registerOutgoingCall(
      inviteID: 'invite-B',
      inviter: 'peer',
      invitee: 'self',
      data: '{"type":"audio"}',
      friendNumber: 4,
    );

    final ok = await bridge.acceptInvitation('invite-B');

    expect(ok, isFalse);
    expect(av.answeredFriendNumbers, const [4]);
  });

  test(
    'endCall is a no-op for an unknown inviteID instead of throwing',
    () async {
      final sdk = _FakeSdkPlatform();
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av);

      final ok = await bridge.endCall('never-registered');

      expect(ok, isFalse);
      expect(av.endedFriendNumbers, isEmpty);
      expect(sdk.cancelledInviteIds, isEmpty);
    },
  );

  test('rejectInvitation propagates SDK reject failure to caller', () async {
    final sdk = _FakeSdkPlatform()..rejectCode = 6000;
    final av = _FakeAvBackend();
    final bridge = CallBridgeService(sdk, av);
    bridge.registerOutgoingCall(
      inviteID: 'invite-R',
      inviter: 'peer',
      invitee: 'self',
      data: '{}',
      friendNumber: 5,
    );

    final ok = await bridge.rejectInvitation('invite-R');

    expect(ok, isFalse);
  });

  test(
    'incoming cancellation while ringing does not end an unanswered ToxAV leg',
    () async {
      final sdk = _FakeSdkPlatform();
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av);
      final changes = <_CallChange>[];
      bridge.onCallStateChanged = (inviteID, state, {endReason}) {
        changes.add(_CallChange(inviteID, state, endReason));
      };

      sdk.listener!.onReceiveNewInvitation(
        'invite-in-cancel',
        'peer-1',
        '',
        const ['self'],
        '{"type":"audio","audio":true,"video":false}',
      );
      sdk.listener!.onInvitationCancelled('invite-in-cancel', 'peer-1', '{}');

      expect(av.endedFriendNumbers, isEmpty);
      expect(bridge.getCallInfo('invite-in-cancel'), isNull);
      expect(changes.last.state, CallState.ended);
      expect(changes.last.endReason, 'cancel');
    },
  );

  test('incoming cancellation after prior inCall emits hangup', () {
    fakeAsync((asyncZone) {
      final sdk = _FakeSdkPlatform();
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av);
      final changes = <_CallChange>[];
      bridge.onCallStateChanged = (inviteID, state, {endReason}) {
        changes.add(_CallChange(inviteID, state, endReason));
      };
      _receiveIncomingInvite(sdk, inviteID: 'invite-in-call-cancel');
      final accepted = _expectFutureValue(
        asyncZone,
        bridge.acceptInvitation('invite-in-call-cancel'),
      );

      sdk.listener!.onInvitationCancelled(
        'invite-in-call-cancel',
        'peer-1',
        '{}',
      );
      asyncZone.flushMicrotasks();

      expect(accepted, isTrue);
      expect(av.endedFriendNumbers, const [7]);
      expect(bridge.getCallInfo('invite-in-call-cancel'), isNull);
      expect(changes.last.state, CallState.ended);
      expect(changes.last.endReason, 'hangup');
    });
  });

  test(
    'incoming timeout while ringing does not end an unanswered ToxAV leg',
    () async {
      final sdk = _FakeSdkPlatform();
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av);
      final changes = <_CallChange>[];
      bridge.onCallStateChanged = (inviteID, state, {endReason}) {
        changes.add(_CallChange(inviteID, state, endReason));
      };

      sdk.listener!.onReceiveNewInvitation(
        'invite-in-timeout',
        'peer-1',
        '',
        const ['self'],
        '{"type":"audio","audio":true,"video":false}',
      );
      sdk.listener!.onInvitationTimeout('invite-in-timeout', const ['self']);

      expect(av.endedFriendNumbers, isEmpty);
      expect(bridge.getCallInfo('invite-in-timeout'), isNull);
      expect(changes.last.state, CallState.ended);
      expect(changes.last.endReason, 'timeout');
    },
  );

  test('outgoing rejection tears down the already-started ToxAV leg', () {
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend();
    final bridge = CallBridgeService(sdk, av);
    final changes = <_CallChange>[];
    bridge.onCallStateChanged = (inviteID, state, {endReason}) {
      changes.add(_CallChange(inviteID, state, endReason));
    };

    bridge.registerOutgoingCall(
      inviteID: 'invite-out-reject',
      inviter: 'self',
      invitee: 'friend-1',
      data: '{"type":"audio","audio":true,"video":false}',
      friendNumber: 7,
    );
    // The ToxAV leg actually started (adapter called startCall → markAvLegStarted).
    bridge.markAvLegStarted('invite-out-reject');
    sdk.listener!.onInviteeRejected('invite-out-reject', 'friend-1', '{}');

    expect(av.endedFriendNumbers, const [7]);
    expect(bridge.getCallInfo('invite-out-reject'), isNull);
    expect(changes.single.state, CallState.ended);
    expect(changes.single.endReason, 'reject');
  });

  test('outgoing timeout tears down the already-started ToxAV leg', () {
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend();
    final bridge = CallBridgeService(sdk, av);
    final changes = <_CallChange>[];
    bridge.onCallStateChanged = (inviteID, state, {endReason}) {
      changes.add(_CallChange(inviteID, state, endReason));
    };

    bridge.registerOutgoingCall(
      inviteID: 'invite-out-timeout',
      inviter: 'self',
      invitee: 'friend-1',
      data: '{"type":"audio","audio":true,"video":false}',
      friendNumber: 7,
    );
    // The ToxAV leg actually started (adapter called startCall → markAvLegStarted).
    bridge.markAvLegStarted('invite-out-timeout');
    sdk.listener!.onInvitationTimeout('invite-out-timeout', const ['friend-1']);

    expect(av.endedFriendNumbers, const [7]);
    expect(bridge.getCallInfo('invite-out-timeout'), isNull);
    expect(changes.single.state, CallState.ended);
    expect(changes.single.endReason, 'timeout');
  });

  test('outgoing teardown in the registerOutgoingCall->startCall gap does not '
      'end a never-started ToxAV leg', () {
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend();
    final bridge = CallBridgeService(sdk, av);
    final changes = <_CallChange>[];
    bridge.onCallStateChanged = (inviteID, state, {endReason}) {
      changes.add(_CallChange(inviteID, state, endReason));
    };

    // Registered (state: calling), friendNumber resolved — but the adapter has
    // NOT yet reached _avService.startCall() / markAvLegStarted. This is the
    // realistic gap where a fast reject/timeout/cancel can land.
    bridge.registerOutgoingCall(
      inviteID: 'invite-out-gap',
      inviter: 'self',
      invitee: 'friend-1',
      data: '{"type":"audio","audio":true,"video":false}',
      friendNumber: 7,
    );
    sdk.listener!.onInvitationTimeout('invite-out-gap', const ['friend-1']);

    // No media leg existed yet, so endCall() must NOT fire on it (native
    // endCall with no call in progress can block/error).
    expect(av.endedFriendNumbers, isEmpty);
    expect(bridge.getCallInfo('invite-out-gap'), isNull);
    expect(changes.single.state, CallState.ended);
    expect(changes.single.endReason, 'timeout');
  });

  test(
    'outgoing invite removed synchronously after UI initiation does not start '
    'AV and returns false',
    () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform();
        final av = _FakeAvBackend();
        final bridge = CallBridgeService(sdk, av);
        final adapter = _expectFutureValue(
          asyncZone,
          TUICallKitAdapter.initialize(sdk, av, bridge),
        );
        adapter.isCallIdle = () => true;
        late Future<bool> removeFuture;
        adapter.onOutgoingCallInitiated = (inviteID, _, __) {
          removeFuture = bridge.endCall(inviteID);
        };

        final handled = _expectFutureValue(
          asyncZone,
          adapter.handleCall(type: TYPE_AUDIO, userids: const ['friend-1']),
        );
        final removed = _expectFutureValue(asyncZone, removeFuture);

        expect(removed, isTrue);
        expect(handled, isFalse);
        expect(
          av.startedFriendNumbers,
          isEmpty,
          reason: 'call was removed by UI before adapter reached startCall',
        );
        expect(bridge.getCallInfo('invite-1'), isNull);
      });
    },
  );

  test('outgoing invite removed while startCall awaits ends new AV leg and '
      'returns false', () {
    fakeAsync((asyncZone) {
      final sdk = _FakeSdkPlatform();
      final av = _FakeAvBackend()
        ..startCompleter = Completer<bool>()
        ..endOutcomes.addAll(const [false, true]);
      final bridge = CallBridgeService(sdk, av);
      final adapter = _expectFutureValue(
        asyncZone,
        TUICallKitAdapter.initialize(sdk, av, bridge),
      );
      adapter.isCallIdle = () => true;

      final handledFuture = adapter.handleCall(
        type: TYPE_AUDIO,
        userids: const ['friend-1'],
      );
      asyncZone.flushMicrotasks();
      expect(av.startedFriendNumbers, const [7]);

      final removed = _expectFutureValue(asyncZone, bridge.endCall('invite-1'));
      expect(removed, isTrue);
      expect(bridge.getCallInfo('invite-1'), isNull);
      expect(
        av.endedFriendNumbers,
        isEmpty,
        reason: 'the AV leg has not succeeded yet',
      );

      av.startCompleter!.complete(true);
      final result = _settleFuture(asyncZone, handledFuture);

      expect(result.error, isNull);
      expect(result.value, isFalse);
      expect(av.endedFriendNumbers, const [7]);
      expect(asyncZone.nonPeriodicTimerCount, greaterThan(0));

      _drainTeardownRetryBudget(asyncZone);

      expect(av.endedFriendNumbers, const [7, 7]);
      expect(asyncZone.nonPeriodicTimerCount, 0);
    });
  });

  test(
    'incoming call removed while SDK accept awaits never answers or inCalls',
    () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform()
          ..acceptCompleter = Completer<V2TimCallback>();
        final av = _FakeAvBackend();
        final bridge = CallBridgeService(sdk, av);
        final changes = <_CallChange>[];
        bridge.onCallStateChanged = (inviteID, state, {endReason}) {
          changes.add(_CallChange(inviteID, state, endReason));
        };
        _receiveIncomingInvite(sdk, inviteID: 'invite-accept-race');

        final acceptFuture = bridge.acceptInvitation('invite-accept-race');
        asyncZone.flushMicrotasks();
        expect(sdk.acceptCallCount, 1);
        expect(av.answeredFriendNumbers, isEmpty);

        sdk.listener!.onInvitationCancelled(
          'invite-accept-race',
          'peer-1',
          '{}',
        );
        expect(bridge.getCallInfo('invite-accept-race'), isNull);

        sdk.acceptCompleter!.complete(V2TimCallback(code: 0, desc: 'ok'));
        final result = _settleFuture(asyncZone, acceptFuture);

        expect(result.error, isNull);
        expect(result.value, isFalse);
        expect(
          av.answeredFriendNumbers,
          isEmpty,
          reason: 'removed call must not be answered after SDK accept resolves',
        );
        expect(changes.where((c) => c.state == CallState.inCall), isEmpty);
      });
    },
  );

  test('incoming call removed while answer awaits ends new AV leg and never '
      'emits inCall', () {
    fakeAsync((asyncZone) {
      final sdk = _FakeSdkPlatform();
      final av = _FakeAvBackend()
        ..answerCompleter = Completer<bool>()
        ..endOutcomes.addAll(const [false, true]);
      final bridge = CallBridgeService(sdk, av);
      final changes = <_CallChange>[];
      bridge.onCallStateChanged = (inviteID, state, {endReason}) {
        changes.add(_CallChange(inviteID, state, endReason));
      };
      _receiveIncomingInvite(sdk, inviteID: 'invite-answer-race');

      final acceptFuture = bridge.acceptInvitation('invite-answer-race');
      asyncZone.flushMicrotasks();
      expect(av.answeredFriendNumbers, const [7]);

      sdk.listener!.onInvitationCancelled('invite-answer-race', 'peer-1', '{}');
      expect(bridge.getCallInfo('invite-answer-race'), isNull);

      av.answerCompleter!.complete(true);
      final result = _settleFuture(asyncZone, acceptFuture);

      expect(result.error, isNull);
      expect(result.value, isFalse);
      expect(changes.where((c) => c.state == CallState.inCall), isEmpty);
      expect(av.endedFriendNumbers, const [7]);
      expect(asyncZone.nonPeriodicTimerCount, greaterThan(0));

      _drainTeardownRetryBudget(asyncZone);

      expect(av.endedFriendNumbers, const [7, 7]);
      expect(asyncZone.nonPeriodicTimerCount, 0);
    });
  });

  group('bounded hidden teardown cleanup', () {
    test('replacement waits for a pending friend AV teardown', () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform()..inviteIDs.add('invite-2');
        final av = _FakeAvBackend()..endOutcomes.addAll(const [false, true]);
        final bridge = CallBridgeService(sdk, av);
        final adapter = _expectFutureValue(
          asyncZone,
          TUICallKitAdapter.initialize(sdk, av, bridge),
        );
        adapter.isCallIdle = () => true;

        expect(
          _expectFutureValue(
            asyncZone,
            adapter.handleCall(type: TYPE_AUDIO, userids: const ['friend-1']),
          ),
          isTrue,
        );
        _expectFutureValue(asyncZone, bridge.endCall('invite-1'));
        expect(av.endedFriendNumbers, const [7]);
        expect(asyncZone.nonPeriodicTimerCount, greaterThan(0));

        final replacement = adapter.handleCall(
          type: TYPE_AUDIO,
          userids: const ['friend-1'],
        );
        asyncZone.flushMicrotasks();
        expect(av.startedFriendNumbers, const [7]);

        _drainTeardownRetryBudget(asyncZone);
        expect(av.endedFriendNumbers, const [7, 7]);
        expect(_expectFutureValue(asyncZone, replacement), isTrue);
        expect(av.startedFriendNumbers, const [7, 7]);
      });
    });

    test('incoming answer waits for a pending friend AV teardown', () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform();
        final av = _FakeAvBackend()..endOutcomes.addAll(const [false, true]);
        final bridge = CallBridgeService(sdk, av);
        bridge.registerOutgoingCall(
          inviteID: 'invite-old-av',
          inviter: 'self',
          invitee: 'friend-1',
          data: '{}',
          friendNumber: 7,
        );
        bridge.markAvLegStarted('invite-old-av');
        _expectFutureValue(asyncZone, bridge.endCall('invite-old-av'));
        expect(av.endedFriendNumbers, const [7]);

        _receiveIncomingInvite(sdk, inviteID: 'invite-incoming-fence');
        final accept = bridge.acceptInvitation('invite-incoming-fence');
        asyncZone.flushMicrotasks();
        expect(
          av.answeredFriendNumbers,
          isEmpty,
          reason: 'incoming answer must wait for old AV teardown retries',
        );

        _drainTeardownRetryBudget(asyncZone);
        expect(av.endedFriendNumbers, const [7, 7]);
        expect(_expectFutureValue(asyncZone, accept), isTrue);
        expect(av.answeredFriendNumbers, const [7]);
      });
    });

    test('awaited AV teardown waits through bounded retry terminal state', () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform();
        final av = _FakeAvBackend()..endOutcomes.addAll(const [false, true]);
        final bridge = CallBridgeService(sdk, av);
        bridge.registerOutgoingCall(
          inviteID: 'invite-await-av',
          inviter: 'self',
          invitee: 'friend-1',
          data: '{}',
          friendNumber: 7,
        );
        bridge.markAvLegStarted('invite-await-av');

        final teardown = bridge.endAvLegAndWaitForTeardown(
          'invite-await-av',
          7,
        );
        asyncZone.flushMicrotasks();
        expect(av.endedFriendNumbers, const [7]);
        expect(asyncZone.nonPeriodicTimerCount, greaterThan(0));

        var completed = false;
        teardown.then((_) => completed = true);
        asyncZone.flushMicrotasks();
        expect(completed, isFalse);

        _drainTeardownRetryBudget(asyncZone);
        expect(av.endedFriendNumbers, const [7, 7]);
        expect(completed, isTrue);
        expect(asyncZone.nonPeriodicTimerCount, 0);
      });
    });

    test('rejectInvitation hides ringing call while SDK reject result-code '
        'failure retries to bounded success', () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform()..rejectOutcomes.addAll(const [6000, 0]);
        final av = _FakeAvBackend();
        final bridge = CallBridgeService(sdk, av);
        final changes = <_CallChange>[];
        bridge.onCallStateChanged = (inviteID, state, {endReason}) {
          changes.add(_CallChange(inviteID, state, endReason));
        };
        _receiveIncomingInvite(sdk, inviteID: 'invite-reject-code');

        final result = _settleFuture(
          asyncZone,
          bridge.rejectInvitation('invite-reject-code'),
        );

        expect(result.error, isNull);
        expect(result.value, isFalse);
        expect(
          bridge.getCallInfo('invite-reject-code'),
          isNull,
          reason: 'failed signaling teardown must not keep visible call state',
        );
        expect(changes.last.state, CallState.ended);
        expect(changes.last.endReason, 'reject');
        expect(sdk.rejectedInviteIds, const ['invite-reject-code']);
        expect(asyncZone.nonPeriodicTimerCount, greaterThan(0));

        _drainTeardownRetryBudget(asyncZone);

        expect(sdk.rejectedInviteIds, const [
          'invite-reject-code',
          'invite-reject-code',
        ]);
        expect(asyncZone.nonPeriodicTimerCount, 0);
        asyncZone.elapse(_teardownRetryBudget);
        expect(
          sdk.rejectedInviteIds.length,
          2,
          reason: 'successful hidden cleanup must drop its private retry key',
        );
      });
    });

    test(
      'rejectInvitation hides ringing call when SDK reject throws and retries '
      'to bounded success',
      () {
        fakeAsync((asyncZone) {
          final sdk = _FakeSdkPlatform()
            ..rejectOutcomes.addAll([
              _ThrowingOutcome(StateError('reject transport failed')),
              0,
            ]);
          final av = _FakeAvBackend();
          final bridge = CallBridgeService(sdk, av);
          final changes = <_CallChange>[];
          bridge.onCallStateChanged = (inviteID, state, {endReason}) {
            changes.add(_CallChange(inviteID, state, endReason));
          };
          _receiveIncomingInvite(sdk, inviteID: 'invite-reject-exception');

          final result = _settleFuture(
            asyncZone,
            bridge.rejectInvitation('invite-reject-exception'),
          );

          expect(
            result.error,
            isNull,
            reason: 'SDK exceptions should be converted into cleanup failure',
          );
          expect(result.value, isFalse);
          expect(bridge.getCallInfo('invite-reject-exception'), isNull);
          expect(changes.last.state, CallState.ended);
          expect(changes.last.endReason, 'reject');

          _drainTeardownRetryBudget(asyncZone);

          expect(sdk.rejectedInviteIds, const [
            'invite-reject-exception',
            'invite-reject-exception',
          ]);
          expect(asyncZone.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'endCall hides outgoing pre-answer cancel while SDK cancel result-code '
      'failure retries to bounded exhaustion',
      () {
        fakeAsync((asyncZone) {
          final sdk = _FakeSdkPlatform()
            ..cancelOutcomes.addAll(
              List<int>.filled(_maxTeardownAttempts, 6000),
            );
          final av = _FakeAvBackend();
          final bridge = CallBridgeService(sdk, av);
          final changes = <_CallChange>[];
          bridge.onCallStateChanged = (inviteID, state, {endReason}) {
            changes.add(_CallChange(inviteID, state, endReason));
          };
          _registerOutgoing(bridge, inviteID: 'invite-cancel-code');

          final ok = _expectFutureValue(
            asyncZone,
            bridge.endCall('invite-cancel-code'),
          );

          expect(ok, isTrue);
          expect(bridge.getCallInfo('invite-cancel-code'), isNull);
          expect(changes.single.state, CallState.ended);
          expect(changes.single.endReason, 'cancel');
          expect(sdk.cancelledInviteIds, const ['invite-cancel-code']);
          expect(asyncZone.nonPeriodicTimerCount, greaterThan(0));

          _drainTeardownRetryBudget(asyncZone);

          expect(sdk.cancelledInviteIds.length, _maxTeardownAttempts);
          expect(asyncZone.nonPeriodicTimerCount, 0);
          asyncZone.elapse(_teardownRetryBudget);
          expect(
            sdk.cancelledInviteIds.length,
            _maxTeardownAttempts,
            reason: 'exhausted hidden cleanup must drop its private retry key',
          );
        });
      },
    );

    test('endCall hides active AV hangup while ToxAV endCall result-code '
        'failure retries to bounded success', () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform();
        final av = _FakeAvBackend()..endOutcomes.addAll(const [false, true]);
        final bridge = CallBridgeService(sdk, av);
        final changes = <_CallChange>[];
        bridge.onCallStateChanged = (inviteID, state, {endReason}) {
          changes.add(_CallChange(inviteID, state, endReason));
        };
        _registerOutgoing(
          bridge,
          inviteID: 'invite-av-code',
          markAvLegStarted: true,
        );
        sdk.listener!.onInviteeAccepted('invite-av-code', 'friend-1', '{}');

        final ok = _expectFutureValue(
          asyncZone,
          bridge.endCall('invite-av-code'),
        );

        expect(ok, isTrue);
        expect(bridge.getCallInfo('invite-av-code'), isNull);
        expect(changes.last.state, CallState.ended);
        expect(changes.last.endReason, 'hangup');
        expect(av.endedFriendNumbers, const [7]);
        expect(asyncZone.nonPeriodicTimerCount, greaterThan(0));

        _drainTeardownRetryBudget(asyncZone);

        expect(av.endedFriendNumbers, const [7, 7]);
        expect(asyncZone.nonPeriodicTimerCount, 0);
        asyncZone.elapse(_teardownRetryBudget);
        expect(
          av.endedFriendNumbers.length,
          2,
          reason:
              'successful hidden AV cleanup must drop its private retry key',
        );
      });
    });

    test('dispose cancels pending hidden teardown retry', () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform()..cancelOutcomes.addAll(const [6000, 0]);
        final av = _FakeAvBackend();
        final bridge = CallBridgeService(sdk, av);
        _registerOutgoing(bridge, inviteID: 'invite-dispose-cancel');

        final ok = _expectFutureValue(
          asyncZone,
          bridge.endCall('invite-dispose-cancel'),
        );

        expect(ok, isTrue);
        expect(bridge.getCallInfo('invite-dispose-cancel'), isNull);
        expect(sdk.cancelledInviteIds, const ['invite-dispose-cancel']);
        expect(asyncZone.nonPeriodicTimerCount, greaterThan(0));

        bridge.dispose();
        expect(asyncZone.nonPeriodicTimerCount, 0);
        asyncZone.elapse(_teardownRetryBudget);

        expect(sdk.cancelledInviteIds, const ['invite-dispose-cancel']);
      });
    });

    test('stale AV retry does not end a newer active call for same friend', () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform();
        final av = _FakeAvBackend()..endOutcomes.addAll(const [false, true]);
        final bridge = CallBridgeService(sdk, av);

        _registerOutgoing(
          bridge,
          inviteID: 'invite-stale-ended',
          markAvLegStarted: true,
        );
        sdk.listener!.onInviteeAccepted('invite-stale-ended', 'friend-1', '{}');
        final ok = _expectFutureValue(
          asyncZone,
          bridge.endCall('invite-stale-ended'),
        );

        expect(ok, isTrue);
        expect(av.endedFriendNumbers, const [7]);
        expect(asyncZone.nonPeriodicTimerCount, 1);

        _registerOutgoing(
          bridge,
          inviteID: 'invite-new-active',
          markAvLegStarted: true,
        );
        sdk.listener!.onInviteeAccepted('invite-new-active', 'friend-1', '{}');
        expect(
          bridge.getCallInfo('invite-new-active')?.state,
          CallState.inCall,
        );

        asyncZone.elapse(const Duration(seconds: 1));
        asyncZone.flushMicrotasks();

        expect(
          av.endedFriendNumbers,
          const [7],
          reason: 'stale retry must not end the newer call on the same friend',
        );
        expect(
          bridge.getCallInfo('invite-new-active')?.state,
          CallState.inCall,
        );

        bridge.dispose();
        expect(asyncZone.nonPeriodicTimerCount, 0);
      });
    });

    test('SDK accept failure hides call and bounded-retries reject code and '
        'exception failures', () {
      fakeAsync((asyncZone) {
        final sdk = _FakeSdkPlatform()
          ..acceptCode = 7000
          ..rejectOutcomes.addAll([
            6000,
            _ThrowingOutcome(StateError('reject retry failed')),
            0,
          ]);
        final av = _FakeAvBackend();
        final bridge = CallBridgeService(sdk, av);
        final changes = <_CallChange>[];
        bridge.onCallStateChanged = (inviteID, state, {endReason}) {
          changes.add(_CallChange(inviteID, state, endReason));
        };
        _receiveIncomingInvite(sdk, inviteID: 'invite-accept-code');

        final ok = _expectFutureValue(
          asyncZone,
          bridge.acceptInvitation('invite-accept-code'),
        );

        expect(ok, isFalse);
        expect(
          bridge.getCallInfo('invite-accept-code'),
          isNull,
          reason: 'failed accept teardown must not keep visible call state',
        );
        expect(changes.last.state, CallState.ended);
        expect(changes.last.endReason, 'cancel');
        expect(sdk.rejectedInviteIds, const ['invite-accept-code']);
        expect(asyncZone.nonPeriodicTimerCount, greaterThan(0));

        _drainTeardownRetryBudget(asyncZone);

        expect(sdk.rejectedInviteIds, const [
          'invite-accept-code',
          'invite-accept-code',
          'invite-accept-code',
        ]);
        expect(asyncZone.nonPeriodicTimerCount, 0);
        asyncZone.elapse(_teardownRetryBudget);
        expect(
          sdk.rejectedInviteIds.length,
          3,
          reason: 'successful accept-failure reject cleanup must drop state',
        );
      });
    });

    test(
      'post-accept answer failure hides call and bounded-retries AV end without '
      'signaling cancel',
      () {
        fakeAsync((asyncZone) {
          final sdk = _FakeSdkPlatform();
          final av = _FakeAvBackend()
            ..answerResult = false
            ..endOutcomes.addAll(const [false, true]);
          final bridge = CallBridgeService(sdk, av);
          final changes = <_CallChange>[];
          bridge.onCallStateChanged = (inviteID, state, {endReason}) {
            changes.add(_CallChange(inviteID, state, endReason));
          };
          _receiveIncomingInvite(sdk, inviteID: 'invite-answer-fail');

          final ok = _expectFutureValue(
            asyncZone,
            bridge.acceptInvitation('invite-answer-fail'),
          );

          expect(ok, isFalse);
          expect(av.answeredFriendNumbers, const [7]);
          expect(
            bridge.getCallInfo('invite-answer-fail'),
            isNull,
            reason: 'failed post-accept teardown must hide visible state',
          );
          expect(changes.last.state, CallState.ended);
          expect(changes.last.endReason, 'hangup');
          expect(av.endedFriendNumbers, const [7]);
          expect(
            sdk.cancelledInviteIds,
            isEmpty,
            reason:
                'native Accept erases the received route; post-accept '
                'answer failure must not call SDK cancel',
          );
          expect(asyncZone.nonPeriodicTimerCount, greaterThan(0));

          _drainTeardownRetryBudget(asyncZone);

          expect(av.endedFriendNumbers, const [7, 7]);
          expect(sdk.cancelledInviteIds, isEmpty);
          expect(asyncZone.nonPeriodicTimerCount, 0);
          asyncZone.elapse(_teardownRetryBudget);
          expect(
            av.endedFriendNumbers.length,
            2,
            reason: 'successful post-accept AV cleanup must drop state',
          );
          expect(
            sdk.cancelledInviteIds,
            isEmpty,
            reason: 'successful post-accept cleanup is AV-only',
          );
        });
      },
    );
  });

  test(
    'diagnostics omit call identifiers and raw signaling payloads',
    () async {
      const sentinels = <String>[
        'INVITE_PRIVACY_SENTINEL_INCOMING',
        'INVITE_PRIVACY_SENTINEL_OUTGOING',
        'INVITE_PRIVACY_SENTINEL_ERROR',
        'USER_PRIVACY_SENTINEL_INVITER',
        'USER_PRIVACY_SENTINEL_INVITEE',
        'GROUP_PRIVACY_SENTINEL_ROOM',
        'RAW_PAYLOAD_PRIVACY_SENTINEL',
        '424242424',
        'ERROR_PRIVACY_SENTINEL',
      ];
      final logger = _RecordingLogger();
      final sdk = _FakeSdkPlatform()
        ..acceptCode = 7000
        ..rejectOutcomes.add(
          _ThrowingOutcome(
            StateError('ERROR_PRIVACY_SENTINEL reject transport'),
          ),
        );
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av, logger: logger);

      sdk.listener!.onReceiveNewInvitation(
        'INVITE_PRIVACY_SENTINEL_INCOMING',
        'USER_PRIVACY_SENTINEL_INVITER',
        'GROUP_PRIVACY_SENTINEL_ROOM',
        const ['USER_PRIVACY_SENTINEL_INVITEE'],
        '{"raw":"RAW_PAYLOAD_PRIVACY_SENTINEL"}',
      );
      sdk.listener!.onInvitationCancelled(
        'INVITE_PRIVACY_SENTINEL_INCOMING',
        'USER_PRIVACY_SENTINEL_INVITER',
        '{"raw":"RAW_PAYLOAD_PRIVACY_SENTINEL"}',
      );
      bridge.registerOutgoingCall(
        inviteID: 'INVITE_PRIVACY_SENTINEL_OUTGOING',
        inviter: 'USER_PRIVACY_SENTINEL_INVITER',
        invitee: 'USER_PRIVACY_SENTINEL_INVITEE',
        groupID: 'GROUP_PRIVACY_SENTINEL_ROOM',
        data: '{"raw":"RAW_PAYLOAD_PRIVACY_SENTINEL"}',
        friendNumber: 424242424,
      );
      bridge.markAvLegStarted('INVITE_PRIVACY_SENTINEL_OUTGOING');
      sdk.listener!.onInviteeAccepted(
        'INVITE_PRIVACY_SENTINEL_OUTGOING',
        'USER_PRIVACY_SENTINEL_INVITEE',
        '{"raw":"RAW_PAYLOAD_PRIVACY_SENTINEL"}',
      );
      sdk.listener!.onInviteeRejected(
        'INVITE_PRIVACY_SENTINEL_OUTGOING',
        'USER_PRIVACY_SENTINEL_INVITEE',
        '{"raw":"RAW_PAYLOAD_PRIVACY_SENTINEL"}',
      );
      bridge.registerOutgoingCall(
        inviteID: 'INVITE_PRIVACY_SENTINEL_ERROR',
        inviter: 'USER_PRIVACY_SENTINEL_INVITER',
        invitee: 'USER_PRIVACY_SENTINEL_INVITEE',
        data: '{"raw":"RAW_PAYLOAD_PRIVACY_SENTINEL"}',
        friendNumber: 424242424,
      );
      await bridge.acceptInvitation('INVITE_PRIVACY_SENTINEL_ERROR');

      final diagnostics = logger.entries.join('\n');
      expect(logger.entries, isNotEmpty);
      for (final sentinel in sentinels) {
        expect(
          diagnostics,
          isNot(contains(sentinel)),
          reason: 'diagnostics must not include $sentinel',
        );
      }
    },
  );

  test('same-key hidden teardown replaces older pending retry timer', () {
    fakeAsync((asyncZone) {
      final sdk = _FakeSdkPlatform()
        ..rejectOutcomes.addAll(const [6000, 6000, 0]);
      final av = _FakeAvBackend();
      final bridge = CallBridgeService(sdk, av);

      _receiveIncomingInvite(sdk, inviteID: 'invite-dedupe');
      _settleFuture(asyncZone, bridge.rejectInvitation('invite-dedupe'));
      expect(sdk.rejectedInviteIds, const ['invite-dedupe']);
      expect(asyncZone.nonPeriodicTimerCount, 1);

      _receiveIncomingInvite(sdk, inviteID: 'invite-dedupe');
      _settleFuture(asyncZone, bridge.rejectInvitation('invite-dedupe'));
      expect(sdk.rejectedInviteIds, const ['invite-dedupe', 'invite-dedupe']);
      expect(
        asyncZone.nonPeriodicTimerCount,
        1,
        reason: 'the replacement cleanup owns the only pending retry timer',
      );

      _drainTeardownRetryBudget(asyncZone);

      expect(sdk.rejectedInviteIds, const [
        'invite-dedupe',
        'invite-dedupe',
        'invite-dedupe',
      ]);
      expect(asyncZone.nonPeriodicTimerCount, 0);
    });
  });
}

const Duration _teardownRetryBudget = Duration(seconds: 20);
const int _maxTeardownAttempts = 6;

({T? value, Object? error}) _settleFuture<T>(
  FakeAsync asyncZone,
  Future<T> future,
) {
  T? value;
  Object? error;
  future.then(
    (futureValue) => value = futureValue,
    onError: (Object futureError, StackTrace _) => error = futureError,
  );
  asyncZone.flushMicrotasks();
  return (value: value, error: error);
}

T _expectFutureValue<T>(FakeAsync asyncZone, Future<T> future) {
  final result = _settleFuture(asyncZone, future);
  expect(result.error, isNull);
  return result.value as T;
}

void _drainTeardownRetryBudget(FakeAsync asyncZone) {
  asyncZone.elapse(_teardownRetryBudget);
  asyncZone.flushMicrotasks();
}

void _receiveIncomingInvite(_FakeSdkPlatform sdk, {required String inviteID}) {
  sdk.listener!.onReceiveNewInvitation(inviteID, 'peer-1', '', const [
    'self',
  ], '{"type":"audio","audio":true,"video":false}');
}

void _registerOutgoing(
  CallBridgeService bridge, {
  required String inviteID,
  bool markAvLegStarted = false,
}) {
  bridge.registerOutgoingCall(
    inviteID: inviteID,
    inviter: 'self',
    invitee: 'friend-1',
    data: '{"type":"audio","audio":true,"video":false}',
    friendNumber: 7,
  );
  if (markAvLegStarted) {
    bridge.markAvLegStarted(inviteID);
  }
}

class _CallChange {
  const _CallChange(this.inviteID, this.state, this.endReason);

  final String inviteID;
  final CallState state;
  final String? endReason;
}

class _FakeSdkPlatform extends TencentCloudChatSdkPlatform {
  V2TimSignalingListener? listener;
  final List<String> cancelledInviteIds = <String>[];
  final List<String> rejectedInviteIds = <String>[];
  final List<Object> cancelOutcomes = <Object>[];
  final List<Object> rejectOutcomes = <Object>[];
  final List<Completer<V2TimValueCallback<String>>> inviteCompleters = [];
  Completer<V2TimCallback>? acceptCompleter;
  int inviteCallCount = 0;
  final List<String> inviteIDs = <String>['invite-1'];
  int acceptCallCount = 0;
  int inviteCode = 0;
  int acceptCode = 0;
  int cancelCode = 0;
  int rejectCode = 0;

  @override
  Future<void> addSignalingListener({
    required V2TimSignalingListener listener,
  }) async {
    this.listener = listener;
  }

  @override
  Future<void> removeSignalingListener({
    V2TimSignalingListener? listener,
  }) async {
    if (this.listener == listener) {
      this.listener = null;
    }
  }

  @override
  Future<V2TimValueCallback<String>> invite({
    required String invitee,
    required String data,
    int timeout = 30,
    bool onlineUserOnly = false,
    offlinePushInfo,
  }) async {
    inviteCallCount++;
    if (inviteCompleters.isNotEmpty) {
      return inviteCompleters.removeAt(0).future;
    }
    if (inviteCode != 0) {
      return V2TimValueCallback<String>(
        code: inviteCode,
        desc: 'fail',
        data: null,
      );
    }
    final id = inviteCallCount <= inviteIDs.length
        ? inviteIDs[inviteCallCount - 1]
        : 'invite-$inviteCallCount';
    return V2TimValueCallback<String>(code: 0, desc: 'ok', data: id);
  }

  @override
  Future<V2TimCallback> cancel({required String inviteID, String? data}) async {
    cancelledInviteIds.add(inviteID);
    final code = _nextSdkCode(cancelOutcomes, cancelCode);
    return V2TimCallback(code: code, desc: code == 0 ? 'ok' : 'no');
  }

  @override
  Future<V2TimCallback> accept({required String inviteID, String? data}) async {
    acceptCallCount++;
    final completer = acceptCompleter;
    if (completer != null) {
      return completer.future;
    }
    return V2TimCallback(code: acceptCode, desc: acceptCode == 0 ? 'ok' : 'no');
  }

  @override
  Future<V2TimCallback> reject({required String inviteID, String? data}) async {
    rejectedInviteIds.add(inviteID);
    final code = _nextSdkCode(rejectOutcomes, rejectCode);
    return V2TimCallback(code: code, desc: code == 0 ? 'ok' : 'no');
  }

  int _nextSdkCode(List<Object> outcomes, int fallbackCode) {
    final outcome = outcomes.isEmpty ? fallbackCode : outcomes.removeAt(0);
    if (outcome is _ThrowingOutcome) {
      throw outcome.error;
    }
    return outcome as int;
  }
}

class _FakeAvBackend implements CallAvBackend {
  final List<int> endedFriendNumbers = <int>[];
  final List<int> answeredFriendNumbers = <int>[];
  final List<int> startedFriendNumbers = <int>[];
  final List<Object> endOutcomes = <Object>[];
  final List<Object> startOutcomes = <Object>[];
  final List<Completer<bool>> startCompleters = <Completer<bool>>[];
  final List<Completer<void>> startCallSignals = <Completer<void>>[];
  Completer<bool>? answerCompleter;
  Completer<bool>? startCompleter;
  int friendNumber = 7;
  bool answerResult = true;
  bool startResult = true;
  bool endResult = true;

  @override
  bool get isAvailable => true;

  @override
  bool get isInitialized => true;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<bool> answerCall(
    int friendNumber, {
    int audioBitRate = 64000,
    int videoBitRate = 5000000,
  }) async {
    answeredFriendNumbers.add(friendNumber);
    final completer = answerCompleter;
    if (completer != null) {
      return completer.future;
    }
    return answerResult;
  }

  @override
  Future<bool> endCall(int friendNumber) async {
    endedFriendNumbers.add(friendNumber);
    final outcome = endOutcomes.isEmpty ? endResult : endOutcomes.removeAt(0);
    if (outcome is _ThrowingOutcome) {
      throw outcome.error;
    }
    return outcome as bool;
  }

  @override
  Future<bool> muteAudio(int friendNumber, bool mute) async => true;

  @override
  Future<bool> muteVideo(int friendNumber, bool hide) async => true;

  @override
  int getFriendNumberByUserId(String userId) => friendNumber;

  @override
  Future<bool> startCall(
    int friendNumber, {
    int audioBitRate = 48,
    int videoBitRate = 5000,
  }) async {
    startedFriendNumbers.add(friendNumber);
    if (startCallSignals.isNotEmpty) {
      final signal = startCallSignals.removeAt(0);
      if (!signal.isCompleted) signal.complete();
    }
    if (startCompleters.isNotEmpty) {
      return startCompleters.removeAt(0).future;
    }
    if (startOutcomes.isNotEmpty) {
      final outcome = startOutcomes.removeAt(0);
      if (outcome is _ThrowingOutcome) throw outcome.error;
      return outcome as bool;
    }
    final completer = startCompleter;
    if (completer != null) {
      return completer.future;
    }
    return startResult;
  }
}

class _ThrowingOutcome {
  const _ThrowingOutcome(this.error);

  final Object error;
}

class _RecordingLogger implements LoggerService {
  final List<String> entries = <String>[];

  @override
  void log(String message) => entries.add('info $message');

  @override
  void logDebug(String message) => entries.add('debug $message');

  @override
  void logError(String message, Object error, StackTrace stack) {
    entries.add('error $message $error $stack');
  }

  @override
  void logWarning(String message) => entries.add('warning $message');
}
