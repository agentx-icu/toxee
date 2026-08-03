// S26 driver: ACCEPTing a pending friend request creates a friendship.
//
// LIVE-VALIDATION OWED: this is a two-process gate (A + B in separate VMs) and
// has NOT yet been run on a live paired DHT. The fresh-pair friend-request
// delivery can be flaky; the assertions below distinguish "B's application
// never reached A" from "accepted but B not in friends[]" so a live failure
// points at the right stage.
//
// Contract under test (S26):
//   When the recipient ACCEPTS an inbound friend request, the requester enters
//   friends[] AND the corresponding pending application item is removed from
//   friendApplications[] (the accept consumes the pending request and creates a
//   friendship).
//
// This is the S46/S54/S27 sibling with the ACCEPT action: S46 set
// autoAcceptFriends=true and asserted auto-accept; S54 asserted a pending
// application; S27 declined the pending application and asserted it was gone
// with no friendship; S26 accepts the pending application and asserts the
// requester is now a friend with the pending application gone.
//
// This is the FRESH base: two fresh registrations (NOT a restored pair) — the
// accept needs a NEW pending application. Per the handoff notes
// (tool/mcp_test/REAL_UI_TWO_PROCESS.md) the B -> A direction is the
// stable one, so SENDER/REQUESTER=B, RECIPIENT/ACCEPTER=A.
//
// Sequence:
//   1. Connect A, B. ensureReady(nickname: 'echo_live_test') both. Wait for
//      both to report isConnected.
//   2. Read both currentAccountToxId values. Fail if either is empty.
//   3. REQUESTER=B: send l3_add_friend_request to toxA. Treat "already sent" as
//      benign.
//   4. Poll A's friendApplications[] until it contains a pending entry for toxB
//      (by Tox public key). If it never arrives, fail loudly at the
//      "application never reached A" stage (delivery flake, not an accept bug).
//   5. ACCEPTER=A: l3_accept_friend_request to toxB.
//   6. PRIMARY assert (A1): A.friends[] CONTAINS toxB — the accept created a
//      friendship. A brief race is tolerated by re-checking once after 2s.
//   7. SECONDARY assert (A2): A.friendApplications[] no longer contains a
//      pending entry for toxB — the accept consumed the pending application.

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  exitCode = await _main(args);
}

