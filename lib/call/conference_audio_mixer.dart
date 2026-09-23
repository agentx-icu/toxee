import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Mixes the per-peer PCM streams of a legacy Tox AV conference into the one
/// mono stream the speaker plays.
///
/// toxcore's group AV (`groupav.c`) decodes every peer separately and hands
/// the app one callback per peer per packet: 48 kHz, 1 or 2 channels, frame
/// sizes from 2.5 to 60 ms. Nothing downstream can play N streams at once, so
/// this class keeps a small jitter buffer per peer and, when the playback
/// device asks for samples ([pull]), sums the peers with clipping.
///
/// Timing model: the playback device is the clock. Frames arrive whenever the
/// Dart poll loop drains the native queue ([push]); the device's feed callback
/// pulls whatever is buffered. A peer only starts contributing once it has
/// [primeMs] of audio buffered, which is the jitter cushion; a peer that stops
/// sending contributes silence and is forgotten after [idlePullLimit] empty
/// pulls, so its next talk spurt re-primes.
///
/// Empty pulls alone cannot expire the priming: playback stops pulling once it
/// is starved (see `AudioHandler._feedOrStarve`), which is exactly what a
/// silent conference produces. A peer that has run dry therefore also re-primes
/// on elapsed idle time ([idleReprimeAfter]).
class ConferenceAudioMixer {
  ConferenceAudioMixer({
    this.outputSampleRate = 48000,
    int primeMs = 40,
    int maxBufferedMs = 240,
    this.idlePullLimit = 50,
    this.idleReprimeAfter = const Duration(milliseconds: 200),
    DateTime Function()? clock,
  }) : primeSamples = outputSampleRate * primeMs ~/ 1000,
       maxBufferedSamples = outputSampleRate * maxBufferedMs ~/ 1000,
       _clock = clock ?? DateTime.now;

  final int outputSampleRate;

  /// Samples a peer must have buffered before it is mixed in.
  final int primeSamples;

  /// Per-peer cap; older audio is dropped past this (bounded latency).
  final int maxBufferedSamples;

  /// Consecutive pulls without data after which a peer is dropped.
  final int idlePullLimit;

  /// Silence (with an empty buffer) after which a peer must re-prime.
  final Duration idleReprimeAfter;

  final DateTime Function() _clock;

  final Map<int, _PeerBuffer> _peers = <int, _PeerBuffer>{};

  @visibleForTesting
  int get peerCount => _peers.length;

  @visibleForTesting
  int bufferedSamplesFor(int peerNumber) => _peers[peerNumber]?.length ?? 0;

  /// Queue one decoded frame from [peerNumber].
  ///
  /// [pcm] is interleaved; [sampleCount] is per channel (the libtoxav
  /// contract). Stereo is averaged to mono and a non-48 kHz stream is
  /// linearly resampled, so every peer buffer is in the output format.
  void push({
    required int peerNumber,
    required List<int> pcm,
    required int sampleCount,
    required int channels,
    required int sampleRate,
  }) {
    if (sampleCount <= 0 || channels <= 0 || sampleRate <= 0) return;
    if (pcm.length < sampleCount * channels) return;
    var mono = downmixToMono(pcm, sampleCount, channels);
    if (sampleRate != outputSampleRate) {
      mono = resampleLinear(mono, sampleRate, outputSampleRate);
    }
    final peer = _peers.putIfAbsent(peerNumber, _PeerBuffer.new);
    final now = _clock();
    // Talking again after a silence that drained the buffer: the cushion this
    // peer was mixed with is gone, so rebuild it instead of playing the first
    // packet of the new spurt straight out.
    if (peer.primed &&
        peer.length == 0 &&
        now.difference(peer.lastPush) >= idleReprimeAfter) {
      peer.primed = false;
    }
    peer.lastPush = now;
    peer.append(mono);
    peer.idlePulls = 0;
    final overflow = peer.length - maxBufferedSamples;
    if (overflow > 0) peer.dropOldest(overflow);
    if (!peer.primed && peer.length >= primeSamples) peer.primed = true;
  }

