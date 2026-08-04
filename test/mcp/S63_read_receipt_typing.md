# S63 — Read receipt / typing indicator

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(paired,both online) history=seeded(c2c_<peer>)`  (the `paired_for_e2e` composition — blocked on the multi-instance spike)
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because it needs two live toxees on a real DHT plus the Tox-level typing/receipt event surface (`tox_self_set_typing` / `setFriendTypingCallback`, custom-message receipts) — neither half is L2-deterministic.
**Status**: typing leg covered (`run_fixture_c_typing.sh`, validated live). Read-receipt: the send path is now ENABLED (`_sendReceipt` early-return removed; `receipt:` control messages are sent on inbound), but live testing (`run_fixture_c_receipt.sh`) CONFIRMED the sender's message does not flip `isReceived` — ROOT CAUSE: the receipt references a msgID that does not correlate across instances (the sender's local msgID is not round-tripped with the C2C message), so `_handleReceipt` finds no match. Needs a tim2tox msgID round-trip fix to fully land.

## Precondition
- Two toxee instances in separate macOS Containers (distinct `CFBundleIdentifier`) so `SharedPreferences`/sandbox don't clobber — same discipline as S26
- Both plaintext profiles, `autoLogin=true`, A and B paired (each in the other's `local_friends_*`), both reach Online (poll `<nick>\nOnline` ≤60s per side)
- A seeded `c2c_<peer>` conversation open on both sides; `MCP_BINDING=marionette`

## Driver (the flow this WOULD exercise once the surface is wired)
> Not runnable today — there is no typing UI consumer and `_sendReceipt` early-returns (see Notes). Recorded as the intended L3 flow for when both halves land.

### (a) Typing indicator
1. On A: open conversation with B (snapshot → tap row)
2. On B: open conversation with A, then enter a few characters into the message input (no send)
3. On A: a "typing…" affordance would appear in the conversation header/footer within ~5s
4. On B: clear the input (or wait out the 3s expiry)
5. On A: the indicator would clear

### (b) Read receipt
6. On A: send "ping" to B
7. On B: open/read the conversation (mark-viewed path)
8. On A: a "read" marker would appear on the "ping" bubble within ~10s

## Assertions (aspirational — gated on the wiring in Notes)
- A1 (typing send): B's keystroke would call `FfiChatService.sendTyping` → FFI `tim2tox_ffi_set_typing` → `tox_self_set_typing` (`ffi/tim2tox_ffi.cpp:1351,1364`) — surface exists, no caller today
- A2 (typing recv): A's poll log would show a `typing:<uid>:1` line parsed in `ffi_chat_service.dart:1501-1510`; `FakeIM._scanTyping` emits `FakeTypingEvent` (`lib/sdk_fake/fake_im.dart:760-767`)
- A3 (typing UI): A's conversation surface would render a "typing…" indicator and clear it on `typing:<uid>:0` — no consuming widget exists yet
- A4 (read marker): A's "ping" bubble would show a "read" marker after B reads, via `_handleReceipt(msgID,'read',…)` → `onRecvC2CReadReceipt` (`tim2tox_sdk_platform.dart:1946`) — blocked while `_sendReceipt` is disabled
- A5: `official.get_runtime_errors({})` empty on both sessions vs baseline

## Notes
- **Primary blocker — neither half is wired today** (this is what makes the scenario `informational only`, independent of multi-instance). Typing: outbound `sendTyping`/`setTyping` has **zero callers** in `lib/` or the Platform layer (no input-field listener), and no UIKit widget consumes `onTyping`/`FakeTypingEvent` to render an indicator — the FFI/event surface exists but is dead. A1/A2 are testable at the tim2tox layer; A3 has no UI to assert against.
- **Read receipts are explicitly disabled**: `_sendReceipt` returns early under `// TODO: 暂时屏蔽发送已读回执` (`ffi_chat_service.dart:5190-5191`), so the `'read'` receipt never goes over the wire. `onRecvC2CReadReceipt` (`tim2tox_sdk_platform.dart:1946`) only fires for `isReceived` (delivery), not `isRead` — so A4 cannot pass. The 'received' delivery half is the closest live thing.
- Also blocked on Fixture C — two live toxees on the DHT. See `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`.
- Do not write Driver assertions as if these features exist; promote to `covered` only after both the C++/FFI surface is re-enabled AND a UI consumer + UiKeys land (`chat_message_input_field`, a typing-indicator key, a per-bubble read-marker key).
