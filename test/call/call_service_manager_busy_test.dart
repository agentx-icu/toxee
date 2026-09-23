// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimSignalingListener.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart' as ffi_lib;
import 'package:tim2tox_dart/service/call_bridge_service.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/service/toxav_service.dart';
import 'package:tim2tox_dart/service/tuicallkit_adapter.dart';
import 'package:toxee/call/av_conference_session_bridge.dart';
import 'package:toxee/call/call_media_capabilities.dart';
import 'package:toxee/call/call_service_manager.dart';
import 'package:toxee/call/call_state_notifier.dart';
import 'package:toxee/call/ringtone_player.dart';

/// GC-3 through the REAL [CallServiceManager] callbacks (not a hand copy of
/// its wiring): the ended-event filter, the native busy reject, the
/// `_onCallState` friend filter, redelivery and glare.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const friendA = 7;
  const friendB = 9;
  const friendC = 11;
  // Real Tox public keys (64 hex): glare compares validated identities.
  final userA = 'a' * 64;
  final userB = 'b' * 64;
  final userC = 'c' * 64;

  late _FakeSdk sdk;
  late _FakeToxAv av;
  late CallBridgeService bridge;
  late CallStateNotifier callState;
  late CallServiceManager manager;
  late List<String> records;
  late _FakeChat chat;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sdk = _FakeSdk();
    av = _FakeToxAv({friendA: userA, friendB: userB, friendC: userC});
    bridge = CallBridgeService(sdk, av);
    callState = CallStateNotifier();
    chat = _FakeChat();
    manager = CallServiceManager(chat, callState, ringtone: _FakeRingtone());
    manager.debugAttachBackends(av, bridge);
    records = <String>[];
    manager.onCallRecordNeeded = (peer, _, outgoing, __, reason) {
      records.add('$peer:${outgoing ? 'out' : 'in'}:$reason');
    };
  });

  tearDown(() {
    bridge.dispose();
    callState.dispose();
  });

  /// An established signaling call with friend A, as the UI sees it.
  void inCallWithA() {
    sdk.listener!.onReceiveNewInvitation(
      'invite-A',
      userA,
      '',
      const ['self'],
      '{}',
    );
    callState.startRinging(
      mode: CallMode.audio,
      direction: CallDirection.incoming,
      inviteID: 'invite-A',
      remoteUserID: userA,
    );
    callState.enterCall();
  }

  test('second signaling invite while inCall: busy reject, call untouched',
      () async {
    inCallWithA();
    sdk.listener!.onReceiveNewInvitation(
      'invite-B',
      userB,
      '',
      const ['self'],
      '{}',
    );
    await pumpEventQueue();

    expect(callState.state, CallUIState.inCall);
    expect(callState.inviteID, 'invite-A');
    expect(sdk.rejects, [('invite-B', CallBridgeService.lineBusyRejectData)]);
    expect(records, ['$userB:in:line_busy']);
  });

  test('ended event for a foreign invite does not end the live call',
      () async {
    inCallWithA();
    // e.g. an unknown/stale invite rejected through the bridge.
    await bridge.rejectInvitation('invite-stale');
    await pumpEventQueue();

    expect(callState.state, CallUIState.inCall);
    expect(callState.inviteID, 'invite-A');
    expect(records, isEmpty);
  });

  test('native call from another friend while inCall is declined as busy',
      () async {
    inCallWithA();
    ToxAVService.dispatchAvCall(0, friendB, true, false);
    await pumpEventQueue();

    expect(av.ended, [friendB]);
    expect(callState.state, CallUIState.inCall);
    expect(callState.inviteID, 'invite-A');
    expect(records, ['$userB:in:line_busy']);
  });

  test('the ringing peer\'s own ToxAV leg is ignored, not rejected', () async {
    sdk.listener!.onReceiveNewInvitation(
      'invite-A',
      userA,
      '',
      const ['self'],
      '{}',
    );
    callState.startRinging(
      mode: CallMode.audio,
      direction: CallDirection.incoming,
      inviteID: 'invite-A',
      remoteUserID: userA,
    );
    ToxAVService.dispatchAvCall(0, friendA, true, false);
    await pumpEventQueue();

    expect(av.ended, isEmpty);
    expect(callState.inviteID, 'invite-A');
    expect(callState.state, CallUIState.ringing);
  });

  test('signaling busy + the same caller\'s ToxAV leg record ONE missed call',
      () async {
    inCallWithA();
    sdk.listener!.onReceiveNewInvitation(
      'invite-B',
      userB,
      '',
      const ['self'],
      '{}',
    );
    ToxAVService.dispatchAvCall(0, friendB, true, false);
    await pumpEventQueue();

    expect(records, ['$userB:in:line_busy']);
  });

  test('_onCallState for a different friend cannot end the live call', () {
    inCallWithA();
    ToxAVService.dispatchAvCallState(0, friendB, 2); // FINISHED
    ToxAVService.dispatchAvCallState(0, friendB, 1); // ERROR

    expect(callState.state, CallUIState.inCall);
    expect(callState.inviteID, 'invite-A');
    expect(records, isEmpty);
  });

  test('_onCallState while idle is ignored (no phantom "call ended")', () {
    ToxAVService.dispatchAvCallState(0, friendB, 2);
    expect(callState.state, CallUIState.idle);
  });

  test('a redelivered invite for the call on screen is not busy-rejected',
      () async {
    inCallWithA();
    sdk.listener!.onReceiveNewInvitation(
      'invite-A',
      userA,
      '',
      const ['self'],
      '{}',
    );
    await pumpEventQueue();

    expect(sdk.rejects, isEmpty);
    expect(callState.state, CallUIState.inCall);
    expect(callState.inviteID, 'invite-A');
  });

  group('glare (both call each other at once)', () {
    void ringingOutTo(String user, String inviteID) {
      bridge.registerOutgoingCall(
        inviteID: inviteID,
        inviter: 'self',
        invitee: user,
        data: '{}',
        friendNumber: user == userA ? friendA : friendB,
      );
      callState.startRinging(
        mode: CallMode.audio,
        direction: CallDirection.outgoing,
        inviteID: inviteID,
        remoteUserID: user,
      );
    }

    test('the higher key yields: cancels its call and lets the peer ring',
        () async {
      chat.selfToxIdValue = 'f' * 76; // > userA
      ringingOutTo(userA, 'out-1');
      sdk.listener!.onReceiveNewInvitation(
        'invite-A',
        userA,
        '',
        const ['self'],
        '{}',
      );
      await pumpEventQueue();

      expect(sdk.rejects, isEmpty);
      expect(sdk.cancels, ['out-1']);
      expect(bridge.getCallInfo('invite-A'), isNotNull);
      expect(records, ['$userA:out:cancel']);
    });

    test('the placeholder login alias never decides glare', () async {
      // Both peers would share this alias: neither may yield on it.
      chat.selfIdValue = 'FlutterUIKitClient';
      chat.selfToxIdValue = null; // identity not resolvable
      ringingOutTo(userA, 'out-1');
      sdk.listener!.onReceiveNewInvitation(
        'invite-A',
        userA,
        '',
        const ['self'],
        '{}',
      );
      await pumpEventQueue();

      expect(sdk.cancels, isEmpty, reason: 'deterministic plain busy');
      expect(sdk.rejects.single.$1, 'invite-A');
      expect(callState.inviteID, 'out-1');
    });

    test('the lower key keeps its call and silently declines', () async {
      chat.selfToxIdValue = '0' * 76; // < userA
      ringingOutTo(userA, 'out-1');
      sdk.listener!.onReceiveNewInvitation(
        'invite-A',
        userA,
        '',
        const ['self'],
        '{}',
      );
      await pumpEventQueue();

      expect(sdk.rejects.single.$1, 'invite-A');
      expect(sdk.cancels, isEmpty);
      expect(callState.inviteID, 'out-1');
      expect(callState.state, CallUIState.ringing);
      expect(records, isEmpty, reason: 'glare is not a missed call');
    });
  });

  test('callGlareYields is antisymmetric on 76-char ids', () {
    final a = 'A' * 64 + '0' * 12;
    final b = 'b' * 64 + '1' * 12;
    expect(
      callGlareYields(selfToxId: a, peerId: b),
      isNot(callGlareYields(selfToxId: b, peerId: a)),
    );
    expect(callGlareYields(selfToxId: '', peerId: b), isFalse);
    expect(callGlareYields(selfToxId: null, peerId: b), isFalse);
    // Malformed / placeholder identities on either side: plain busy.
    expect(callGlareYields(selfToxId: 'FlutterUIKitClient', peerId: b), isFalse);
    expect(callGlareYields(selfToxId: b, peerId: 'FlutterUIKitClient'), isFalse);
    expect(callGlareYields(selfToxId: 'f' * 63, peerId: b), isFalse);
    expect(callGlareYields(selfToxId: 'g' * 64, peerId: b), isFalse);
  });

  group('unresolved friend number (review #9)', () {
    test('an invite from a not-yet-resolvable caller stores no sentinel, and '
        'the caller\'s real ToxAV end still ends the call', () async {
      av.hidden.add(userC); // lookup returns 0xFFFFFFFF at invite time
      sdk.listener!.onReceiveNewInvitation(
        'invite-C',
        userC,
        '',
        const ['self'],
        '{}',
      );
      await pumpEventQueue();
      expect(bridge.getCallInfo('invite-C')!.friendNumber, isNull);
      callState.enterCall();
      av.hidden.remove(userC); // friend now resolvable

      ToxAVService.dispatchAvCallState(0, friendC, 2); // FINISHED
      expect(callState.state, isNot(CallUIState.inCall));
    });

    test('never resolvable: the peer identity still matches its leg',
        () async {
      av.hidden.add(userC);
      sdk.listener!.onReceiveNewInvitation(
        'invite-C',
        userC,
        '',
        const ['self'],
        '{}',
      );
      await pumpEventQueue();
      callState.enterCall();
      ToxAVService.dispatchAvCallState(0, friendB, 2); // someone else
      expect(callState.state, CallUIState.inCall);
      ToxAVService.dispatchAvCallState(0, friendC, 2); // the caller's leg
      expect(callState.state, isNot(CallUIState.inCall));
    });
  });

  group('native incoming re-validated after the caller lookup (review #10)',
      () {
    test('pipeline claimed during the lookup: declined as busy, not rung',
        () async {
      ToxAVService.dispatchAvCall(0, friendB, true, false); // idle → lookup
      inCallWithA(); // a call claims the pipeline meanwhile
      await pumpEventQueue();

      expect(callState.inviteID, 'invite-A');
      expect(callState.state, CallUIState.inCall);
      expect(av.ended, [friendB]);
      expect(records, ['$userB:in:line_busy']);
    });

    test('caller hangs up during the lookup: no ghost ring', () async {
      ToxAVService.dispatchAvCall(0, friendB, true, false);
      ToxAVService.dispatchAvCallState(0, friendB, 2); // FINISHED
      await pumpEventQueue();
      expect(callState.state, CallUIState.idle);
    });
  });

  test('a redelivered busy invite is rejected once (review #12)', () async {
    inCallWithA();
    for (var i = 0; i < 3; i++) {
      sdk.listener!.onReceiveNewInvitation(
        'invite-B',
        userB,
        '',
        const ['self'],
        '{}',
      );
    }
    await pumpEventQueue();
    expect(sdk.rejects, [('invite-B', CallBridgeService.lineBusyRejectData)]);
    expect(records, ['$userB:in:line_busy']);
  });

  test('a real retry after a busy reject is a new missed call (review #14)',
      () async {
    inCallWithA();
    sdk.listener!.onReceiveNewInvitation('invite-B1', userB, '', const [], '{}');
    ToxAVService.dispatchAvCall(0, friendB, true, false); // same attempt
    await pumpEventQueue();
    sdk.listener!.onReceiveNewInvitation('invite-B2', userB, '', const [], '{}');
    await pumpEventQueue();
    expect(records, ['$userB:in:line_busy', '$userB:in:line_busy']);
  });

  test('dispose ends the live call\'s AV leg and gates late callbacks '
      '(pre-existing #2)', () async {
    bridge.registerOutgoingCall(
      inviteID: 'out-1',
      inviter: 'self',
      invitee: userA,
      data: '{}',
      friendNumber: friendA,
    );
    bridge.markAvLegStarted('out-1', friendNumber: friendA);
    final listener = sdk.listener!;
    var events = 0;
    bridge.onCallStateChanged = (_, __, {endReason}) => events++;
    await bridge.dispose();
    expect(av.ended, [friendA]);
    expect(sdk.cancels, ['out-1'], reason: 'unanswered outgoing invite');
    expect(sdk.listener, isNull);
    listener.onReceiveNewInvitation('late', userB, '', const [], '{}');
    listener.onInviteeAccepted('out-1', userA, '');
    expect(bridge.getActiveCalls(), isEmpty);
    expect(events, 0);
  });

  test('manager dispose ends native legs and deactivates the call audio '
      'session, awaited (review #4)', () async {
    final calls = <String>[];
    const channel = MethodChannel('toxee/call_audio');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    ToxAVService.dispatchAvCall(0, friendB, true, false); // native ring
    await pumpEventQueue();
    expect(callState.inviteID, 'native_av_$friendB');
    await manager.syncPlatformEffectsForState(CallUIState.ringing);
    expect(calls, contains('activateSession'));

    await manager.dispose();
    expect(av.ended, [friendB], reason: 'leg ended before ToxAV shutdown');
    expect(calls.last, 'deactivateSession');
    calls.clear();
    // Nothing may re-activate the session after logout.
    await manager.syncPlatformEffectsForState(CallUIState.inCall);
    expect(calls, isEmpty);
  });

  group('outgoing preflight claims the pipeline (review P1 #1)', () {
    const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

    /// Holds the "OS permission sheet" open until [gate] completes, then grants.
    void gatePermissionSheet(Completer<void> gate) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, (call) async {
            await gate.future;
            if (call.method == 'requestPermissions') {
              final requested = (call.arguments as List).cast<int>();
              return <int, int>{for (final v in requested) v: 1};
            }
            return 1; // granted
          });
    }

    setUp(() {
      // Keep the capture-device probe out of the way: it is awaited by the
      // preflight and would otherwise reach the camera plugin.
      CallMediaCapabilities.debugDeviceHasCamera = false;
    });

    tearDown(() {
      CallMediaCapabilities.debugDeviceHasCamera = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissions, null);
    });

    test('a call claimed while the permission sheet was up refuses the call',
        () async {
      final gate = Completer<void>();
      gatePermissionSheet(gate);
      final pending = manager.debugPreflightOutgoingCall(userB, TYPE_AUDIO);
      await pumpEventQueue();
      // The pipeline is claimed while the user is still answering the sheet;
      // the pre-sheet busy check said "free".
      inCallWithA();
      gate.complete();

      expect(await pending, isFalse);
    });

    test('an approved outgoing call reserves the pipeline until it rings',
        () async {
      final gate = Completer<void>()..complete();
      gatePermissionSheet(gate);
      expect(
        await manager.debugPreflightOutgoingCall(userB, TYPE_AUDIO),
        isTrue,
      );
      // The invite has not surfaced yet (no ringing state), but the audio
      // pipeline is spoken for: a conference join must not take it.
      final joined = await manager.conferenceBridge.enable(
        groupId: 'tox_conf_1',
        displayName: 'Room',
        owner: AvConferenceSessionOwner(),
        onAudioFrame: (_, __, ___, ____, _____, ______, _______) {},
      );
      expect(joined, AvConferenceEnableResult.busy);
    });

    test('a setup that never produces an invite releases the reservation',
        () async {
      final gate = Completer<void>()..complete();
      gatePermissionSheet(gate);
      expect(
        await manager.debugPreflightOutgoingCall(userB, TYPE_AUDIO),
        isTrue,
      );
      expect(
        await manager.debugPreflightOutgoingCall(userB, TYPE_AUDIO),
        isFalse,
        reason: 'the first attempt still holds the claim',
      );
      expect(
        manager.uiNotice.value,
        isNull,
        reason: 'a double tap on the call button is not a busy line',
      );
      expect(
        await manager.debugPreflightOutgoingCall(userC, TYPE_AUDIO),
        isFalse,
      );
      expect(manager.uiNotice.value, isNotNull, reason: 'another peer: busy');
      // The adapter failed after the preflight: nothing will ever ring, so the
      // claim must not wedge calling for the rest of the session.
      manager.debugOnCallSetupFailed(
        CallSetupFailureReason.inviteFailed,
        <String>[userB],
      );
      expect(
        await manager.debugPreflightOutgoingCall(userB, TYPE_AUDIO),
        isTrue,
      );
    });
  });

  test('a late acceptance for an invite that is not on screen is refused '
      '(review P1 #1)', () async {
    // invite-A is RINGING on screen; nothing may turn it into a connected
    // call but its own acceptance.
    sdk.listener!.onReceiveNewInvitation(
      'invite-A',
      userA,
      '',
      const ['self'],
      '{}',
    );
    await pumpEventQueue();
    expect(callState.state, CallUIState.ringing);
    bridge.registerOutgoingCall(
      inviteID: 'out-stale',
      inviter: 'self',
      invitee: userB,
      data: '{}',
      friendNumber: friendB,
    );
    // The peer accepted an invite we already replaced: entering `inCall` for
    // it would put the call on screen into a call with the wrong peer.
    bridge.onCallStateChanged!('out-stale', CallState.inCall);
    await pumpEventQueue();

    expect(callState.inviteID, 'invite-A');
    expect(callState.state, CallUIState.ringing, reason: 'still just a ring');
    expect(bridge.getCallInfo('out-stale'), isNull, reason: 'torn down');
  });

  test('a delayed FINISHED from the old leg cannot end a redial to the same '
      'friend (pre-existing #4)', () async {
    inCallWithA();
    await manager.hangUp();
    // Redial the same friend: a new invite, the same ToxAV friend number.
    sdk.listener!.onReceiveNewInvitation(
      'invite-A2',
      userA,
      '',
      const ['self'],
      '{}',
    );
    await pumpEventQueue();
    bridge.onCallStateChanged!('invite-A2', CallState.inCall);
    expect(callState.state, CallUIState.inCall);

    // The FINISHED of the leg we ended lands now (toxav reports call state per
    // FRIEND, with no leg identity).
    ToxAVService.dispatchAvCallState(0, friendA, 2);
    expect(callState.state, CallUIState.inCall);
    expect(callState.inviteID, 'invite-A2');

    // The new leg's own terminal still ends it.
    ToxAVService.dispatchAvCallState(0, friendA, 2);
    expect(callState.state, isNot(CallUIState.inCall));
  });

  test('a queued platform-effects step cannot reactivate the audio session '
      'after logout (review P1 #2)', () async {
    final calls = <String>[];
    final activated = Completer<void>();
    const channel = MethodChannel('toxee/call_audio');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      // The first activation parks in the platform channel, so the next sync
      // is still QUEUED when dispose lands.
      if (call.method == 'activateSession' && !activated.isCompleted) {
        await activated.future;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final first = manager.syncPlatformEffectsForState(CallUIState.ringing);
    await pumpEventQueue();
    final queued = manager.syncPlatformEffectsForState(CallUIState.inCall);
    final teardown = manager.dispose();
    activated.complete();
    await first;
    await queued;
    await teardown;

    expect(
      calls.where((c) => c == 'activateSession').length,
      1,
      reason: 'the queued step must abort, not re-activate',
    );
    expect(calls.last, 'deactivateSession');
  });

  test('conference teardown does not lower a call that started during it '
      '(review P1 #3)', () async {
    final calls = <String>[];
    const channel = MethodChannel('toxee/call_audio');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await manager.debugConferenceHooks.onMediaStarted?.call('Room');
    expect(manager.debugForegroundElevatedForCall, isTrue);

    // The bridge drops conference ownership BEFORE awaiting the audio release,
    // so a 1:1 call can start (and elevate the service) inside that window.
    inCallWithA();
    bridge.onCallStateChanged!('invite-A', CallState.inCall);
    calls.clear();
    await manager.debugConferenceHooks.onMediaStopped?.call();

    expect(
      manager.debugForegroundElevatedForCall,
      isTrue,
      reason: 'the live call still owns the foreground service',
    );
    expect(calls, isNot(contains('deactivateSession')));
  });

  test('BusyRejectLedger keys by invite, correlating the ToxAV leg', () {
    final ledger = BusyRejectLedger();
    final t0 = DateTime(2026, 9, 17, 12);
    DateTime at(int s) => t0.add(Duration(seconds: s));
    expect(ledger.claim(peerKey: 'A', inviteId: 'i1', now: t0), isTrue);
    // Its ToxAV leg and a redelivery of the invite: same attempt.
    expect(ledger.claim(peerKey: 'A', now: at(1)), isFalse);
    expect(ledger.claim(peerKey: 'A', inviteId: 'i1', now: at(2)), isFalse);
    // A retry 10 s later is a new attempt (a new invite ID)…
    expect(ledger.claim(peerKey: 'A', inviteId: 'i2', now: at(10)), isTrue);
    // …whose own leg correlates with it, not with i1.
    expect(ledger.claim(peerKey: 'A', now: at(11)), isFalse);
    // Leg first, invite second (either order).
    expect(ledger.claim(peerKey: 'B', now: at(12)), isTrue);
    expect(ledger.claim(peerKey: 'B', inviteId: 'j1', now: at(13)), isFalse);
    // A native-only retry long after is new.
    expect(ledger.claim(peerKey: 'B', now: at(60)), isTrue);
  });
}

