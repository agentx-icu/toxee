# S76 — Hang up an active call

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=A autoLogin=on network=online friends=1`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — ending a *connected* call needs two live toxees + a real ToxAV media leg; no L2 surface produces a real `inCall`.
**Covered-by**: `test/ui/call/in_call_controls_real_ui_test.dart` (UI half, L1 widget-layer); `tool/mcp_test/run_fixture_c_call.sh voice` (L3 two-process teardown).
**Status**: UI half covered at the widget layer (L1) — `test/ui/call/in_call_controls_real_ui_test.dart` pumps the real `CallOverlay` (its `ListenableBuilder` + `AnimatedSwitcher` view switching) from a connected `inCall` (A1) and taps the real `UiKeys.callHangupButton`, asserting the tap dispatches `hangUp` exactly once through the production `CallOverlayManager` interface (manager = test double delegating to the same `CallStateNotifier.endCall()` the production `CallServiceManager` calls; the real teardown body stays on the 2proc gate), the call ends, and the real overlay reflects it — `ValueKey('inCall')` leaves, the brief `ValueKey('ended')` affordance (`callEnded`) shows, then the overlay auto-resets back to its child (A4). The connected two-process teardown (A2 call record, A6 peer `stateFinished`) stays L3-pinned and is exercised by `tool/mcp_test/run_fixture_c_call.sh voice` (from `inCall`, A `l3_call_action hangup`; both A and B return to `ended`/`idle`; validated live 2026-06-01).

## Precondition
- A signed in, online; one C2C with paired friend B (`friends=1`); both Online.
- A and B in a **connected** call: A's overlay shows `ValueKey('inCall')` (`call_overlay.dart:130`), duration ticking.
- Two toxees, distinct `CFBundleIdentifier` (A=`com.toxee.app`, B=`com.toxee.b.app`); same as S67/S69.
- macOS mic TCC pre-granted both bundles (`permission_helper.dart:30-35`).
- `MCP_BINDING=marionette`.

## Driver
1. Baseline `official.get_runtime_errors({})`; confirm `ValueKey('inCall')` present, duration > 2s.
2. Tap hang-up via `UiKeys.callHangupButton` (`call_hangup_button`). Snapshot-ref / label matching remains the fallback. Drives `manager.hangUp()` (`call_service_manager.dart:1000`).
3. Poll log + snapshot ≤5s for record + overlay dismissal.

## Assertions
- A1: Step 1, `ValueKey('inCall')` present; `outgoing`/`incoming` absent.
- A2: after tap, A's log has `[FakeUIKit] _insertCallRecord: endReason=hangup,` with `duration=<N>` `N>0` (`fake_uikit_core.dart:108`); via `_emitCallRecord('hangup')` (`call_service_manager.dart:1016-1018`).
- A3: A calls `_avService.endCall` (`call_service_manager.dart:1033`) then `_callState.endCall()` (`:1037`); duration timer cancelled.
- A4: `inCall` gone; brief `ValueKey('ended')` (`call_overlay.dart:132`) may flash ~2s — tolerate `'ended'` or no overlay.
- A5 (negative): `endReason=hangup`, NOT `cancel`/`timeout`/`reject`/`remote_hangup` (peer path `:637`).
- A6: B sees `stateFinished`/`stateError` (`call_service_manager.dart:627`) → B emits own `endReason=hangup`, returns idle.
- A7: `get_runtime_errors` matches baseline; no `FATAL`/`bad_alloc`/`tox_kill`.

## Notes
- L3-pin: connected call still needs two live toxees (Fixture C, `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`), but the executable gate above means the scenario is no longer just blocked.
- L3-pin (media): real leg needs ToxAV audio flowing (`SENDING_A|ACCEPTING_A`, `:664`); media spike TBD.
- Record deduped per call by `_callRecordEmitted` (`:195`) — exactly one per hang-up.
- `callHangupButton` is now available; remaining assertions are about connected-call teardown rather than locating the control.
- `_onCallState` (`:623`) is `debugPrint`-gated — use durable A2 line as marker.
