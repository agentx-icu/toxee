import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart' as ffi_lib;
import 'package:tim2tox_dart/service/toxav_service.dart';
import 'package:toxee/call/audio_handler.dart';
import 'package:toxee/call/av_conference_session_bridge.dart';
import 'package:toxee/call/call_conference_bridge.dart';
import 'package:toxee/call/conference_audio_mixer.dart';

/// GC-1: joining a legacy AV conference must send the microphone and play the
/// peers, through the single shared [AudioHandler] pipeline.
void main() {
  late _FakeMic mic;
  late _FakeSpeaker speaker;
  late AudioHandler audio;
  late _FakeBackend backend;
  late List<String> hookEvents;
  var oneToOneActive = false;
  var micGranted = true;

  CallConferenceBridge makeBridge() {
    return CallConferenceBridge(
      resolveBackend: () async => backend,
      audio: audio,
      isOneToOneCallActive: () => oneToOneActive,
      requestMicrophone: () async => micGranted,
      createMixer: () => ConferenceAudioMixer(primeMs: 20),
      hooks: ConferenceMediaHooks(
        onMediaStarted: (name) async => hookEvents.add('start:$name'),
        onMediaStopped: () async => hookEvents.add('stop'),
      ),
    );
  }

  setUp(() {
    mic = _FakeMic();
    speaker = _FakeSpeaker();
    audio = AudioHandler(captureDevice: mic, playbackDevice: speaker);
    backend = _FakeBackend();
    hookEvents = <String>[];
    oneToOneActive = false;
    micGranted = true;
  });

  tearDown(() async {
    await mic.close();
  });

  Future<AvConferenceEnableResult> join(
    CallConferenceBridge bridge,
    AvConferenceSessionOwner owner, {
    List<int>? frames,
  }) {
    return bridge.enable(
      groupId: 'tox_conf_1',
      displayName: 'Room',
      owner: owner,
      onAudioFrame: (_, __, ___, ____, _____, ______, _______) {
        frames?.add(1);
      },
    );
  }

  test('join captures the mic into toxav group audio (960 @ 48k mono)', () async {
    final bridge = makeBridge();
    final owner = AvConferenceSessionOwner();

    expect(await join(bridge, owner), AvConferenceEnableResult.enabled);
    expect(backend.enabled, {'tox_conf_1'});
    expect(bridge.hasActiveSession, isTrue);
    expect(hookEvents, ['start:Room']);
    expect(audio.owner, AudioHandlerOwner.conference);
    expect(mic.config?.sampleRate, 48000);

    mic.emitFrames(3);
    await pumpEventQueue();

    expect(backend.sent.length, 3);
    expect(backend.sent.first.sampleCount, 960);
    expect(backend.sent.first.channels, 1);
    expect(backend.sent.first.rate, 48000);
    expect(backend.sent.first.groupId, 'tox_conf_1');
  });

  test('Mute stops SENDING the mic; it does not touch receive', () async {
    final bridge = makeBridge();
    final owner = AvConferenceSessionOwner();
    await join(bridge, owner);

    expect(
      await bridge.setMicMuted(groupId: 'tox_conf_1', owner: owner, muted: true),
      isTrue,
    );
    mic.emitFrames(2);
    await pumpEventQueue();
    expect(backend.sent, isEmpty);
    expect(backend.muteCalls, isEmpty, reason: 'mic mute is send-side only');

    await bridge.setMicMuted(groupId: 'tox_conf_1', owner: owner, muted: false);
    mic.emitFrames(1);
    await pumpEventQueue();
    expect(backend.sent.length, 1);
  });

  test('received peer frames are mixed and fed to the speaker', () async {
    final bridge = makeBridge();
    final owner = AvConferenceSessionOwner();
    final controllerFrames = <int>[];
    await join(bridge, owner, frames: controllerFrames);

    // First frame on a starved device is fed as soon as the (queued) setup
    // completes (the kick).
    backend.deliver('tox_conf_1', peer: 1, value: 1000);
    await pumpEventQueue();
    expect(speaker.setupCount, 1);
    expect(speaker.fed.single.first, 1000);

    // Device is playing: further frames queue until it asks for more.
    backend.deliver('tox_conf_1', peer: 1, value: 1000);
    backend.deliver('tox_conf_1', peer: 2, value: 234);
    expect(speaker.fed.length, 1);
    expect(controllerFrames.length, 3, reason: 'controller still counts');

    speaker.deviceCallback(0);
    expect(speaker.fed.length, 2);
    expect(speaker.fed.last.length, 960);
    expect(speaker.fed.last.first, 1234, reason: 'both peers summed');
  });

  test('deafen mutes the receive side natively and stops playback', () async {
    final bridge = makeBridge();
    final owner = AvConferenceSessionOwner();
    await join(bridge, owner);

    expect(
      await bridge.setDeafened(
        groupId: 'tox_conf_1',
        owner: owner,
        deafened: true,
      ),
      isTrue,
    );
    expect(backend.muteCalls, [true]);
    backend.deliver('tox_conf_1', peer: 1, value: 50);
    expect(speaker.fed, isEmpty);

    mic.emitFrames(1);
    await pumpEventQueue();
    expect(backend.sent.length, 1, reason: 'deafen keeps sending the mic');
  });

  test('refuses (busy) while a 1:1 call owns the pipeline', () async {
    oneToOneActive = true;
    final bridge = makeBridge();

    expect(
      await join(bridge, AvConferenceSessionOwner()),
      AvConferenceEnableResult.busy,
    );
    expect(backend.enabled, isEmpty);
    expect(mic.started, isFalse);
    expect(bridge.hasActiveSession, isFalse);
  });

  test('a second conference is busy while one has media', () async {
    final bridge = makeBridge();
    await join(bridge, AvConferenceSessionOwner());

    final other = await bridge.enable(
      groupId: 'tox_conf_2',
      displayName: 'Other',
      owner: AvConferenceSessionOwner(),
      onAudioFrame: (_, __, ___, ____, _____, ______, _______) {},
    );
    expect(other, AvConferenceEnableResult.busyOtherConference);
    expect(backend.enabled, {'tox_conf_1'});
  });

  test('mic permission denied joins listen-only without opening the mic', () async {
    micGranted = false;
    final bridge = makeBridge();

    expect(
      await join(bridge, AvConferenceSessionOwner()),
      AvConferenceEnableResult.enabledReceiveOnly,
    );
    expect(mic.started, isFalse);
    expect(bridge.hasActiveSession, isTrue);
  });

  test('disable releases the mic, the hooks and the busy flag', () async {
    final bridge = makeBridge();
    final owner = AvConferenceSessionOwner();
    await join(bridge, owner);

    expect(await bridge.disable(groupId: 'tox_conf_1', owner: owner), isTrue);
    expect(mic.stopCount, greaterThan(0));
    expect(audio.owner, AudioHandlerOwner.none);
    expect(bridge.hasActiveSession, isFalse);
    expect(backend.enabled, isEmpty);
    expect(hookEvents, ['start:Room', 'stop']);

    mic.emitFrames(1);
    await pumpEventQueue();
    expect(backend.sent, isEmpty);
  });

  test('disable stops local media even when the native disable fails', () async {
    final bridge = makeBridge();
    final owner = AvConferenceSessionOwner();
    await join(bridge, owner);
    backend.disableResult = false;

    expect(await bridge.disable(groupId: 'tox_conf_1', owner: owner), isFalse);
    expect(audio.owner, AudioHandlerOwner.none);
    expect(bridge.hasActiveSession, isFalse);
  });

  test('a 1:1 teardown (AudioHandler.stop) cannot cut a live conference',
      () async {
    final bridge = makeBridge();
    await join(bridge, AvConferenceSessionOwner());

    await audio.stop();
    expect(audio.owner, AudioHandlerOwner.conference);
    mic.emitFrames(1);
    await pumpEventQueue();
    expect(backend.sent.length, 1);
    // And 1:1 remote audio is not mixed into the conference speaker.
    audio.onAudioReceived(3, List<int>.filled(960, 9), 960, 1, 48000);
    expect(speaker.fed, isEmpty);
  });

  test('leaving mid-speech and rejoining still plays (plugin _needsStart '
      'survives release)', () async {
    final bridge = makeBridge();
    final owner = AvConferenceSessionOwner();
    await join(bridge, owner);
    backend.deliver('tox_conf_1', peer: 1, value: 500);
    await pumpEventQueue();
    expect(speaker.fed.length, 1, reason: 'playing when the user leaves');

    // Leave while the device still holds audio: no zero event ever comes.
    await bridge.disable(groupId: 'tox_conf_1', owner: owner);
    expect(speaker.releaseCount, 1);

    final rejoinOwner = AvConferenceSessionOwner();
    expect(await join(bridge, rejoinOwner), AvConferenceEnableResult.enabled);
    backend.deliver('tox_conf_1', peer: 1, value: 700);
    await pumpEventQueue();
    expect(speaker.setupCount, 2);
    expect(speaker.fed.length, 2, reason: 'rejoined session must be fed');
    expect(speaker.fed.last.first, 700);
  });

  test('a drained device is re-kicked by the next frame', () async {
    final bridge = makeBridge();
    await join(bridge, AvConferenceSessionOwner());
    backend.deliver('tox_conf_1', peer: 1, value: 1);
    await pumpEventQueue();
    speaker.deviceCallback(0); // drained, nothing buffered → starved
    expect(speaker.fed.length, 1);
    backend.deliver('tox_conf_1', peer: 1, value: 2);
    expect(speaker.fed.length, 2);
    // A low-buffer event with nothing to give is NOT starvation: the zero
    // event still follows, so no extra kick.
    speaker.deviceCallback(100);
    backend.deliver('tox_conf_1', peer: 1, value: 3);
    expect(speaker.fed.length, 2);
    speaker.deviceCallback(0);
    expect(speaker.fed.length, 3);
  });

  test('a late 1:1 frame with no owner does not set playback up', () async {
    audio.onAudioReceived(3, List<int>.filled(960, 9), 960, 1, 48000);
    expect(speaker.setupCount, 0);
    expect(speaker.fed, isEmpty);
  });

  test('interruption suspends mic + speaker; resume reopens both', () async {
    final states = <AvConferenceMediaState>[];
    final bridge = makeBridge();
    final owner = AvConferenceSessionOwner();
    await bridge.enable(
      groupId: 'tox_conf_1',
      displayName: 'Room',
      owner: owner,
      onAudioFrame: (_, __, ___, ____, _____, ______, _______) {},
      onMediaStateChanged: states.add,
    );

    await bridge.suspendForInterruption();
    expect(states, [AvConferenceMediaState.interrupted]);
    expect(audio.owner, AudioHandlerOwner.none);
    expect(bridge.hasActiveSession, isTrue, reason: 'still joined');
    backend.deliver('tox_conf_1', peer: 1, value: 5);
    expect(speaker.fed, isEmpty);

    await bridge.resumeAfterInterruption();
    expect(states.last, AvConferenceMediaState.full);
    expect(hookEvents, ['start:Room', 'start:Room'], reason: 'session re-set');
    mic.emitFrames(1);
    await pumpEventQueue();
    expect(backend.sent.length, 1);
    backend.deliver('tox_conf_1', peer: 1, value: 5);
    await pumpEventQueue();
    expect(speaker.fed, isNotEmpty);
  });

  test('resume without a microphone falls back to listen-only', () async {
    final states = <AvConferenceMediaState>[];
    final bridge = makeBridge();
    await bridge.enable(
      groupId: 'tox_conf_1',
      displayName: 'Room',
      owner: AvConferenceSessionOwner(),
      onAudioFrame: (_, __, ___, ____, _____, ______, _______) {},
      onMediaStateChanged: states.add,
    );
    await bridge.suspendForInterruption();
    mic.failNextStart = true;
    await bridge.resumeAfterInterruption();
    expect(states, [
      AvConferenceMediaState.interrupted,
      AvConferenceMediaState.listenOnly,
    ]);
  });

  test('dispose (logout) stops media, disables natively, runs no hooks',
      () async {
    final bridge = makeBridge();
    await join(bridge, AvConferenceSessionOwner());
    await bridge.dispose();
    expect(hookEvents, ['start:Room'], reason: 'manager restores platform');
    expect(audio.owner, AudioHandlerOwner.none);
    expect(backend.disableCalls, 1, reason: 'toxav_groupchat_disable_av');
    expect(backend.enabled, isEmpty);
    expect(
      await join(bridge, AvConferenceSessionOwner()),
      AvConferenceEnableResult.failed,
    );
  });

  test('disable requested during the pipeline start runs after it '
      '(serialized), disabling natively exactly once', () async {
    final bridge = makeBridge();
    final owner = AvConferenceSessionOwner();
    final gate = Completer<void>();
    mic.startGate = gate;
    final joining = join(bridge, owner);
    await pumpEventQueue();
    final disabling = bridge.disable(groupId: 'tox_conf_1', owner: owner);
    await pumpEventQueue();
    expect(backend.disableCalls, 0, reason: 'queued behind the start');
    gate.complete();
    expect(await joining, AvConferenceEnableResult.enabled);
    expect(await disabling, isTrue);
    expect(backend.disableCalls, 1);
    expect(audio.owner, AudioHandlerOwner.none);
    expect(bridge.hasActiveSession, isFalse);
  });

  group('AudioHandler serialization (review #1, pre-existing #1)', () {
    test('a stop still awaiting the recorder cannot touch the next call',
        () async {
      final av = _FakeToxAv();
      await audio.startCapture(1, av);
      expect(mic.startCount, 1);
      final stopGate = Completer<void>();
      mic.stopGate = stopGate;
      final stoppingA = audio.stop(); // call A ends; recorder.stop pending
      final startingB = audio.startCapture(2, av); // call B starts right away
      await pumpEventQueue();
      expect(mic.startCount, 1, reason: 'B waits for A\'s device teardown');
      stopGate.complete();
      await stoppingA;
      final claimB = await startingB;
      expect(claimB, isNotNull);
      expect(mic.startCount, 2);
      expect(mic.stopCount, 1, reason: 'A\'s stop did not hit B\'s recorder');
      expect(audio.owner, AudioHandlerOwner.call);
      expect(audio.isCapturing, isTrue);
      mic.emitFrames(1);
      await pumpEventQueue();
      expect(av.sentTo, [2]);
    });

    test('a stale claim cannot stop a newer call', () async {
      final av = _FakeToxAv();
      final claimA = await audio.startCapture(1, av);
      await audio.startCapture(2, av);
      await audio.stop(claim: claimA);
      expect(audio.owner, AudioHandlerOwner.call);
      expect(audio.isCapturing, isTrue);
    });

    test('1:1 playback only plays the active friend\'s PCM', () async {
      await audio.startCapture(1, _FakeToxAv());
      audio.onAudioReceived(2, List<int>.filled(960, 9), 960, 1, 48000);
      await pumpEventQueue();
      expect(speaker.setupCount, 0, reason: 'a second caller\'s leg');
      expect(speaker.fed, isEmpty);
      audio.onAudioReceived(1, List<int>.filled(960, 7), 960, 1, 48000);
      await pumpEventQueue();
      expect(speaker.fed.single.first, 7);
    });

    test('dispose refuses later starts and releases queued ones', () async {
      final av = _FakeToxAv();
      final gate = Completer<void>();
      mic.startGate = gate;
      final starting = audio.startCapture(1, av);
      await pumpEventQueue();
      final disposing = audio.dispose();
      gate.complete();
      expect(await starting, isNull);
      await disposing;
      expect(audio.owner, AudioHandlerOwner.none);
      expect(await audio.startCapture(1, av), isNull);
    });
  });

  group('conference lifecycle queue (review #2 #3 #5 #6 #7)', () {
    test('logout during the mic prompt: enable never opens audio', () async {
      final prompt = Completer<bool>();
      final bridge = CallConferenceBridge(
        resolveBackend: () async => backend,
        audio: audio,
        isOneToOneCallActive: () => false,
        requestMicrophone: () => prompt.future,
      );
      final joining = join(bridge, AvConferenceSessionOwner());
      await pumpEventQueue();
      await bridge.dispose();
      prompt.complete(true);
      expect(await joining, AvConferenceEnableResult.failed);
      expect(mic.started, isFalse);
      expect(backend.enabled, isEmpty);
      expect(audio.owner, AudioHandlerOwner.none);
    });

    test('logout while the start hook runs: no audio, group disabled',
        () async {
      final hookGate = Completer<void>();
      final bridge = CallConferenceBridge(
        resolveBackend: () async => backend,
        audio: audio,
        isOneToOneCallActive: () => false,
        requestMicrophone: () async => true,
        hooks: ConferenceMediaHooks(
          onMediaStarted: (_) => hookGate.future,
        ),
      );
      final joining = join(bridge, AvConferenceSessionOwner());
      await pumpEventQueue();
      expect(backend.enabled, {'tox_conf_1'});
      final disposing = bridge.dispose();
      expect(backend.enabled, isEmpty, reason: 'native disable is immediate');
      hookGate.complete();
      expect(await joining, AvConferenceEnableResult.failed);
      await disposing;
      expect(mic.started, isFalse);
      expect(audio.owner, AudioHandlerOwner.none);
      expect(bridge.hasActiveSession, isFalse);
    });

    test('an owner giving up after a failed disable hands the group to a '
        'bounded background retry', () async {
      final bridge = CallConferenceBridge(
        resolveBackend: () async => backend,
        audio: audio,
        isOneToOneCallActive: () => false,
        requestMicrophone: () async => true,
        disableRetryDelays: const [Duration(milliseconds: 1)],
      );
      final owner = AvConferenceSessionOwner();
      await join(bridge, owner);
      backend.disableResult = false;
      expect(await bridge.disable(groupId: 'tox_conf_1', owner: owner), isFalse);
      expect(backend.enabled, {'tox_conf_1'}, reason: 'still owned natively');
      bridge.clearReceiveCallback(groupId: 'tox_conf_1', owner: owner);
      backend.disableResult = true;
      // Poll for the background retry rather than sleeping past its (injected
      // 1ms) delay: a fixed 20ms is a race on a loaded host.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (backend.enabled.isNotEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(backend.enabled, isEmpty);
      expect(backend.disableCalls, 2);
      await bridge.dispose();
      expect(backend.disableCalls, 2, reason: 'nothing left to disable');
    });

    test('re-joining an abandoned, still-enabled group adopts it', () async {
      final bridge = CallConferenceBridge(
        resolveBackend: () async => backend,
        audio: audio,
        isOneToOneCallActive: () => false,
        requestMicrophone: () async => true,
        disableRetryDelays: const [Duration(seconds: 30)],
      );
      final first = AvConferenceSessionOwner();
      await join(bridge, first);
      backend.disableResult = false;
      await bridge.disable(groupId: 'tox_conf_1', owner: first);
      bridge.clearReceiveCallback(groupId: 'tox_conf_1', owner: first);
      backend.disableResult = true;
      expect(
        await join(bridge, AvConferenceSessionOwner()),
        AvConferenceEnableResult.enabled,
      );
      await bridge.dispose(); // also cancels the (now moot) retry timer
      expect(backend.enabled, isEmpty);
    });

    test('focus lost while a resume is starting ends interrupted, mic closed',
        () async {
      final states = <AvConferenceMediaState>[];
      final hookGate = Completer<void>();
      var hookCalls = 0;
      final bridge = CallConferenceBridge(
        resolveBackend: () async => backend,
        audio: audio,
        isOneToOneCallActive: () => false,
        requestMicrophone: () async => true,
        hooks: ConferenceMediaHooks(
          onMediaStarted: (_) async {
            if (++hookCalls == 2) await hookGate.future;
          },
        ),
      );
      await bridge.enable(
        groupId: 'tox_conf_1',
        displayName: 'Room',
        owner: AvConferenceSessionOwner(),
        onAudioFrame: (_, __, ___, ____, _____, ______, _______) {},
        onMediaStateChanged: states.add,
      );
      await bridge.suspendForInterruption();
      final resuming = bridge.resumeAfterInterruption(); // focus gained
      await pumpEventQueue();
      final suspending = bridge.suspendForInterruption(); // focus lost again
      hookGate.complete();
      await resuming;
      await suspending;
      expect(states.last, AvConferenceMediaState.interrupted);
      expect(audio.owner, AudioHandlerOwner.none);
      expect(audio.isCapturing, isFalse);
    });

    test('a resume refused by a transient 1:1 owner retries when it ends',
        () async {
      final states = <AvConferenceMediaState>[];
      final bridge = makeBridge();
      await bridge.enable(
        groupId: 'tox_conf_1',
        displayName: 'Room',
        owner: AvConferenceSessionOwner(),
        onAudioFrame: (_, __, ___, ____, _____, ______, _______) {},
        onMediaStateChanged: states.add,
      );
      await bridge.suspendForInterruption();
      await audio.startCapture(5, _FakeToxAv()); // 1:1 holds the pipeline
      await bridge.resumeAfterInterruption();
      expect(states, [AvConferenceMediaState.interrupted]);
      await audio.stop(); // the 1:1 call ends
      await pumpEventQueue();
      expect(states.last, AvConferenceMediaState.full);
      expect(audio.owner, AudioHandlerOwner.conference);
    });

    test('a released callback\'s stop cannot tear down a quick re-join',
        () async {
      final bridge = CallConferenceBridge(
        resolveBackend: () async => backend,
        audio: audio,
        isOneToOneCallActive: () => false,
        requestMicrophone: () async => true,
        createMixer: () => ConferenceAudioMixer(primeMs: 20),
        disableRetryDelays: const [Duration(seconds: 30)],
        hooks: ConferenceMediaHooks(
          onMediaStarted: (name) async => hookEvents.add('start:$name'),
          onMediaStopped: () async => hookEvents.add('stop'),
        ),
      );
      final first = AvConferenceSessionOwner();
      await join(bridge, first);
      bridge.clearReceiveCallback(groupId: 'tox_conf_1', owner: first);
      final rejoin = await join(bridge, AvConferenceSessionOwner());
      expect(rejoin, AvConferenceEnableResult.enabled);
      await pumpEventQueue();
      expect(hookEvents, ['start:Room', 'stop', 'start:Room']);
      expect(audio.owner, AudioHandlerOwner.conference);
      expect(audio.isCapturing, isTrue);
      mic.emitFrames(1);
      await pumpEventQueue();
      expect(backend.sent.length, 1);
      await bridge.dispose();
    });
  });

  test('listen-only startConference / stopConference round-trip', () async {
    final result = await audio.startConference(
      onCapturedFrame: (_) {},
      playbackSource: _EmptySource(),
      captureMicrophone: false,
    );
    expect(result, ConferenceAudioStart.playbackOnly);
    await audio.stopConference();
    expect(audio.owner, AudioHandlerOwner.none);
  });
}

