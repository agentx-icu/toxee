# S69 — Call mid-ring rejection by network drop

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=A1,B1 autoLogin=on network=B-drops-mid-ring friends=1 profileCrypt=plaintext`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — real `TOXAV_FRIEND_CALL_STATE_*` from a vanished peer over the live DHT; no L2 surface can fake it.
**Status**: covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_network_drop.sh` (A & B in an established call; A drives the reconnect path via l3_call_action network_drop → call.isReconnecting, then after the 8s grace call.state=ended/network_error). Validated live 2026-06-01. NOTE: ToxAV exposes no peer-offline callback, so the drop is driven through the app's real markReconnecting() reconnect path (the seam), not by killing the peer.

## Precondition
- Two toxee instances in separate macOS Containers — A = `com.toxee.app`, B = `com.toxee.b.app` (distinct `CFBundleIdentifier` so `SharedPreferences` don't clobber); same constraint as S26.
- A and B already paired friends (`friends=1`); both plaintext profiles, `autoLogin=on`, `MCP_BINDING=marionette`.
- Both reach Online before driving (poll `<nick>\nOnline` ≤60s per side, per S10/S26).
- A in the foreground on a chat or home screen; A's call state idle (no overlay mounted; `CallUIState.idle`).
- A controllable way to drop B mid-ring: kill the B Toxee PID (`pgrep -fl "Debug/Toxee.app"` filtered to the B container), or down B's only routable interface (S10's `sudo ifconfig <iface> down` discipline, tear-down trap to restore on exit).
- macOS Notification permission for `com.toxee.app` = Granted (required for A5; otherwise A5 is unverifiable).

## Driver
1. B: place a voice call to A via `UiKeys.chatCallVoiceButton` (`chat_call_voice_button`). Text/tooltip matching remains the fallback.
2. A: poll snapshot ≤20s for `IncomingCallView(key: ValueKey('incoming'))` (`call_overlay.dart:119-121`, `CallUIState.ringing`+`incoming`). Confirm RINGING, not accepted.
3. Drop B mid-ring while A still shows `'incoming'`: kill B's PID (or `sudo ifconfig <iface> down`). Do NOT tap Accept/Decline on A.
4. A: poll log ≤60s for teardown markers (A2); poll snapshot for `'incoming'` to disappear.
5. A: re-snapshot — assert no `'inCall'` ever mounted, call state reset to idle.

## Assertions
- A1: while ringing (Step 2), A's overlay contains `ValueKey('incoming')` (`call_overlay.dart:121`); `ValueKey('inCall')` (`call_overlay.dart:130`) absent.
- A2 (primary teardown): ≤60s after B drops, A's log contains `[FakeUIKit] _insertCallRecord: endReason=cancel,` (`AppLogger.info`, durable in `logs/app_*.log`; `fake_uikit_core.dart:108-110`, branch `cancel`→actionType 2 at `:115`) — incoming-ring-dropped record.
- A3: `'incoming'` auto-dismisses (no `ValueKey('incoming')`). A brief `ValueKey('ended')` (`call_overlay.dart:131-132`) may flash for the 2s `_endedResetTimer` (`call_state_notifier.dart:129`) before idle; tolerate `'ended'` or no overlay.
- A4 (no orphaned in-call): `ValueKey('inCall')` NEVER appears across Steps 2-5 — A was only ever ringing.
- A5 (missed-call): ring ended without local accept → A fires `_emitMissedCallNotification` (`call_service_manager.dart:648-650` / `:555-556`). Verify via NotificationService or Notification Center (playbook §7b osascript). Gated on the Notification-permission precondition.
- A6 (no orphaned ToxAV session): A's `_onCallState` ran the `stateError|stateFinished` branch — `_cleanupNativeCall()`+`_callState.endCall()` (`call_service_manager.dart:653-656`); a fresh call can ring again (idle, not stuck).
- A7 (negative): no `FATAL`, `bad_alloc`, `terminate called`, `tox_kill` in A's log; `official.get_runtime_errors({})` on A matches the Step-1 baseline.

## Notes
- L3-pin (multi-instance): needs two live toxees in separate Containers — see `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md` — but this flow is now covered by the executable Fixture C gate above rather than remaining purely blocked.
- L3-pin (media): the trigger is a real `TOXAV_FRIEND_CALL_STATE_FINISHED`/`ERROR` (`call_service_manager.dart:618-619,627`) delivered to A's `_onCallState` via the ToxAV `_av_call_state_callback` FFI (`tim2tox_ffi.dart:219`, wired at `toxav_service.dart:493`); media spike TBD (ToxAV call lifecycle under automation).
- `[CallServiceManager] _onCallState: friendNumber=…, state=…` (`call_service_manager.dart:623`) is **`debugPrint`-gated** (debug-only) — use the durable `AppLogger.info` `[FakeUIKit] _insertCallRecord` line (A2) as the load-bearing marker, not the debug trace.
- Ringing-drop (callee never accepted) maps to `endReason='cancel'` (incoming) — NOT `'network_error'` (`call_service_manager.dart:639-641`). `'network_error'` is the inCall reconnect-grace path only (`markReconnecting`, `call_service_manager.dart:267-304`); don't assert it here.
