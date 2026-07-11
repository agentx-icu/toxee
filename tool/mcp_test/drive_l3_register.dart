// Register a fresh L3 TEST account in a running debug toxee instance, so the
// L3 mutating tools (create_group, set_setting, ...) are allowed to run.
//
// l3_register_account records the new account in Prefs.getL3SeedToxIds, which
// `_activeAccountIsTest()` (lib/ui/testing/l3_debug_tools.dart) treats as a
// test account by construction. This is the per-instance setup the self-
// creating L3 suites (e.g. --suite=group) need before run_l3_scenarios.dart.
// With --seed-echo it ALSO seeds the echo peer as a friend + conversation so
// the echo-conversation-bound hermetic scenarios pass without the on-disk
// echo_seeded fixture (only L3-self-id, bound to the exact fixture account
// toxId, and the requiresEchoPeer live-round-trip scenarios remain uncovered).
//
// Usage:
//   dart run tool/mcp_test/drive_l3_register.dart <ws_uri> [nickname] [--seed-echo]
//
//   --seed-echo   after registering, seed the canonical echo peer as a friend
//                 (l3_seed_friend) and inject a c2c bubble (l3_inject_c2c_text)
//                 so the echo-conversation-bound hermetic scenarios
//                 (session-settings, recvopt-mute, friend-remark, and the
//                 send/pin/reply c2c gates) have the conversation they assert
//                 on — without needing the on-disk echo_seeded fixture. Does
//                 NOT make the requiresEchoPeer (live round-trip) scenarios
//                 pass; those still need --echo + a running echo peer.
//
// Exits 0 once the new account is registered AND sessionReady (and, with
// --seed-echo, the echo conversation is present); non-zero on failure.

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

// Canonical echo peer the L3 scenarios target (every scenario's `target`).
const _echoPeerToxId =
    '3116CBE0974181B6EC4B32555413655B42C7456A93C6AF98A23E95127B587244';

Future<int> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final seedEcho = args.contains('--seed-echo');
  if (positional.isEmpty) {
    print('usage: drive_l3_register.dart <ws_uri> [nickname] [--seed-echo]');
    return 64;
  }
  final wsUri = positional[0];
  final nickname = positional.length > 1 ? positional[1] : 'echo_live_test';

  final vm = await vmServiceConnectUri(wsUri);
  final isolateId = await _findMainIsolate(vm);

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, Object?> a,
  ) async {
    final resp = await vm.callServiceExtension(
      method,
      isolateId: isolateId,
      args: {for (final e in a.entries) e.key: e.value.toString()},
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
  }

  // Finish setup once the account is registered + sessionReady:
  //  (1) best-effort wait for the Tox DHT connection so L3-session-state
  //      (asserts isConnected=true) passes;
  //  (2) with --seed-echo, seed the canonical echo peer as a friend + a c2c
  //      bubble so the echo-conversation-bound hermetic scenarios have the
  //      conversation they assert on.
  Future<int> finishSetup() async {
    final connectDeadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(connectDeadline)) {
      final s = await call('ext.mcp.toolkit.l3_dump_state', const {});
      if (s['isConnected'] == true) {
        print('[l3-register] isConnected=true');
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!seedEcho) return 0;
    print('[l3-register] seeding echo peer (friend + c2c bubble)');
    final f = await call('ext.mcp.toolkit.l3_seed_friend', {
      'userId': _echoPeerToxId,
    });
    if (f['ok'] != true) {
      print('[l3-register] l3_seed_friend failed: ${f['error'] ?? f}');
      return 1;
    }
    final inj = await call('ext.mcp.toolkit.l3_inject_c2c_text', {
      'userId': _echoPeerToxId,
      'text': 'l3 seed bubble',
    });
    if (inj['ok'] != true) {
      print('[l3-register] l3_inject_c2c_text failed: ${inj['error'] ?? inj}');
      return 1;
    }
    final pkPrefix = _echoPeerToxId.substring(0, 16);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final s = await call('ext.mcp.toolkit.l3_dump_state', const {});
      if ((s['conversations']?.toString() ?? '').contains(pkPrefix)) {
        print('[l3-register] OK echo conversation present');
        return 0;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    print('[l3-register] timed out waiting for echo conversation');
    return 1;
  }

  try {
    await _waitForExtension(
      vm,
      isolateId,
      'ext.mcp.toolkit.l3_register_account',
      timeoutSecs: 60,
    );

    // Already on a usable account? (idempotent — don't stack registrations.)
    // A fresh launch on a previously-seeded state dir AUTO-LOGS-IN: an eager
    // single probe reported sessionReady=false mid-boot, we then registered
    // and collided with the existing nickname. Give auto-login a settle
    // window before deciding the state really has no account.
    Map<String, dynamic> pre = const {};
    final preDeadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(preDeadline)) {
      pre = await call('ext.mcp.toolkit.l3_dump_state', const {});
      if (pre['sessionReady'] == true) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (pre['sessionReady'] == true &&
        (pre['currentAccountToxId']?.toString().isNotEmpty ?? false)) {
      print(
        '[l3-register] session already ready '
        '(toxId=${pre['currentAccountToxId']}); skipping register',
      );
      return await finishSetup();
    }

    print('[l3-register] registering test account nickname="$nickname"');
    final reg = await call('ext.mcp.toolkit.l3_register_account', {
      'nickname': nickname,
    });
    if (reg['ok'] != true) {
      final detail = '${reg['detail'] ?? ''}';
      print(
        '[l3-register] l3_register_account failed: ${reg['error'] ?? reg}'
        '${detail.isNotEmpty ? ' — $detail' : ''}',
      );
      if (detail.contains('already exists')) {
        // Racing an in-flight auto-login of the account we would have
        // created: fall through to the sessionReady wait instead of failing.
        print('[l3-register] account exists — waiting for auto-login instead');
        final d2 = DateTime.now().add(const Duration(seconds: 90));
        while (DateTime.now().isBefore(d2)) {
          final s = await call('ext.mcp.toolkit.l3_dump_state', const {});
          if (s['sessionReady'] == true) {
            print(
              '[l3-register] OK sessionReady (existing account '
              '${s['currentAccountToxId']})',
            );
            return await finishSetup();
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        print('[l3-register] timed out waiting for existing-account login');
      }
      return 1;
    }

    // Poll for sessionReady so run_l3_scenarios.dart's session preflight and
    // the create_group calls have a live, logged-in account to act on.
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      final s = await call('ext.mcp.toolkit.l3_dump_state', const {});
      if (s['sessionReady'] == true) {
        print(
          '[l3-register] OK sessionReady; toxId=${s['currentAccountToxId']}',
        );
        return await finishSetup();
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    print('[l3-register] timed out waiting for sessionReady');
    return 1;
  } catch (e) {
    print('[l3-register] ERROR: $e');
    return 1;
  } finally {
    await vm.dispose();
  }
}

Future<void> _waitForExtension(
  VmService vm,
  String isolateId,
  String name, {
  required int timeoutSecs,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final iso = await vm.getIsolate(isolateId);
    if ((iso.extensionRPCs ?? const <String>[]).contains(name)) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw Exception('extension $name not registered within ${timeoutSecs}s');
}

Future<String> _findMainIsolate(VmService vm) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final isolates = (await vm.getVM()).isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty) {
      for (final iso in isolates) {
        if ((iso.name ?? '').toLowerCase().contains('main')) return iso.id!;
      }
      return isolates.first.id!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw Exception('no isolate appeared');
}
