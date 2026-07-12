// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

const _p1rCases = {
  'relaunch_history_autologin',
  'offline_pending_relaunch',
  'presence_dot_relaunch',
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
    'presence_dot_relaunch' => await _p1rPresenceDotRelaunch(
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
  var skipped = 0;
  // `skipWin` skips ONLY on the headless Windows VM (kept for
  // relaunch_history_autologin, which has no in-driver Windows app-relaunch path
  // but PASSES on macOS). `skipEnv` (below) is the cross-platform env skip used
  // for cases that are un-constructible on ANY single-host real-UI run —
  // offline_pending_relaunch, call_from_profile_tiles, group_join_by_id_real_ui
  // — verified live (offlineData=false / "callee never rang" / chat-id "").
  // Both return true iff the case was skipped (so the caller doesn't run it).
  bool skipWin(String id, String why) {
    if (!_isWindowsRealUi) return false;
    skipped++;
    print('[pair] sweep_p1_relaunch SKIP: $id — $why');
    return true;
  }
  // Env-structural skip that applies to ANY single-host real-UI run (macOS AND
  // Windows), not just Windows. These cases genuinely cannot be constructed when
  // both peers share one host with a reused launch: they require stopping/taking
  // a peer offline (no in-app offline sim), real ToxAV call ringing across two
  // same-host sandboxed processes, or a public-NGC DHT announce/chat-id that is
  // empty same-host. Verified live (offlineData=false / "callee never rang" /
  // chat-id ""), matching the documented cross-platform SKIP set. A second
  // physical device/host is required to exercise them.
  bool skipEnv(String id, String why) {
    skipped++;
    print('[pair] sweep_p1_relaunch SKIP: $id — $why');
    return true;
  }
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

  if (!skipWin('relaunch_history_autologin',
      'peer stop+relaunch has no in-driver Windows path')) {
    await tally('relaunch_history_autologin', () async {
      toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? toxA;
      toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? toxB;
      return _p1rHistoryAutologin(a, b, toxA, toxB, nickA);
    });
  }
  // offline_pending_relaunch + presence_dot_relaunch DO run on macOS (a local
  // process stop+relaunch of B): the peer is taken offline by killing its
  // process, and A's real toxcore then detects it offline (the cases now WAIT
  // for that detection before asserting). They stay skipped on the headless
  // Windows VM, which has no in-driver app-relaunch path.
  if (!skipWin('offline_pending_relaunch',
      'peer stop+relaunch has no in-driver Windows path')) {
    await tally('offline_pending_relaunch', () async {
      toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? toxA;
      toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? toxB;
      return _p1rOfflinePendingRelaunch(a, b, toxA, toxB, nickB);
    });
  }
  if (!skipWin('presence_dot_relaunch',
      'peer stop+relaunch has no in-driver Windows path')) {
    await tally('presence_dot_relaunch', () async {
      toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? toxA;
      toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? toxB;
      return _p1rPresenceDotRelaunch(a, b, toxA, toxB, nickB);
    });
  }
  // ToxAV ringing across two same-host sandboxed processes does not reach the
  // callee ("callee never rang" live), even over TCP-only — a real second
  // host/device is required. (Works on the Windows VM where the comment below
  // was written; documented cross-platform AV SKIP applies on macOS same-host.)
  if (!skipEnv('call_from_profile_tiles',
      'same-host ToxAV call signalling does not ring the callee ("callee never '
      'rang" live); needs a second physical device')) {
    await tally('call_from_profile_tiles', () async {
      toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? toxA;
      toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? toxB;
      return _p1rCallFromProfileTiles(a, b, toxA, toxB);
    });
  }
  if (!skipEnv('group_join_by_id_real_ui',
      'public NGC chat-id resolution/DHT announce is unreliable same-host (the '
      "founder's public group chat-id comes back empty); distinct from the "
      'now-fixed founder→joiner delivery transport')) {
    await tally('group_join_by_id_real_ui', () => _p1rGroupJoinByIdRealUi(a, b));
  }

  print('[pair] sweep_p1_relaunch summary: passed=$passed failed=$failed '
      'skipped=$skipped');
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
    // Wait for A's toxcore to DETECT B offline before sending. Right after B's
    // process is killed, toxcore still believes B is online for ~30-60s (the
    // friend-connection timeout), so a send in that window goes out on the wire
    // (isPending=false) instead of queuing — the root of the old "offlineData=
    // false" skip. Poll the real friend `online` flag until it flips.
    final offlineDetected = await _p1rWaitFriendOnline(
      a,
      toxB,
      want: false,
      timeoutSecs: 90,
    );
    if (!offlineDetected) {
      print('[pair] offline_pending_relaunch: A never detected B offline');
      return false;
    }
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
      'pendingRow=$pendingRow pendingSpinner=$pendingSpinner (row/spinner are '
      'best-effort — the sender-side id form \'..._FlutterUIKitClient\' can '
      'differ from the rendered row\'s msgID key; the dump isPending=true is the '
      'authoritative offline-queue signal)',
    );
    // HARD: the send actually QUEUED as pending (dump isPending=true) — proving A
    // detected B offline and did NOT deliver on the wire. The rendered pending
    // bubble/spinner are logged but not gated (id-form mismatch above).
    if (pendingId == null) {
      return false;
    }

    await _p1rLaunchStoppedInstance(b, expectedToxId: toxB, nick: nickB);
    bRelaunched = true;
    await _p1rReseedMutualBootstrap(a, b);
    final delivered =
        await _p1rWaitMessagePending(
          a,
          convId,
          text,
          pending: false,
          timeoutSecs: 120,
        ) !=
        null;
    final bReceived = await _waitC2cMessageText(
      b,
      toxA,
      text,
      isSelf: false,
      timeoutSecs: 120,
    );
    print(
      '[pair] offline_pending_relaunch: delivered=$delivered '
      'bReceived=$bReceived',
    );
    // HARD: after B relaunches, the pending message FLIPS to delivered (isPending
    // false) AND B actually receives it — the full pending→deliver lifecycle.
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

/// Re-wire the same-host loopback DHT bootstrap between A and B after B was
/// relaunched, so B reconnects to A promptly rather than waiting on cold DHT
/// convergence (mirrors the fixture-c bootstrap the sweeps use at launch).
/// Best-effort — the online-poll that follows is the authoritative gate.
Future<void> _p1rReseedMutualBootstrap(Inst a, Inst b) async {
  try {
    for (final ext in fixtureCBootstrapExtensions) {
      await a.waitExt(ext);
      await b.waitExt(ext);
    }
    await wireFullMeshBootstrap([
      BootstrapTarget('A', a.vm, a.iso),
      BootstrapTarget('B', b.vm, b.iso),
    ]);
  } on Object catch (e) {
    print('[pair] presence reseed bootstrap best-effort failed: $e');
  }
}

/// Whether the friend [peerTox] is currently `online` in [inst]'s dump.
Future<bool> _p1rFriendOnline(Inst inst, String peerTox) async {
  final pk = _pubkey(peerTox);
  final friends = ((await inst.dumpState())['friends'] as List?) ?? const [];
  return friends.any((f) =>
      f is Map &&
      _pubkey(f['userId']?.toString() ?? '') == pk &&
      f['online'] == true);
}

/// Poll until [inst] sees the friend [peerTox]'s `online` flag == [want].
Future<bool> _p1rWaitFriendOnline(
  Inst inst,
  String peerTox, {
  required bool want,
  int timeoutSecs = 90,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _p1rFriendOnline(inst, peerTox) == want) return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

/// presence_dot_relaunch (S51/S53): with the C2C conversation open on A, take B
/// OFFLINE (stop the process) and assert A's REAL presence dot flips to the
/// `:offline` state key, then relaunch B and assert it flips back to `:online`.
/// Drives the genuine conversation-item online-dot widget (state-suffixed key),
/// not just the dump flag. Ends with B back up + online.
Future<bool> _p1rPresenceDotRelaunch(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
  String nickB,
) async {
  final convId = _c2cConvId(toxB);
  // Land on the chats home so the conversation ROW (which carries the dot) is
  // mounted; open the chat first to guarantee the row exists.
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] presence_dot_relaunch: A chat did not open');
    return false;
  }
  await returnToChatsHome(a, rounds: 4);
  final onlineKey = 'conversation_item_online_dot:$convId:online';
  final offlineKey = 'conversation_item_online_dot:$convId:offline';
  // Warm up: ensure A currently sees B online (dot :online). Poll a bit — a fresh
  // handshake can take a moment to mark the peer online.
  final onlineBefore = await _p1rWaitFriendOnline(a, toxB, want: true, timeoutSecs: 60);
  final dotOnlineBefore =
      onlineBefore && await a.waitKeyCenter(onlineKey, timeoutSecs: 10);
  if (!dotOnlineBefore) {
    print('[pair] presence_dot_relaunch: A did not see B online before stop '
        '(online=$onlineBefore)');
    return false;
  }
  var bRelaunched = false;
  try {
    await _p1rStopInstanceOnly(b);
    // A's toxcore detects B offline after the friend-connection timeout. This
    // can be slow/variable same-host (especially as the SECOND B-bounce in the
    // sweep, after offline_pending_relaunch), so allow a generous window.
    final offlineDetected =
        await _p1rWaitFriendOnline(a, toxB, want: false, timeoutSecs: 200);
    await returnToChatsHome(a, rounds: 2);
    final dotOffline =
        offlineDetected && await a.waitKeyCenter(offlineKey, timeoutSecs: 15);
    await a.shot('/tmp/ui_p1r_presence_offline_A.png');
    if (!dotOffline) {
      print('[pair] presence_dot_relaunch: offline dot did not appear '
          '(offlineDetected=$offlineDetected)');
      return false;
    }
    await _p1rLaunchStoppedInstance(b, expectedToxId: toxB, nick: nickB);
    bRelaunched = true;
    // Re-establish the same-host connection (bootstrap both ways) so B comes
    // back online promptly instead of waiting on cold DHT.
    await _p1rReseedMutualBootstrap(a, b);
    final onlineAgain =
        await _p1rWaitFriendOnline(a, toxB, want: true, timeoutSecs: 200);
    await returnToChatsHome(a, rounds: 2);
    final dotOnlineAgain =
        onlineAgain && await a.waitKeyCenter(onlineKey, timeoutSecs: 20);
    await a.shot('/tmp/ui_p1r_presence_online_A.png');
    print('[pair] presence_dot_relaunch: dotOnlineBefore=$dotOnlineBefore '
        'dotOffline=$dotOffline onlineAgain=$onlineAgain '
        'dotOnlineAgain=$dotOnlineAgain');
    return dotOffline && dotOnlineAgain;
  } finally {
    if (!bRelaunched) {
      try {
        await _p1rLaunchStoppedInstance(b, expectedToxId: toxB, nick: nickB);
        await _p1rReseedMutualBootstrap(a, b);
      } on Object catch (e) {
        print('[pair] WARN presence_dot_relaunch recovery relaunch failed: $e');
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
  // A call needs the PEER actually ONLINE, not just DHT-connected — warm up by
  // polling the friend's online flag both ways so the profile-tile call doesn't
  // fail with "callee never rang" on a cold connection (mirrors sweep_calls_misc).
  Future<bool> friendOnline(Inst inst, String peerTox) async {
    final pk = _pubkey(peerTox);
    final friends = ((await inst.dumpState())['friends'] as List?) ?? const [];
    return friends.any((f) =>
        f is Map &&
        _pubkey(f['userId']?.toString() ?? '') == pk &&
        f['online'] == true);
  }

  for (var i = 0; i < 40; i++) {
    if (await friendOnline(a, toxB) && await friendOnline(b, toxA)) break;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
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
  // The three profile call tiles (Send | Voice | Video) are fixed-width and can
  // pack tightly; a CENTER-COORDINATE tap on the Voice tile can land on the
  // adjacent Video tile (observed live: the voice tile produced a type=video
  // call). Use a KEY tap, which invokes the keyed InkWell's own onTap directly
  // (flutter_skill _tryInvokeCallback) rather than a coordinate — so the correct
  // per-tile handler fires regardless of packing. (A double-fire is harmless: a
  // second start while ringing is suppressed by the duplicate-outgoing guard.)
  if (!await caller.waitKey(tileKey, timeoutSecs: 8) ||
      !await caller.tryTapKey(tileKey, retries: 4)) {
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
  // B joins a PUBLIC group by its 64-char NGC CHAT-ID, not A's local group id
  // ("tox_N"). _createGroupViaUI now resolves the chat-id for public groups; B's
  // own local group id matches the chat-id (exact/prefix), so the chat-id is also
  // what B's joined conversation is keyed by (see drive_fixture_c_join).
  final chatId = created.chatId.trim();
  if (!RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(chatId)) {
    print('[pair] group_join_by_id_real_ui: public chat-id not 64-hex: '
        '"$chatId" (localGid=${created.groupId})');
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
  await b.focusType('add_group_join_id_input', chatId);
  await b.focusType('add_group_join_message_input', 'real-ui join $nonce');
  await b.focusType('add_group_alias_input', alias);
  if (!await _p1cTapTextOnce(b, 'Send Join Request')) {
    print('[pair] group_join_by_id_real_ui: submit not tappable');
    return false;
  }
  final joined = await _waitConversationListed(
    b,
    'group_$chatId',
    timeoutSecs: 45,
  );
  final aliasVisible = joined && await b.waitText(alias, timeoutSecs: 8);
  if (joined) {
    await openGroupChat(b, groupId: chatId, groupName: alias);
  }
  final groupSurface =
      joined &&
      await b.waitKey('chat_input_text_field', timeoutSecs: 8) &&
      await sendComposerMessage(b, 'RUIP1JOIN-MSG-$nonce');
  print(
    '[pair] group_join_by_id_real_ui: chatId=${_shortId(chatId)} '
    'localGid=${created.groupId} joined=$joined '
    'aliasVisible=$aliasVisible groupSurface=$groupSurface',
  );
  return joined && aliasVisible && groupSurface;
}

/// CROSS-HOST driver: A on macOS (real-UI, osascript), B on a Linux VM (headless,
/// synthetic flutter_skill input via [Inst.isLinux]), reachable over its tunneled
/// VM service. This runs the 3 cases that CANNOT be constructed same-host — public
/// NGC join-by-chat-id, legacy-conference bidirectional lifecycle, and a ToxAV call
/// that must actually RING the callee — because they need genuine network
/// separation between the two Tox peers. Prep: register both (A real-UI, B
/// synthetic), wait for the real DHT, wire the CROSS-HOST full-mesh bootstrap
/// (`bootstrapHost` = each side's routable IP, not loopback), seed a deterministic
/// mutual friendship over it, then run the requested case unchanged.
Future<int> runXhostCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String which,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[xhost] $which: missing tox id (A="$toxA" B="$toxB")');
    return 1;
  }
  print('[xhost] $which: A=${_shortId(toxA)}@${a.bootstrapHost} '
      'B=${_shortId(toxB)}@${b.bootstrapHost}');
  if (!(await areFriends(a, toxB) && await areFriends(b, toxA))) {
    await a.waitState((s) => s['isConnected'] == true,
        label: 'A connected', timeoutSecs: 120);
    await b.waitState((s) => s['isConnected'] == true,
        label: 'B connected', timeoutSecs: 120);
    // Cross-host full-mesh bootstrap (real IPs via bootstrapHost) so the two Tox
    // DHTs on DIFFERENT hosts learn each other, then a deterministic mutual
    // norequest friendship — a real P2P friendship that carries live C2C/NGC.
    await _wireSweepLoopbackBootstrap(a, b);
    if (!await _seedMutualFriendship(a, b, toxA, toxB, nickA, nickB)) {
      print('[xhost] $which: cross-host friendship seed failed');
      return 1;
    }
    print('[xhost] $which: cross-host friendship established');
  }
  // The friendship helpers granted+REVOKED the test-seed marker, so both accounts
  // are non-test here. The group cases use test-GATED seams (l3_group_chat_id to
  // resolve a public group's joinable chat-id; l3_group_member_list; the call
  // adapter). Grant the marker for the case duration so those seams work, then
  // revoke it. (Same "seed only to reach a gated seam" pattern the sweeps use;
  // the asserted actions stay real widget gestures / the real join+call handlers.)
  final markedA = await a.markAccountTest();
  final markedB = await b.markAccountTest();
  try {
    final ok = switch (which) {
      'xhost_group_join' => await _p1rGroupJoinByIdRealUi(a, b),
      'xhost_conference' =>
        await _hveConferenceBidirectionalMessageLifecycle(a, b, nickA, nickB),
      'xhost_call' => await _p1rCallFromProfileTiles(a, b, toxA, toxB),
      _ => false,
    };
    print('[xhost] $which: ${ok ? "PASS" : "FAIL"}');
    return ok ? 0 : 1;
  } finally {
    if (markedA) await a.unmarkAccountTest();
    if (markedB) await b.unmarkAccountTest();
  }
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
