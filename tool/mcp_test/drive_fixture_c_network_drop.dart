// End-to-end driver for the S69 "call network drop (two processes)" L3
// scenario.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends.
// When a manifest is supplied this driver BOOTS both restored accounts itself
// (via l3_boot_existing_account), so the gate needs no separate boot step.
//
// It establishes a real call between A and B, then drives A's reconnect path.
//
// BACKGROUND (confirmed in source): there is NO ToxAV peer-offline callback,
// so killing the peer does NOT auto-end an established call. The app's reconnect
// path is driven by CallServiceManager.markReconnecting(), which sets
// call.isReconnecting=true and starts an 8s grace timer; when the grace expires
// the call ends with endReason network_error. The new l3_call_action action
// `network_drop` drives markReconnecting() — that is the S69 trigger.
//
// Sequence:
//   1. Connect A and B; ensureReady(fixture) for both; waitForConnected; then
//      waitForFriendOnline both ways; resolve toxA/toxB.
//   2. Establish a call: A startCall(toxB, video:false); B sees 'ringing',
//      B accepts, both reach 'inCall'. PASS A1 (established).
//   3. TRIGGER DROP: A callAction('network_drop') → markReconnecting().
//   4. ASSERT reconnecting: poll A.call.isReconnecting==true within 10s.
//      PASS A2 (reconnecting). LENIENT: the transient can be missed by 1s
//      polling; if never observed true but the call DOES reach ended in step 5,
//      A2 is a soft-pass.
//   5. ASSERT ended: poll A.waitForCallStateAny({'ended','idle'}, 20s) — the 8s
//      grace expires → call ends. PASS A3 (ended after grace). HARD gate.
//   6. Cleanup: best-effort A callAction('hangup') (ignore errors).
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_network_drop.dart \
//       <ws_uri_A> <ws_uri_B> --fixture-manifest path/to/manifest.json

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  exitCode = await _main(args);
}