class _FakeChat implements FfiChatService {
  String selfIdValue = '';
  String? selfToxIdValue;

  @override
  String get selfId => selfIdValue;

  @override
  String? getSelfToxId() => selfToxIdValue;

  @override
  void setAvSessionActive(bool active) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoFfi implements ffi_lib.Tim2ToxFfi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeToxAv extends ToxAVService {
  _FakeToxAv(this._users) : super(_NoFfi());

  final Map<int, String> _users;
  final List<int> ended = <int>[];

  /// Users whose friend-number lookup returns the Tox sentinel.
  final Set<String> hidden = <String>{};

  @override
  bool get isAvailable => true;

  @override
  bool get isInitialized => true;

  @override
  Future<bool> endCall(int friendNumber) async {
    ended.add(friendNumber);
    return true;
  }

  @override
  String? getUserIdByFriendNumber(int friendNumber) => _users[friendNumber];

  @override
  int getFriendNumberByUserId(String userId) {
    if (hidden.contains(userId)) return 0xFFFFFFFF;
    for (final e in _users.entries) {
      if (e.value == userId) return e.key;
    }
    return 0xFFFFFFFF;
  }

  @override
  void shutdown() {}
}

class _FakeRingtone implements RingtonePlayer {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeSdk extends TencentCloudChatSdkPlatform {
  V2TimSignalingListener? listener;
  final List<(String, String?)> rejects = <(String, String?)>[];
  final List<String> cancels = <String>[];

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
    cancels.add(inviteID);
    return V2TimCallback(code: 0, desc: 'ok');
  }
}
