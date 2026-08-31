// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// mobile_mention_multi_select_inserts — the MULTI-SELECT leg of the mobile
// @-mention picker: TWO ticked member rows + confirm must insert BOTH
// "@<label> " tokens. A group needs 2 NON-SELF members, and NGC membership is
// a LIVE peer list (no seam can fake a member), so this is the harness's
// first THREE-INSTANCE case: a C instance (a macOS Toxee process, launched
// in-case via launch_toxee_instance.sh) registers a throwaway account and
// is invited over a SEEDED friend link into the PRIVATE group (public
// join-by-chat-id never converged under TCP-only — see the create-group
// comment). Own campaign by design — the working agreement's "conflicting
// state contract" exception (the extra instance and its teardown must not
// leak into chained sweeps). Result state: FRIENDS (the seeded A<->B
// friendship persists; the A<->C one is deleted in teardown).

const _mmCase = 'mobile_mention_multi_select_inserts';

// Host-side relay port: fixtureCTcpRelayHostPort. A-guest listener: 3389.
const _mmGuestRelayPort = 3389;

/// Ditto a private app copy (same-bundle double-launch breaks VM-service
/// attach — launch_fixture_c_pair.sh precedent) and launch instance [name].
/// Returns the connected Inst + the copy path (the caller deletes it — the
/// A/B bundle GC in _multi_instance_lib.sh cannot reclaim C copies), or null
/// after printing the failed step. A post-launch failure (metadata parse /
/// VM attach) best-effort stops the live process before returning null, so
/// no orphan survives the null return (codex High).
Future<({Inst inst, String copy})?> _mmLaunchExtraMacInstance(
  String name, {
  required bool tcpOnly,
}) async {
  final bundle =
      Platform.environment['TOXEE_APP_BUNDLE'] ??
      'build/macos/Build/Products/Debug/Toxee.app';
  final copy =
      'tool/mcp_test/.multi_instance_runtime/copies/'
      'Toxee$name-${DateTime.now().millisecondsSinceEpoch}.app';
  await Process.run('mkdir', ['-p', File(copy).parent.path]);
  final d = await Process.run('/usr/bin/ditto', [bundle, copy]);
  if (d.exitCode != 0) {
    print('[pair] $_mmCase: ditto $name copy failed: ${d.stderr}');
    await Process.run('rm', ['-rf', copy]);
    return null;
  }
  final env = <String, String>{
    'TOXEE_APP_BUNDLE': copy,
    if (tcpOnly) 'TOX_FORCE_TCP_ONLY': '1',
  };
  final launch = await Process.run(
    'tool/mcp_test/launch_toxee_instance.sh',
    [name],
    environment: env,
    includeParentEnvironment: true,
  );
  if (launch.exitCode != 0) {
    print(
      '[pair] $_mmCase: launch_toxee_instance.sh $name failed '
      '(exit ${launch.exitCode}): ${launch.stderr}',
    );
    await Process.run('rm', ['-rf', copy]);
    return null;
  }
  Inst? inst;
  try {
    final meta = await _p1rReadInstanceRuntime(name);
    inst = Inst(name, meta.ws, meta.pid);
    await inst.connect();
    return (inst: inst, copy: copy);
  } catch (e) {
    print('[pair] $_mmCase: $name attach failed after launch: $e');
    // Pass the known pid so an ORPHANED diagnostic can name it (codex).
    await _mmStopExtraInstance(name: name, copy: copy, inst: inst);
    return null;
  }
}

/// Stop instance [name] + delete its bundle [copy]. The stop script exits
/// nonzero when the process SURVIVES — retry once, then print an ORPHANED
/// diagnostic (never throw: this runs in cleanup paths).
Future<void> _mmStopExtraInstance({
  required String name,
  String? copy,
  Inst? inst,
}) async {
  try {
    await inst?.dispose();
  } catch (_) {}
  // Guarded end-to-end: this helper runs on cleanup paths where a throw
  // would skip the caller's later contract checks (codex High).
  try {
    for (var attempt = 1; attempt <= 2; attempt++) {
      final r = await Process.run('tool/mcp_test/stop_toxee_instance.sh', [
        name,
      ]);
      if (r.exitCode == 0) break;
      print(
        '[pair] $_mmCase: stop $name attempt $attempt exit ${r.exitCode}: '
        '${r.stderr.toString().trim()}'
        '${attempt == 2 ? ' — may be ORPHANED (pid=${inst?.pid})' : ''}',
      );
    }
    if (copy != null) {
      await Process.run('rm', ['-rf', copy]);
    }
  } on Object catch (e) {
    print('[pair] $_mmCase: stop $name cleanup threw: $e (pid=${inst?.pid})');
  }
}

