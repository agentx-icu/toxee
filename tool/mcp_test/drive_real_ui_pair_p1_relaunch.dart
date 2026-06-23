// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

const _p1rCases = {
  'relaunch_history_autologin',
  'offline_pending_relaunch',
  'call_from_profile_tiles',
  'group_join_by_id_real_ui',
};

bool _isP1RelaunchCaseScenario(String scenario) => _p1rCases.contains(scenario);

Future<int> runP1RelaunchCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario, {
  required bool bootRestored,
}) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for $scenario: A=$toxA B=$toxB');
  }
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    print('[pair] $scenario establishing friendship first');
    final friended =
        await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB);
    if (!friended) return 1;
  } else if (!bootRestored) {
    await _p1rSeedConversationRow(a, toxB);
    await _p1rSeedConversationRow(b, toxA);
  }

  final ok = switch (scenario) {
    'relaunch_history_autologin' => await _p1rHistoryAutologin(
      a,
      b,
      toxA,
      toxB,
      nickA,
    ),
    'offline_pending_relaunch' => await _p1rOfflinePendingRelaunch(
      a,
      b,
      toxA,
      toxB,
      nickB,
    ),
    'call_from_profile_tiles' => await _p1rCallFromProfileTiles(
      a,
      b,
      toxA,
      toxB,
    ),
    'group_join_by_id_real_ui' => await _p1rGroupJoinByIdRealUi(a, b),
    _ => throw ArgumentError('unsupported P1 relaunch case: $scenario'),
  };
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runP1RelaunchSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  var toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  var toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for sweep_p1_relaunch: A=$toxA B=$toxB');
  }
  final friended =
      await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB);
  if (!friended) return 1;

  var passed = 0;
  var failed = 0;
  Future<void> tally(String name, Future<bool> Function() run) async {
    try {
      final ok = await run();
      if (ok) {
        passed++;
      } else {
        failed++;
      }
      print('[pair] sweep_p1_relaunch ${ok ? 'PASS' : 'FAIL'}: $name');
    } on Object catch (e, st) {
      failed++;
      print('[pair] sweep_p1_relaunch EXCEPTION in $name: $e');
      print(st);
    }
  }

  await tally('relaunch_history_autologin', () async {
    toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? toxA;
    toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? toxB;
    return _p1rHistoryAutologin(a, b, toxA, toxB, nickA);
  });
  await tally('offline_pending_relaunch', () async {
    toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? toxA;
    toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? toxB;
    return _p1rOfflinePendingRelaunch(a, b, toxA, toxB, nickB);
  });
  await tally('call_from_profile_tiles', () async {
    toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? toxA;
    toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? toxB;
    return _p1rCallFromProfileTiles(a, b, toxA, toxB);
  });
  await tally('group_join_by_id_real_ui', () => _p1rGroupJoinByIdRealUi(a, b));

  print('[pair] sweep_p1_relaunch summary: passed=$passed failed=$failed');
  return failed == 0 ? 0 : 1;
}

Future<void> _p1rSeedConversationRow(Inst inst, String peerTox) async {
  if (await _waitConversationListed(
    inst,
    _c2cConvId(peerTox),
    timeoutSecs: 2,
  )) {
    return;
  }
  final text = 'RUIP1RROW-${DateTime.now().microsecondsSinceEpoch}';
  await _sendAndIdentify(inst, peerTox, text);
}

