# S70 — Call duration timeout (outgoing ring no-answer)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=A autoLogin=on network=online friends=1`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — real 30s signaling no-answer timeout fires only against a live online peer over the DHT; no L2 surface can age out a real invite.
**Status**: the "no auto-end" INVARIANT is now gated (2026-06-08) — N/A reclassified as an executable invariant. The product has NO call-duration/inactivity timeout that auto-ends an established call (`callDuration` is display-only). `test/call/call_duration_no_timeout_test.dart` locks this with `fakeAsync` over the zero-dependency `CallStateNotifier`: `enterCall()` then elapse 10 min + 2 h → `callDuration` increments to match AND `state` stays `CallUIState.inCall` (no auto-end), and only an explicit `endCall()` ends it; a second test proves `startRinging()` alone never starts the duration clock (the 1s timer is gated on `enterCall()`, call_state_notifier.dart:114). So a regression that adds a max-duration auto-end ONTO the `CallStateNotifier` (or breaks the increment) is caught — SCOPED to that layer; an auto-end wired above it (CallServiceManager / AV layer) is out of this gate's reach (codex). The two REAL call timeouts remain covered elsewhere: unanswered-ring = S77 (`run_fixture_c_missed_call.sh`), network-drop 8s reconnect grace = S69 (`run_fixture_c_network_drop.sh`). Shared desktop+mobile.
**Covered-by**: `test/call/call_duration_no_timeout_test.dart`

## Precondition
- A signed in, online; one C2C conversation with **friend B (paired)**; B's toxee online on DHT (twin), but B **never answers** — online-but-silent so the invite ages out instead of auto-cancelling on offline (`call_service_manager.dart:480-488`).
- This scenario drives an **outgoing voice call** from A to B (audio invite, no video).
- `useCallKit == true` — else the `Icons.call` voice button is not rendered (gated at `third_party/chat-uikit-flutter/.../tencent_cloud_chat_message_header_actions.dart:25`, `Icons.call` at `:29`).
- macOS mic TCC for `com.toxee.app` pre-granted (desktop takes no in-app prompt; `permission_helper.dart:32`).
- `MCP_BINDING=marionette`.

## Driver
1. Baseline `official.get_runtime_errors({})`; poll snapshot ≤60s for sidebar `<nicknameA>\nOnline`.
2. Tap `UiKeys.sidebarChats` (`sidebar_chats_tab`); snapshot → tap B's conversation row.
3. Tap the voice button by snapshot ref (header `Icons.call`); no key exists yet (see Notes). This drives `invite(timeout: 30)` (`tuicallkit_adapter.dart:141-145`).
4. Poll snapshot ≤5s for `OutgoingCallView(key: ValueKey('outgoing'))` (`call_overlay.dart:122`) — confirm RINGING outgoing, NOT inCall.
5. Do NOT tap hang-up. Wait out the 30s native ring window; poll log + snapshot until the overlay dismisses (allow ≥35s).

## Assertions
- A1: at Step 4, overlay shows `ValueKey('outgoing')` / `ValueKey('outgoing-call-actions')` (`outgoing_call_view.dart:45`); `ValueKey('inCall')` (`call_overlay.dart:130`) absent — never answered.
- A2 (primary timeout): ≤35s after invite, A's log contains `[FakeUIKit] _insertCallRecord: endReason=timeout,` (`AppLogger.info`, durable in `logs/app_*.log`; `fake_uikit_core.dart:108-110`, `'timeout'`→actionType 5 at `:121-122`). Path: native `SignalingInvitationTimeout` → `onInvitationTimeout` (`call_bridge_service.dart:150-159`, `endReason: 'timeout'`) → `_onCallStateChanged` ended branch → `_emitCallRecord('timeout')` (`call_service_manager.dart:538-554`).
- A3: `ValueKey('outgoing')` auto-dismisses with no local hang-up. A brief `ValueKey('ended')` (`call_overlay.dart:132`) may flash for the 2s `_endedResetTimer` (`call_state_notifier.dart:129`) before idle; tolerate `'ended'` or no overlay.
- A4 (negative — wrong reason): record is `endReason=timeout`, NOT `cancel`/`reject`/`network_error`. `'cancel'` is the **incoming** ring-drop path (`call_service_manager.dart:641`); `'network_error'` is the inCall reconnect-grace path only.
- A5: `official.get_runtime_errors({})` matches Step-1 baseline; no `FATAL`/`bad_alloc`/`tox_kill` in A's log.

## Notes
- Two timeout sources map to `'timeout'`: the signaling 30s no-answer (`onInvitationTimeout`, the mechanism here) and the ToxAV ringing `STATE_FINISHED`/`STATE_ERROR` branch (`call_service_manager.dart:639-641`). Both end the OUTGOING ring; A2's record is the load-bearing marker for either.
- Fixture C: needs a second online toxee that stays silent — see S69 / `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md` (distinct `CFBundleIdentifier`). If B is offline the call auto-cancels in ~800ms as `'cancel'`, NOT `'timeout'` — wrong scenario.
- Media spike: the silent leg still opens a ToxAV invite; mic gate + ToxAV lifecycle under automation are unvalidated (playbook §5a, §7b).
- `[CallStateNotifier] startRinging` (`call_state_notifier.dart:95`) and `[CallServiceManager] _onCallState` (`:623`) are `debugPrint`-gated — debug-only, not release contracts.
- `chatCallVoiceButton` and `callHangupButton` are now available. Snapshot-ref / label matching remains only as fallback.