final class _NoFfi implements ffi_lib.Tim2ToxFfi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeToxAv extends ToxAVService {
  _FakeToxAv() : super(_NoFfi());

  final List<int> sentTo = <int>[];

  @override
  Future<bool> sendAudioFrame(
    int friendNumber,
    List<int> pcm,
    int sampleCount,
    int channels,
    int samplingRate,
  ) async {
    sentTo.add(friendNumber);
    return true;
  }
}

class _EmptySource implements PcmPullSource {
  @override
  Int16List pull(int maxSamples) => Int16List(0);
}

class _FakeMic implements PcmCaptureDevice {
  // Closed in [close] (stop / tearDown).
  // ignore: close_sinks
  StreamController<Uint8List>? _controller;
  RecordConfig? config;
  bool started = false;
  int stopCount = 0;

  @override
  Future<bool> hasPermission() async => true;

  Completer<void>? startGate;
  Completer<void>? stopGate;
  bool failNextStart = false;
  int startCount = 0;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    final gate = startGate;
    startGate = null;
    if (gate != null) await gate.future;
    if (failNextStart) {
      failNextStart = false;
      throw StateError('mic busy');
    }
    this.config = config;
    started = true;
    startCount++;
    _controller = StreamController<Uint8List>();
    return _controller!.stream;
  }

  void emitFrames(int count) {
    final c = _controller;
    if (c == null || c.isClosed) return;
    for (var i = 0; i < count; i++) {
      c.add(Uint8List(AudioHandler.bytesPerFrame));
    }
  }

  @override
  Future<void> stop() async {
    final gate = stopGate;
    stopGate = null;
    if (gate != null) await gate.future;
    stopCount++;
    await close();
  }

  Future<void> close() async {
    final c = _controller;
    _controller = null;
    if (c == null || c.isClosed) return;
    // An un-listened controller's close() never completes.
    if (c.hasListener) {
      await c.close();
    } else {
      unawaited(c.close());
    }
  }
}

