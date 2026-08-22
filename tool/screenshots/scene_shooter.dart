// Scene shooter for the product-screenshot driver.
//
// Owns everything about writing one scene PNG: foregrounding the app,
// keeping transient toasts out of the frame, retrying empty captures,
// duplicate-frame detection, and the end-of-run summary. Decoupled from the
// driver's private `_Shot` connection class via the three callbacks so it can
// live in its own file.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// `flutter_skill` service-extension invoker (`_Shot.skill` tear-off).
typedef SkillCall =
    Future<Map<String, dynamic>> Function(
      String method, [
      Map<String, Object?> args,
    ]);

/// Grabs the DEVICE framebuffer as PNG bytes (null = capture failed).
typedef NativeCapture = Future<List<int>?> Function();

/// A [NativeCapture] for the mobile targets, or null to keep the Flutter-layer
/// capture (always the case on desktop, and the DEFAULT on mobile).
///
/// Why this is opt-in (`capture.sh`'s `TOXEE_SHOT_NATIVE_FRAMES=1`, which
/// passes `--sim-udid` / `--adb-serial`): the Flutter layer alone leaves the OS
/// status-bar and home-indicator areas as blank bands, which read as
/// unfinished chrome, and the device framebuffer includes them. BUT
/// `simctl io screenshot` returns what the simulator's display server has
/// COMPOSITED, and with no interactive GUI session (a plain ssh shell) that
/// stops updating: measured 2026-08-22, five scenes came back byte-identical
/// to each other AND to the previous run's frames — a frozen screen showing a
/// stale alert — while the app log proved the driver had navigated every
/// scene. Use it only from a session that owns the Mac's display.
NativeCapture? deviceCapture({String? simUdid, String? adbSerial}) {
  if (simUdid != null && simUdid.isNotEmpty) {
    return () async {
      final tmp = File(
        '${Directory.systemTemp.path}/toxee_shot_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      final r = await Process.run('xcrun', [
        'simctl',
        'io',
        simUdid,
        'screenshot',
        '--type=png',
        tmp.path,
      ]);
      if (r.exitCode != 0 || !tmp.existsSync()) {
        print('[shot] simctl screenshot failed: ${r.stderr}');
        return null;
      }
      final bytes = await tmp.readAsBytes();
      await tmp.delete();
      return bytes;
    };
  }
  if (adbSerial != null && adbSerial.isNotEmpty) {
    return () async {
      final r = await Process.run('adb', [
        '-s',
        adbSerial,
        'exec-out',
        'screencap',
        '-p',
      ], stdoutEncoding: null);
      if (r.exitCode != 0) {
        print('[shot] adb screencap failed: ${r.stderr}');
        return null;
      }
      return r.stdout as List<int>;
    };
  }
  return null;
}

class SceneShooter {
  SceneShooter(
    this.outDir,
    this.platform, {
    required this.foreground,
    required this.skill,
    required this.waitMs,
    this.nativeCapture,
  });

  final Directory outDir;
  final String platform;
  final Future<void> Function() foreground;
  final SkillCall skill;
  final Future<void> Function(int ms) waitMs;

  /// When set, frames come from the device framebuffer instead of the
  /// Flutter layer (see [deviceCapture]). The SnackBar checks still introspect
  /// the widget tree through [skill] either way.
  final NativeCapture? nativeCapture;

  /// One frame as PNG bytes, from whichever source this shooter uses; null
  /// when the source produced nothing (the caller retries).
  Future<List<int>?> _captureFrame() async {
    final native = nativeCapture;
    if (native != null) {
      final frame = await native();
      if (frame != null && frame.isNotEmpty) return frame;
      // A device grab that produced nothing is not a reason to fail the scene
      // when the Flutter layer can still answer.
      print('[shot:$platform] device capture empty — falling back to the '
          'Flutter layer for this frame');
    }
    final r = await skill('screenshot', const {});
    final b64 = r['image'] as String?;
    if (b64 == null || b64.isEmpty) return null;
    return base64Decode(b64);
  }

  final List<String> _ok = [];
  final List<String> _failed = [];
  final List<String> _warned = [];
  // Byte fingerprints: two DIFFERENT scenes that are byte-identical means a
  // navigation silently didn't take — surface it loudly.
  final Map<String, String> _frameOwners = {};

