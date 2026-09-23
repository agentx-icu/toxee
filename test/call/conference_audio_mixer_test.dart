import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/conference_audio_mixer.dart';

void main() {
  List<int> frame(int value, [int n = 960]) => List<int>.filled(n, value);

  test('a peer is silent until it has primed its jitter buffer', () {
    final mixer = ConferenceAudioMixer(primeMs: 40);
    mixer.push(
      peerNumber: 1,
      pcm: frame(100),
      sampleCount: 960,
      channels: 1,
      sampleRate: 48000,
    );
    expect(mixer.pull(2048), isEmpty, reason: '20 ms < 40 ms prime');
    mixer.push(
      peerNumber: 1,
      pcm: frame(100),
      sampleCount: 960,
      channels: 1,
      sampleRate: 48000,
    );
    final out = mixer.pull(2048);
    expect(out.length, 1920);
    expect(out.every((s) => s == 100), isTrue);
  });

  test('sums peers and clips to int16', () {
    final mixer = ConferenceAudioMixer(primeMs: 20);
    for (final (peer, value) in [(1, 30000), (2, 30000), (3, -5)]) {
      mixer.push(
        peerNumber: peer,
        pcm: frame(value),
        sampleCount: 960,
        channels: 1,
        sampleRate: 48000,
      );
    }
    final out = mixer.pull(960);
    expect(out.length, 960);
    expect(out.first, 32767);

    final neg = ConferenceAudioMixer(primeMs: 20);
    for (final peer in [1, 2]) {
      neg.push(
        peerNumber: peer,
        pcm: frame(-30000),
        sampleCount: 960,
        channels: 1,
        sampleRate: 48000,
      );
    }
    expect(neg.pull(960).first, -32768);
  });

  test('a short peer contributes what it has, then silence', () {
    final mixer = ConferenceAudioMixer(primeMs: 10);
    mixer.push(
      peerNumber: 1,
      pcm: frame(10, 960),
      sampleCount: 960,
      channels: 1,
      sampleRate: 48000,
    );
    mixer.push(
      peerNumber: 2,
      pcm: frame(1, 480),
      sampleCount: 480,
      channels: 1,
      sampleRate: 48000,
    );
    final out = mixer.pull(2048);
    expect(out.length, 960);
    expect(out[0], 11);
    expect(out[479], 11);
    expect(out[480], 10);
  });

  test('stereo peers are averaged to mono', () {
    final mixer = ConferenceAudioMixer(primeMs: 10);
    final stereo = <int>[];
    for (var i = 0; i < 480; i++) {
      stereo
        ..add(100)
        ..add(300);
    }
    mixer.push(
      peerNumber: 4,
      pcm: stereo,
      sampleCount: 480,
      channels: 2,
      sampleRate: 48000,
    );
    final out = mixer.pull(2048);
    expect(out.length, 480);
    expect(out.every((s) => s == 200), isTrue);
  });

  test('non-48 kHz peers are resampled to the output rate', () {
    final mixer = ConferenceAudioMixer(primeMs: 10);
    mixer.push(
      peerNumber: 1,
      pcm: frame(50, 480),
      sampleCount: 480,
      channels: 1,
      sampleRate: 24000,
    );
    expect(mixer.bufferedSamplesFor(1), 960);
  });

  test('buffer is capped: oldest audio is dropped (bounded latency)', () {
    final mixer = ConferenceAudioMixer(primeMs: 20, maxBufferedMs: 60);
    for (var i = 0; i < 10; i++) {
      mixer.push(
        peerNumber: 1,
        pcm: frame(i),
        sampleCount: 960,
        channels: 1,
        sampleRate: 48000,
      );
    }
    expect(mixer.bufferedSamplesFor(1), 2880);
    // Newest three frames survive.
    expect(mixer.pull(960).first, 7);
  });

  test('an idle peer is forgotten and re-primes on its next talk spurt', () {
    final mixer = ConferenceAudioMixer(primeMs: 40, idlePullLimit: 3);
    for (var i = 0; i < 2; i++) {
      mixer.push(
        peerNumber: 1,
        pcm: frame(5),
        sampleCount: 960,
        channels: 1,
        sampleRate: 48000,
      );
    }
    expect(mixer.pull(4096).length, 1920);
    for (var i = 0; i < 3; i++) {
      expect(mixer.pull(4096), isEmpty);
    }
    expect(mixer.peerCount, 0);
    mixer.push(
      peerNumber: 1,
      pcm: frame(5),
      sampleCount: 960,
      channels: 1,
      sampleRate: 48000,
    );
    expect(mixer.pull(4096), isEmpty, reason: 're-priming');
  });

  test('a peer that went silent re-primes even though nothing PULLED', () {
    // Regression: priming expired by empty pulls only, but playback stops
    // pulling once starved (AudioHandler._feedOrStarve), which is exactly what
    // a silent conference does — so after a long gap the peer's next packet
    // was played with no jitter cushion at all.
    var now = DateTime(2026, 9, 22, 10);
    final mixer = ConferenceAudioMixer(
      primeMs: 40,
      idleReprimeAfter: const Duration(milliseconds: 200),
      clock: () => now,
    );
    void push() => mixer.push(
      peerNumber: 1,
      pcm: frame(5),
      sampleCount: 960,
      channels: 1,
      sampleRate: 48000,
    );

    push();
    push();
    expect(mixer.pull(4096).length, 1920, reason: 'primed, buffer drained');
    // The peer stops talking. Playback is starved, so pull() is never called.
    now = now.add(const Duration(seconds: 5));
    push();
    expect(mixer.pull(4096), isEmpty, reason: 'must re-prime after the gap');
    push();
    expect(mixer.pull(4096).length, 1920);
  });

  test('a brief gap inside one talk spurt does NOT re-prime', () {
    var now = DateTime(2026, 9, 22, 10);
    final mixer = ConferenceAudioMixer(
      primeMs: 40,
      idleReprimeAfter: const Duration(milliseconds: 200),
      clock: () => now,
    );
    void push() => mixer.push(
      peerNumber: 1,
      pcm: frame(5),
      sampleCount: 960,
      channels: 1,
      sampleRate: 48000,
    );

    push();
    push();
    expect(mixer.pull(4096).length, 1920);
    now = now.add(const Duration(milliseconds: 60));
    push();
    expect(mixer.pull(4096).length, 960, reason: 'still primed');
  });

  test('malformed frames are ignored', () {
    final mixer = ConferenceAudioMixer(primeMs: 10);
    mixer.push(
      peerNumber: 1,
      pcm: frame(1, 10),
      sampleCount: 960,
      channels: 1,
      sampleRate: 48000,
    );
    mixer.push(
      peerNumber: 1,
      pcm: frame(1),
      sampleCount: 960,
      channels: 0,
      sampleRate: 48000,
    );
    expect(mixer.peerCount, 0);
  });
}