/// Best-effort re-issue + verification of the host->A relay forward
/// (host:fixtureCTcpRelayHostPort -> A-guest:3389, exactly the launcher's
/// mapping). DIAGNOSTIC, not a gate: even with the local star down the
/// trio can converge over PUBLIC relays — slower, but the friend-online
/// gates absorb it. (Historic: host 3389 was silently hijacked by an
/// unrelated legacy qemu VM, which is why the host port moved to 33390.)
Future<bool> _mmEnsureAndroidRelayForward(Inst a) async {
  if (!a.isAndroid) return true;
  final serial = await _androidDeviceIdFor(a);
  if (serial == null || serial.isEmpty) {
    print('[pair] $_mmCase: no adb serial for A');
    return false;
  }
  // Mirror the launcher EXACTLY: host:hostPort -> A-guest:3389 (re-binding
  // with a wrong guest target would silently break the mapping — codex High).
  await Process.run('adb', [
    '-s',
    serial,
    'forward',
    'tcp:${fixtureCTcpRelayHostPort()}',
    'tcp:$_mmGuestRelayPort',
  ]);
  final list = await Process.run('adb', ['-s', serial, 'forward', '--list']);
  final ok = list.stdout.toString().contains(
    'tcp:${fixtureCTcpRelayHostPort()}',
  );
  print('[pair] $_mmCase: relay forward on $serial verified=$ok');
  return ok;
}

