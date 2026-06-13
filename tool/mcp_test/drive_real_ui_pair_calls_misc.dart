// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch 8 of the real-UI sweep campaign — "Calls + misc" (10 cases, FINAL write
// batch). See tool/mcp_test/REAL_UI_SWEEP_CAMPAIGN.md.
//
// `sweep_calls_misc` drives BOTH instances. ONE handshake at the top establishes
// the A<->B friendship; the call cases CHAIN the live call state efficiently
// (a voice block then a video block) so the campaign reuses ringing/inCall
// transitions instead of tearing every call fully down between cases:
//
//   86 mute-toggle-in-voice-call  — start a voice call (B calls A, A accepts →
//        both inCall), DON'T hang up → toggle mute on/off via the keyed dock
//        button (`call_mic_mute_button`), asserting `call.isMuted` flips both
//        ways (REAL state signal, not a log grep).
//   89 callee-hangup              — A (the callee) ends THIS same call via the
//        keyed `call_hangup_button` → BOTH sides settle to idle.
//   90 call-record-bubble-renders — after that completed call, A's chat history
//        carries a `mediaKind=='call_record'` bubble (the FakeUIKit call-record
//        insert path) — assert it renders.
//   88 missed-record              — B calls A, B cancels BEFORE A answers
//        (`_startVoiceCallUntilRinging` then B hangs up while A still ringing) →
//        A's missed-call record (`actionType==2` cancel) renders.
//   85 video-call-accept-hangup   — `chat_call_video_button` → A accepts → both
//        inCall + mode==video → hangup → idle.
//   87 camera-toggle-in-video-call— DURING that same video call (before 85's
//        hangup) toggle the camera off/on via `call_camera_toggle_button`,
//        asserting `call.isVideoEnabled` flips both ways.
//
// Then the misc cases (single-instance unless noted):
//   91 home-tabs-cycle            — chats→contacts→settings→chats with a chat
//        open; the IndexedStack retains the open chat (dump homeShellTab +
//        the offstage-aware waits).
//   92 theme-switch-chat-open     — open the C2C chat, flip dark/light via the
//        real settings control, assert the chat re-renders (bubbles intact + no
//        crash), flip back.
//   94 search-window-open         — seed a unique message term, open the global
//        search overlay (Cmd+Ctrl+F — the only entry), type the term → the
//        message-result row renders → tap it → the in-conversation
//        SearchChatHistoryWindow mounts (the surface the brief names).
//   93 window-resize-responsive   — LAST. Narrow the macOS window past the 720pt
//        bottom-nav breakpoint via osascript → assert the mobile layout-swap
//        signal (`home_bottom_nav` appears) → restore the width. SKIP(resize
//        refused) honestly if the raw-launched window won't size-script.
//
// State contract (registered in fixture_c_unified_runner.dart):
//   required = no-friend  (the sweep does its OWN handshake, reusing Batch-4's
//                          `_establishFriendshipForSweep`)
//   result   = friends    (no case deletes the friend; the calls end idle, the
//                          conversation row stays alive; the end-guard lands
//                          both on the chats home and recomputes endFriends)
//
// CALL-ISOLATION DISCIPLINE: every call case asserts BOTH sides are idle before
// the next call begins (the documented lesson behind the earlier "double-invite
// miscount"). The voice block (86→89) and the video block (87/85) each settle to
// idle before the next block starts; `_ensureBothIdle` is the guard.
//
// CALL DOCK KEYS (verified in the fork + lib/call):
//   - chat header start buttons: `chat_call_voice_button` / `chat_call_video_button`
//     (tencent_cloud_chat_message_header_actions.dart).
//   - incoming-call dock: `call_accept_button` / `call_decline_button`
//     (incoming_call_view.dart → UiKeys.callAcceptButton / callDeclineButton).
//   - in-call dock: `call_mic_mute_button` / `call_camera_toggle_button` (video
//     only) / `call_hangup_button` (in_call_view.dart → UiKeys.call*).
// All are CallDockAction keys plumbed onto the actual tappable InkWell
// (call_ui_components.dart:386), so flutter_skill/find.byKey lands them.

/// Read a sub-field of the dump `call` object (e.g. `isMuted`, `isVideoEnabled`,
/// `mode`), or null when there is no live call state.
Future<Object?> _callField(Inst inst, String field) async {
  final s = await inst.dumpState();
  final call = (s['call'] as Map?)?.cast<String, dynamic>();
  return call?[field];
}

