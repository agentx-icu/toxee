import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Plays a ringtone (generated tone) when there is an incoming call. Stops when call is accepted/rejected.
class RingtonePlayer {
  final AudioPlayer _player = AudioPlayer();
  String? _tempWavPath;
  bool _playing = false;

  /// Start playing ringtone in loop (incoming call).
  Future<void> start() async {
    if (_playing) return;
    try {
      _tempWavPath ??= await _createRingtoneWav();
      if (_tempWavPath == null) return;
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setSource(DeviceFileSource(_tempWavPath!));
      await _player.resume();
      _playing = true;
    } catch (e) {
      // ignore: no asset or platform error
    }
  }

  /// Stop ringtone.
  Future<void> stop() async {
    if (!_playing) return;
    try {
      await _player.stop();
      _playing = false;
    } catch (_) {}
  }

  /// Release native AudioPlayer resources and clean up temp file.
  Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (_) {}
    if (_tempWavPath != null) {
      try {
        final file = File(_tempWavPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _tempWavPath = null;
    }
  }

  /// Create a short WAV file (440 Hz beep, 0.4s on, looped by audioplayers).
  static Future<String?> _createRingtoneWav() async {
    const sampleRate = 44100;
    const durationSec = 0.4;
    const freq = 440.0;
    final numSamples = (sampleRate * durationSec).round();
    final bytes = ByteData(44 + numSamples * 2);
    int pos = 0;
    void writeU32(int v) {
      bytes.setUint32(pos, v, Endian.little);
      pos += 4;
    }
    void writeU16(int v) {
      bytes.setUint16(pos, v, Endian.little);
      pos += 2;
    }
    // "RIFF"
    bytes.setUint8(pos, 0x52); pos++;
    bytes.setUint8(pos, 0x49); pos++;
    bytes.setUint8(pos, 0x46); pos++;
    bytes.setUint8(pos, 0x46); pos++;
    writeU32(36 + numSamples * 2);
    // "WAVE"
    bytes.setUint8(pos, 0x57); pos++;
    bytes.setUint8(pos, 0x41); pos++;
    bytes.setUint8(pos, 0x56); pos++;
    bytes.setUint8(pos, 0x45); pos++;
    // "fmt "
    bytes.setUint8(pos, 0x66); pos++;
    bytes.setUint8(pos, 0x6d); pos++;
    bytes.setUint8(pos, 0x74); pos++;
    bytes.setUint8(pos, 0x20); pos++;
    writeU32(16);
    writeU16(1); // PCM
    writeU16(1); // mono
    writeU32(sampleRate);
    writeU32(sampleRate * 2); // byte rate
    writeU16(2); // block align
    writeU16(16); // bits per sample
    // "data"
    bytes.setUint8(pos, 0x64); pos++;
    bytes.setUint8(pos, 0x61); pos++;
    bytes.setUint8(pos, 0x74); pos++;
    bytes.setUint8(pos, 0x61); pos++;
    writeU32(numSamples * 2);
    const step = 2 * math.pi * freq / sampleRate;
    for (int i = 0; i < numSamples; i++) {
      final sample = (0.3 * math.sin(step * i) * 32767).round().clamp(-32768, 32767);
      bytes.setInt16(pos, sample, Endian.little);
      pos += 2;
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(
        dir.path, 'ringtone_${DateTime.now().millisecondsSinceEpoch}.wav'));
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file.path;
  }
}