/// Wait until [inst] sees the friend behind [peerTox] ONLINE — a group
/// invite travels the LIVE friend link (fresh norequest seeds must connect).
Future<bool> _mmWaitFriendOnline(Inst inst, String peerTox) async {
  final pk = _pubkey(peerTox);
  // 120s: a COLD TCP-relay link can exceed 60s (proof45 expired at 60s).
  for (var i = 0; i < 120; i++) {
    final friends = ((await inst.dumpState())['friends'] as List?) ?? const [];
    final online = friends.any(
      (f) =>
          f is Map &&
          _pubkey(f['userId']?.toString() ?? '') == pk &&
          f['online'] == true,
    );
    if (online) return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

/// The case. Exit codes: 0 PASS, 1 FAIL, 75 SKIP (desktop composer — the
/// inline panel has its own multi-mention surface; this pins the MOBILE
/// picker's `selectMembers` accumulation + joined "@l1 @l2 " insertion,
/// tencent_cloud_chat_message_input_mobile.dart mentionTextList.join()).
Future<int> runMentionMultiCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  const confirmKey = 'mention_member_list_confirm_button';
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  var aMarked = false;
  var bMarked = false;
  ({Inst inst, String copy})? c;
  var gid = '';
  var toxAT = '';
  var toxCT = '';
  final name = 'RUI-MSEL-${DateTime.now().millisecondsSinceEpoch % 1000000}';
  try {
    aMarked = await a.markAccountTest();
    bMarked = await b.markAccountTest();
    if (!aMarked || !bMarked) {
      print('[pair] $_mmCase: markAccountTest failed (a=$aMarked b=$bMarked)');
      return 1;
    }
    // PRIVATE group + friend-link INVITES (the machinery every proven group
    // case uses). Public join-by-chat-id was tried first and is a dead end
    // here: NGC public discovery under TCP-only runs onion-over-relay and
    // takes minutes cold (proof39/41 first attempts never converged in 90s).
    final created = await a.l3('l3_create_group', {
      'name': name,
      'type': 'private',
    });
    gid = (created['groupId'] ?? '').toString();
    if (created['ok'] != true || gid.isEmpty) {
      print('[pair] $_mmCase: create failed $created');
      return 1;
    }
    // Gate BEFORE paying for the C instance: the case needs A's MOBILE
    // composer (desktop resolves mentions through the inline panel).
    await openGroupChat(a, groupId: gid, groupName: name, viaL3Seam: true);
    final composer = await _kg4ComposerKind(a);
    if (composer == _Kg4Composer.desktop) {
      print(
        '[pair] $_mmCase: SKIP — desktop composer (inline mention panel; '
        'the mobile picker under test never mounts on this shell)',
      );
      return 75;
    }
    if (composer != _Kg4Composer.mobile) {
      print('[pair] $_mmCase: composer state $composer — chat surface missing');
      return 1;
    }
    // Deterministic A<->B friendship: mutual tox_friend_add_norequest over
    // the wired mesh (the `_seedMutualFriendship` class of seeding — a REAL
    // P2P friendship; the add-friend UI has its own dedicated cases).
    final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
    final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
    toxAT = toxA;
    await wireFullMeshBootstrap([
      BootstrapTarget('A', a.vm, a.iso, host: a.bootstrapHost),
      BootstrapTarget('B', b.vm, b.iso, host: b.bootstrapHost),
    ], tcpRelayFallbackPort: _pairTcpRelayFallbackPort(a, b));
    await a.l3('l3_seed_friend', {'userId': _pubkey(toxB), 'nickname': nickB});
    await b.l3('l3_seed_friend', {'userId': _pubkey(toxA), 'nickname': nickA});
    if (!await _retryBool(
          () => areFriends(a, toxB),
          label: 'A has B (msel seed)',
          attempts: 20,
        ) ||
        !await _retryBool(
          () => areFriends(b, toxA),
          label: 'B has A (msel seed)',
          attempts: 20,
        )) {
      print('[pair] $_mmCase: mutual A<->B seed did not take');
      return 1;
    }
    if (!await _mmWaitFriendOnline(a, toxB) ||
        !await _mmWaitFriendOnline(b, toxA)) {
      print('[pair] $_mmCase: A<->B friend link never came ONLINE');
      return 1;
    }
    await _setAutoAcceptGroupInvites(b, true);
    final beforeB = await _groupConversationCandidates(b);
    await _inviteToGroup(a, gid, toxB);
    final gidB = await _waitForJoinedGroup(
      b,
      name,
      before: beforeB,
      timeoutSecs: 45,
    );
    if (gidB == null) {
      print('[pair] $_mmCase: B never auto-joined the invited group');
      return 1;
    }
    // Mobile pairs (Android emulators AND iOS Simulators) run TCP-only; C
    // must too, or its UDP DHT never meets their relay star (codex parity).
    c = await _mmLaunchExtraMacInstance('C', tcpOnly: a.isAndroid || a.isIos);
    if (c == null) return 1;
    final ci = c.inst;
    await ci.waitExt('ext.mcp.toolkit.l3_register_account');
    final reg = await ci.l3('l3_register_account', {'nickname': 'RealUiCarol'});
    if (reg['ok'] != true) {
      print('[pair] $_mmCase: C register failed $reg');
      return 1;
    }
    // Wire C toward the pair: full-mesh DHT bootstrap (UDP platforms) plus
    // best-effort local relay accelerators. Neither is fatal — the proven
    // transport for the TCP-only mobile stars is the public relay set (see
    // _mmEnsureAndroidRelayForward doc).
    await _mmEnsureAndroidRelayForward(a);
    for (final ext in fixtureCBootstrapExtensions) {
      await ci.waitExt(ext);
    }
    await wireFullMeshBootstrap([
      BootstrapTarget('A', a.vm, a.iso, host: a.bootstrapHost),
      BootstrapTarget('B', b.vm, b.iso, host: b.bootstrapHost),
      BootstrapTarget('C', ci.vm, ci.iso),
    ], tcpRelayFallbackPort: _pairTcpRelayFallbackPort(a, b));
    // Android only: iOS pairs run their OWN fixed listener ports; give C an
    // iOS hint only when an iOS trio campaign is proven (don't guess ports).
    if (a.isAndroid) {
      final dht = await a.l3('l3_dht_info');
      final dhtId = (dht['dhtId'] ?? '').toString();
      if (dhtId.isNotEmpty) {
        final r = await ci.l3('l3_add_bootstrap_node', {
          'host': '127.0.0.1',
          'port': '${fixtureCTcpRelayHostPort()}',
          'pubkey': dhtId,
        });
        print('[pair] $_mmCase: C -> A local relay hint ok=${r['ok']}');
      } else {
        print('[pair] $_mmCase: A reported no dhtId ($dht) — public relays');
      }
    }
    // C joins the same way: seeded friendship with A, then a friend-link
    // invite (C's registered account is already seed-marked).
    final toxC = (reg['toxId'] ?? '').toString();
    toxCT = toxC;
    if (toxC.isEmpty) {
      print('[pair] $_mmCase: C register returned no toxId: $reg');
      return 1;
    }
    await ci.l3('l3_seed_friend', {'userId': _pubkey(toxA), 'nickname': nickA});
    await a.l3('l3_seed_friend', {
      'userId': _pubkey(toxC),
      'nickname': 'RealUiCarol',
    });
    if (!await _retryBool(
      () => areFriends(a, toxC),
      label: 'A has C (msel seed)',
      attempts: 20,
    )) {
      print('[pair] $_mmCase: A<->C seed did not take');
      return 1;
    }
    if (!await _mmWaitFriendOnline(a, toxC) ||
        !await _mmWaitFriendOnline(ci, toxA)) {
      print('[pair] $_mmCase: A<->C friend link never came ONLINE');
      return 1;
    }
    await _setAutoAcceptGroupInvites(ci, true);
    final beforeC = await _groupConversationCandidates(ci);
    await _inviteToGroup(a, gid, toxC);
    final gidC = await _waitForJoinedGroup(
      ci,
      name,
      before: beforeC,
      timeoutSecs: 45,
    );
    if (gidC == null) {
      print('[pair] $_mmCase: C never auto-joined the invited group');
      return 1;
    }
    // Membership is a LIVE peer list — wait for BOTH non-self members.
    var members = <({String userId, String nickName})>[];
    for (var i = 0; i < 60 && members.length < 2; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final r = await a.l3('l3_group_member_list', {'groupId': gid});
      members = [
        for (final m in (r['members'] as List?) ?? const [])
          if (m is Map && m['isSelf'] != true)
            if ((m['userID']?.toString() ?? '').isNotEmpty)
              (
                userId: m['userID'].toString(),
                nickName: m['nickName']?.toString() ?? '',
              ),
      ];
    }
    if (members.length < 2) {
      print(
        '[pair] $_mmCase: group never reached 2 non-self members '
        '(got ${members.length})',
      );
      return 1;
    }
    await openGroupChat(a, groupId: gid, groupName: name, viaL3Seam: true);
    final nonce = DateTime.now().microsecondsSinceEpoch % 1000000;
    final prefix = 'MSEL$nonce';
    if (!await _kg4SetComposerText(a, prefix)) return 1;
    if (!await _kg4SetComposerText(a, '$prefix@')) return 1;
    if (!await a.waitKeyCenter(confirmKey, timeoutSecs: 12)) {
      print('[pair] $_mmCase: the picker route never mounted');
      await _kg3PopToRoot(a);
      return 1;
    }
    // Tick BOTH rows — selectMembers accumulates; only @All auto-submits.
    for (final m in members.take(2)) {
      final rowKey = 'mention_member:${m.userId}';
      if (!await a.waitKeyCenter(rowKey, timeoutSecs: 10) ||
          !await a.tapKeyCenter(rowKey, timeoutSecs: 6)) {
        print('[pair] $_mmCase: member row $rowKey unavailable');
        await a.tapKeyCenter('mention_member_list_back_button', timeoutSecs: 6);
        await _kg3PopToRoot(a);
        return 1;
      }
    }
    if (!await a.tapKeyCenter(confirmKey, timeoutSecs: 8)) {
      print('[pair] $_mmCase: confirm could not be tapped');
      await _kg3PopToRoot(a);
      return 1;
    }
    await _kg4WaitKeyCenterGone(a, confirmKey, timeoutSecs: 10);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await a.l3('l3_composer_send', const {});
    final sent = await _kg4WaitGroupTextStartingWith(a, gid, prefix);
    await a.shot('/tmp/ui_msel_${a.name}.png');
    if (sent == null) {
      print('[pair] $_mmCase: the composer message never reached the group');
      return 1;
    }
    // BOTH tokens, atomically appended: "<prefix>@<l1> @<l2> " exactly, and
    // each ticked member's label (nickName ?? userID) present.
    final shape = RegExp(
      '^${RegExp.escape(prefix)}(@\\S+ ){2}\$',
    ).hasMatch(sent);
    final labels = [
      for (final m in members.take(2))
        m.nickName.isNotEmpty ? m.nickName : m.userId,
    ];
    final both = labels.every((l) => sent.contains('@$l '));
    print(
      '[pair] $_mmCase: sent="$sent" shape=$shape labels=$labels both=$both',
    );
    return shape && both ? 0 : 1;
  } finally {
    try {
      // C leaves its groups BEFORE it is stopped (codex: stopping first
      // strands the membership; C's app-support dir is reused across runs).
      var contractDirty = false;
      if (c != null) {
        // C leaves its groups AND both ends of the throwaway A<->C
        // friendship are deleted BEFORE C stops. Each op has its OWN guard +
        // checked result (codex: one try let an early throw skip the rest and
        // {ok:false} passed silently); a failed A-side delete breaks the
        // declared FRIENDS result contract -> the case is FAILED below.
        try {
          await _leaveAllGroups(c.inst);
        } on Object catch (e) {
          print('[pair] $_mmCase: C leave-groups failed: $e');
        }
        if (toxAT.isNotEmpty) {
          try {
            final r = await c.inst.l3('l3_delete_friend', {
              'userId': _pubkey(toxAT),
            });
            if (r['ok'] != true) print('[pair] $_mmCase: C-side delete: $r');
          } on Object catch (e) {
            print('[pair] $_mmCase: C-side delete threw: $e');
          }
        }
        if (toxCT.isNotEmpty) {
          try {
            final r = await a.l3('l3_delete_friend', {
              'userId': _pubkey(toxCT),
            });
            if (r['ok'] != true) {
              contractDirty = true;
              print('[pair] $_mmCase: A-side delete of C FAILED: $r');
            }
          } on Object catch (e) {
            contractDirty = true;
            print('[pair] $_mmCase: A-side delete of C threw: $e');
          }
        }
        await _mmStopExtraInstance(name: 'C', copy: c.copy, inst: c.inst);
      }
      if (gid.isNotEmpty) {
        try {
          await _leaveAllGroups(b);
          await _leaveAllGroups(a);
        } on Object catch (e) {
          print('[pair] $_mmCase: leave-groups failed: $e');
        }
      }
      // Guarded independently: a nav throw must not swallow the contract
      // check below (codex round-5).
      try {
        await returnToChatsHome(a, rounds: 3);
      } on Object catch (e) {
        print('[pair] $_mmCase: return-home cleanup: $e');
      }
      if (contractDirty) {
        // Surfaces as a FAILURE even off a passing body: A still lists the
        // stopped C — the registered FRIENDS result would be a lie.
        throw DriveError(
          '[$_mmCase] A<->C friendship not fully cleaned — result-state '
          'contract broken',
        );
      }
    } on DriveError {
      rethrow;
    } on Object catch (e) {
      print('[pair] $_mmCase cleanup: $e');
    } finally {
      // Unmark in independent finallys — cleanup throws must not leak the
      // broad L3 marker; a failed unmark is LOUD (codex Medium).
      if (aMarked) {
        try {
          if (!await a.unmarkAccountTest()) {
            print('[pair] $_mmCase: A unmark FAILED — marker may leak');
          }
        } on Object catch (e) {
          print('[pair] $_mmCase: A unmark THREW ($e) — marker may leak');
        }
      }
      if (bMarked) {
        try {
          if (!await b.unmarkAccountTest()) {
            print('[pair] $_mmCase: B unmark FAILED — marker may leak');
          }
        } on Object catch (e) {
          print('[pair] $_mmCase: B unmark THREW ($e) — marker may leak');
        }
      }
    }
  }
}
