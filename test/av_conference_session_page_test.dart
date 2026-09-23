import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/av_conference_session_bridge.dart';
import 'package:toxee/call/av_conference_session_controller.dart';
import 'package:toxee/call/av_conference_session_page.dart';
import 'package:toxee/i18n/app_localizations.dart';

void main() {
  testWidgets(
    'renders a localized frame count with tabular figures and hang-up tooltip',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final bridge = _FakeAvConferenceSessionBridge();
      final controller = AvConferenceSessionController(
        groupId: 'tox_conf_pcm_page_active',
        displayName: 'qTox AV room',
        bridge: bridge,
      );

      await tester.pumpWidget(_TestHarness(controller: controller));
      await tester.pump();

      bridge.emitFrame(groupId: 'tox_conf_pcm_page_active');
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(AvConferenceSessionPage)),
      )!;
      final frameCountLabel = l10n.callReceivedFrames(1);

      expect(find.byTooltip(l10n.callHangUp), findsOneWidget);
      expect(find.bySemanticsLabel(frameCountLabel), findsOneWidget);
      expect(find.text(frameCountLabel), findsOneWidget);

      final frameCountText = tester.widget<Text>(find.text(frameCountLabel));
      expect(
        frameCountText.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );

      semantics.dispose();
    },
  );

  testWidgets(
    'shows joining, active, disabled, closing, and left states distinctly',
    (tester) async {
      final enableResult = Completer<bool>();
      final bridge = _FakeAvConferenceSessionBridge()
        ..nextEnableResult = enableResult;
      final controller = AvConferenceSessionController(
        groupId: 'tox_conf_pcm_page_states',
        displayName: 'State room',
        bridge: bridge,
      );

      await tester.pumpWidget(_TestHarness(controller: controller));

      final l10n = AppLocalizations.of(
        tester.element(find.byType(AvConferenceSessionPage)),
      )!;

      expect(
        controller.session.lifecycle,
        AvConferenceSessionLifecycle.joining,
      );
      expect(find.text(l10n.callCalling), findsOneWidget);

      enableResult.complete(true);
      await tester.pumpAndSettle();

      expect(controller.session.lifecycle, AvConferenceSessionLifecycle.active);
      expect(find.text(l10n.audio), findsOneWidget);

      expect(await controller.setEnabled(false), isTrue);
      await tester.pump();

      expect(
        controller.session.lifecycle,
        AvConferenceSessionLifecycle.disabled,
      );
      expect(find.text(l10n.disable), findsOneWidget);

      expect(await controller.join(), isTrue);
      await tester.pump();

      final disableResult = Completer<bool>();
      final disableStarted = Completer<void>();
      bridge
        ..nextDisableCompletion = disableResult
        ..disableStarted = disableStarted;

      unawaited(controller.leave());
      await disableStarted.future;
      await tester.pump();

      expect(
        controller.session.lifecycle,
        AvConferenceSessionLifecycle.closing,
      );
      expect(find.text(l10n.callLeaving), findsOneWidget);

      disableResult.complete(true);
      await tester.pumpAndSettle();

      expect(controller.session.lifecycle, AvConferenceSessionLifecycle.left);
      expect(find.text(l10n.callEnded), findsOneWidget);
    },
  );

  testWidgets('shows retry and leave affordances after join failure', (
    tester,
  ) async {
    final failedEnable = Completer<bool>()..complete(false);
    final bridge = _FakeAvConferenceSessionBridge()
      ..nextEnableResult = failedEnable;
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_page_failed',
      displayName: 'Failed room',
      bridge: bridge,
    );

    await tester.pumpWidget(_TestHarness(controller: controller));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AvConferenceSessionPage)),
    )!;

    expect(controller.session.lifecycle, AvConferenceSessionLifecycle.failed);
    expect(find.text(l10n.joinFailed), findsOneWidget);
    expect(find.text(l10n.retry), findsOneWidget);
    expect(find.text(l10n.callHangUp), findsOneWidget);
  });

  testWidgets('mic Mute and receive-side "Mute others" are separate controls', (
    tester,
  ) async {
    final bridge = _FakeAvConferenceSessionBridge();
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_page_deafen',
      displayName: 'Deafen room',
      bridge: bridge,
    );

    await tester.pumpWidget(_TestHarness(controller: controller));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AvConferenceSessionPage)),
    )!;

    expect(find.text(l10n.callMute), findsWidgets);
    expect(find.text(l10n.callConferenceMuteIncoming), findsOneWidget);

    await tester.tap(find.byKey(AvConferenceSessionPage.deafenButtonKey));
    await tester.pumpAndSettle();

    expect(controller.session.isDeafened, isTrue);
    expect(controller.session.isMuted, isFalse);
    expect(bridge.deafenStates, <bool>[true]);
    expect(find.text(l10n.callConferenceUnmuteIncoming), findsOneWidget);
  });

  testWidgets('busy join explains that a call must end first', (tester) async {
    final bridge = _FakeAvConferenceSessionBridge()..nextEnableBusy = true;
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_page_busy',
      displayName: 'Busy room',
      bridge: bridge,
    );

    await tester.pumpWidget(_TestHarness(controller: controller));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AvConferenceSessionPage)),
    )!;

    expect(find.text(l10n.callBusyInCall), findsOneWidget);
  });

  testWidgets('busy because of another conference says so', (tester) async {
    final bridge = _FakeAvConferenceSessionBridge()
      ..nextEnableBusyResult = AvConferenceEnableResult.busyOtherConference;
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_page_other',
      displayName: 'Other room',
      bridge: bridge,
    );

    await tester.pumpWidget(_TestHarness(controller: controller));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AvConferenceSessionPage)),
    )!;

    expect(find.text(l10n.callBusyInOtherConference), findsOneWidget);
    expect(find.text(l10n.callBusyInCall), findsNothing);
  });

  testWidgets('an OS audio interruption is shown on the session', (
    tester,
  ) async {
    final bridge = _FakeAvConferenceSessionBridge();
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_page_interrupted',
      displayName: 'Interrupted room',
      bridge: bridge,
    );

    await tester.pumpWidget(_TestHarness(controller: controller));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AvConferenceSessionPage)),
    )!;

    bridge.mediaStateCallback!(AvConferenceMediaState.interrupted);
    await tester.pump();
    expect(find.text(l10n.callAudioInterrupted), findsOneWidget);
  });

  testWidgets('listen-only join disables the mic and says so', (tester) async {
    final bridge = _FakeAvConferenceSessionBridge()..receiveOnly = true;
    final controller = AvConferenceSessionController(
      groupId: 'tox_conf_pcm_page_listen',
      displayName: 'Listen room',
      bridge: bridge,
    );

    await tester.pumpWidget(_TestHarness(controller: controller));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AvConferenceSessionPage)),
    )!;

    expect(find.text(l10n.callConferenceListenOnly), findsOneWidget);
    expect(find.byIcon(Icons.mic_off), findsWidgets);
  });
}

