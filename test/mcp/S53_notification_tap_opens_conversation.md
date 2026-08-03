# S53 — Tap a message notification → opens the conversation

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online friends=1 history=seeded window=default`
**Harness mode**: peerHarness=none (the triggering inbound message needs a live peer — no single-instance inject path)
**Promotion target**: L3-pinned — the trigger is a live inbound C2C message over the DHT (no FFI test-inject shim: `testInject*` absent from `lib/` and `third_party/tim2tox/dart/lib`), and the observable is an OS notification + OS-level tap, neither L2-drivable.
**Status**: routing half covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_notification_tap.sh` (`l3_simulate_notification_tap` injects a `c2c_<pubkey>` payload onto the same `NotificationService.onSelectStream` the OS tap handler uses → real `_routeToNotificationPayload` → `_openChat` → `UikitDataFacade.currentConversation` flips to the tapped peer, asserted via `l3_dump_state.currentConversation`). Validated live 2026-06-01. The OS banner POST + OS-level tap remain OS-gated and out of scope for this gate.

## Precondition
- A online; one C2C conversation with peer B, NOT the open chat (else `_shouldSuppress` foreground+active guard, `notification_message_listener.dart:182`/`207-211`).
- That conversation NOT muted (`recvOpt == 0`, `notification_message_listener.dart:224-225`).
- macOS notification authorization for `com.toxee.app` = Granted.
- Accessibility permission for the controlling terminal (to drive the OS tap).
- A second Tox endpoint (Fixture C twin B) to send the trigger — no single-instance inject path.

## Driver
1. A: confirm A↔B row exists and is NOT the open chat; baseline `official.get_runtime_errors({})`.
2. A: move off the A↔B chat (Settings tab or another conversation) so the active-conversation guard can't apply.
3. From twin B: send ONE text to A over the DHT (only trigger path).
4. Wait ≥300 ms (BadgeService debounce) + poll cycle; assert the OS banner posted (see Notes — via `log stream`).
5. Tap the banner via `osascript` against Notification Center; assert routing.
6. Within ~1s: assert A flips to Chats tab AND the A↔B conversation is open.

## Assertions
- Step 4 (banner): NO Dart success/posted log exists — `showMessageNotification` ends at `_plugin.show(..., payload: conversationId)` (`notification_service.dart:373-384`) with no success line. Prove via `log stream --predicate 'subsystem == "com.apple.UserNotifications.UNUserNotificationCenter"'` deliver for `com.toxee.app`, AND assert the failure warn `[NotificationService] showMessageNotification failed for conv=<id>` (`notification_service.dart:390`) is ABSENT.
- Step 4: A log `[BadgeService] badge written: <N+1>` (`badge_service.dart:112`) — in-app unread advanced.
- Step 5 (tap): `_handleNotificationResponse` fires `_onSelectController.add(payload)` (`notification_service.dart:599-603`) with `c2c_<Bpubkey>` → `onSelectStream` → `NotificationMessageListener.register(onConversationTapped:)` (`notification_message_listener.dart:54-93`, `.listen` at `:65`) → `_routeToNotificationPayload` (`home_page_bootstrap.dart:919`). The add emits NO log line; the observable is the tab/conversation change.
- Step 6 (primary): `_routeToNotificationPayload` strips `c2c_` (`home_page_bootstrap.dart:925-926`) → `_openChat(peerId:<Bpubkey>)` (`:949`), which sets `_index = 0` (`home_page.dart:571`) — flips to Chats tab. Verify via snapshot: chat header = B's showName, `UiKeys.chatInputTextField` present.
- Negative: A log MUST NOT contain `Notification payload has unknown prefix:` (`home_page_bootstrap.dart:935`) nor `Notification payload empty after strip:` (`:940`).
- Step 1 vs end: `official.get_runtime_errors({})` back to baseline.

## Notes
- L3-pin: tap routing is real and wired (not a gap); the pin is the live-inbound trigger (Fixture C twin) + the OS notification/tap surface, none of which a single instance or L2 can produce. Blocked until `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md` passes; echo peer NOT a substitute (playbook §3.7).
- No posted/success log exists for `showMessageNotification` — the only banner log is the failure warn at `notification_service.dart:390`. Prove the banner via `log stream` on the UNUserNotificationCenter subsystem (same gap S58/S59 call out).
- OS-gate caveat: macOS-only; the Notification Center AppleScript scrape is brittle. If it can't drive the tap, the routing half is exercisable at L1/L2 via the `onSelectStream`→`_routeToNotificationPayload` seam, leaving only the live-banner half on L3.
- Cold-start tap variant (tap while A killed) is also wired via `consumeLaunchPayload` (`notification_message_listener.dart:97-100`) — out of scope; this covers the running-app tap.
