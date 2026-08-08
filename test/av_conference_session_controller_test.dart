import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/av_conference_session_bridge.dart';
import 'package:toxee/call/av_conference_session_controller.dart';

void main() {
  test(
    'join enables the av_conference session and owns frame delivery',
    () async {
      final bridge = _FakeAvConferenceSessionBridge();
      final controller = AvConferenceSessionController(
        groupId: 'tox_conf_pcm_1',
        displayName: 'qTox AV room',
        bridge: bridge,
      );

      expect(controller.session.lifecycle, AvConferenceSessionLifecycle.idle);
      expect(controller.session.receivedFrameCount, 0);

      final joined = await controller.join();

      expect(joined, isTrue);
      expect(controller.session.lifecycle, AvConferenceSessionLifecycle.active);
      expect(bridge.enableCalls, 1);
      expect(bridge.enabledGroups, contains('tox_conf_pcm_1'));

      bridge.emitFrame(groupId: 'tox_conf_pcm_1');
      expect(controller.session.receivedFrameCount, 1);
    },
  );

  test('local mute persists across disable and re-enable', () async {
    final bridge = _FakeAvConferenceSessionBridge();
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_2',
      displayName: 'Muted room',
      bridge: bridge,
    );

    await controller.join();

    final muted = await controller.toggleMuted();
    expect(muted, isTrue);
    expect(controller.session.isMuted, isTrue);
    expect(bridge.muteStates, <bool>[true]);

    final disabled = await controller.setEnabled(false);
    expect(disabled, isTrue);
    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.disabled);
    expect(bridge.disableCalls, 1);

    final reenabled = await controller.setEnabled(true);
    expect(reenabled, isTrue);
    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.active);
    expect(controller.session.isMuted, isTrue);
    expect(bridge.enableCalls, 2);
    expect(bridge.muteStates, <bool>[true, true]);
  });

  test('leave and dispose teardown the backend once', () async {
    final bridge = _FakeAvConferenceSessionBridge();
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_3',
      displayName: 'Disposable room',
      bridge: bridge,
    );

    await controller.join();

    await Future.wait<void>([controller.leave(), controller.disposeSession()]);

    expect(bridge.disableCalls, 1);
    expect(bridge.clearReceiveCallbackCalls, 1);
    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.disposed);

    await controller.disposeSession();
    expect(bridge.disableCalls, 1);
    expect(bridge.clearReceiveCallbackCalls, 1);
  });

  test(
    'duplicate same-group session cannot teardown the active owner',
    () async {
      final bridge = _FakeAvConferenceSessionBridge();
      final owner = AvConferenceSessionController(
        groupId: 'tox_conf_pcm_shared',
        displayName: 'Owner',
        bridge: bridge,
      );
      final duplicate = AvConferenceSessionController(
        groupId: 'tox_conf_pcm_shared',
        displayName: 'Duplicate',
        bridge: bridge,
      );

      expect(await owner.join(), isTrue);
      expect(await duplicate.join(), isFalse);

      await duplicate.disposeSession();

      expect(bridge.disableCalls, 0);
      expect(bridge.enabledGroups, <String>{'tox_conf_pcm_shared'});
      expect(bridge.hasReceiveCallbackFor('tox_conf_pcm_shared'), isTrue);

      bridge.emitFrame(groupId: 'tox_conf_pcm_shared');
      expect(owner.session.receivedFrameCount, 1);
      expect(duplicate.session.receivedFrameCount, 0);

      await owner.disposeSession();

      expect(bridge.disableCalls, greaterThanOrEqualTo(1));
      expect(bridge.clearReceiveCallbackCalls, 1);
      expect(bridge.enabledGroups, isEmpty);
      expect(bridge.hasReceiveCallback, isFalse);
    },
  );

  test(
    'disposeSession surfaces disable failure and releases ownership',
    () async {
      final bridge = _FakeAvConferenceSessionBridge();
      final ownerA = AvConferenceSessionController(
        groupId: 'tox_conf_pcm_replacement',
        displayName: 'Owner A',
        bridge: bridge,
      );
      final ownerB = AvConferenceSessionController(
        groupId: 'tox_conf_pcm_replacement',
        displayName: 'Owner B',
        bridge: bridge,
      );

      expect(await ownerA.join(), isTrue);
      bridge.nextDisableResult = false;

      await ownerA.disposeSession();

      expect(ownerA.session.lifecycle, AvConferenceSessionLifecycle.failed);
      expect(ownerA.session.failure, AvConferenceSessionFailure.disable);
      expect(bridge.disableCalls, 1);
      expect(bridge.clearReceiveCallbackCalls, 1);
      expect(bridge.hasReceiveCallbackFor('tox_conf_pcm_replacement'), isFalse);
      expect(await ownerB.join(), isTrue);
      expect(ownerB.session.lifecycle, AvConferenceSessionLifecycle.active);
    },
  );

  test('join failure keeps the session in a retryable failed state', () async {
    final failedEnable = Completer<bool>()..complete(false);
    final bridge = _FakeAvConferenceSessionBridge()
      ..nextEnableResult = failedEnable;
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_join_failed',
      displayName: 'Join failed room',
      bridge: bridge,
    );

    expect(await controller.join(), isFalse);

    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.failed);
    expect(controller.session.failure, AvConferenceSessionFailure.join);
    expect(bridge.hasReceiveCallbackFor('tox_conf_pcm_join_failed'), isFalse);

    expect(await controller.join(), isTrue);
    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.active);
    expect(bridge.enableCalls, 2);
  });

  test('disable failure clears the callback and keeps retry visible', () async {
    final bridge = _FakeAvConferenceSessionBridge();
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_disable_failed',
      displayName: 'Disable failed room',
      bridge: bridge,
    );

    expect(await controller.join(), isTrue);
    bridge.nextDisableResult = false;

    expect(await controller.setEnabled(false), isFalse);

    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.failed);
    expect(controller.session.failure, AvConferenceSessionFailure.disable);
    expect(bridge.clearReceiveCallbackCalls, 1);
    expect(
      bridge.hasReceiveCallbackFor('tox_conf_pcm_disable_failed'),
      isFalse,
    );

    expect(await controller.join(), isTrue);
    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.active);
    expect(bridge.enableCalls, 2);
  });

  test(
    'leave surfaces disable failure and releases ownership',
    () async {
      final bridge = _FakeAvConferenceSessionBridge();
      final ownerA = AvConferenceSessionController(
        groupId: 'tox_conf_pcm_leave_disable_failed',
        displayName: 'Leave failure room',
        bridge: bridge,
      );
      final ownerB = AvConferenceSessionController(
        groupId: 'tox_conf_pcm_leave_disable_failed',
        displayName: 'Replacement room',
        bridge: bridge,
      );

      expect(await ownerA.join(), isTrue);
      bridge.nextDisableResult = false;

      await ownerA.leave();

      expect(ownerA.session.lifecycle, AvConferenceSessionLifecycle.failed);
      expect(ownerA.session.failure, AvConferenceSessionFailure.disable);
      expect(bridge.disableCalls, 1);
      expect(bridge.clearReceiveCallbackCalls, 1);
      expect(
        bridge.hasReceiveCallbackFor('tox_conf_pcm_leave_disable_failed'),
        isFalse,
      );
      expect(await ownerB.join(), isTrue);
      expect(ownerB.session.lifecycle, AvConferenceSessionLifecycle.active);
    },
  );

  test('dispose during join rolls back a late successful enable', () async {
    final enableResult = Completer<bool>();
    final enableStarted = Completer<void>();
    final bridge = _FakeAvConferenceSessionBridge()
      ..nextEnableResult = enableResult
      ..enableStarted = enableStarted;
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_join_race',
      displayName: 'Closing room',
      bridge: bridge,
    );

    final joinFuture = controller.join();
    await enableStarted.future;
    final disposeFuture = controller.disposeSession();

    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.closing);
    expect(bridge.disableCalls, 0);
    expect(bridge.clearReceiveCallbackCalls, 0);

    enableResult.complete(true);

    expect(await joinFuture, isFalse);
    await disposeFuture;
    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.disposed);
    expect(bridge.disableCalls, 1);
    expect(bridge.clearReceiveCallbackCalls, 1);
    expect(bridge.enabledGroups, isEmpty);
    expect(bridge.hasReceiveCallback, isFalse);
  });

  test('failed mute restoration rolls back the enabled session', () async {
    final bridge = _FakeAvConferenceSessionBridge();
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_mute_failure',
      displayName: 'Muted room',
      bridge: bridge,
    );
    await controller.join();
    await controller.setMuted(true);
    await controller.setEnabled(false);

    final muteResult = Completer<bool>();
    final muteStarted = Completer<void>();
    bridge
      ..nextSetMutedResult = muteResult
      ..setMutedStarted = muteStarted;

    final joinFuture = controller.join();
    await muteStarted.future;
    expect(bridge.enabledGroups, contains('tox_conf_pcm_mute_failure'));
    expect(bridge.hasReceiveCallback, isTrue);

    muteResult.complete(false);

    expect(await joinFuture, isFalse);
    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.failed);
    expect(controller.session.failure, AvConferenceSessionFailure.mute);
    expect(controller.session.isMuted, isTrue);
    expect(bridge.disableCalls, 2);
    expect(bridge.clearReceiveCallbackCalls, 2);
    expect(bridge.enabledGroups, isEmpty);
    expect(bridge.hasReceiveCallback, isFalse);
  });

  test(
    'active mute failure moves the session into a failed retry state',
    () async {
      final failedMute = Completer<bool>()..complete(false);
      final bridge = _FakeAvConferenceSessionBridge()
        ..nextSetMutedResult = failedMute;
      final controller = AvConferenceSessionController(
        groupId: 'tox_conf_pcm_active_mute_failure',
        displayName: 'Active mute room',
        bridge: bridge,
      );

      expect(await controller.join(), isTrue);
      expect(await controller.toggleMuted(), isFalse);

      expect(controller.session.lifecycle, AvConferenceSessionLifecycle.failed);
      expect(controller.session.failure, AvConferenceSessionFailure.mute);
      expect(controller.session.isMuted, isFalse);
      expect(bridge.clearReceiveCallbackCalls, 1);
      expect(
        bridge.hasReceiveCallbackFor('tox_conf_pcm_active_mute_failure'),
        isFalse,
      );
    },
  );

  test('leave surfaces a closing lifecycle before the session ends', () async {
    final disableResult = Completer<bool>();
    final disableStarted = Completer<void>();
    final bridge = _FakeAvConferenceSessionBridge()
      ..nextDisableCompletion = disableResult
      ..disableStarted = disableStarted;
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_closing',
      displayName: 'Closing room',
      bridge: bridge,
    );

    expect(await controller.join(), isTrue);

    final leaveFuture = controller.leave();
    await disableStarted.future;

    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.closing);

    disableResult.complete(true);
    await leaveFuture;

    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.left);
  });
}

