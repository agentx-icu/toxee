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
    // The contract under test, not just "it recovers eventually": retrying per
    // arriving frame would hammer the platform 50x/s, so the handler backs off
    // for exactly this long (`AudioHandler._playbackRetryAt`). Bounding the
    // wait to the SPECIFIED backoff plus CI slack is what makes a regression
    // to, say, a 10 s backoff fail here — kicking in a loop for 20 s recovered
    // from that too, and passed.
    const backoff = Duration(seconds: 1);
    const ciSlack = Duration(seconds: 2);

    speaker.failSetup = true;
    await joinListenOnly();
    final backoffArmedAt = DateTime.now();
    audio.kickPlayback();
    await pumpEventQueue();
    expect(speaker.setupCount, 1);

    audio.kickPlayback();
    await pumpEventQueue();
    expect(speaker.setupCount, 1, reason: 'backoff still running');

    speaker.failSetup = false;
    source.queue.addAll(<int>[7, 7, 7]);

    // Wait the backoff out WITHOUT kicking, so nothing can retry early...
    final retryDue = backoffArmedAt.add(backoff);
    while (DateTime.now().isBefore(retryDue)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(speaker.setupCount, 1,
        reason: 'nothing retries on its own; it takes a kick');

    // ...then a post-backoff kick must succeed. A couple of repeats absorb
    // clock/scheduler granularity on a loaded CI host; the deadline is the
    // backoff plus slack, not an open-ended budget.
    final deadline = retryDue.add(ciSlack);
    while (speaker.setupCount < 2 && DateTime.now().isBefore(deadline)) {
      audio.kickPlayback();
      await pumpEventQueue();
      if (speaker.setupCount < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    expect(speaker.setupCount, 2,
        reason: 'a kick after the ${backoff.inSeconds}s backoff must retry the '
            'setup (allowing ${ciSlack.inSeconds}s of CI slack)');
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
