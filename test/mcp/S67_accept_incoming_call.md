# S67 — Accept incoming call

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B separate sandboxes) autoLogin=on network=online friends=1(paired,both online)`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — needs two live toxees on a real DHT + real ToxAV media + OS mic gate, none hermeticizable in L2.
**Status**: covered by executable Fixture C call gate — `tool/mcp_test/run_fixture_c_call.sh voice` (B `l3_call_action accept`; both A and B reach `call.state==inCall`). Validated live 2026-06-01.

## Precondition
- Two toxee instances in separate macOS Containers with distinct `CFBundleIdentifier` (A = `com.toxee.app`, B = `com.toxee.b.app`) so `SharedPreferences` don't clobber.
- A and B already paired: `Prefs.local_friends_<toxA16>` on A contains normalized toxB, and the mirror holds on B (Fixture C "paired_for_e2e" snapshot, §8 of `doc/architecture/UI_TEST_LAYERING.md`).
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette`.
- Both reach Online before driving (poll `<nick>\nOnline` ≤60s per side); A's friend-list row for toxB shows online.
- macOS Microphone permission for BOTH `com.toxee.app` and `com.toxee.b.app` = Granted (mic-capture gate is at the OS audio-capture layer, NOT the Dart permission_handler call — see Notes).

## Driver
1. B: open C2C with toxA, tap `UiKeys.chatCallVoiceButton` (`chat_call_voice_button`) → B's ToxAV `startCall`.
2. A: wait ≤15s for `IncomingCallView` (`incoming_call_view.dart:11`); dock has `ValueKey('incoming-call-actions')` (`:44`).
3. A: tap Accept via `UiKeys.callAcceptButton` (`call_accept_button`). Text match on `接受` / `Accept` remains the fallback.
4. Accept → `RingingCallManager.acceptCall()` → `CallServiceManager.acceptCall()` (`call_service_manager.dart:936`): native `_avService.answerCall` (`:954`) or signaling `_callBridge.acceptInvitation` (`:968`).
5. Poll A ≤10s for `InCallView`; poll B ≤10s for its in-call transition.

## Assertions
- A1: ≤15s, A logs `[CallStateNotifier] startRinging: mode=CallMode.audio, direction=CallDirection.incoming` (`call_state_notifier.dart:95`, debug build) and `ValueKey('incoming-call-actions')` present in snapshot.
- A2 (native): on accept A logs `[ToxAVService] answerCall: friendNumber=<n> …` then `answerCall succeeded` (`toxav_service.dart:550-565`); MUST NOT log `answerCall failed`.
- A2b (signaling, `inviteID` not `native_av_*`): `acceptInvitation` → same `answerCall succeeded`, then `onCallStateChanged(inviteID, CallState.inCall)` (`call_bridge_service.dart:245,250`).
- A3: A in-call via `InCallView` surface + ticking duration timer — `enterCall()` (`call_service_manager.dart:961`/`:528`) emits NO log (`call_state_notifier.dart:110-119`), so assert the surface, not a string.
- A4: A logs `[CallServiceManager] _onCallState: friendNumber=<n>, state=<bitfield>` with `SENDING_A`(4)/`ACCEPTING_A`(16) set (`call_service_manager.dart:623,664`).
- A5: incoming dock gone post-accept; ringtone stops (`_ringtone.stop()`, `:960`).
- A6 (bidirectional): ≤10s B leaves ringing, `_onCallState` sees `SENDING_A|ACCEPTING_A` → `enterCall()` (`:664-670`); B's `InCallView` surfaces.
- A7: `official.get_runtime_errors({})` empty vs baseline, both sessions.
- A8: no `[ToxAVService] answerCall: initialization failed` (`toxav_service.dart:556`) on A.

## Notes
- Still L3-pinned on a second live toxee and a real inbound ToxAV callback; no on-disk inject can simulate `_onIncomingCall` (`call_service_manager.dart:573`) because it fires only from a real `call_cb_` (`third_party/tim2tox/source/ToxAVManager.cpp:76-77`). The executable Fixture C gate above now covers that dependency in practice.
- The remaining caveat is the live audio environment itself: the connected transition still needs the ToxAV stack actually answering and media flowing (`SENDING_A|ACCEPTING_A`), so TCC/pre-granted capture stays part of the precondition.
- Mic gate: `CallPermissionHelper.shouldRequestRuntimePermission` is `false` on macOS (`permission_helper.dart:30-35`) so Dart never prompts, but the OS gates real capture in `AudioHandler.startCapture`. Pre-grant BOTH bundles (B is the caller and also captures): `tccutil reset Microphone com.toxee.app` and `tccutil reset Microphone com.toxee.b.app`, then approve each once. A denied OS mic is silent audio, not a Dart error.
- Key status: `chatCallVoiceButton`, `callAcceptButton`, and `callHangupButton` are now available. The remaining blockers are live media/runtime concerns, not control discovery.
- Sibling of S68 (decline) — same fixture shape, same two blocks.
