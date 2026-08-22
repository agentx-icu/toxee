// Cross-platform product-screenshot driver.
//
// Drives ONE already-running toxee instance (desktop / android / ipad / ios),
// seeds rich demo data LOCALLY via the debug L3 surface (no peer, no P2P), and
// captures the 5 product scenes in light theme:
//   c2c · group_chat · new_application · self_profile · settings
//
// capture.sh launches each platform (with the MCP_BINDING=skill + TOXEE_L3_TEST
// debug surface), resolves its VM-service ws URI, and invokes this driver once
// per platform:
//
//   dart run tool/screenshots/capture_product_screenshots.dart \
//     --platform <desktop|android|ipad|ios> --ws-uri ws://127.0.0.1:PORT/TOKEN/ws \
//     --out screenshot/<platform> [--pid <macos-pid>] \
//     [--sim-udid <udid> | --adb-serial <serial>]
//
// Navigation is LAYOUT-AWARE: desktop + iPad render the wide master-detail
// shell (rail; l3_open_chat binds the right pane); android + iPhone render the
// narrow shell (bottom nav; chats open as a pushed route, popped via
// l3_pop_to_root between scenes). Capture: desktop uses
// flutter_skill.screenshot (the Flutter layer — no host-window grab, no
// screen-recording permission). Mobile captures the DEVICE framebuffer instead
// (`simctl io screenshot` / `adb screencap`) when `--sim-udid` / `--adb-serial`
// is given, so the OS status bar and home indicator are part of the product
// shot rather than blank safe-area bands; capture.sh pins the status bar
// (9:41, full battery) before launch.

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'scene_shooter.dart';
import 'seed_data.dart';
import 'seed_runner.dart';

/// macOS window size (wide layout). iPad/phone use the device screen.
///
/// 1400x909 is the largest 1024:665 frame (the aspect doc/product/index.html
/// declares for the desktop shots, 1024x665 after `--sync-site` downscales to
/// 1024 wide) that fits a 1512x982-point MacBook display under the menu bar
/// and title bar. The previous 2000x1468 request did not fit: macOS clamped
/// the height to the visible frame and the shots silently came out 2000x1047
/// (a 1.91 aspect the page then misframed). [_Shot.setWindowBounds] reads the
/// size back and fails the run if the window manager did not honour it.
const _windowW = 1400, _windowH = 909;

/// Wide = rail + master-detail (desktop, tablet); narrow = bottom nav + pushed
/// routes (phone). Drives how a chat is opened and whether routes need popping.
enum _DeviceKind { wide, narrow }

Future<void> main(List<String> args) async {
  exitCode = await _main(args);
}

