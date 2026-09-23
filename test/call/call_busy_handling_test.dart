// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimSignalingListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tim2tox_dart/service/call_bridge_service.dart';
import 'package:toxee/call/call_service_manager.dart';
import 'package:toxee/call/call_state_notifier.dart';

/// GC-3: a second incoming call while one is on screen must be rejected as
/// busy and must NOT touch the active call's state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('busy arbitration (signaling path)', () {
    late _FakeSdk sdk;
    late CallBridgeService bridge;
    late CallStateNotifier callState;
    late List<String> ringing;
    late List<(String, String?)> ended;
    late List<CallInfo> busyRejected;
    var conferenceActive = false;

    setUp(() {
      sdk = _FakeSdk();
      bridge = CallBridgeService(sdk, _FakeAv());
      callState = CallStateNotifier();
      ringing = <String>[];
      ended = <(String, String?)>[];
      busyRejected = <CallInfo>[];
      conferenceActive = false;
      // Same wiring as CallServiceManager.initialize.
      bridge.isBusyForInvitation = (_) => isCallPipelineBusy(
        state: callState.state,
        conferenceActive: conferenceActive,
      );
      bridge.onInvitationRejectedBusy = busyRejected.add;
      bridge.onCallStateChanged = (inviteID, state, {endReason}) {
        if (state == CallState.ringing) {
          ringing.add(inviteID);
          callState.startRinging(
            mode: CallMode.audio,
            direction: CallDirection.incoming,
            inviteID: inviteID,
            remoteUserID: bridge.getCallInfo(inviteID)!.inviter,
          );
        } else if (state == CallState.ended) {
          ended.add((inviteID, endReason));
        }
      };
    });

    tearDown(() {
      bridge.dispose();
      callState.dispose();
    });

    test('second invite while inCall is busy-rejected; active call '
        'state and inviteID are untouched', () async {
      sdk.listener!.onReceiveNewInvitation(
        'invite-A',
        'friend-A',
        '',
        const ['self'],
        '{"video":false}',
      );
      callState.enterCall();
      expect(callState.state, CallUIState.inCall);

      sdk.listener!.onReceiveNewInvitation(
        'invite-B',
        'friend-B',
        '',
        const ['self'],
        '{"video":true}',
      );
      await pumpEventQueue();

      expect(ringing, <String>['invite-A']);
      expect(callState.state, CallUIState.inCall);
      expect(callState.inviteID, 'invite-A');
      expect(callState.remoteUserID, 'friend-A');
      expect(sdk.rejects, <(String, String?)>[
        ('invite-B', CallBridgeService.lineBusyRejectData),
      ]);
      expect(ended, isEmpty, reason: 'busy reject must not emit ended');
      expect(busyRejected.single.inviter, 'friend-B');
      expect(bridge.getCallInfo('invite-B'), isNull);
      expect(bridge.getCallInfo('invite-A'), isNotNull);
    });

    test('invite while ringing is busy too', () async {
      sdk.listener!.onReceiveNewInvitation(
        'invite-A',
        'friend-A',
        '',
        const ['self'],
        '{}',
      );
      sdk.listener!.onReceiveNewInvitation(
        'invite-B',
        'friend-B',
        '',
        const ['self'],
        '{}',
      );
      await pumpEventQueue();

      expect(callState.state, CallUIState.ringing);
      expect(callState.inviteID, 'invite-A');
      expect(sdk.rejects.single.$1, 'invite-B');
    });

    test('invite while an AV conference owns the mic is busy', () async {
      conferenceActive = true;
      sdk.listener!.onReceiveNewInvitation(
        'invite-C',
        'friend-C',
        '',
        const ['self'],
        '{}',
      );
      await pumpEventQueue();

      expect(ringing, isEmpty);
      expect(callState.state, CallUIState.idle);
      expect(sdk.rejects.single.$2, CallBridgeService.lineBusyRejectData);
    });

    test('invite during the ended banner is NOT busy', () async {
      sdk.listener!.onReceiveNewInvitation(
        'invite-A',
        'friend-A',
        '',
        const ['self'],
        '{}',
      );
      callState.endCall();
      sdk.listener!.onReceiveNewInvitation(
        'invite-B',
        'friend-B',
        '',
        const ['self'],
        '{}',
      );
      await pumpEventQueue();

      expect(ringing, <String>['invite-A', 'invite-B']);
      expect(sdk.rejects, isEmpty);
    });

    test('rejectInvitationAsBusy (post-await race) rejects with the busy '
        'payload and emits no ended event', () async {
      conferenceActive = false;
      bridge.isBusyForInvitation = (_) => false; // raced past the check
      sdk.listener!.onReceiveNewInvitation(
        'invite-A',
        'friend-A',
        '',
        const ['self'],
        '{}',
      );
      ended.clear();

      expect(await bridge.rejectInvitationAsBusy('invite-A'), isTrue);
      expect(sdk.rejects.single, (
        'invite-A',
        CallBridgeService.lineBusyRejectData,
      ));
      expect(ended, isEmpty);
      expect(busyRejected.single.inviteID, 'invite-A');
      expect(await bridge.rejectInvitationAsBusy('invite-A'), isFalse);
    });

    test('rejectInvitationAsBusy refuses an accepted call (live AV leg) '
        'instead of orphaning it (review #13)', () async {
      bridge.isBusyForInvitation = (_) => false;
      sdk.listener!.onReceiveNewInvitation(
        'invite-A',
        'friend-A',
        '',
        const ['self'],
        '{}',
      );
      expect(await bridge.acceptInvitation('invite-A'), isTrue);
      expect(bridge.getCallInfo('invite-A')!.avLegStarted, isTrue);

      expect(await bridge.rejectInvitationAsBusy('invite-A'), isFalse);
      expect(bridge.getCallInfo('invite-A'), isNotNull);
      expect(sdk.rejects, isEmpty);
      expect(busyRejected, isEmpty);
    });

    test('an unknown inviter never stores the Tox sentinel (review #9)', () {
      bridge = CallBridgeService(sdk, _FakeAv(unknown: {'friend-X', 'self'}));
      bridge.onCallStateChanged = (inviteID, state, {endReason}) {};
      sdk.listener!.onReceiveNewInvitation(
        'invite-X',
        'friend-X',
        '',
        const ['self'],
        '{}',
      );
      expect(bridge.getCallInfo('invite-X')!.friendNumber, isNull);
      expect(CallBridgeService.isValidFriendNumber(0xFFFFFFFF), isFalse);
      expect(CallBridgeService.isValidFriendNumber(0), isTrue);
    });

    test('caller side maps a line_busy reject to endReason line_busy', () {
      bridge.registerOutgoingCall(
        inviteID: 'out-1',
        inviter: 'self',
        invitee: 'friend-A',
        data: '{}',
        friendNumber: 7,
      );
      sdk.listener!.onInviteeRejected(
        'out-1',
        'friend-A',
        CallBridgeService.lineBusyRejectData,
      );
      bridge.registerOutgoingCall(
        inviteID: 'out-2',
        inviter: 'self',
        invitee: 'friend-A',
        data: '{}',
        friendNumber: 7,
      );
      sdk.listener!.onInviteeRejected('out-2', 'friend-A', '');

      expect(ended, <(String, String?)>[
        ('out-1', 'line_busy'),
        ('out-2', 'reject'),
      ]);
    });
  });

  test('isLineBusyData only accepts the line_busy marker', () {
    expect(
      CallBridgeService.isLineBusyData(CallBridgeService.lineBusyRejectData),
      isTrue,
    );
    expect(CallBridgeService.isLineBusyData('{"line_busy":""}'), isTrue);
    expect(CallBridgeService.isLineBusyData(''), isFalse);
    expect(CallBridgeService.isLineBusyData('{"businessID":"av_call"}'), isFalse);
    expect(CallBridgeService.isLineBusyData('not json'), isFalse);
  });

  test('isCallPipelineBusy: ringing/inCall/reconnecting/conference only', () {
    for (final state in CallUIState.values) {
      final expected =
          state == CallUIState.ringing ||
          state == CallUIState.inCall ||
          state == CallUIState.reconnecting;
      expect(
        isCallPipelineBusy(state: state, conferenceActive: false),
        expected,
        reason: '$state',
      );
      expect(isCallPipelineBusy(state: state, conferenceActive: true), isTrue);
    }
  });

  test('GC-4: an active conference boosts the AV poll; leaving drops it', () {
    // enable → media active → boost on, even with no 1:1 call.
    expect(
      shouldBoostAvPoll(state: CallUIState.idle, conferenceActive: true),
      isTrue,
    );
    // disable → media gone → idle cadence again.
    expect(
      shouldBoostAvPoll(state: CallUIState.idle, conferenceActive: false),
      isFalse,
    );
    expect(
      shouldBoostAvPoll(state: CallUIState.inCall, conferenceActive: false),
      isTrue,
    );
  });

  test('BusyRejectLedger: one record per attempt, not per caller window', () {
    final ledger = BusyRejectLedger();
    final t0 = DateTime(2026, 9, 17, 12);
    DateTime at(int s) => t0.add(Duration(seconds: s));
    expect(ledger.claim(peerKey: 'A', inviteId: 'a1', now: t0), isTrue);
    // Signaling invite + the same caller's ToxAV leg: one record.
    expect(ledger.claim(peerKey: 'A', now: at(2)), isFalse);
    expect(ledger.claim(peerKey: 'B', inviteId: 'b1', now: at(2)), isTrue);
    // A genuine retry 10 s later is recorded again.
    expect(ledger.claim(peerKey: 'A', inviteId: 'a2', now: at(12)), isTrue);
  });
}