  /// True when a SnackBar is in the element tree right now (best-effort:
  /// introspection failures read as "clear" so they never block a capture).
  Future<bool> _snackBarVisible() async {
    try {
      final r = await skill('findByType', const {'type': 'SnackBar'});
      final elements = (r['elements'] as List<dynamic>?) ?? const [];
      return elements.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Product shots must not carry transient toasts (e.g. the "Cannot reach
  /// the DHT after 30s" banner that legitimately fires in the offline seed
  /// environment). SnackBars auto-dismiss in ~4s, so wait for the tree to be
  /// clear of them — bounded, and a leftover is only a warning: the capture
  /// still proceeds.
  Future<void> _waitForNoSnackBar() async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      if (!await _snackBarVisible()) return;
      await waitMs(500);
    }
    warn('a SnackBar was still visible when the capture deadline hit');
  }

  Future<void> shot(String scene) async {
    final path = '${outDir.path}/$scene.png';
    await _waitForNoSnackBar();
    for (var attempt = 1; attempt <= 3; attempt++) {
      await foreground();
      await waitMs(350);
      final frame = await _captureFrame();
      if (frame != null && frame.isNotEmpty) {
        // A toast can pop in the window between the pre-wait and the actual
        // frame render (the DHT banner fires on a 30s timer, so it races the
        // scene walk). Verify AFTER the fact: a SnackBar animates over ~200ms
        // and lives ~4s, so if the tree is clear milliseconds after the
        // capture, the captured frame was clean too. If not, wait it out and
        // retake within the existing attempt loop.
        if (await _snackBarVisible()) {
          if (attempt < 3) {
            print(
              '[shot:$platform] $scene attempt $attempt caught a SnackBar '
              '— waiting it out and retaking',
            );
            await _waitForNoSnackBar();
            continue;
          }
          // A knowingly toast-contaminated product shot must FAIL the scene:
          // exiting 0 with a polluted asset defeats the pipeline's purpose.
          // The frame is still written (overwritten by the next good run) so
          // the failure can be diagnosed by eye.
          await File(path).writeAsBytes(frame);
          _failed.add(scene);
          stderr.writeln(
            '[shot:$platform] FAILED: $scene — SnackBar still visible after '
            '3 attempts (contaminated frame kept for inspection)',
          );
          return;
        }
        final bytes = frame;
        await File(path).writeAsBytes(bytes);
        final dims = _pngDims(bytes);
        final fp =
            '${bytes.length}:${bytes.fold<int>(0, (h, b) => (h * 31 + b) & 0x7fffffff)}';
        final owner = _frameOwners[fp];
        if (owner != null) {
          warn('$scene is byte-identical to $owner — navigation likely no-op');
        }
        _frameOwners.putIfAbsent(fp, () => scene);
        print(
          '[shot:$platform] $scene.png ${dims ?? "?x?"} '
          '(${(bytes.length / 1024).round()} KB)',
        );
        _ok.add(scene);
        return;
      }
      print('[shot:$platform] $scene attempt $attempt empty — retrying');
      await waitMs(800);
    }
    _failed.add(scene);
    stderr.writeln('[shot:$platform] FAILED: $scene');
  }

  void warn(String msg) {
    _warned.add(msg);
    print('[shot:$platform] WARN $msg');
  }

  bool summarize() {
    print('\n── $platform summary ──');
    print('ok     : ${_ok.join(", ")}');
    if (_warned.isNotEmpty) print('warned : ${_warned.join("; ")}');
    if (_failed.isNotEmpty) {
      stderr.writeln('FAILED : ${_failed.join(", ")}');
      return false;
    }
    return true;
  }
}

/// Width×height from a PNG IHDR, or null if not a PNG.
String? _pngDims(List<int> bytes) {
  if (bytes.length < 24 || bytes[1] != 0x50) return null;
  int be(int o) =>
      (bytes[o] << 24) |
      (bytes[o + 1] << 16) |
      (bytes[o + 2] << 8) |
      bytes[o + 3];
  return '${be(16)}x${be(20)}';
}