/// Mirrors flutter_pcm_sound 3.3.3 as far as AudioHandler can observe it:
/// setup/feed/release are plain calls and the device only calls back when the
/// native side reports a low-buffer or zero event ([deviceCallback]). There is
/// no start(), and nothing resets on release — like the plugin, whose static
/// `_needsStart` survives `release()` (the reviewer's item 1).
class _FakeSpeaker implements PcmPlaybackDevice {
  void Function(int)? _callback;
  int setupCount = 0;
  int releaseCount = 0;
  final List<Int16List> fed = <Int16List>[];

  /// Native reports `remainingFrames` (0 = fully drained).
  void deviceCallback(int remainingFrames) => _callback?.call(remainingFrames);

  @override
  Future<void> setup({required int sampleRate, required int channelCount}) async {
    setupCount++;
  }

  @override
  void setFeedThreshold(int frames) {}

  @override
  void setFeedCallback(void Function(int remainingFrames)? callback) {
    _callback = callback;
  }

  @override
  void feed(Int16List samples) {
    fed.add(samples);
  }

  @override
  Future<void> release() async {
    releaseCount++;
  }
}

class _Sent {
  _Sent(this.groupId, this.sampleCount, this.channels, this.rate);
  final String groupId;
  final int sampleCount;
  final int channels;
  final int rate;
}

