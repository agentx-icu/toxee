// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimSignalingListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
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
  });

  test('does not send signaling invite when outgoing call preflight denies',
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
  });

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
      final handled =
          await adapter.handleCall(type: TYPE_AUDIO, userids: userids);
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

  test('acceptInvitation returns false when SDK accept returns non-zero code',
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

    expect(ok, isFalse,
        reason:
            'SDK accept failed; the async result must propagate to the caller. '
            'Pre-fix the void contract silently dropped this branch.');
    expect(av.answeredFriendNumbers, isEmpty,
        reason: 'ToxAV answer must not be issued when signaling accept fails');
  });

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

  test('endCall is a no-op for an unknown inviteID instead of throwing',
      () async {
    final sdk = _FakeSdkPlatform();
    final av = _FakeAvBackend();
    final bridge = CallBridgeService(sdk, av);

    final ok = await bridge.endCall('never-registered');

    expect(ok, isFalse);
    expect(av.endedFriendNumbers, isEmpty);
    expect(sdk.cancelledInviteIds, isEmpty);
  });

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
    sdk.listener!.onInvitationCancelled(
      'invite-in-cancel',
      'peer-1',
      '{}',
    );

    expect(av.endedFriendNumbers, isEmpty);
    expect(bridge.getCallInfo('invite-in-cancel'), isNull);
    expect(changes.last.state, CallState.ended);
    expect(changes.last.endReason, 'cancel');
  });

  test('incoming timeout while ringing does not end an unanswered ToxAV leg',
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
    sdk.listener!.onInvitationTimeout(
      'invite-in-timeout',
      const ['self'],
    );

    expect(av.endedFriendNumbers, isEmpty);
    expect(bridge.getCallInfo('invite-in-timeout'), isNull);
    expect(changes.last.state, CallState.ended);
    expect(changes.last.endReason, 'timeout');
  });

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
    sdk.listener!.onInviteeRejected(
      'invite-out-reject',
      'friend-1',
      '{}',
    );

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
    sdk.listener!.onInvitationTimeout(
      'invite-out-timeout',
      const ['friend-1'],
    );

    expect(av.endedFriendNumbers, const [7]);
    expect(bridge.getCallInfo('invite-out-timeout'), isNull);
    expect(changes.single.state, CallState.ended);
    expect(changes.single.endReason, 'timeout');
  });

  test(
      'outgoing teardown in the registerOutgoingCall->startCall gap does not '
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
    sdk.listener!.onInvitationTimeout(
      'invite-out-gap',
      const ['friend-1'],
    );

    // No media leg existed yet, so endCall() must NOT fire on it (native
    // endCall with no call in progress can block/error).
    expect(av.endedFriendNumbers, isEmpty);
    expect(bridge.getCallInfo('invite-out-gap'), isNull);
    expect(changes.single.state, CallState.ended);
    expect(changes.single.endReason, 'timeout');
  });
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
  int inviteCallCount = 0;
  int inviteCode = 0;
  int acceptCode = 0;
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
    if (inviteCode != 0) {
      return V2TimValueCallback<String>(
          code: inviteCode, desc: 'fail', data: null);
    }
    return V2TimValueCallback<String>(code: 0, desc: 'ok', data: 'invite-1');
  }

  @override
  Future<V2TimCallback> cancel({
    required String inviteID,
    String? data,
  }) async {
    cancelledInviteIds.add(inviteID);
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> accept({
    required String inviteID,
    String? data,
  }) async {
    return V2TimCallback(code: acceptCode, desc: acceptCode == 0 ? 'ok' : 'no');
  }

  @override
  Future<V2TimCallback> reject({
    required String inviteID,
    String? data,
  }) async {
    return V2TimCallback(code: rejectCode, desc: rejectCode == 0 ? 'ok' : 'no');
  }
}

class _FakeAvBackend implements CallAvBackend {
  final List<int> endedFriendNumbers = <int>[];
  final List<int> answeredFriendNumbers = <int>[];
  final List<int> startedFriendNumbers = <int>[];
  bool answerResult = true;
  bool startResult = true;

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
    return answerResult;
  }

  @override
  Future<bool> endCall(int friendNumber) async {
    endedFriendNumbers.add(friendNumber);
    return true;
  }

  @override
  Future<bool> muteAudio(int friendNumber, bool mute) async => true;

  @override
  Future<bool> muteVideo(int friendNumber, bool hide) async => true;

  @override
  int getFriendNumberByUserId(String userId) => 7;

  @override
  Future<bool> startCall(
    int friendNumber, {
    int audioBitRate = 48,
    int videoBitRate = 5000,
  }) async {
    startedFriendNumbers.add(friendNumber);
    return startResult;
  }
}