Future<int> _main(List<String> args) async {
  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--fixture-manifest') {
      // Accepted for arg-shape parity with the sibling drivers, but ignored:
      // S26 requires a FRESH pending application, so a restored pair is never
      // used here.
      if (i + 1 >= args.length) {
        print('usage: --fixture-manifest requires a path');
        return 64;
      }
      i++;
    } else {
      positional.add(arg);
    }
  }
  if (positional.length < 2) {
    print(
      'usage: drive_fixture_c_accept.dart <ws_uri_A> <ws_uri_B> '
      '[--fixture-manifest path] (manifest ignored — S26 needs a fresh pair)',
    );
    return 64;
  }
  final a = await _PairDriver.connect('A', positional[0]);
  final b = await _PairDriver.connect('B', positional[1]);
  try {
    await a.ensureReady(nickname: 'echo_live_test');
    await b.ensureReady(nickname: 'echo_live_test');
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids after registration: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-accept] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    final nonce = 'S26-accept-${DateTime.now().microsecondsSinceEpoch}';

    // Freshness (codex P2): prove the application is created THIS run. A stale
    // pending app or an existing friendship from a reused pair would let the
    // gate pass without exercising a fresh B->A request + accept.
    if (await a.hasFriendApplication(toxB)) {
      throw _DriveError(
        'setup: A already has a pending application from B BEFORE B sends — '
        'not a fresh pair (stale state); S26 needs a fresh request',
      );
    }
    if (await a.hasFriend(toxB)) {
      throw _DriveError(
        'setup: A and B are already friends BEFORE the request — not a fresh '
        'pair (stale state)',
      );
    }

    // REQUESTER=B: friend request to A.
    await b.addFriendRequest(toxA, message: nonce);

    // The application must land on A before A can accept it. A miss here is a
    // fresh-pair delivery flake, NOT an accept bug — fail at this exact stage.
    await a.waitForFriendApplication(toxB, timeoutSecs: 120);
    print('[fixture-c-accept] B application reached A');

    // ACCEPTER=A: accept the pending application.
    await a.acceptFriendRequest(toxB);

    // PRIMARY assert (A1): the accept created a friendship. Tolerate a brief
    // race by re-checking once after 2s.
    var isFriend = await a.hasFriend(toxB);
    if (!isFriend) {
      await Future<void>.delayed(const Duration(seconds: 2));
      isFriend = await a.hasFriend(toxB);
    }
    if (!isFriend) {
      throw _DriveError(
        'PRIMARY assertion failed: B not present in A friends[] after accept — '
        'the application reached A and was accepted, but no friendship was '
        'created (accept bug, not a delivery flake)',
      );
    }
    print('[fixture-c-accept] PASS A1 friendship-created');

    // SECONDARY assert (A2): the accept consumed the pending application.
    if (await a.hasFriendApplication(toxB)) {
      throw _DriveError(
        'SECONDARY assertion failed: B application still present in A '
        'friendApplications[] after accept — the accept must consume the '
        'pending application',
      );
    }
    print('[fixture-c-accept] PASS A2 application-removed');

    print('[fixture-c-accept] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-accept] ERROR: ${e.message}');
    return 1;
  } finally {
    await a.dispose();
    await b.dispose();
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
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_register_account',
      timeoutSecs: 60,
    );
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_add_friend_request',
      timeoutSecs: 60,
    );
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_accept_friend_request',
      timeoutSecs: 60,
    );
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

  Future<Map<String, dynamic>> dumpState({String? userId}) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_dump_state',
      userId == null
          ? const <String, Object?>{}
          : <String, Object?>{'userId': userId},
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
  }

  Future<String> currentToxId() async {
    final s = await dumpState();
    return (s['currentAccountToxId']?.toString() ?? '').trim();
  }

  Future<void> ensureReady({required String nickname}) async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      print('[fixture-c-accept][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-accept][$name] registering via l3_register_account',
    );
    final resp = await _call(
      'ext.mcp.toolkit.l3_register_account',
      <String, Object?>{'nickname': nickname},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError('[$name] l3_register_account failed: ${json['error']}');
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

  Future<void> addFriendRequest(String toxId, {required String message}) async {
    print(
      '[fixture-c-accept][$name] sending friend request '
      '${toxId.substring(0, 16)}...',
    );
    final resp = await _call(
      'ext.mcp.toolkit.l3_add_friend_request',
      <String, Object?>{'userId': toxId, 'message': message},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      final resultInfo = json['resultInfo']?.toString().toLowerCase() ?? '';
      if (resultInfo.contains('already sent')) {
        // reviewer C2: the freshness pre-flight already ruled out a STALE
        // pending app, so "already sent" here is just a fast-delivery race
        // (B's local state flagged the request sent before A's dump ingested
        // it). Treat it as benign — the request IS in flight; fall through to
        // waitForFriendApplication (this is the documented S26 intent, unlike
        // the decline gate which requires a brand-new request).
        print('[$name] friend request already in flight (benign); proceeding');
        return;
      }
      throw _DriveError(
        '[$name] l3_add_friend_request failed: ${json['error']}',
      );
    }
  }

  Future<void> acceptFriendRequest(String userId) async {
    print(
      '[fixture-c-accept][$name] accepting friend request '
      '${userId.substring(0, 16)}...',
    );
    final resp = await _call(
      'ext.mcp.toolkit.l3_accept_friend_request',
      <String, Object?>{'userId': userId},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_accept_friend_request failed: ${json['error']}',
      );
    }
  }

  /// Polls friendApplications[] for a pending entry from [fromUserId] (matched
  /// by Tox public key). Returns on success; throws on timeout. A timeout here
  /// means the fresh-pair request never reached this side (delivery flake).
  Future<void> waitForFriendApplication(
    String fromUserId, {
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      if (await hasFriendApplication(fromUserId)) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError(
      '[$name] friend application from ${fromUserId.substring(0, 16)} never '
      'arrived before timeout (fresh-pair delivery flake, not an accept bug)',
    );
  }

  /// Require a dump_state LIST field to be genuinely present (codex P2). A
  /// missing field or its `${field}Error` companion means the read-model is
  /// broken / the session isn't ready — that must NOT be read as an empty list,
  /// else a presence/absence assertion (now a friend / application removed)
  /// false-passes on a broken dump. Throws so the failure is loud.
  List<dynamic> _requireList(Map<String, dynamic> state, String field) {
    if (state.containsKey('${field}Error')) {
      throw _DriveError(
        '[$name] l3_dump_state.$field errored: ${state['${field}Error']} '
        '— cannot trust presence/absence',
      );
    }
    final v = state[field];
    if (v is! List) {
      throw _DriveError(
        '[$name] l3_dump_state.$field missing/not-a-list (session not ready or '
        'read-model broken) — cannot assert presence/absence',
      );
    }
    return v;
  }

  Future<bool> hasFriendApplication(String userId) async {
    final wantPk = _toxPublicKey(userId);
    final state = await dumpState();
    final apps = _requireList(state, 'friendApplications');
    for (final app in apps) {
      if (app is! Map) continue;
      final appUserId = app['userId']?.toString() ?? '';
      if (_toxPublicKey(appUserId) == wantPk) {
        return true;
      }
    }
    return false;
  }

  Future<bool> hasFriend(String userId) async {
    final wantPk = _toxPublicKey(userId);
    final state = await dumpState();
    final friends = _requireList(state, 'friends');
    for (final friend in friends) {
      if (friend is! Map) continue;
      final friendId = friend['userId']?.toString() ?? '';
      if (_toxPublicKey(friendId) == wantPk) {
        return true;
      }
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
}

String _toxPublicKey(String userId) {
  final normalized = userId.trim().toUpperCase();
  return normalized.length >= 64 ? normalized.substring(0, 64) : normalized;
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
