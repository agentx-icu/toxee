# S77 — Missed incoming call → call record + notification

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=A autoLogin=on network=online friends=1`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — an inbound ring that ages out needs a second live toxee placing a real ToxAV call + a real OS notification gate; neither hermeticizable in L2.
**Status**: covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_missed_call.sh` (A calls B, B sees the incoming ring and never answers, A cancels the unanswered ring → both end = a missed incoming call on B). Validated live 2026-06-01. NOTE: the native ToxAV ring has no auto-timeout, so a missed call is realized by caller-cancel (not a 30s ring timeout).

## Precondition
- A signed in, online; one C2C with paired friend B (`friends=1`); both Online.
- B places an **incoming voice call** to A; A **never answers** (ring ages out / B cancels).
- Two toxees, distinct `CFBundleIdentifier` (A=`com.toxee.app`, B=`com.toxee.b.app`); same as S67/S69.
- A foreground, call state idle (`CallUIState.idle`).
- macOS Notification permission for `com.toxee.app` = Granted (required for A4).
- macOS mic TCC pre-granted both bundles (`permission_helper.dart:30-35`); `MCP_BINDING=marionette`.

## Driver
1. Baseline `official.get_runtime_errors({})`.
2. B: place a voice call to A (no key — tap by label/tooltip, §6b).
3. A: poll snapshot ≤15s for `ValueKey('incoming')` (`call_overlay.dart:121`). Confirm RINGING; do NOT tap Accept/Decline.
4. Let the ring age out / B cancels — do not interact on A.
5. Poll A's log ≤60s for missed record + notification markers; poll snapshot for `'incoming'` dismiss.

## Assertions
- A1: Step 3, A's overlay has `ValueKey('incoming')`; `inCall` (`call_overlay.dart:130`) absent.
- A2: ≤60s, A's log has `[FakeUIKit] _insertCallRecord: endReason=cancel,` (`fake_uikit_core.dart:108`); via `_emitCallRecord('cancel')` on unanswered incoming ring (`call_service_manager.dart:639-642` native / `:545-554` signaling).
- A3 (missed): unanswered incoming → `wasIncoming` true → `_emitMissedCallNotification()` (`call_service_manager.dart:648-649` / `:555-556`). `'reject'` is NOT this path (`:553` excludes it).
- A4 (OS notif): A fires `showMissedCallNotification` (`call_service_manager.dart:217` → `notification_service.dart:518`); title "Missed call"/body=displayName (`:538`). No success log — assert via Notification Center / `log stream` (§7b, S58), and `[NotificationService] showMissedCallNotification failed` (`:574`) ABSENT.
- A5: `'incoming'` auto-dismisses; brief `ValueKey('ended')` (`call_overlay.dart:132`) may flash ~2s — tolerate `'ended'` or no overlay.
- A6 (negative): `endReason=cancel`, NOT `hangup`/`timeout`/`reject`. Outgoing `'timeout'` does NOT notify (`:645-650` notifies only `wasIncoming`).
- A7: `get_runtime_errors` matches baseline; no `FATAL`/`bad_alloc`/`tox_kill`.

## Notes
- L3-pin: B must place a real inbound ToxAV call from a second live toxee (Fixture C, `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`); `_onIncomingCall` fires only from real `call_cb_` (S67). Stays `blocked`.
- L3-pin (media + OS notif): inbound ring opens a real ToxAV invite (media spike TBD); banner needs Notification permission (A4-gated).
- Sibling of S70 (outgoing `'timeout'`, non-notifying mirror) and S58 (notif via `log stream`).
- Record deduped per call by `_callRecordEmitted` (`:195`) — one per missed call.
- `_onCallState` (`:623`) is `debugPrint`-gated — use durable A2 line as marker.
