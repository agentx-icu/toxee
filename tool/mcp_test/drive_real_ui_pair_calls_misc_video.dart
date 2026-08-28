// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// VIDEO-call half of the calls_misc sweep (cases 85 + 87), plus the device
// capability probe that decides whether they can run at all.
//
// Split out of `drive_real_ui_pair_calls_misc.dart` along a real seam: the
// parent file drives VOICE calls and the misc shell cases, which need no
// camera and run everywhere. Everything here is conditional on the device
// actually having capture hardware — see [_videoCallEntryReason].

/// Null when this device DOES offer a video-call entry point; otherwise the
/// SKIP reason. The header's video button is gated on `useVideoCall` (from
/// `CallMediaCapabilities.supportsVideoCapture()`); hiding it on a
/// camera-less device is CORRECT product behaviour (offering it raised an
/// unanswerable system camera sheet on the iOS Simulator). The honest SKIP
/// needs TWO guards, because a missing video button alone is ambiguous:
///  1. the sibling VOICE button must be present ("hidden on purpose", not
///     "chat never opened");
///  2. `videoCaptureSupported == false` AND the env self-identifies as
///     camera-less-BY-DESIGN (`iosSimulator` or `androidEmulatorHarness`) —
///     else a real-hardware capture OUTAGE would be swallowed as SKIP. On
///     physical hardware a missing video button stays a FAILURE.
Future<String?> _videoCallEntryReason(Inst caller, String calleeId) async {
  await openChat(caller, calleeId, preferConversationList: true);
  await caller.foreground();
  if (!await caller.waitKey('chat_call_voice_button', timeoutSecs: 10)) {
    // Header not mounted at all — NOT a capability verdict. Let the normal
    // failure path report it.
    return null;
  }
  if (await caller.waitKey('chat_call_video_button', timeoutSecs: 3)) {
    return null;
  }
  final state = await caller.dumpState();
  final capable = state['videoCaptureSupported'];
  // Camera-less-BY-DESIGN environments: the iOS Simulator (self-reported)
  // and Android EMULATORS (the launcher stamps TOXEE_ANDROID_EMULATOR=true
  // only for emulator-* adb serials — a physical device only ever receives
  // it as false), surfaced as androidEmulatorHarness.
  final cameraLessByDesign =
      state['iosSimulator'] == true || state['androidEmulatorHarness'] == true;
  if (capable != false || !cameraLessByDesign) {
    print(
      '[pair] video-call entry is ABSENT but this is NOT the expected '
      'camera-less environment (videoCaptureSupported=$capable '
      'iosSimulator=${state['iosSimulator']} '
      'androidEmulatorHarness=${state['androidEmulatorHarness']}). Treating '
      'it as a real failure rather than a skip: on hardware with a camera '
      'the header must render chat_call_video_button, and a one-shot empty '
      'availableCameras() at bootstrap no longer latches for the session '
      '(CallMediaCapabilities.refreshCaptureDevices re-probes).',
    );
    return null;
  }
  return 'no video-call entry on this device: the chat header renders '
      'chat_call_voice_button but NOT chat_call_video_button, and the app '
      'itself reports videoCaptureSupported=false in a '
      'camera-less-by-design environment (iOS Simulator or Android '
      'emulator). '
      'useVideoCall is gated on CallMediaCapabilities.supportsVideoCapture() '
      '(lib/runtime/session_runtime_coordinator.dart:283); the Simulator has no '
      'camera, availableCameras() returns [] and the app logs "capture devices '
      'enumerated: count=0 deviceHasCamera=false". Re-run on hardware with a '
      'camera to exercise these two cases.';
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
    // STALE-CALL DRAIN: a LATE audio invite (voice-case retry duplicate —
    // the first invite was still in signaling flight when the retry fired)
    // can land AFTER the idle gate; its overlay eats the video tap and its
    // ring is what the wait sees (live). Drain until BOTH sides hold idle.
    for (var drain = 0; drain < 4; drain++) {
      if (await _callState(caller) == 'idle' &&
          await _callState(callee) == 'idle') {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (await _callState(caller) == 'idle' &&
            await _callState(callee) == 'idle') {
          break;
        }
      }
      print('[pair] WARN stale call before video tap — draining');
      await caller.tryTapKey('call_hangup_button', retries: 1);
      await callee.tryTapKey('call_decline_button', retries: 1);
      await _waitCallStateAny(caller, {'idle'}, timeoutSecs: 6);
    }
    // SINGLE-FIRE element-tree tap (the skill key tap double-fires; its 2nd
    // pointer replays into whatever now sits at the row coordinates).
    if (!await caller.tapKeyAt('chat_call_video_button')) {
      await caller.tapKeyCenter('chat_call_video_button', timeoutSecs: 8);
    }
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (await _waitCallStateAnyForegrounded(callee, {
      'ringing',
      'incoming',
    }, timeoutSecs: timeoutSecs)) {
      if (await _callField(callee, 'mode') == 'video') {
        return true;
      }
      print('[pair] WARN AUDIO ring during video start — clearing both');
      await callee.tryTapKey('call_decline_button', retries: 1);
      await caller.tryTapKey('call_hangup_button', retries: 2);
      await _waitCallStateAny(caller, {'idle'}, timeoutSecs: 8);
      await _waitCallStateAny(callee, {'idle'}, timeoutSecs: 8);
      continue;
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
  // In-sweep, a route pushed over the call minimizes it to the PiP card and
  // unmounts the full-screen hangup button — restore first (2026-08-24).
  await _restoreCallOverlayIfMinimized(b);
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
/// Start a VIDEO call (B calls A, A accepts → both inCall + mode==video),
/// toggle the camera off/on (case 87, `call.isVideoEnabled` flips), then hang
/// up (case 85). Returns both case outcomes for separate tallies.
Future<({bool videoCall, bool cameraToggle, String? skipReason})>
_callVideoWithCameraToggle(Inst a, Inst b, String toxA) async {
  if (!await _ensureBothIdle(a, b)) {
    print('[pair] video call: a prior call did not settle to idle');
    return (videoCall: false, cameraToggle: false, skipReason: null);
  }
  // Camera-less devices deliberately render no video button — a genuine
  // capability SKIP, not a failure (see [_videoCallEntryReason]).
  final entryProblem = await _videoCallEntryReason(b, toxA);
  if (entryProblem != null) {
    print('[pair] video call: SKIP — $entryProblem');
    return (videoCall: false, cameraToggle: false, skipReason: entryProblem);
  }
  final ringing = await _startVideoCallUntilRinging(b, a, toxA);
  if (!ringing) {
    print('[pair] video call: incoming video call never rang');
    return (videoCall: false, cameraToggle: false, skipReason: null);
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
    return (videoCall: false, cameraToggle: false, skipReason: null);
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
  return (videoCall: videoCall, cameraToggle: cameraToggle, skipReason: null);
}