class _FakeSdk extends TencentCloudChatSdkPlatform {
  V2TimSignalingListener? listener;
  final List<(String, String?)> rejects = <(String, String?)>[];

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
    if (this.listener == listener) this.listener = null;
  }

  @override
  Future<V2TimCallback> reject({required String inviteID, String? data}) async {
    rejects.add((inviteID, data));
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> cancel({required String inviteID, String? data}) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }

  @override
  Future<V2TimCallback> accept({required String inviteID, String? data}) async {
    return V2TimCallback(code: 0, desc: 'ok');
  }
}

class _FakeAv implements CallAvBackend {
  _FakeAv({this.unknown = const <String>{}});

  /// Users unknown to Tox: their lookup returns the `UINT32_MAX` sentinel.
  final Set<String> unknown;

  @override
  bool get isAvailable => true;

  @override
  bool get isInitialized => true;

  @override
  Future<bool> initialize() async => true;

  @override
  int getFriendNumberByUserId(String userId) =>
      unknown.contains(userId) ? 0xFFFFFFFF : userId.hashCode & 0xff;

  @override
  Future<bool> startCall(
    int friendNumber, {
    int audioBitRate = 48,
    int videoBitRate = 0,
  }) async => true;

  @override
  Future<bool> answerCall(
    int friendNumber, {
    int audioBitRate = 48,
    int videoBitRate = 0,
  }) async => true;

  @override
  Future<bool> endCall(int friendNumber) async => true;

  @override
  Future<bool> muteAudio(int friendNumber, bool mute) async => true;

  @override
  Future<bool> muteVideo(int friendNumber, bool hide) async => true;
}