Future<bool> _p1rHistoryAutologin(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
  String nickA,
) async {
  final text = 'RUIP1RELAUNCH-HIST-${DateTime.now().microsecondsSinceEpoch}';
  final msgId = await _sendAndIdentify(a, toxB, text);
  if (msgId == null) {
    print('[pair] relaunch_history_autologin: send/identify failed');
    return false;
  }
  final bReceived = await _waitC2cMessageText(
    b,
    toxA,
    text,
    isSelf: false,
    timeoutSecs: 45,
  );
  if (!bReceived) {
    print('[pair] relaunch_history_autologin: B never received seed message');
    return false;
  }

  await _p1rRelaunchInstance(a, expectedToxId: toxA, nick: nickA);
  final state = await a.dumpState();
  final autologged =
      state['sessionReady'] == true &&
      state['currentAccountToxId']?.toString() == toxA;
  await ensureHome(a, nickA);
  final rowListed = await _waitConversationListed(
    a,
    _c2cConvId(toxB),
    timeoutSecs: 20,
  );
  final chatOpen = await _ensureChatOpen(a, toxB);
  final historyPresent = await _waitC2cMessageText(
    a,
    toxB,
    text,
    isSelf: true,
    timeoutSecs: 20,
  );
  final rowRendered = await a.waitKey(
    'message_list_item:$msgId',
    timeoutSecs: 8,
  );
  print(
    '[pair] relaunch_history_autologin: autologged=$autologged '
    'rowListed=$rowListed chatOpen=$chatOpen historyPresent=$historyPresent '
    'rowRendered=$rowRendered',
  );
  return autologged && rowListed && chatOpen && historyPresent && rowRendered;
}

Future<bool> _p1rOfflinePendingRelaunch(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
  String nickB,
) async {
  final convId = _c2cConvId(toxB);
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] offline_pending_relaunch: A chat did not open');
    return false;
  }
  await _p1rStopInstanceOnly(b);
  var bRelaunched = false;
  try {
    final text = 'RUIP1OFFLINE-${DateTime.now().microsecondsSinceEpoch}';
    final sentLocally = await sendComposerMessage(a, text);
    if (!sentLocally) {
      print('[pair] offline_pending_relaunch: local offline send failed');
      return false;
    }
    final pendingId = await _p1rWaitMessagePending(
      a,
      convId,
      text,
      pending: true,
      timeoutSecs: 20,
    );
    // Resolve the pending bubble + spinner via the element-tree walk
    // (waitKeyCenter): they are rows inside the message ListView, which
    // flutter_skill's whole-tree waitKey can't always see (same constraint the
    // group member-list / search-history rows hit). Observed: pendingId present
    // in the dump but waitKey(message_list_item) / waitKey(message_send_status)
    // both false.
    final pendingRow =
        pendingId != null &&
        await a.waitKeyCenter('message_list_item:$pendingId', timeoutSecs: 6);
    final pendingSpinner =
        pendingId != null &&
        await a.waitKeyCenter(
          'message_send_status:$pendingId:sending',
          timeoutSecs: 6,
        );
    print(
      '[pair] offline_pending_relaunch: pendingId=$pendingId '
      'pendingRow=$pendingRow pendingSpinner=$pendingSpinner',
    );
    if (pendingId == null || !pendingRow || !pendingSpinner) {
      return false;
    }

    await _p1rLaunchStoppedInstance(b, expectedToxId: toxB, nick: nickB);
    bRelaunched = true;
    final delivered =
        await _p1rWaitMessagePending(
          a,
          convId,
          text,
          pending: false,
          timeoutSecs: 90,
        ) !=
        null;
    final bReceived = await _waitC2cMessageText(
      b,
      toxA,
      text,
      isSelf: false,
      timeoutSecs: 90,
    );
    print(
      '[pair] offline_pending_relaunch: delivered=$delivered '
      'bReceived=$bReceived',
    );
    return delivered && bReceived;
  } finally {
    // Recover B whenever it isn't confirmed back up — covers BOTH the
    // never-attempted path AND the case where the in-body relaunch THREW
    // (launchAttempted=true but bRelaunched=false), which the old
    // `!bRelaunched && !launchAttempted` guard skipped, leaving B down for the
    // next sweep case (codex-review catch). `_p1rLaunchStoppedInstance` no-ops
    // when B is already up.
    if (!bRelaunched) {
      try {
        await _p1rLaunchStoppedInstance(b, expectedToxId: toxB, nick: nickB);
      } on Object catch (e) {
        print(
          '[pair] WARN offline_pending_relaunch recovery relaunch failed: $e',
        );
      }
    }
  }
}

