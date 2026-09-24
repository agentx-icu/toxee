import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:toxee/call/audio_handler.dart';

/// A failed playback `setup()` used to be swallowed while playback was still
/// marked READY: every later frame was fed to a device that was never
/// configured, and nothing ever retried — the call stayed silent for its whole
/// duration. Mobile-visible: this is the same speaker path on iOS and Android.
void main() {
  late _FakeSpeaker speaker;
  late AudioHandler audio;
  late _Source source;

  setUp(() {
    speaker = _FakeSpeaker();
    source = _Source();
    audio = AudioHandler(captureDevice: _FakeMic(), playbackDevice: speaker);
  });

  tearDown(() async {
    await audio.dispose();
  });

  Future<void> joinListenOnly() async {
    await audio.startConference(
      onCapturedFrame: (_) {},
      playbackSource: source,
      captureMicrophone: false,
    );
  }

  test('a failed setup leaves playback released and feeds nothing', () async {
    speaker.failSetup = true;
    await joinListenOnly();
    source.queue.addAll(<int>[1, 2, 3]);
    audio.kickPlayback();
    await pumpEventQueue();

    expect(speaker.setupCount, 1);
    expect(speaker.fed, isEmpty, reason: 'device was never configured');
    // A device callback that arrives anyway must not feed it either.
    speaker.deviceCallback(0);
    expect(speaker.fed, isEmpty);
  });

  test('the next audio after the backoff retries the setup', () async {
    speaker.failSetup = true;
    await joinListenOnly();
    audio.kickPlayback();
    await pumpEventQueue();
    expect(speaker.setupCount, 1);

    // Retrying per arriving frame would hammer the platform 50x/s, so the
    // handler backs off for a second — hence the real wait here.
    audio.kickPlayback();
    await pumpEventQueue();
    expect(speaker.setupCount, 1, reason: 'backoff still running');

    speaker.failSetup = false;
    source.queue.addAll(<int>[7, 7, 7]);
    // Poll the backoff out instead of sleeping a fixed 1100ms past it: a kick
    // that arrives while the backoff is still running is a no-op (it neither
    // sets the device up nor drains the queue), so retrying until the setup
    // lands waits for the condition rather than for the clock.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (speaker.setupCount < 2 && DateTime.now().isBefore(deadline)) {
      audio.kickPlayback();
      await pumpEventQueue();
      if (speaker.setupCount < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    expect(speaker.setupCount, 2, reason: 'recovered');
    expect(speaker.fed.single, Int16List.fromList(<int>[7, 7, 7]));
  });

  test('a new owner is not blocked by the previous one\'s backoff', () async {
    speaker.failSetup = true;
    await joinListenOnly();
    audio.kickPlayback();
    await pumpEventQueue();
    expect(speaker.setupCount, 1);

    speaker.failSetup = false;
    await audio.stopConference();
    await joinListenOnly();
    source.queue.addAll(<int>[4]);
    audio.kickPlayback();
    await pumpEventQueue();

    expect(speaker.setupCount, 2);
    expect(speaker.fed.single, Int16List.fromList(<int>[4]));
  });
}

class _Source implements PcmPullSource {
  final List<int> queue = <int>[];

  @override
  Int16List pull(int maxSamples) {
    final n = queue.length > maxSamples ? maxSamples : queue.length;
    final out = Int16List.fromList(queue.sublist(0, n));
    queue.removeRange(0, n);
    return out;
  }
}

class _FakeSpeaker implements PcmPlaybackDevice {
  void Function(int)? _callback;
  bool failSetup = false;
  int setupCount = 0;
  final List<Int16List> fed = <Int16List>[];

  void deviceCallback(int remainingFrames) => _callback?.call(remainingFrames);

  @override
  Future<void> setup({
    required int sampleRate,
    required int channelCount,
  }) async {
    setupCount++;
    if (failSetup) throw StateError('speaker unavailable');
  }

  @override
  void setFeedThreshold(int frames) {}

  @override
  void setFeedCallback(void Function(int remainingFrames)? callback) {
    _callback = callback;
  }

  @override
  void feed(Int16List samples) => fed.add(samples);

  @override
  Future<void> release() async {}
}

class _FakeMic implements PcmCaptureDevice {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    return const Stream<Uint8List>.empty();
  }

  @override
  Future<void> stop() async {}
}