Future<int> _main(List<String> args) async {
  String? platform, wsUri, outDir, pidArg, simUdid, adbSerial;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--platform':
        platform = args[++i];
      case '--ws-uri':
        wsUri = args[++i];
      case '--out':
        outDir = args[++i];
      case '--pid':
        pidArg = args[++i];
      case '--sim-udid':
        simUdid = args[++i];
      case '--adb-serial':
        adbSerial = args[++i];
      default:
        stderr.writeln('unknown arg: ${args[i]}');
        return 64;
    }
  }
  if (platform == null || wsUri == null || outDir == null) {
    stderr.writeln(
      'usage: capture_product_screenshots.dart --platform <desktop|android|'
      'ipad|ios> --ws-uri <ws://…/ws> --out <dir> [--pid <macos-pid>] '
      '[--sim-udid <udid> | --adb-serial <serial>]',
    );
    return 64;
  }
  const kinds = {
    'desktop': _DeviceKind.wide,
    'ipad': _DeviceKind.wide,
    'android': _DeviceKind.narrow,
    'ios': _DeviceKind.narrow,
  };
  final kind = kinds[platform];
  if (kind == null) {
    stderr.writeln('unknown platform "$platform" (desktop|android|ipad|ios)');
    return 64;
  }
  final isDesktop = platform == 'desktop';
  final out = Directory(outDir);
  await out.create(recursive: true);

  _Shot? s;
  try {
    s = await _Shot.connect(
      wsUri: wsUri,
      platform: platform,
      kind: kind,
      isDesktop: isDesktop,
      pid: int.tryParse(pidArg ?? ''),
    );
    final shooter = SceneShooter(
      out,
      platform,
      foreground: s.foreground,
      skill: s.skill,
      waitMs: s.waitMs,
      nativeCapture: deviceCapture(simUdid: simUdid, adbSerial: adbSerial),
    );
    await s.ensureReady();
    await s.waitForHomeReady();

    // ── seed (idempotent, fully local) ──────────────────────────────────
    // Seed BEFORE waiting on DHT: seeding is fully local (needs no peer/
    // connection), and a long idle wait here can let the session re-init and
    // transiently drop FakeUIKit.im.ffi out from under the seed tools.
    final groupId = await seedAll(s);

    // Presence: the seed environment has no DHT peers, so a real connection
    // may never come. Give it a short chance, then drive the SAME connection
    // stream every presence widget listens to (self dot, "Online" labels) —
    // a hero shot in which the app and every peer are "Offline" reads as a
    // disconnected product, which is not what is being shown.
    await s.waitConnectedBestEffort(secs: 5);
    await s.l3('l3_set_connection', {'connected': 'true'});
    if (platform == 'ios' || platform == 'ipad') {
      // The Simulator has no camera, so the video-call affordances hide
      // (camera-less devices take the receive-only video path). A phone has
      // one: show the same header a phone shows.
      await s.l3('l3_set_capture_device', {'hasCamera': 'true'});
    }
    if (platform == 'ipad') {
      // The product page frames the tablet shot landscape (1024x768); the
      // Simulator boots portrait.
      await s.l3('l3_set_orientation', {'orientation': 'landscape'});
      await s.waitMs(1500);
    }

    // ── theme + english, then the 5 scenes ───────────────────────────────
    // Theme defaults to light; override with TOXEE_SHOT_THEME=dark to capture
    // the dark palette (e.g. to verify the dark theme covers every surface).
    final shotTheme = (Platform.environment['TOXEE_SHOT_THEME'] ?? 'light')
        .toLowerCase()
        .trim();
    await s.l3('l3_set_setting', {
      'key': 'themeMode',
      'value': shotTheme == 'dark' ? 'dark' : 'light',
    });
    await s.l3('l3_set_setting', {'key': 'languageCode', 'value': 'en'});
    if (isDesktop) await s.setWindowBounds(_windowW, _windowH);
    await s.waitMs(900);

    // 1 · C2C chat.
    await s.openChat(userId: personaAlex.pubKey);
    await s.waitMs(1700);
    await shooter.shot('c2c');
    await s.popToRoot();

    // 2 · group chat.
    if (groupId != null) {
      await s.openChat(groupId: groupId);
      await s.waitMs(1700);
      await shooter.shot('group_chat');
      await s.popToRoot();
    } else {
      shooter.warn('group not created — group_chat scene skipped');
    }

    // 3 · new application (Contacts → New Contacts list).
    await s.l3('l3_force_home_root', {'tab': 'contacts'});
    await s.waitMs(1000);
    await s.tapKey('contact_new_contacts_tab', retries: 4, optional: true);
    await s.waitMs(1300);
    await shooter.shot('new_application');
    await s.popToRoot();

    // 4 · self profile (Tox ID + QR) — over the Chats root, not over whatever
    // the previous scene left (a profile dialog on top of the pending friend
    // request read as two scenes in one frame).
    await s.l3('l3_force_home_root', {'tab': 'chats'});
    await s.waitMs(700);
    await s.l3('l3_open_self_profile', const {});
    await s.waitMs(1600);
    await shooter.shot('self_profile');
    await s.popToRoot();

    // 5 · settings.
    await s.l3('l3_force_home_root', {'tab': 'settings'});
    await s.waitMs(1300);
    await shooter.shot('settings');

    return shooter.summarize() ? 0 : 1;
  } on _DriveError catch (e) {
    stderr.writeln('[capture:$platform] ERROR: ${e.message}');
    return 1;
  } finally {
    await s?.dispose();
  }
}

// ───────────────────────────── instance driver ──────────────────────────

class _Shot implements SeedClient {
  _Shot({
    required this.vm,
    required this.isolateId,
    required this.wsUri,
    required this.platform,
    required this.kind,
    required this.isDesktop,
    required this.pid,
  });

  VmService vm;
  String isolateId;
  final String wsUri;
  @override
  final String platform;
  final _DeviceKind kind;
  final bool isDesktop;
  final int? pid;
  @override
  String toxId = '';