/// Poll until [inst]'s dump `call.<field>` equals [want] (no throw).
Future<bool> _waitCallField(
  Inst inst,
  String field,
  Object? want, {
  int timeoutSecs = 12,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _callField(inst, field) == want) return true;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

/// Both peers must be back to idle before the next call case begins (the
/// call-isolation lesson). Best-effort hangs up any lingering call on each side,
/// then waits for idle. Returns whether BOTH reached idle.
Future<bool> _ensureBothIdle(Inst a, Inst b, {int timeoutSecs = 15}) async {
  for (final inst in [a, b]) {
    final st = await _callState(inst);
    if (st != null && st != 'idle') {
      await inst.foreground();
      await inst.tryTapKey('call_hangup_button', retries: 2);
    }
  }
  final aIdle = await _waitCallStateAny(a, {'idle'}, timeoutSecs: timeoutSecs);
  final bIdle = await _waitCallStateAny(b, {'idle'}, timeoutSecs: timeoutSecs);
  return aIdle && bIdle;
}

/// Start a VIDEO call from [caller] to [callee] and wait until [callee] sees the
/// ring. Mirrors `_startVoiceCallUntilRinging` but taps the chat header's
/// `chat_call_video_button`. Returns whether the callee reached ringing/incoming.
Future<bool> _startVideoCallUntilRinging(
  Inst caller,
  Inst callee,
  String calleeId, {
  int attempts = 3,
  int timeoutSecs = 10,
}) async {
  final calleePubkey = _pubkey(calleeId);
  for (var attempt = 0; attempt < attempts; attempt++) {
    await openChat(
      caller,
      calleeId,
      preferConversationList: true,
      requirePeerOnline: true,
    );
    await _reopenChatFromConversationList(caller, 'c2c_$calleePubkey');
    await caller.foreground();
    await caller.tapKey('chat_call_video_button');
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (await _waitCallStateAnyForegrounded(callee, {
      'ringing',
      'incoming',
    }, timeoutSecs: timeoutSecs)) {
      return true;
    }
    final callerState = await _callState(caller);
    final calleeState = await _callState(callee);
    print(
      '[pair] WARN video-call start retry '
      '(attempt ${attempt + 1}/$attempts '
      'callerState=$callerState calleeState=$calleeState)',
    );
    if (callerState == 'ringing' ||
        callerState == 'inCall' ||
        callerState == 'ended') {
      await caller.foreground();
      await caller.tryTapKey('call_hangup_button', retries: 2);
    }
    await _waitCallStateAny(caller, {'idle'}, timeoutSecs: 5);
    await _waitCallStateAny(callee, {'idle'}, timeoutSecs: 5);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Count [inst]'s call-record bubbles for the C2C conversation with [friendId]
/// from the dump `messages[]` (a record is `mediaKind=='call_record'`). Reads
/// the conversation-scoped dump so it only counts records for THIS chat.
Future<int> _callRecordCount(Inst inst, String friendId) async {
  final convId = 'c2c_${_pubkey(friendId)}';
  final s = await inst.dumpState(conversationId: convId);
  final msgs = (s['messages'] as List?) ?? const [];
  var n = 0;
  for (final m in msgs) {
    if (m is Map && m['mediaKind']?.toString() == 'call_record') n++;
  }
  return n;
}

/// Wait until [inst]'s call-record count for [friendId] is at least [want].
Future<bool> _waitCallRecordCount(
  Inst inst,
  String friendId,
  int want, {
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _callRecordCount(inst, friendId) >= want) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Whether a call-record bubble ROW is rendered in [inst]'s open chat. The fork
/// renders call records through the message list; the row container key is
/// `message_list_item:<msgID>`. We resolve the record msgID from the dump, then
/// assert its row mounts. Returns whether at least one record row is rendered.
Future<bool> _callRecordRowRendered(
  Inst inst,
  String friendId, {
  int timeoutSecs = 12,
}) async {
  final convId = 'c2c_${_pubkey(friendId)}';
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState(conversationId: convId);
    final msgs = (s['messages'] as List?) ?? const [];
    for (final m in msgs) {
      if (m is! Map) continue;
      if (m['mediaKind']?.toString() != 'call_record') continue;
      final id = m['msgID']?.toString() ?? m['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (await inst.waitKey('message_list_item:$id', timeoutSecs: 1)) {
        return true;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

// ===========================================================================
// case 86 — call_mute_toggle_incall (S74)  [two-process; starts the voice block]
// ===========================================================================
/// Start a voice call (B calls A, A accepts → both inCall), DON'T hang up, then
/// toggle mute ON then OFF on the in-call dock (`call_mic_mute_button`),
/// asserting A's `call.isMuted` flips ON then back OFF (the REAL state signal).
/// The call is LEFT IN inCall so case 89 (callee-hangup) ends this SAME call.
/// Returns the inCall continuation flag via the out-param style: it returns true
/// only when the call reached inCall AND both mute toggles flipped the state.
Future<bool> _callMuteToggleIncall(Inst a, Inst b, String toxA) async {
  // Make sure no stale call lingers — a lingering call would poison this case
  // (the "double-invite miscount" lesson), so a failed idle-settle is HARD.
  if (!await _ensureBothIdle(a, b)) {
    print(
      '[pair] call_mute_toggle_incall: a prior call did not settle to idle',
    );
    return false;
  }
  // B (caller) rings A (callee) — same direction as runCallVoice.
  final ringing = await _startVoiceCallUntilRinging(b, a, toxA);
  if (!ringing) {
    print('[pair] call_mute_toggle_incall: incoming voice call never rang');
    return false;
  }
  // A accepts → both inCall.
  await a.foreground();
  await a.tapKey('call_accept_button');
  final inCallA = await _waitCallStateAny(a, {'inCall'});
  final inCallB = await _waitCallStateAny(b, {'inCall'});
  if (!inCallA || !inCallB) {
    print(
      '[pair] call_mute_toggle_incall: did not reach inCall '
      '(A=${await _callState(a)} B=${await _callState(b)})',
    );
    await _ensureBothIdle(a, b);
    return false;
  }
  // Toggle mute on the CALLEE (A) dock — the keyed mic button.
  await a.foreground();
  final mutedBefore = await _callField(a, 'isMuted') == true;
  if (!await a.tapKeyCenter('call_mic_mute_button', timeoutSecs: 8)) {
    print('[pair] call_mute_toggle_incall: mute button not tappable');
    await _ensureBothIdle(a, b);
    return false;
  }
  final mutedOn = await _waitCallField(a, 'isMuted', !mutedBefore);
  // Toggle back (unmute / restore).
  if (!await a.tapKeyCenter('call_mic_mute_button', timeoutSecs: 8)) {
    print('[pair] call_mute_toggle_incall: mute button not tappable (restore)');
    await _ensureBothIdle(a, b);
    return false;
  }
  final mutedOff = await _waitCallField(a, 'isMuted', mutedBefore);
  await a.shot('/tmp/ui_b8_mute_A.png');
  // Leave the call inCall (case 89 ends it). Confirm it's STILL inCall.
  final stillInCall = await _callState(a) == 'inCall';
  print(
    '[pair] call_mute_toggle_incall: inCall=$inCallA/$inCallB '
    'mutedBefore=$mutedBefore mutedOn=$mutedOn mutedOff=$mutedOff '
    'stillInCall=$stillInCall',
  );
  return mutedOn && mutedOff && stillInCall;
}

// ===========================================================================
// case 89 — call_callee_hangup (S76)  [two-process; ends the voice block]
// ===========================================================================
/// The callee (A) ends the SAME voice call from case 86 via the keyed
/// `call_hangup_button` → BOTH sides settle to idle/ended. If case 86 already
/// tore the call down (e.g. it failed mid-way), re-establish a quick voice call
/// so this case still drives the callee-hangup path honestly.
Future<bool> _callCalleeHangup(Inst a, Inst b, String toxA) async {
  // If the call from case 86 is no longer live, re-establish one (B calls A, A
  // accepts) so the callee-hangup is still the asserted action.
  if (await _callState(a) != 'inCall' || await _callState(b) != 'inCall') {
    await _ensureBothIdle(a, b);
    final ringing = await _startVoiceCallUntilRinging(b, a, toxA);
    if (!ringing) {
      print('[pair] call_callee_hangup: could not re-establish a voice call');
      return false;
    }
    await a.foreground();
    await a.tapKey('call_accept_button');
    final inCallA = await _waitCallStateAny(a, {'inCall'});
    final inCallB = await _waitCallStateAny(b, {'inCall'});
    if (!inCallA || !inCallB) {
      print(
        '[pair] call_callee_hangup: re-established call did not reach inCall',
      );
      await _ensureBothIdle(a, b);
      return false;
    }
  }
  // A is the CALLEE — A ends the call.
  await a.foreground();
  await a.tapKeyCenter('call_hangup_button', timeoutSecs: 8);
  final endedA = await _waitCallStateAny(a, {'ended', 'idle'});
  final endedB = await _waitCallStateAny(b, {'ended', 'idle'});
  // Settle both to idle (the local notifier auto-resets ended -> idle after 2s).
  final idle = await _ensureBothIdle(a, b);
  await a.shot('/tmp/ui_b8_callee_hangup_A.png');
  print(
    '[pair] call_callee_hangup: endedA=$endedA endedB=$endedB bothIdle=$idle',
  );
  return endedA && endedB && idle;
}

// ===========================================================================
// case 90 — call_record_bubble_renders  [two-process; reads after the voice block]
// ===========================================================================
/// After the completed voice call (86 → 89), A's chat history must carry a NEW
/// call-record bubble (the FakeUIKit `_insertCallRecord` path writes a
/// `mediaKind=='call_record'` ChatMessage into the conversation). [baseline] is
/// the record count BEFORE the voice block — case 90 requires the count to
/// EXCEED it (codex P2: on a restored `paired_for_e2e` launch the conversation
/// may already carry stale call records, so `>= 1` could false-pass even if the
/// just-finished call produced no record). Then assert a record row renders.
Future<bool> _callRecordBubbleRenders(
  Inst a,
  String toxB, {
  required int baseline,
}) async {
  // The record is inserted on call end; give it a beat to persist + reopen the
  // chat fresh so the history reloads from FfiChatService.
  await returnToChatsHome(a, rounds: 4);
  final hasNewRecord = await _waitCallRecordCount(
    a,
    toxB,
    baseline + 1,
    timeoutSecs: 20,
  );
  if (!hasNewRecord) {
    print(
      '[pair] call_record_bubble_renders: no NEW call_record persisted '
      '(baseline=$baseline now=${await _callRecordCount(a, toxB)})',
    );
    return false;
  }
  await openChat(a, _pubkey(toxB));
  final rowRendered = await _callRecordRowRendered(a, toxB, timeoutSecs: 15);
  await a.shot('/tmp/ui_b8_call_record_A.png');
  await returnToChatsHome(a, rounds: 4);
  final count = await _callRecordCount(a, toxB);
  print(
    '[pair] call_record_bubble_renders: baseline=$baseline hasNewRecord='
    '$hasNewRecord count=$count rowRendered=$rowRendered',
  );
  return hasNewRecord && rowRendered;
}

// ===========================================================================
// case 88 — call_missed_record_row (S77)  [two-process]
// ===========================================================================
/// B calls A, then B CANCELS the unanswered ring before A picks up → A sees a
/// MISSED incoming call. The FakeUIKit call-record path inserts a record on the
/// cancel; assert A's call-record count INCREASES (a new missed-call record
/// rendered) and a record row mounts. Reuses the missed-call recipe (the caller
/// cancels while the callee is still ringing — drive_fixture_c_missed_call.dart).
Future<bool> _callMissedRecordRow(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  // A lingering call would poison the missed-call accounting — HARD-gate idle.
  if (!await _ensureBothIdle(a, b)) {
    print('[pair] call_missed_record_row: a prior call did not settle to idle');
    return false;
  }
  final before = await _callRecordCount(a, toxB);
  // B (caller) rings A (callee).
  final ringing = await _startVoiceCallUntilRinging(b, a, toxA);
  if (!ringing) {
    print('[pair] call_missed_record_row: incoming call never rang');
    return false;
  }
  // Let A genuinely ring for a few seconds (truly unanswered), confirm A is
  // still ringing, then B CANCELS (the missed-call realization).
  await Future<void>.delayed(const Duration(seconds: 3));
  final stillRinging = await _waitCallStateAnyForegrounded(a, {
    'ringing',
    'incoming',
  }, timeoutSecs: 4);
  await b.foreground();
  await b.tapKeyCenter('call_hangup_button', timeoutSecs: 8);
  // Both tear down WITHOUT A having accepted = a missed incoming call from A.
  final endedA = await _waitCallStateAny(a, {'ended', 'idle'});
  final endedB = await _waitCallStateAny(b, {'ended', 'idle'});
  await _ensureBothIdle(a, b);
  // A's call-record count must INCREASE (a new missed/cancel record).
  final got = await _waitCallRecordCount(a, toxB, before + 1, timeoutSecs: 20);
  // Open the chat + assert a record row renders.
  await openChat(a, _pubkey(toxB));
  final rowRendered = await _callRecordRowRendered(a, toxB, timeoutSecs: 12);
  await a.shot('/tmp/ui_b8_missed_A.png');
  await returnToChatsHome(a, rounds: 4);
  final after = await _callRecordCount(a, toxB);
  print(
    '[pair] call_missed_record_row: stillRinging=$stillRinging endedA=$endedA '
    'endedB=$endedB before=$before after=$after got=$got '
    'rowRendered=$rowRendered',
  );
  return got && rowRendered;
}

// ===========================================================================
// case 85 + 87 — video call with camera toggle (S66 + S75)  [two-process]
// ===========================================================================
/// Start a VIDEO call (B calls A via `chat_call_video_button`, A accepts → both
/// inCall + mode==video). DURING the call (case 87) toggle the camera off/on via
/// `call_camera_toggle_button`, asserting A's `call.isVideoEnabled` flips OFF
/// then back ON. Then (case 85) hang up → both idle. Returns a record of both
/// case outcomes so the sweep can tally 85 and 87 separately.
Future<({bool videoCall, bool cameraToggle})> _callVideoWithCameraToggle(
  Inst a,
  Inst b,
  String toxA,
) async {
  // A lingering call would poison the video block — HARD-gate idle first.
  if (!await _ensureBothIdle(a, b)) {
    print('[pair] video call: a prior call did not settle to idle');
    return (videoCall: false, cameraToggle: false);
  }
  final ringing = await _startVideoCallUntilRinging(b, a, toxA);
  if (!ringing) {
    print('[pair] video call: incoming video call never rang');
    return (videoCall: false, cameraToggle: false);
  }
  await a.foreground();
  await a.tapKey('call_accept_button');
  final inCallA = await _waitCallStateAny(a, {'inCall'});
  final inCallB = await _waitCallStateAny(b, {'inCall'});
  // Confirm the call mode is actually VIDEO (the video button path).
  final modeVideo = await _waitCallField(a, 'mode', 'video', timeoutSecs: 8);
  if (!inCallA || !inCallB || !modeVideo) {
    print(
      '[pair] video call: did not reach inCall video '
      '(A=${await _callState(a)} B=${await _callState(b)} '
      'mode=${await _callField(a, 'mode')})',
    );
    await _ensureBothIdle(a, b);
    return (videoCall: false, cameraToggle: false);
  }
  // --- case 87: camera toggle DURING the video call ---
  await a.foreground();
  final videoBefore = await _callField(a, 'isVideoEnabled') == true;
  var cameraToggle = false;
  if (await a.tapKeyCenter('call_camera_toggle_button', timeoutSecs: 8)) {
    final off = await _waitCallField(a, 'isVideoEnabled', !videoBefore);
    final restored =
        await a.tapKeyCenter('call_camera_toggle_button', timeoutSecs: 8) &&
        await _waitCallField(a, 'isVideoEnabled', videoBefore);
    cameraToggle = off && restored;
    print(
      '[pair] call_camera_toggle_incall: videoBefore=$videoBefore '
      'off=$off restored=$restored',
    );
  } else {
    print('[pair] call_camera_toggle_incall: camera button not tappable');
  }
  await a.shot('/tmp/ui_b8_camera_A.png');
  // --- case 85: hang up the video call → both idle ---
  await a.foreground();
  await a.tapKeyCenter('call_hangup_button', timeoutSecs: 8);
  final endedA = await _waitCallStateAny(a, {'ended', 'idle'});
  final endedB = await _waitCallStateAny(b, {'ended', 'idle'});
  final idle = await _ensureBothIdle(a, b);
  await a.shot('/tmp/ui_b8_video_A.png');
  final videoCall = inCallA && inCallB && modeVideo && endedA && endedB && idle;
  print(
    '[pair] call_video_accept_hangup: inCall=$inCallA/$inCallB modeVideo=$modeVideo '
    'endedA=$endedA endedB=$endedB bothIdle=$idle => videoCall=$videoCall',
  );
  return (videoCall: videoCall, cameraToggle: cameraToggle);
}

// ===========================================================================
// case 91 — home_tabs_cycle_state_retained  [single-instance]
// ===========================================================================
/// Read the home shell's snapshot of the OPEN chat-tab conversation id
/// (`homeShellCurrentConversationId`) — the value the chats tab's IndexedStack
/// branch holds, distinct from the live `currentConversation` which a tab swap
/// to contacts/settings changes. Null when the chats tab has no open detail.
Future<String?> _homeShellCurrentConversationId(Inst inst) async {
  final s = await inst.dumpState();
  return s['homeShellCurrentConversationId']?.toString();
}

/// Open the C2C chat, then cycle chats→contacts→settings→chats by tapping the
/// REAL sidebar tabs (a plain IndexedStack `_index` setState — NOT
/// `_forceHomeRootAndWait`, which RESETS the chats-tab detail and would make the
/// retention assertion vacuous; codex P1). Assert the IndexedStack RETAINS the
/// open chat: `homeShellCurrentConversationId` stays the C2C id THROUGH the
/// contacts/settings detour AND is still the C2C id after returning to chats,
/// where the chat surface re-renders WITHOUT any re-open. Drives the production
/// sidebar tab widgets; reads the home-shell snapshot.
Future<bool> _homeTabsCycleStateRetained(Inst inst, String toxB) async {
  final c2c = 'c2c_${_pubkey(toxB)}';
  // Open the chat so the chats-tab IndexedStack branch holds a detail.
  await openChat(inst, _pubkey(toxB));
  final openConv = await _homeShellCurrentConversationId(inst);
  if (openConv != c2c) {
    print(
      '[pair] home_tabs_cycle: chat did not open '
      '(homeShellCurrentConversationId=$openConv)',
    );
    return false;
  }
  // Tap the REAL sidebar Contacts tab (IndexedStack index switch). The chats
  // tab branch is KEPT ALIVE off-stage, so its open-chat detail must survive.
  if (!await inst.tapKeyCenter('sidebar_contacts_tab', timeoutSecs: 6)) {
    print('[pair] home_tabs_cycle: contacts tab not tappable');
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final onContacts = await _waitHomeShellTab(inst, 'contacts');
  final retainedThroughContacts =
      await _homeShellCurrentConversationId(inst) == c2c;
  // Tap the REAL sidebar Settings tab.
  if (!await inst.tapKeyCenter('sidebar_settings_tab', timeoutSecs: 6)) {
    print('[pair] home_tabs_cycle: settings tab not tappable');
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final onSettings = await _waitHomeShellTab(inst, 'settings');
  final retainedThroughSettings =
      await _homeShellCurrentConversationId(inst) == c2c;
  // Tap back to the REAL sidebar Chats tab — the retained IndexedStack branch
  // re-stages the SAME open chat WITHOUT re-opening it.
  if (!await inst.tapKeyCenter('sidebar_chats_tab', timeoutSecs: 6)) {
    print('[pair] home_tabs_cycle: chats tab not tappable');
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 800));
  final onChats = await _waitHomeShellTab(inst, 'chats');
  // The retained chat detail surfaces with NO re-open — assert the chat surface
  // is ready AND the open conversation is still the C2C one.
  final retained =
      onChats &&
      await _homeShellCurrentConversationId(inst) == c2c &&
      await _chatSurfaceReady(inst, c2c, timeoutSecs: 8);
  await inst.shot('/tmp/ui_b8_tabs_${inst.name}.png');
  await returnToChatsHome(inst, rounds: 4);
  print(
    '[pair] home_tabs_cycle: onContacts=$onContacts '
    'retainedThroughContacts=$retainedThroughContacts onSettings=$onSettings '
    'retainedThroughSettings=$retainedThroughSettings onChats=$onChats '
    'retained=$retained',
  );
  return onContacts &&
      retainedThroughContacts &&
      onSettings &&
      retainedThroughSettings &&
      retained;
}

/// Poll until the home shell's tab equals [tab] ('chats'|'contacts'|'settings').
Future<bool> _waitHomeShellTab(
  Inst inst,
  String tab, {
  int timeoutSecs = 6,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _homeShellTab(inst) == tab) return true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

// ===========================================================================
// case 92 — theme_switch_chat_open (S57)  [two-process state, drives A only]
// ===========================================================================
/// With the C2C chat OPEN, flip the theme dark→light via the REAL settings
/// Appearance control, then assert the chat re-renders intact (the composer +
/// at least one bubble survive the rebuild, no crash) and the dump themeMode
/// persisted. Flip back to the original mode at the end (poison guard).
Future<bool> _themeSwitchChatOpen(Inst inst, String toxB) async {
  // Seed at least one bubble so "bubbles intact after rebuild" is assertable.
  await openChat(inst, _pubkey(toxB));
  final seedText = 'B8THEME-${DateTime.now().microsecondsSinceEpoch}';
  final seeded = await sendComposerMessage(inst, seedText);
  final c2c = 'c2c_${_pubkey(toxB)}';
  if (!seeded) {
    print('[pair] theme_switch_chat_open: could not seed a bubble');
    return false;
  }
  final originalMode =
      (await inst.dumpState())['themeMode']?.toString() ?? 'system';
  // Pick the flip target distinct from the current rendered brightness.
  final flipTo = originalMode == 'dark' ? 'Light' : 'Dark';
  final flipMode = flipTo == 'Dark' ? 'dark' : 'light';
  // Flip the theme via the real Appearance segment (settings), then return to
  // the chat and assert it re-rendered intact.
  await _openSettings(inst);
  final flipped = await _tapThemeSegment(inst, flipTo);
  final persisted =
      flipped && await _waitStringState(inst, 'themeMode', flipMode);
  // Re-open the chat — it must still render (composer + the seeded bubble).
  await returnToChatsHome(inst, rounds: 4);
  await _reopenChatFromConversationList(inst, c2c);
  final chatReady = await _chatSurfaceReady(inst, c2c, timeoutSecs: 10);
  // BUBBLE INTACT = the seeded message's actual chat-surface ROW renders after
  // the theme rebuild (codex P1: `_lastMessage` reads the conversation-LIST
  // preview text, NOT the open chat surface — a broken bubble render would still
  // pass). Resolve the own message's msgID and assert `message_list_item:<id>`
  // is in the tree.
  var bubbleIntact = false;
  if (chatReady) {
    final msgId = await _ownMessageId(inst, toxB, seedText);
    if (msgId != null) {
      bubbleIntact = await inst.waitKey(
        'message_list_item:$msgId',
        timeoutSecs: 8,
      );
    }
  }
  final alive = (await inst.dumpState())['sessionReady'] == true;
  await inst.shot('/tmp/ui_b8_theme_${inst.name}.png');
  // Restore the original theme (poison guard for later cases).
  await _openSettings(inst);
  final restoreLabel = originalMode == 'dark'
      ? 'Dark'
      : (originalMode == 'light' ? 'Light' : 'System');
  await _tapThemeSegment(inst, restoreLabel);
  await _waitStringState(inst, 'themeMode', originalMode);
  await returnToChatsHome(inst, rounds: 4);
  print(
    '[pair] theme_switch_chat_open: originalMode=$originalMode flipTo=$flipMode '
    'flipped=$flipped persisted=$persisted chatReady=$chatReady '
    'bubbleIntact=$bubbleIntact alive=$alive',
  );
  return flipped && persisted && chatReady && bubbleIntact && alive;
}

// ===========================================================================
// case 94 — search_chat_history_window_open (S93)  [two-process state, drives A]
// ===========================================================================
/// Seed a UNIQUE message term in the C2C chat, open the GLOBAL search overlay
/// (Cmd+Ctrl+F — the only entry; there is no visible search button), type the
/// term → the MESSAGE-result row (`search_result_message_<convId>`) renders →
/// tap it → the in-conversation `SearchChatHistoryWindow` mounts (asserted by
/// its "Search Chat History" AppBar title). This is the surface the brief names;
/// the global overlay is the production entry to it. Closes the overlay after.
Future<bool> _searchChatHistoryWindowOpen(Inst inst, String toxB) async {
  final c2c = 'c2c_${_pubkey(toxB)}';
  // Seed a unique searchable term as a real message.
  await openChat(inst, _pubkey(toxB));
  final term = 'B8SEARCHTERM${DateTime.now().microsecondsSinceEpoch}';
  if (!await sendComposerMessage(inst, term)) {
    print('[pair] search_chat_history_window_open: could not seed search term');
    return false;
  }
  await returnToChatsHome(inst, rounds: 4);
  // Open the global search overlay (the only entry to message search).
  await inst.foreground();
  try {
    await inst.osaSearchShortcut();
  } on PermissionBlockedError catch (e) {
    print(
      '[pair] search_chat_history_window_open: shortcut blocked: ${e.message}',
    );
    return false;
  }
  if (!await inst.waitKey('message_search_field', timeoutSecs: 10)) {
    print(
      '[pair] search_chat_history_window_open: search overlay did not open',
    );
    return false;
  }
  await inst.focusType('message_search_field', term);
  await Future<void>.delayed(const Duration(milliseconds: 900));
  // The MESSAGE-result row keyed by the conversation id must render (the chat
  // history match surface). Wait through the 300ms debounce + FFI search.
  final resultKey = await _c2ceFirstVisibleKey(inst, [
    'search_result_message_$c2c',
    'search_result_message:$c2c',
  ]);
  final resultRow = resultKey != null;
  var windowOpened = false;
  if (resultKey != null) {
    // Tap the result → the in-conversation SearchChatHistoryWindow opens.
    await inst.tapKeyCenter(resultKey, timeoutSecs: 6);
    // The window's AppBar title is "Search Chat History" (distinct from the
    // global overlay, which shares message_search_field).
    windowOpened = await inst.waitText('Search Chat History', timeoutSecs: 8);
  }
  await inst.shot('/tmp/ui_b8_search_${inst.name}.png');
  // Close everything back to the chats home (ESC pops the window then the
  // overlay). Best-effort, then a force-home-root.
  for (var i = 0; i < 3; i++) {
    if (!await inst.waitKey('message_search_field', timeoutSecs: 1)) break;
    try {
      await inst.osaEscape();
    } on DriveError {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  await returnToChatsHome(inst, rounds: 4);
  final closed = await inst.waitKeyGone('message_search_field', timeoutSecs: 4);
  print(
    '[pair] search_chat_history_window_open: resultRow=$resultRow '
    'windowOpened=$windowOpened closed=$closed',
  );
  return resultRow && windowOpened && closed;
}

// ===========================================================================
// case 93 — window_resize_responsive (S60)  [single-instance; SKIP-able]
// ===========================================================================
/// Narrow the macOS window past the 720pt bottom-nav breakpoint via osascript,
/// then assert the MOBILE layout-swap signal (`home_bottom_nav` appears — it
/// renders ONLY when `shouldShowBottomNav`, a pure width check). While narrow,
/// also DRIVE the mobile bottom-nav routing (tap the Contacts item → homeShellTab
/// goes 'contacts', tap Chats → back to 'chats') so the swap isn't only proven
/// visually — the bottom nav actually NAVIGATES (codex P3 mobile-parity: the
/// desktop sidebar and the mobile bottom nav share the same `onTap` → `_index`
/// setState, so this exercises the mobile routing path the desktop harness can't
/// otherwise reach). Then restore the width and assert the bar is GONE. Returns:
///   - true  : the swap + bottom-nav routing worked in BOTH directions (PASS)
///   - false : the window resized but the swap/routing did NOT happen (FAIL —
///             a real bug)
///   - null  : the window refused scripted resize (SKIP(resize-refused) — the
///             raw-launched window can't be sized; never a fake pass)
Future<bool?> _windowResizeResponsive(Inst inst) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  final original = await inst.windowSize();
  if (original == null) {
    print(
      '[pair] window_resize_responsive: window size unreadable — '
      'SKIP(resize-refused)',
    );
    return null;
  }
  // In desktop layout the bottom nav must be ABSENT to start.
  final beforeNav = await inst.waitKey('home_bottom_nav', timeoutSecs: 1);
  // Narrow well below the 720pt breakpoint.
  final narrowed = await inst.resizeWindow(560, original.h);
  if (!narrowed) {
    print(
      '[pair] window_resize_responsive: resize refused — SKIP(resize-refused)',
    );
    return null;
  }
  final applied = await inst.windowSize();
  // The OS may clamp the minimum width (window_manager min-size). If it didn't
  // actually narrow past the breakpoint, treat as SKIP (can't prove the swap).
  if (applied == null || applied.w >= 720) {
    print(
      '[pair] window_resize_responsive: width not applied past breakpoint '
      '(applied=$applied) — SKIP(resize-refused)',
    );
    // Restore best-effort before bailing.
    await inst.resizeWindow(original.w, original.h);
    return null;
  }
  // The mobile bottom nav must now appear (the responsive swap signal).
  final swapped = await inst.waitKey('home_bottom_nav', timeoutSecs: 8);
  await inst.shot('/tmp/ui_b8_resize_narrow_${inst.name}.png');
  // Drive the mobile bottom-nav ROUTING while narrow: tap Contacts → tab moves;
  // tap Chats → back. The items are label-text widgets inside the bottom nav
  // (now the only place those labels render, since the sidebar is gone in narrow
  // mode), so tap by label and assert homeShellTab actually changed.
  var navRouted = false;
  if (swapped) {
    await _tryTapText(inst, 'Contacts');
    final onContacts = await _waitHomeShellTab(
      inst,
      'contacts',
      timeoutSecs: 6,
    );
    await _tryTapText(inst, 'Chats');
    final backToChats = await _waitHomeShellTab(inst, 'chats', timeoutSecs: 6);
    navRouted = onContacts && backToChats;
    print(
      '[pair] window_resize_responsive: bottom-nav routing '
      'onContacts=$onContacts backToChats=$backToChats',
    );
  }
  // Restore the original width → the bottom nav must go away again.
  final restored = await inst.resizeWindow(original.w, original.h);
  final navGone =
      restored && await inst.waitKeyGone('home_bottom_nav', timeoutSecs: 8);
  await inst.shot('/tmp/ui_b8_resize_wide_${inst.name}.png');
  print(
    '[pair] window_resize_responsive: beforeNav=$beforeNav applied=$applied '
    'swapped=$swapped navRouted=$navRouted restored=$restored navGone=$navGone',
  );
  // PASS only if the swap happened both ways, the bottom nav actually NAVIGATED,
  // and the desktop layout had no bottom nav to begin with.
  return !beforeNav && swapped && navRouted && navGone;
}

// ===========================================================================
// sweep_calls_misc — Batch 8: chain all 10 calls/misc cases on ONE launch.
// ===========================================================================
/// Order (call-isolation + state-poison-aware): handshake once → voice block
/// (86 mute-toggle-in-call, leaves the call inCall → 89 callee-hangup ends it →
/// 90 call-record bubble reads the completed call) → 88 missed-record (B cancels
/// an unanswered ring) → video block (85 video-call + 87 camera-toggle, driven
/// together so the camera toggle runs DURING the same video call) → misc (91
/// home-tabs-cycle → 92 theme-switch-with-chat-open → 94 search-window-open → 93
/// window-resize LAST, SKIP-able). The friendship is never deleted → ends
/// FRIENDS. A `finally` end-guard restores the window size + lands both home.
Future<int> runCallsMiscSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[sweep] sweep_calls_misc: missing tox ids (A=$toxA B=$toxB)');
    return 1;
  }
  print(
    '[sweep] sweep_calls_misc: A=${_shortId(toxA)} ($nickA) '
    'B=${_shortId(toxB)} ($nickB)',
  );

  var passed = 0;
  var failed = 0;
  var skipped = 0;
  final results = <String, String>{};
  var endFriends = false;

  Future<void> hard(String id, Future<bool> Function() run) async {
    bool ok;
    String? detail;
    try {
      ok = await run();
    } on PermissionBlockedError {
      rethrow;
    } on DriveError catch (e) {
      ok = false;
      detail = 'DriveError: ${e.message}';
    }
    if (ok) {
      passed++;
      results[id] = 'PASS';
      print('[sweep] $id: PASS');
    } else {
      failed++;
      results[id] = 'FAIL';
      print('[sweep] $id: FAIL${detail != null ? ' ($detail)' : ''}');
    }
  }

  /// A SKIP-able case (`bool?`): null → SKIP, false → FAIL, true → PASS.
  Future<void> soft(String id, Future<bool?> Function() run) async {
    bool? r;
    String? detail;
    try {
      r = await run();
    } on PermissionBlockedError {
      rethrow;
    } on DriveError catch (e) {
      r = false;
      detail = 'DriveError: ${e.message}';
    }
    if (r == null) {
      skipped++;
      results[id] = 'SKIP';
      print('[sweep] $id: SKIP');
    } else if (r) {
      passed++;
      results[id] = 'PASS';
      print('[sweep] $id: PASS');
    } else {
      failed++;
      results[id] = 'FAIL';
      print('[sweep] $id: FAIL${detail != null ? ' ($detail)' : ''}');
    }
  }

  const callCaseIds = <String>[
    'call_mute_toggle_incall',
    'call_callee_hangup',
    'call_record_bubble_renders',
    'call_missed_record_row',
    'call_video_accept_hangup',
    'call_camera_toggle_incall',
  ];

  try {
    // --- Establish the A<->B friendship (real-UI handshake) once. ---
    final friended = await _establishFriendshipForSweep(
      a,
      b,
      toxA,
      toxB,
      nickA,
      nickB,
    );
    if (!friended) {
      print('[sweep] sweep_calls_misc: handshake FAILED — no case can run');
      for (final id in const [
        ...callCaseIds,
        'home_tabs_cycle_state_retained',
        'theme_switch_chat_open',
        'search_chat_history_window_open',
        'window_resize_responsive',
      ]) {
        failed++;
        results[id] = 'FAIL';
      }
    } else {
      // Wait for connectivity + friend-online so the call signaling can reach
      // the peer (calls need a live transport, like runCallVoice).
      await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
      await b.waitState((s) => s['isConnected'] == true, label: 'B connected');

      // --- VOICE BLOCK: 86 (leaves inCall) → 89 (callee hangup) → 90 (record). ---
      // Snapshot the call-record baseline BEFORE the call so case 90 requires a
      // NEW record (codex P2 — a restored launch may carry stale records).
      final recordBaseline = await _callRecordCount(a, toxB);
      await hard(
        'call_mute_toggle_incall',
        () => _callMuteToggleIncall(a, b, toxA),
      );
      await hard('call_callee_hangup', () => _callCalleeHangup(a, b, toxA));
      await hard(
        'call_record_bubble_renders',
        () => _callRecordBubbleRenders(a, toxB, baseline: recordBaseline),
      );

      // --- 88: missed-call record (B cancels an unanswered ring). ---
      await hard(
        'call_missed_record_row',
        () => _callMissedRecordRow(a, b, toxA, toxB),
      );

      // --- VIDEO BLOCK: 85 + 87 driven together (camera toggle DURING the
      // same video call). Tally each separately. ---
      final video = await _callVideoWithCameraToggle(a, b, toxA);
      if (video.videoCall) {
        passed++;
        results['call_video_accept_hangup'] = 'PASS';
        print('[sweep] call_video_accept_hangup: PASS');
      } else {
        failed++;
        results['call_video_accept_hangup'] = 'FAIL';
        print('[sweep] call_video_accept_hangup: FAIL');
      }
      if (video.cameraToggle) {
        passed++;
        results['call_camera_toggle_incall'] = 'PASS';
        print('[sweep] call_camera_toggle_incall: PASS');
      } else {
        failed++;
        results['call_camera_toggle_incall'] = 'FAIL';
        print('[sweep] call_camera_toggle_incall: FAIL');
      }
      // Make sure no call lingers into the misc cases.
      await _ensureBothIdle(a, b);

      // --- MISC: 91 → 92 → 94 → 93 (resize last). ---
      await hard(
        'home_tabs_cycle_state_retained',
        () => _homeTabsCycleStateRetained(a, toxB),
      );
      await hard('theme_switch_chat_open', () => _themeSwitchChatOpen(a, toxB));
      await hard(
        'search_chat_history_window_open',
        () => _searchChatHistoryWindowOpen(a, toxB),
      );
      await soft('window_resize_responsive', () => _windowResizeResponsive(a));
    }
  } finally {
    // END-STATE GUARD: best-effort restore the window to a desktop width + land
    // both on chats home. The friendship is never deleted, so the registered
    // result is FRIENDS — recompute it from the live state so the runner never
    // trusts an unachieved result.
    try {
      await _ensureBothIdle(a, b);
      final sz = await a.windowSize();
      if (sz != null && sz.w < 720) {
        await a.resizeWindow(1280, sz.h);
      }
      await returnToChatsHome(a, rounds: 4);
      await b.foreground();
      await returnToChatsHome(b, rounds: 4);
    } on PermissionBlockedError catch (e) {
      print('[sweep] sweep_calls_misc end-clean: BLOCKED (${e.message})');
    } on DriveError catch (e) {
      print(
        '[sweep] sweep_calls_misc end-clean: best-effort failed: ${e.message}',
      );
    }
    try {
      endFriends = await areFriends(a, toxB) && await areFriends(b, toxA);
    } on DriveError {
      endFriends = false;
    }
    print(
      '[sweep] sweep_calls_misc RESULTS: $passed PASS / $failed FAIL / '
      '$skipped SKIP ($results) | endFriends=$endFriends',
    );
    try {
      await a.shot('/tmp/ui_calls_misc_sweep_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_calls_misc_sweep_B.png');
    } on DriveError {
      // best-effort
    }
    if (!endFriends) {
      print(
        '[sweep] sweep_calls_misc: end state is NOT friends — failing the '
        'sweep so the runner does not trust the result-state contract',
      );
    }
  }
  // FAIL if any HARD case failed OR the launch did not reach the FRIENDS end
  // state. SKIPs do not fail the sweep.
  return (failed == 0 && endFriends) ? 0 : 1;
}

// ===========================================================================
// Individual-case dispatch (each builds its OWN minimal precondition).
// ===========================================================================
/// Whether [scenario] is one of the 10 Batch-8 calls/misc cases.
bool _isCallsMiscCaseScenario(String scenario) => const {
  'call_video_accept_hangup',
  'call_mute_toggle_incall',
  'call_camera_toggle_incall',
  'call_missed_record_row',
  'call_callee_hangup',
  'call_record_bubble_renders',
  'home_tabs_cycle_state_retained',
  'theme_switch_chat_open',
  'search_chat_history_window_open',
  'window_resize_responsive',
}.contains(scenario);

/// Cases that need an A<->B friendship (the call cases + the chat-open misc
/// cases). `window_resize_responsive` is single-instance (no friendship).
bool _isCallsMiscFriendshipCase(String scenario) => const {
  'call_video_accept_hangup',
  'call_mute_toggle_incall',
  'call_camera_toggle_incall',
  'call_missed_record_row',
  'call_callee_hangup',
  'call_record_bubble_renders',
  'home_tabs_cycle_state_retained',
  'theme_switch_chat_open',
  'search_chat_history_window_open',
}.contains(scenario);

/// Run a single Batch-8 case standalone. The friendship cases establish the
/// A<->B friendship first (or reuse the runner's restored paired_for_e2e); the
/// resize case is single-instance. Returns 0/1 (or 75 for the resize SKIP).
Future<int> runCallsMiscCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario, {
  required bool bootRestored,
}) async {
  if (!bootRestored) {
    await ensureHome(a, nickA);
    await ensureHome(b, nickB, requireHomeMenu: false);
  }

  // window_resize_responsive is single-instance (drive only A).
  if (scenario == 'window_resize_responsive') {
    await ensureHome(a, nickA);
    final r = await _windowResizeResponsive(a);
    return r == null ? _realUiSkipExitCodeForBatch8 : (r ? 0 : 1);
  }

  final cToxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final cToxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (cToxA.isEmpty || cToxB.isEmpty) {
    throw DriveError('missing tox ids for $scenario: A=$cToxA B=$cToxB');
  }
  if (_isCallsMiscFriendshipCase(scenario)) {
    if (!await _establishFriendshipForSweep(a, b, cToxA, cToxB, nickA, nickB)) {
      print('[pair] $scenario: could not establish friendship');
      return 1;
    }
    await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
    await b.waitState((s) => s['isConnected'] == true, label: 'B connected');
  }

  try {
    switch (scenario) {
      case 'call_mute_toggle_incall':
        return await _callMuteToggleIncall(a, b, cToxA) ? 0 : 1;
      case 'call_callee_hangup':
        // Standalone: establish a fresh voice call (the helper re-establishes
        // one when none is live).
        return await _callCalleeHangup(a, b, cToxA) ? 0 : 1;
      case 'call_record_bubble_renders':
        // Standalone: a completed call must exist first — snapshot the baseline,
        // run a quick voice call (start → accept → callee-hangup) to produce a
        // NEW record, then assert it renders (codex P2 — require count > baseline
        // so a restored launch's stale records can't false-pass).
        {
          final baseline = await _callRecordCount(a, cToxB);
          await _callMuteToggleIncall(a, b, cToxA);
          await _callCalleeHangup(a, b, cToxA);
          return await _callRecordBubbleRenders(a, cToxB, baseline: baseline)
              ? 0
              : 1;
        }
      case 'call_missed_record_row':
        return await _callMissedRecordRow(a, b, cToxA, cToxB) ? 0 : 1;
      case 'call_video_accept_hangup':
        return (await _callVideoWithCameraToggle(a, b, cToxA)).videoCall
            ? 0
            : 1;
      case 'call_camera_toggle_incall':
        return (await _callVideoWithCameraToggle(a, b, cToxA)).cameraToggle
            ? 0
            : 1;
      case 'home_tabs_cycle_state_retained':
        return await _homeTabsCycleStateRetained(a, cToxB) ? 0 : 1;
      case 'theme_switch_chat_open':
        return await _themeSwitchChatOpen(a, cToxB) ? 0 : 1;
      case 'search_chat_history_window_open':
        return await _searchChatHistoryWindowOpen(a, cToxB) ? 0 : 1;
    }
    return 1;
  } finally {
    // Don't leak a live call into the next scenario / a reused launch.
    try {
      await _ensureBothIdle(a, b);
    } on DriveError {
      // best-effort
    }
  }
}

/// Batch-8 individual-dispatch SKIP exit code (mirrors the runner's
/// `_realUiSkipExitCode == 75`; redeclared here so the driver part file doesn't
/// depend on the runner constant).
const _realUiSkipExitCodeForBatch8 = 75;
