// Minimal media-spike driver on top of an already-paired Fixture C session.
//
// Usage:
//   dart run tool/mcp_test/drive_fixture_c_call.dart <ws_uri_A> <ws_uri_B>
//     [--video] [--reject] [--toggle-video]
//
// Assumes:
//   - A and B are already launched
//   - A and B are already mutual friends
//   - both are on HomePage with the L3 test surface enabled

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

// The Dart VM DISCARDS whatever `main` returns — the process exit code comes
// only from the global `exitCode` or from `exit()`. This file used to declare
// `Future<int> main(...)`, so every `return 64` / `return 1` below was a no-op
// and the process always exited 0. `run_fixture_c_call.sh` runs under
// `set -euo pipefail`, so a 0 exit made it unconditionally print "PASS" —
// S65/S66/S67/S68/S74/S75/S76 could never fail. Route through `exitCode`, the
// same idiom the other 26 drive_fixture_c_*.dart drivers use.
Future<void> main(List<String> args) async {
  exitCode = await _main(args);
}

Future<int> _main(List<String> args) async {
  if (args.length < 2) {
    print(
      'usage: drive_fixture_c_call.dart <ws_uri_A> <ws_uri_B> '
      '[--video] [--reject] [--toggle-video]',
    );
    return 64;
  }
  final wsA = args[0];
  final wsB = args[1];
  final video = args.contains('--video');
  final reject = args.contains('--reject');
  final toggleVideo = args.contains('--toggle-video');
  final a = await _CallDriver.connect('A', wsA);
  final b = await _CallDriver.connect('B', wsB);
  try {
    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    print(
      '[fixture-c-call] toxA=${toxA.substring(0, 16)}... toxB=${toxB.substring(0, 16)}...',
    );

    await a.startCall(toxB, video: video);
    await b.waitForCallState('ringing', timeoutSecs: 30);
    print('[fixture-c-call] B sees incoming ringing');

    if (reject) {
      await b.callAction('reject');
      await a.waitForCallStateAny({'ended', 'idle'}, timeoutSecs: 20);
      await b.waitForCallStateAny({'ended', 'idle'}, timeoutSecs: 20);
      print('[fixture-c-call] reject completed');
      return 0;
    }

    await b.callAction('accept');
    await a.waitForCallState('inCall', timeoutSecs: 30);
    await b.waitForCallState('inCall', timeoutSecs: 30);
    print('[fixture-c-call] both sides reached inCall');

    await a.callAction('mute');
    await a.waitForMuted(true, timeoutSecs: 10);
    print('[fixture-c-call] A mute toggled on');

    if (toggleVideo) {
      await a.callAction('video');
      await a.waitForVideoEnabled(!video, timeoutSecs: 15);
      print('[fixture-c-call] A video toggle applied');
    }

    await a.callAction('hangup');
    await a.waitForCallStateAny({'ended', 'idle'}, timeoutSecs: 20);
    await b.waitForCallStateAny({'ended', 'idle'}, timeoutSecs: 20);
    print('[fixture-c-call] hangup completed');

    return 0;
  } catch (e) {
    print('[fixture-c-call] ERROR: $e');
    return 1;
  } finally {
    await a.dispose();
    await b.dispose();
  }
}

class _CallDriver {
  _CallDriver(this.name, this.vm, this.isolateId);

  final String name;
  final VmService vm;
  final String isolateId;

  static Future<_CallDriver> connect(String name, String wsUri) async {
    final vm = await vmServiceConnectUri(wsUri);
    final isolateId = await _findMainIsolate(vm);
    final d = _CallDriver(name, vm, isolateId);
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
    throw Exception('[$name] extension $name not registered');
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

  Future<Map<String, dynamic>> dumpState() async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_dump_state',
      const <String, Object?>{},
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
  }

  Future<String> currentToxId() async {
    final s = await dumpState();
    return (s['currentAccountToxId']?.toString() ?? '').trim();
  }

  Future<void> startCall(String userId, {required bool video}) async {
    final resp = await _call('ext.mcp.toolkit.l3_start_call', <String, Object?>{
      'userId': userId,
      'video': video,
    });
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw Exception('[$name] l3_start_call failed: ${json['error']}');
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
      throw Exception(
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
    throw Exception('[$name] call state not in $states within ${timeoutSecs}s');
  }

  Future<void> waitForMuted(bool expected, {required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final s = await dumpState();
      final call = (s['call'] as Map?)?.cast<String, dynamic>();
      if (call?['isMuted'] == expected) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw Exception('[$name] mute state did not become $expected');
  }

  Future<void> waitForVideoEnabled(
    bool expected, {
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final s = await dumpState();
      final call = (s['call'] as Map?)?.cast<String, dynamic>();
      if (call?['isVideoEnabled'] == expected) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw Exception('[$name] video state did not become $expected');
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
  throw Exception('no isolate appeared');
}