final class _FakeAvConferenceSessionBridge
    implements AvConferenceSessionBridge {
  int enableCalls = 0;
  int disableCalls = 0;
  int clearReceiveCallbackCalls = 0;
  final Set<String> enabledGroups = <String>{};
  final List<bool> muteStates = <bool>[];
  final Map<String, AvConferenceAudioFrameCallback> _callbacks =
      <String, AvConferenceAudioFrameCallback>{};
  final Map<String, AvConferenceSessionOwner> _callbackOwners =
      <String, AvConferenceSessionOwner>{};
  final Map<String, AvConferenceSessionOwner> _backendOwners =
      <String, AvConferenceSessionOwner>{};
  Completer<bool>? nextEnableResult;
  bool? nextDisableResult;
  Completer<bool>? nextDisableCompletion;
  Completer<bool>? nextSetMutedResult;
  Completer<void>? enableStarted;
  Completer<void>? disableStarted;
  Completer<void>? setMutedStarted;

  bool get hasReceiveCallback => _callbacks.isNotEmpty;

  bool hasReceiveCallbackFor(String groupId) {
    return _callbacks.containsKey(groupId);
  }

  @override
  void clearReceiveCallback({
    required String groupId,
    required AvConferenceSessionOwner owner,
  }) {
    clearReceiveCallbackCalls += 1;
    if (identical(_callbackOwners[groupId], owner)) {
      _callbackOwners.remove(groupId);
      _callbacks.remove(groupId);
    }
  }

  @override
  Future<bool> disable({
    required String groupId,
    required AvConferenceSessionOwner owner,
  }) async {
    disableCalls += 1;
    if (!identical(_backendOwners[groupId], owner)) {
      return false;
    }
    final started = disableStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final controlledCompletion = nextDisableCompletion;
    nextDisableCompletion = null;
    if (controlledCompletion != null) {
      final disabled = await controlledCompletion.future;
      if (!disabled) {
        return false;
      }
      _backendOwners.remove(groupId);
      enabledGroups.remove(groupId);
      return true;
    }
    final controlledResult = nextDisableResult;
    nextDisableResult = null;
    if (controlledResult == false) {
      return false;
    }
    _backendOwners.remove(groupId);
    enabledGroups.remove(groupId);
    return true;
  }

  void emitFrame({required String groupId}) {
    _callbacks[groupId]?.call(
      groupId,
      7,
      9,
      const <int>[1, 2, 3, 4],
      4,
      1,
      48000,
    );
  }

  @override
  Future<bool> enable({
    required String groupId,
    required AvConferenceSessionOwner owner,
    required AvConferenceAudioFrameCallback onAudioFrame,
  }) async {
    enableCalls += 1;
    if (_callbacks.containsKey(groupId)) {
      return false;
    }
    _callbackOwners[groupId] = owner;
    _callbacks[groupId] = onAudioFrame;
    final started = enableStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final controlledResult = nextEnableResult;
    nextEnableResult = null;
    final enabled = controlledResult == null
        ? true
        : await controlledResult.future;
    if (enabled) {
      _backendOwners[groupId] = owner;
      enabledGroups.add(groupId);
    } else if (identical(_callbackOwners[groupId], owner)) {
      _callbackOwners.remove(groupId);
      _callbacks.remove(groupId);
    }
    return enabled;
  }

  @override
  Future<bool> setMuted({
    required String groupId,
    required AvConferenceSessionOwner owner,
    required bool muted,
  }) async {
    if (!identical(_backendOwners[groupId], owner)) {
      return false;
    }
    muteStates.add(muted);
    final started = setMutedStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final controlledResult = nextSetMutedResult;
    nextSetMutedResult = null;
    return controlledResult == null ? true : await controlledResult.future;
  }
}