  static Future<_Shot> connect({
    required String wsUri,
    required String platform,
    required _DeviceKind kind,
    required bool isDesktop,
    required int? pid,
  }) async {
    // The mobile VM service (reached via adb forward on Android, or a freshly
    // simctl-launched app on iOS) can refuse the very first WebSocket upgrade
    // while it is still coming up — retry the initial connect a few times.
    VmService? vm;
    for (var attempt = 1; vm == null; attempt++) {
      try {
        vm = await vmServiceConnectUri(wsUri);
      } catch (e) {
        if (attempt >= 15) {
          throw _DriveError('[$platform] cannot connect $wsUri: $e');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    final isolateId = await _findMainIsolate(vm);
    final s = _Shot(
      vm: vm,
      isolateId: isolateId,
      wsUri: wsUri,
      platform: platform,
      kind: kind,
      isDesktop: isDesktop,
      pid: pid,
    );
    for (final ext in [
      'ext.mcp.toolkit.l3_dump_state',
      'ext.mcp.toolkit.l3_register_account',
      'ext.flutter.flutter_skill.tap',
      'ext.flutter.flutter_skill.screenshot',
    ]) {
      await s.waitForExtension(ext, timeoutSecs: 120);
    }
    return s;
  }

  Future<void> dispose() => vm.dispose();

  bool _isDisposedError(Object e) {
    final str = '$e';
    return str.contains('disposed') ||
        str.contains('WebSocket') ||
        str.contains('Connection closed');
  }

  Future<void> _reconnect() async {
    print('[$platform] VM service dropped — reconnecting $wsUri');
    try {
      await vm.dispose();
    } catch (_) {}
    vm = await vmServiceConnectUri(wsUri);
    isolateId = await _findMainIsolate(vm);
  }

  Future<void> waitForExtension(String ext, {required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final iso = await vm.getIsolate(isolateId);
      if ((iso.extensionRPCs ?? const <String>[]).contains(ext)) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _DriveError('[$platform] extension $ext never registered');
  }

  Future<Map<String, dynamic>> _raw(
    String method,
    Map<String, Object?> args,
  ) async {
    final stringArgs = <String, String>{
      for (final e in args.entries) e.key: e.value.toString(),
    };
    Future<Map<String, dynamic>> once() async {
      final resp = await vm.callServiceExtension(
        method,
        isolateId: isolateId,
        args: stringArgs,
      );
      return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
    }

    try {
      return await once();
    } catch (e) {
      if (!_isDisposedError(e)) rethrow;
      await _reconnect();
      return once();
    }
  }

  @override
  Future<Map<String, dynamic>> l3(
    String tool,
    Map<String, Object?> args, {
    bool lenient = false,
  }) async {
    final r = await _raw('ext.mcp.toolkit.$tool', args);
    if (r['ok'] != true && !lenient) {
      throw _DriveError('[$platform] $tool failed: $r');
    }
    return r;
  }

  Future<Map<String, dynamic>> skill(
    String method, [
    Map<String, Object?> args = const {},
  ]) => _raw('ext.flutter.flutter_skill.$method', args);

  @override
  Future<Map<String, dynamic>> dumpState({String? userId, String? convId}) =>
      _raw('ext.mcp.toolkit.l3_dump_state', {
        if (userId != null) 'userId': userId,
        if (convId != null) 'conversationId': convId,
      });

  // ── lifecycle ──

  Future<void> ensureReady() async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      toxId = before['currentAccountToxId']?.toString() ?? '';
      if (toxId.isNotEmpty) {
        print('[$platform] session already ready (${_short(toxId)})');
        return;
      }
    }
    print('[$platform] registering hero "$heroNickname"');
    await l3('l3_register_account', {
      'nickname': heroNickname,
      'statusMessage': heroStatusMessage,
    });
    await _retry(
      () async {
        if ((await dumpState())['sessionReady'] != true) {
          throw _DriveError('sessionReady still false');
        }
      },
      attempts: 90,
      intervalMs: 1000,
      label: '[$platform] wait sessionReady',
    );
    final st = await dumpState();
    toxId = st['currentAccountToxId']?.toString() ?? '';
    if (toxId.isEmpty) throw _DriveError('[$platform] no toxId after ready');
    print('[$platform] ready as $heroNickname (${_short(toxId)})');
  }

  /// Wait until HomePage finished `_initAfterSessionReady` — proven by the
  /// home-shell snapshot (`homeShellTab`) appearing in the dump, which is
  /// registered in the SAME block as the l3_open_chat / l3_force_home_root /
  /// l3_open_self_profile / l3_pop_to_root invokers. On the auto-login reuse
  /// path the session is "ready" before the UI mounts, so without this gate the
  /// scene walk races the invoker registration ("invoker not registered") and
  /// the conversation list isn't loaded yet (group re-created as a duplicate).
  Future<void> waitForHomeReady({int secs = 40}) async {
    for (var i = 0; i < secs; i++) {
      if ((await dumpState())['homeShellTab'] != null) {
        print('[$platform] HomePage shell ready');
        return;
      }
      await waitMs(1000);
    }
    print('[$platform] WARN HomePage shell not ready after ${secs}s');
  }

  /// Best-effort DHT-connected wait so the profile shows online — never fails
  /// the run (seeded data is local and needs no connection).
  Future<void> waitConnectedBestEffort({int secs = 20}) async {
    for (var i = 0; i < secs; i++) {
      if ((await dumpState())['isConnected'] == true) {
        print('[$platform] DHT connected');
        return;
      }
      await waitMs(1000);
    }
    print('[$platform] not DHT-connected after ${secs}s — proceeding anyway');
  }

  // ── navigation ──

  /// Open a C2C or group chat, layout-aware. Wide: the l3_open_chat deep-link
  /// binds the master-detail right pane. Narrow: l3_open_chat is desktop-only
  /// (it returns false on a bottom-nav layout), so flip to the Chats tab and
  /// tap the real conversation row, which pushes the UIKit message route.
  Future<void> openChat({String? userId, String? groupId}) async {
    if (kind == _DeviceKind.wide) {
      await l3(
        'l3_open_chat',
        userId != null ? {'userId': userId} : {'groupId': groupId},
      );
      return;
    }
    await l3('l3_force_home_root', {'tab': 'chats'});
    await waitMs(800);
    final convId = userId != null ? 'c2c_$userId' : 'group_$groupId';
    await tapKey('conversation_list_item:$convId', retries: 6);
  }

  Future<void> popToRoot() async {
    await l3('l3_pop_to_root', const {}, lenient: true);
    await waitMs(500);
  }

  // ── UI driving ──

  /// Bring the macOS window frontmost (flutter_skill capture needs a
  /// non-occluded window there). No-op on mobile (the app owns the sim screen).
  Future<void> foreground() async {
    if (!isDesktop || pid == null) return;
    final r = await Process.run('osascript', [
      '-e',
      'tell application "System Events" to set frontmost of '
          '(first process whose unix id is $pid) to true',
    ]);
    if (r.exitCode != 0) {
      print('[$platform] WARN foreground failed: ${r.stderr}');
    }
    await waitMs(450);
  }

  Future<void> tapKey(
    String key, {
    int retries = 6,
    bool optional = false,
  }) async {
    for (var i = 0; i < retries; i++) {
      final r = await skill('tap', {'key': key});
      if (r['success'] == true) {
        await waitMs(350);
        return;
      }
      await waitMs(700);
    }
    if (optional) {
      print('[$platform] tapKey "$key" not found (optional) — continuing');
      return;
    }
    throw _DriveError('[$platform] tapKey "$key" failed after $retries tries');
  }

  /// Size the macOS window and VERIFY it took: macOS clamps a window to the
  /// screen's visible frame, and a silently clamped window changes the shot's
  /// aspect ratio (the product page declares it).
  Future<void> setWindowBounds(int w, int h) async {
    await l3('l3_window_state', {
      'state': 'bounds',
      'width': '$w',
      'height': '$h',
    });
    await waitMs(400);
    final r = await l3('l3_window_state', {'state': 'query_bounds'});
    final gotW = (r['width'] as num?)?.round();
    final gotH = (r['height'] as num?)?.round();
    if (gotW != w || gotH != h) {
      throw _DriveError(
        '[$platform] window is ${gotW}x$gotH, asked ${w}x$h — pick a size '
        'that fits this display so the desktop shots keep the declared aspect',
      );
    }
  }

  @override
  Future<void> waitMs(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));
}

// ───────────────────────────── helpers ──────────────────────────────────

class _DriveError implements Exception {
  _DriveError(this.message);
  final String message;
  @override
  String toString() => message;
}

String _short(String id) => id.length > 16 ? '${id.substring(0, 16)}…' : id;

Future<String> _findMainIsolate(VmService vm) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final v = await vm.getVM();
    final isolates = v.isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty) {
      for (final iso in isolates) {
        if ((iso.name ?? '').toLowerCase().contains('main')) return iso.id!;
      }
      return isolates.first.id!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw _DriveError('no isolate appeared on VM');
}

Future<T> _retry<T>(
  Future<T> Function() body, {
  required int attempts,
  required int intervalMs,
  required String label,
}) async {
  Object? last;
  for (var i = 0; i < attempts; i++) {
    try {
      return await body();
    } catch (e) {
      last = e;
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
  }
  throw _DriveError('retry exhausted ($label): $last');
}