Future<String?> _p1rWaitMessagePending(
  Inst inst,
  String conversationId,
  String text, {
  required bool pending,
  int timeoutSecs = 30,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final state = await inst.dumpState(conversationId: conversationId);
    final messages = (state['messages'] as List?) ?? const [];
    for (final m in messages) {
      if (m is! Map) continue;
      if (m['isSelf'] != true || m['text']?.toString() != text) continue;
      if (m['isPending'] == pending) {
        final id = m['msgID']?.toString() ?? m['id']?.toString() ?? '';
        return id.isEmpty ? null : id;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return null;
}

Future<bool> _p1rCallFromProfileTiles(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  final voice = await _p1rProfileCallRoundtrip(
    caller: a,
    callee: b,
    callerPeerTox: toxB,
    calleePeerTox: toxA,
    tileKey: 'friend_profile_voice_call_tile',
    expectedMode: 'audio',
  );
  if (!voice) return false;
  final video = await _p1rProfileCallRoundtrip(
    caller: a,
    callee: b,
    callerPeerTox: toxB,
    calleePeerTox: toxA,
    tileKey: 'friend_profile_video_call_tile',
    expectedMode: 'video',
  );
  return video;
}

Future<bool> _p1rProfileCallRoundtrip({
  required Inst caller,
  required Inst callee,
  required String callerPeerTox,
  required String calleePeerTox,
  required String tileKey,
  required String expectedMode,
}) async {
  if (!await _ensureBothIdle(caller, callee)) {
    print('[pair] $tileKey: prior call did not settle idle');
    return false;
  }
  if (!await _ensureChatOpen(caller, callerPeerTox)) {
    print('[pair] $tileKey: caller chat did not open');
    return false;
  }
  await caller.foreground();
  if (!await caller.tapKeyCenter('message_header_profile_avatar')) {
    print('[pair] $tileKey: header avatar not tappable');
    return false;
  }
  if (!await caller.waitKey(
    'friend_profile_send_message_tile',
    timeoutSecs: 8,
  )) {
    print('[pair] $tileKey: friend profile did not open');
    return false;
  }
  if (!await caller.tapKeyCenter(tileKey, timeoutSecs: 8)) {
    print('[pair] $tileKey: profile call tile not tappable');
    return false;
  }
  final ringing = await _waitCallStateAnyForegrounded(callee, {
    'ringing',
    'incoming',
  }, timeoutSecs: 20);
  if (!ringing) {
    print('[pair] $tileKey: callee never rang');
    await _ensureBothIdle(caller, callee);
    return false;
  }
  await callee.foreground();
  await callee.tapKey('call_accept_button');
  final inCallCaller = await _waitCallStateAny(caller, {'inCall'});
  final inCallCallee = await _waitCallStateAny(callee, {'inCall'});
  final modeOk = expectedMode == 'audio'
      ? await _p1rWaitCallModeNonVideo(caller)
      : await _waitCallField(caller, 'mode', 'video', timeoutSecs: 8);
  await caller.foreground();
  await caller.tapKeyCenter('call_hangup_button', timeoutSecs: 8);
  final endedCaller = await _waitCallStateAny(caller, {'ended', 'idle'});
  final endedCallee = await _waitCallStateAny(callee, {'ended', 'idle'});
  final idle = await _ensureBothIdle(caller, callee);
  final records = await _waitCallRecordCount(caller, callerPeerTox, 1);
  print(
    '[pair] $tileKey: inCall=$inCallCaller/$inCallCallee modeOk=$modeOk '
    'ended=$endedCaller/$endedCallee idle=$idle records=$records '
    'calleePeer=${_shortId(calleePeerTox)}',
  );
  return inCallCaller &&
      inCallCallee &&
      modeOk &&
      endedCaller &&
      endedCallee &&
      idle &&
      records;
}

Future<bool> _p1rWaitCallModeNonVideo(Inst inst, {int timeoutSecs = 8}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final mode = await _callField(inst, 'mode');
    if (mode == null || mode == 'audio' || mode == 'voice') return true;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

Future<bool> _p1rGroupJoinByIdRealUi(Inst a, Inst b) async {
  final nonce = DateTime.now().millisecondsSinceEpoch;
  final groupName = 'RUIP1JOIN-$nonce';
  final alias = 'JoinAlias-$nonce';
  final created = await _createGroupViaUI(a, groupName, groupType: 'public');
  final gid = created.groupId.trim();
  if (!RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(gid)) {
    print('[pair] group_join_by_id_real_ui: public gid not 64-hex: $gid');
    return false;
  }
  await b.foreground();
  final opened = await b.l3('l3_open_add_group_dialog');
  if (opened['ok'] != true) {
    print('[pair] group_join_by_id_real_ui: open dialog failed: $opened');
    return false;
  }
  if (!await b.waitKey('add_group_join_id_input', timeoutSecs: 12)) {
    await b.shot('/tmp/ui_p1r_join_noinput_B.png');
    print('[pair] group_join_by_id_real_ui: join id input missing');
    return false;
  }
  await b.focusType('add_group_join_id_input', gid);
  await b.focusType('add_group_join_message_input', 'real-ui join $nonce');
  await b.focusType('add_group_alias_input', alias);
  if (!await _p1cTapTextOnce(b, 'Send Join Request')) {
    print('[pair] group_join_by_id_real_ui: submit not tappable');
    return false;
  }
  final joined = await _waitConversationListed(
    b,
    'group_$gid',
    timeoutSecs: 45,
  );
  final aliasVisible = joined && await b.waitText(alias, timeoutSecs: 8);
  if (joined) {
    await openGroupChat(b, groupId: gid, groupName: alias);
  }
  final groupSurface =
      joined &&
      await b.waitKey('chat_input_text_field', timeoutSecs: 8) &&
      await sendComposerMessage(b, 'RUIP1JOIN-MSG-$nonce');
  print(
    '[pair] group_join_by_id_real_ui: gid=${_shortId(gid)} joined=$joined '
    'aliasVisible=$aliasVisible groupSurface=$groupSurface',
  );
  return joined && aliasVisible && groupSurface;
}

Future<void> _p1rStopInstanceOnly(Inst inst) async {
  print(
    '[${inst.name}] stopping instance for relaunch scenario (pid=${inst.pid})',
  );
  try {
    await inst.dispose();
  } catch (_) {}
  final r = await Process.run('tool/mcp_test/stop_toxee_instance.sh', [
    inst.name,
  ]);
  if (r.exitCode != 0) {
    throw DriveError(
      '[${inst.name}] stop_toxee_instance.sh failed '
      '(exit ${r.exitCode}): ${r.stderr}',
    );
  }
}

Future<void> _p1rRelaunchInstance(
  Inst inst, {
  required String expectedToxId,
  required String nick,
}) async {
  await _p1rStopInstanceOnly(inst);
  await _p1rLaunchStoppedInstance(
    inst,
    expectedToxId: expectedToxId,
    nick: nick,
  );
}

Future<void> _p1rLaunchStoppedInstance(
  Inst inst, {
  required String expectedToxId,
  required String nick,
}) async {
  print('[${inst.name}] relaunching instance');
  final launch = await Process.run('tool/mcp_test/launch_toxee_instance.sh', [
    inst.name,
  ]);
  if (launch.exitCode != 0) {
    throw DriveError(
      '[${inst.name}] launch_toxee_instance.sh failed '
      '(exit ${launch.exitCode}): ${launch.stderr}',
    );
  }
  final meta = await _p1rReadInstanceRuntime(inst.name);
  inst.pid = meta.pid;
  inst.ws = meta.ws;
  inst.navToolsUnavailable = false;
  await inst.connect();
  await inst.foreground();
  await _p1rWaitAutologin(inst, expectedToxId);
  await ensureHome(inst, nick);
}

Future<({int pid, String ws})> _p1rReadInstanceRuntime(String name) async {
  final file = File(
    'tool/mcp_test/.multi_instance_runtime/$name/instance.json',
  );
  if (!await file.exists()) {
    throw DriveError('[$name] instance.json missing after relaunch');
  }
  final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final pid = int.tryParse('${json['pid']}') ?? 0;
  final ws = json['ws_uri']?.toString() ?? '';
  if (pid <= 0 || ws.isEmpty) {
    throw DriveError('[$name] malformed instance.json after relaunch: $json');
  }
  return (pid: pid, ws: ws);
}

Future<void> _p1rWaitAutologin(Inst inst, String expectedToxId) async {
  await inst.waitState(
    (state) =>
        state['sessionReady'] == true &&
        state['currentAccountToxId']?.toString() == expectedToxId,
    timeoutSecs: 60,
    label: 'autologin after relaunch',
  );
}