  /// Mix up to [maxSamples] mono samples. Returns an empty list when no primed
  /// peer has audio (the caller then feeds nothing and waits for a [push]).
  Int16List pull(int maxSamples) {
    var length = 0;
    for (final peer in _peers.values) {
      if (peer.primed && peer.length > length) length = peer.length;
    }
    if (length > maxSamples) length = maxSamples;
    final idle = <int>[];
    if (length <= 0) {
      _peers.forEach((peerNumber, peer) {
        if (peer.primed && ++peer.idlePulls >= idlePullLimit) {
          idle.add(peerNumber);
        }
      });
      idle.forEach(_peers.remove);
      return Int16List(0);
    }
    final acc = Int32List(length);
    _peers.forEach((peerNumber, peer) {
      if (!peer.primed) return;
      final taken = peer.mixInto(acc, length);
      if (taken == 0 && ++peer.idlePulls >= idlePullLimit) {
        idle.add(peerNumber);
      } else if (taken > 0) {
        peer.idlePulls = 0;
      }
    });
    idle.forEach(_peers.remove);
    final out = Int16List(length);
    for (var i = 0; i < length; i++) {
      final v = acc[i];
      out[i] = v > 32767 ? 32767 : (v < -32768 ? -32768 : v);
    }
    return out;
  }

  void removePeer(int peerNumber) => _peers.remove(peerNumber);

  void clear() => _peers.clear();

  /// Average interleaved channels into mono.
  @visibleForTesting
  static Int16List downmixToMono(List<int> pcm, int sampleCount, int channels) {
    final out = Int16List(sampleCount);
    if (channels == 1) {
      for (var i = 0; i < sampleCount; i++) {
        out[i] = pcm[i];
      }
      return out;
    }
    for (var i = 0; i < sampleCount; i++) {
      var sum = 0;
      final base = i * channels;
      for (var c = 0; c < channels; c++) {
        sum += pcm[base + c];
      }
      out[i] = sum ~/ channels;
    }
    return out;
  }

  /// Linear-interpolation resampler for the rare non-48 kHz peer stream.
  @visibleForTesting
  static Int16List resampleLinear(Int16List input, int fromRate, int toRate) {
    if (input.isEmpty || fromRate == toRate) return input;
    final outLength = (input.length * toRate / fromRate).round();
    final out = Int16List(outLength);
    final step = fromRate / toRate;
    for (var i = 0; i < outLength; i++) {
      final pos = i * step;
      final idx = pos.floor();
      if (idx >= input.length - 1) {
        out[i] = input[input.length - 1];
        continue;
      }
      final frac = pos - idx;
      out[i] = (input[idx] + (input[idx + 1] - input[idx]) * frac).round();
    }
    return out;
  }
}

/// FIFO of mono samples with an amortised-O(1) head.
class _PeerBuffer {
  final List<int> _samples = <int>[];
  int _head = 0;
  bool primed = false;
  int idlePulls = 0;

  /// When this peer last delivered a frame (re-priming after a silence).
  DateTime lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  int get length => _samples.length - _head;

  void append(Int16List samples) => _samples.addAll(samples);

  void dropOldest(int count) {
    _head += count;
    _compact();
  }

  /// Add up to [max] samples into [acc]; returns how many were consumed.
  int mixInto(Int32List acc, int max) {
    final n = length < max ? length : max;
    for (var i = 0; i < n; i++) {
      acc[i] += _samples[_head + i];
    }
    _head += n;
    _compact();
    return n;
  }

  void _compact() {
    if (_head == 0) return;
    if (_head >= _samples.length) {
      _samples.clear();
      _head = 0;
    } else if (_head > 4096) {
      _samples.removeRange(0, _head);
      _head = 0;
    }
  }
}