class _TestHarness extends StatelessWidget {
  const _TestHarness({required this.controller});

  final AvConferenceSessionController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AvConferenceSessionPage(controller: controller),
    );
  }
}

final class _FakeAvConferenceSessionBridge
    implements AvConferenceSessionBridge {
  final Map<String, AvConferenceAudioFrameCallback> _callbacks =
      <String, AvConferenceAudioFrameCallback>{};
  final Map<String, AvConferenceSessionOwner> _callbackOwners =
      <String, AvConferenceSessionOwner>{};
  final Map<String, AvConferenceSessionOwner> _backendOwners =
      <String, AvConferenceSessionOwner>{};
  final Set<String> _enabledGroups = <String>{};
  Completer<bool>? nextEnableResult;
  Completer<bool>? nextDisableCompletion;
  Completer<void>? disableStarted;

  @override
  void clearReceiveCallback({
    required String groupId,
    required AvConferenceSessionOwner owner,
  }) {
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
    if (!identical(_backendOwners[groupId], owner)) {
      return false;
    }
    final started = disableStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final controlledCompletion = nextDisableCompletion;
    nextDisableCompletion = null;
    final disabled = controlledCompletion == null
        ? true
        : await controlledCompletion.future;
    if (!disabled) {
      return false;
    }
    _backendOwners.remove(groupId);
    _enabledGroups.remove(groupId);
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
  Future<AvConferenceEnableResult> enable({
    required String groupId,
    required String displayName,
    required AvConferenceSessionOwner owner,
    required AvConferenceAudioFrameCallback onAudioFrame,
    AvConferenceMediaStateCallback? onMediaStateChanged,
  }) async {
    mediaStateCallback = onMediaStateChanged;
    final busy = nextEnableBusyResult;
    if (busy != null) {
      nextEnableBusyResult = null;
      return busy;
    }
    final enabled = await _enable(groupId, owner, onAudioFrame);
    if (!enabled) return AvConferenceEnableResult.failed;
    return receiveOnly
        ? AvConferenceEnableResult.enabledReceiveOnly
        : AvConferenceEnableResult.enabled;
  }

  AvConferenceEnableResult? nextEnableBusyResult;
  set nextEnableBusy(bool busy) =>
      nextEnableBusyResult = busy ? AvConferenceEnableResult.busy : null;
  AvConferenceMediaStateCallback? mediaStateCallback;
  bool receiveOnly = false;
  final List<bool> deafenStates = <bool>[];

  @override
  Future<bool> setDeafened({
    required String groupId,
    required AvConferenceSessionOwner owner,
    required bool deafened,
  }) async {
    if (!identical(_backendOwners[groupId], owner)) {
      return false;
    }
    deafenStates.add(deafened);
    return true;
  }

  Future<bool> _enable(
    String groupId,
    AvConferenceSessionOwner owner,
    AvConferenceAudioFrameCallback onAudioFrame,
  ) async {
    if (_callbacks.containsKey(groupId)) {
      return false;
    }
    _callbackOwners[groupId] = owner;
    _callbacks[groupId] = onAudioFrame;
    final controlledResult = nextEnableResult;
    nextEnableResult = null;
    final enabled = controlledResult == null
        ? true
        : await controlledResult.future;
    if (enabled) {
      _backendOwners[groupId] = owner;
      _enabledGroups.add(groupId);
    } else if (identical(_callbackOwners[groupId], owner)) {
      _callbackOwners.remove(groupId);
      _callbacks.remove(groupId);
    }
    return enabled;
  }

  @override
  Future<bool> setMicMuted({
    required String groupId,
    required AvConferenceSessionOwner owner,
    required bool muted,
  }) async {
    return identical(_backendOwners[groupId], owner);
  }
}