class _FakeBackend implements ConferenceAvBackend {
  final Set<String> enabled = <String>{};
  final List<_Sent> sent = <_Sent>[];
  final List<bool> muteCalls = <bool>[];
  AvConferenceAudioFrameCallback? _callback;
  bool disableResult = true;
  int disableCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> enableConferenceAudio(String groupId) async {
    enabled.add(groupId);
    return true;
  }

  @override
  Future<bool> disableConferenceAudio(String groupId) async {
    disableCalls++;
    if (!disableResult) return false;
    enabled.remove(groupId);
    return true;
  }

  @override
  Future<bool> muteConferenceAudio(String groupId, bool mute) async {
    muteCalls.add(mute);
    return true;
  }

  @override
  Future<bool> sendConferenceAudioFrame(
    String groupId,
    List<int> pcm,
    int sampleCount,
    int channels,
    int samplingRate,
  ) async {
    expect(pcm.length, sampleCount * channels);
    sent.add(_Sent(groupId, sampleCount, channels, samplingRate));
    return true;
  }

  @override
  void setConferenceAudioReceiveCallback(
    AvConferenceAudioFrameCallback? callback,
  ) {
    _callback = callback;
  }

  void deliver(String groupId, {required int peer, required int value}) {
    _callback?.call(
      groupId,
      0,
      peer,
      List<int>.filled(960, value),
      960,
      1,
      48000,
    );
  }
}