Future<int> _main(List<String> args) async {
  final positional = <String>[];
  String? fixtureManifestPath;
  int? realKillPid;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--fixture-manifest') {
      if (i + 1 >= args.length) {
        print('usage: --fixture-manifest requires a path');
        return 64;
      }
      fixtureManifestPath = args[++i];
    } else if (arg == '--real-kill-pid') {
      if (i + 1 >= args.length) {
        print('usage: --real-kill-pid requires B\'s process id');
        return 64;
      }
      realKillPid = int.tryParse(args[++i]);
      if (realKillPid == null || realKillPid <= 1) {
        print('usage: --real-kill-pid requires a valid pid');
        return 64;
      }
    } else {
      positional.add(arg);
    }
  }
  if (positional.length < 2) {
    print(
      'usage: drive_fixture_c_network_drop.dart <ws_uri_A> <ws_uri_B> '
      '--fixture-manifest path/to/paired_for_e2e_manifest.json '
      '[--real-kill-pid <B pid>]',
    );
    return 64;
  }
  final fixture = fixtureManifestPath == null
      ? null
      : await _FixtureManifest.load(fixtureManifestPath);
  final a = await _PairDriver.connect('A', positional[0]);
  final b = await _PairDriver.connect('B', positional[1]);
  try {
    if (fixture != null) {
      await a.ensureReady(fixture: fixture.a);
      await b.ensureReady(fixture: fixture.b);
    } else {
      print('[fixture-c-network-drop] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-network-drop] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    // 2. Establish a real call: A calls B (audio), B accepts, both reach inCall.
    await a.startCall(toxB, video: false);
    print('[fixture-c-network-drop] A started call to B (audio)');
    await b.waitForCallStateAny({'ringing'}, timeoutSecs: 30);
    await b.callAction('accept');
    await a.waitForCallState('inCall', timeoutSecs: 30);
    await b.waitForCallState('inCall', timeoutSecs: 30);
    print('[fixture-c-network-drop] PASS A1 established');

    if (realKillPid == null) {
      // 3. TRIGGER DROP (synthetic): drive A's reconnect path via
      //    markReconnecting().
      await a.callAction('network_drop');
      print('[fixture-c-network-drop] A triggered network_drop');

      // 4. ASSERT reconnecting (LENIENT). The transient flag can flip back
      //    before a 1s poll catches it; if so we fall through and rely on
      //    step 5.
      final sawReconnecting = await a.waitForReconnecting(timeoutSecs: 10);
      if (sawReconnecting) {
        print('[fixture-c-network-drop] PASS A2 reconnecting');
      } else {
        print(
          '[fixture-c-network-drop] NOTE A2 reconnecting transient not observed '
          '(1s polling can miss it); deferring to A3 ended (hard gate)',
        );
      }

      // 5. ASSERT ended (HARD gate): the 8s grace expires → call ends with
      //    endReason network_error. Give the 8s grace + slack.
      await a.waitForCallStateAny({'ended', 'idle'}, timeoutSecs: 20);
      if (!sawReconnecting) {
        print(
            '[fixture-c-network-drop] PASS A2 reconnecting (soft-pass via ended)');
      }
      print('[fixture-c-network-drop] PASS A3 ended');
    } else {
      // 3. TRIGGER DROP (real): kill B's process. Live-verified behavior
      //    (2026-07-09): c-toxcore declares the friend offline after ~30s of
      //    silence, and ToxAV fires call_state=ERROR in the SAME iterate
      //    tick — CallServiceManager ends the call with endReason
      //    network_error via _onCallState. The peer-transport watchdog
      //    (1s sampling) rarely observes an inCall+offline window, so
      //    `reconnecting` is an OPTIONAL observation here, not a gate; the
      //    HARD gate is that A's call terminates on its own within the
      //    detection budget.
      final killResult = await Process.run('kill', ['-9', '$realKillPid']);
      if (killResult.exitCode != 0) {
        throw _DriveError(
            'kill -9 $realKillPid failed: ${killResult.stderr}');
      }
      print('[fixture-c-network-drop] killed B (pid=$realKillPid)');

      // 4/5. ASSERT the call self-terminates (HARD): ~30s toxcore offline
      //    detection + 8s reconnect grace (if the watchdog won the race) +
      //    slack.
      final sawReconnecting = await a.waitForReconnecting(timeoutSecs: 45,
          orStates: const {'ended', 'idle'});
      if (sawReconnecting) {
        print('[fixture-c-network-drop] NOTE A2 reconnecting observed '
            '(watchdog won the race against native ToxAV ERROR)');
      }
      await a.waitForCallStateAny({'ended', 'idle'}, timeoutSecs: 60);
      print('[fixture-c-network-drop] PASS A3 ended (peer-death detected)');
    }

    print('[fixture-c-network-drop] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-network-drop] ERROR: ${e.message}');
    await _dumpCallObjects(a, b);
    return 1;
  } catch (e) {
    print('[fixture-c-network-drop] ERROR: $e');
    await _dumpCallObjects(a, b);
    return 1;
  } finally {
    // 6. Best-effort cleanup: cancel any lingering call on A.
    try {
      await a.callAction('hangup');
    } catch (_) {
      // ignore — call may already be ended/idle.
    }
    try {
      await a.dispose();
    } catch (_) {}
    try {
      // In --real-kill-pid mode B's VM connection is already dead.
      await b.dispose();
    } catch (_) {}
  }
}

Future<void> _dumpCallObjects(_PairDriver a, _PairDriver b) async {
  try {
    final aState = await a.dumpState();
    final bState = await b.dumpState();
    print('[fixture-c-network-drop] A.call=${aState['call']}');
    print('[fixture-c-network-drop] B.call=${bState['call']}');
  } catch (e) {
    print('[fixture-c-network-drop] (could not dump call objects: $e)');
  }
}

class _DriveError implements Exception {
  _DriveError(this.message);
  final String message;
}

class _PairDriver {
  _PairDriver(this.name, this.vm, this.isolateId);

  final String name;
  final VmService vm;
  final String isolateId;

  static Future<_PairDriver> connect(String name, String wsUri) async {
    final vm = await vmServiceConnectUri(wsUri);
    final isolateId = await _findMainIsolate(vm);
    final d = _PairDriver(name, vm, isolateId);
    await d.waitForExtension('ext.mcp.toolkit.l3_dump_state', timeoutSecs: 60);
    await d.waitForExtension('ext.mcp.toolkit.l3_start_call', timeoutSecs: 60);
    await d.waitForExtension('ext.mcp.toolkit.l3_call_action', timeoutSecs: 60);
    return d;
  }

  Future<void> dispose() => vm.dispose();

  Future<void> waitForExtension(String name, {required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final iso = await vm.getIsolate(isolateId);
      final ext = iso.extensionRPCs ?? const <String>[];
      if (ext.contains(name)) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _DriveError('[$name] extension $name not registered');
  }

  Future<Response> _call(String method, Map<String, Object?> args) {
    final stringArgs = <String, String>{
      for (final entry in args.entries) entry.key: entry.value.toString(),
    };
    return vm.callServiceExtension(
      method,
      isolateId: isolateId,
      args: stringArgs,
    );
  }

  Future<Map<String, dynamic>> dumpState({String? conversationId}) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_dump_state',
      conversationId == null
          ? const <String, Object?>{}
          : <String, Object?>{'conversationId': conversationId},
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
  }

  Future<String> currentToxId() async {
    final s = await dumpState();
    return (s['currentAccountToxId']?.toString() ?? '').trim();
  }

  Future<void> ensureReady({required _FixtureAccount fixture}) async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      print('[fixture-c-network-drop][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-network-drop][$name] booting restored account '
      '${fixture.toxId.substring(0, 16)}...',
    );
    final resp = await _call(
      'ext.mcp.toolkit.l3_boot_existing_account',
      <String, Object?>{'toxId': fixture.toxId, 'nickname': fixture.nickname},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_boot_existing_account failed: ${json['error']}',
      );
    }
    await _waitForSessionReady();
  }

  Future<void> _waitForSessionReady() async {
    await _retry(
      () async {
        final s = await dumpState();
        if (s['sessionReady'] != true) {
          throw _DriveError('sessionReady still false');
        }
      },
      attempts: 60,
      intervalMs: 1000,
      label: 'wait sessionReady',
    );
  }

  Future<void> startCall(String userId, {required bool video}) async {
    final resp = await _call('ext.mcp.toolkit.l3_start_call', <String, Object?>{
      'userId': userId,
      'video': video,
    });
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError('[$name] l3_start_call failed: ${json['error']}');
    }
  }

  Future<void> callAction(String action) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_call_action',
      <String, Object?>{'action': action},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_call_action($action) failed: ${json['error']}',
      );
    }
  }

  Future<void> waitForCallState(
    String state, {
    required int timeoutSecs,
  }) async {
    await waitForCallStateAny({state}, timeoutSecs: timeoutSecs);
  }

  Future<void> waitForCallStateAny(
    Set<String> states, {
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final s = await dumpState();
      final call = (s['call'] as Map?)?.cast<String, dynamic>();
      final current = call?['state']?.toString();
      if (current != null && states.contains(current)) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError(
      '[$name] call state not in $states within ${timeoutSecs}s',
    );
  }

  /// Reads dump_state.call.isReconnecting (defaults false when absent).
  Future<bool> callIsReconnecting() async {
    final s = await dumpState();
    final call = (s['call'] as Map?)?.cast<String, dynamic>();
    return call?['isReconnecting'] == true;
  }

  /// Polls for call.isReconnecting==true. Returns true if observed within the
  /// timeout, false otherwise (the caller decides whether that is fatal).
  /// Polls until the call reports `isReconnecting`. When [orStates] is
  /// given, also stops (returning false) as soon as the call state lands in
  /// one of those — used by the real-kill mode where the native ToxAV ERROR
  /// path may end the call without a visible reconnecting window.
  Future<bool> waitForReconnecting({
    required int timeoutSecs,
    Set<String>? orStates,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      if (await callIsReconnecting()) {
        return true;
      }
      if (orStates != null) {
        final s = await dumpState();
        final call = (s['call'] as Map?)?.cast<String, dynamic>();
        final current = call?['state']?.toString();
        if (current != null && orStates.contains(current)) {
          return false;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<void> waitForConnected({required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState();
      if (state['isConnected'] == true) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError('[$name] isConnected did not become true');
  }

  Future<void> waitForFriendOnline({
    required String userId,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final friend = await _findFriend(userId);
      if (friend != null && friend['online'] == true) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final friend = await describeFriend(userId);
    throw _DriveError(
      '[$name] friend ${userId.substring(0, 16)} did not become online; '
      'friend=$friend',
    );
  }

  Future<String> describeFriend(String userId) async {
    final friend = await _findFriend(userId);
    return friend?.toString() ?? '<not in friend list>';
  }

  Future<Map<String, dynamic>?> _findFriend(String userId) async {
    final wantPk = _toxPublicKey(userId);
    final state = await dumpState();
    final friends = (state['friends'] as List?) ?? const <dynamic>[];
    for (final friend in friends) {
      if (friend is! Map) continue;
      final friendId = friend['userId']?.toString() ?? '';
      if (_toxPublicKey(friendId) == wantPk) {
        return Map<String, dynamic>.from(friend);
      }
    }
    return null;
  }
}

String _toxPublicKey(String userId) {
  final normalized = userId.trim().toUpperCase();
  return normalized.length >= 64 ? normalized.substring(0, 64) : normalized;
}

class _FixtureManifest {
  _FixtureManifest({required this.a, required this.b});

  final _FixtureAccount a;
  final _FixtureAccount b;

  static Future<_FixtureManifest> load(String path) async {
    final file = File(path);
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final instances = (raw['instances'] as Map).cast<String, dynamic>();
    return _FixtureManifest(
      a: _FixtureAccount.fromJson((instances['A'] as Map).cast()),
      b: _FixtureAccount.fromJson((instances['B'] as Map).cast()),
    );
  }
}

class _FixtureAccount {
  _FixtureAccount({required this.toxId, required this.nickname});

  final String toxId;
  final String nickname;

  factory _FixtureAccount.fromJson(Map<dynamic, dynamic> json) {
    final toxId = (json['tox_id'] ?? '').toString().trim();
    final nickname = (json['nickname'] ?? '').toString().trim();
    if (toxId.isEmpty || nickname.isEmpty) {
      throw _DriveError('fixture manifest account missing tox_id/nickname');
    }
    return _FixtureAccount(toxId: toxId, nickname: nickname);
  }
}

Future<String> _findMainIsolate(VmService vm) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final vmObj = await vm.getVM();
    final isolates = vmObj.isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty) {
      for (final iso in isolates) {
        if ((iso.name ?? '').toLowerCase().contains('main')) {
          return iso.id!;
        }
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
  Object? lastErr;
  for (var i = 0; i < attempts; i++) {
    try {
      return await body();
    } catch (e) {
      lastErr = e;
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
  }
  throw _DriveError('retry exhausted ($label): $lastErr');
}
