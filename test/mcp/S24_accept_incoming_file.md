# S24 — Receive an (auto-accepted) incoming file

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(paired, both online) history=empty` + staged file on B
**Harness mode**: peerHarness=none (the sender must be a second toxee, not the echo peer — see Notes)
**Promotion target**: L3-pinned because receiving needs a second live toxee (B) sending over the real Tox DHT; the `file_request → acceptFileTransfer → file_done` pipeline can't be stood up from an on-disk seed (Fixture C, `UI_TEST_LAYERING.md` §3/§6).
**Covered-by**: `test/ui/chat/media_message_bubbles_real_ui_test.dart` (UI half — a received file message renders the real file bubble with filename + size at both mobile and desktop sizes, and a tap drives the real open-file dispatch; the auto-accept/arrival pipeline stays gated by the two-process artifact below)
**Status**: covered by the two-process Fixture C gate `tool/mcp_test/run_fixture_c_file.sh` (B AUTO-accepts the small inbound file under its size limit; asserts a non-self file message arrives with a written non-empty `filePath`; validated live 2026-06-01), AND at the widget layer (L1). `media_message_bubbles_real_ui_test.dart` renders a received (non-self) file bubble with its filename + formatted size and drives the real `onTapUp → _openFile()` open dispatch (captured at the `OpenFile.open` boundary via a file-element seam) at both mobile (400x800) and desktop (1400x900) — i.e. the recipient-side bubble + open affordance. The native `file_request → acceptFileTransfer → file_done` pipeline + disk landing remain the two-process gate's responsibility. Explicit large-file/manual accept (a dedicated `l3_accept_file` over `acceptFileTransfer`) remains a follow-up.

## Precondition
- A (receiver), B (sender) in separate macOS Containers with distinct `CFBundleIdentifier` (A=`com.toxee.app`, B=`com.toxee.b.app`) — same two-sandbox discipline as S26.
- A and B already friends and both Online (poll sidebar `<nick>\nOnline` ≤60s per side); else B's send takes the offline-queue branch (`ffi_chat_service.dart:5717-5730`).
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette`.
- Staged file on B at `/tmp/toxee_test/s24_incoming.png` for B to send.
- A's recv target: `AppPaths.getAccountFileRecvPath(toxA)` (`app_paths.dart:345`), wired into A's `FfiChatService` as `fileRecvPath:` (`account_service.dart:238,278`; native init `ffi_chat_service.dart:1114-1115`).

## Driver
1. On A: poll sidebar `\nOnline` ≤60s; baseline `official.get_runtime_errors({})`.
2. On B: open conversation with A, attach + send `/tmp/toxee_test/s24_incoming.png` (this is the S21 send flow on B; same `pickFiles` test-override blocker — see Notes).
3. On A: tap `UiKeys.sidebarChats`; open B's conversation row.
4. On A: poll snapshot ≤60s for the incoming bubble. **No accept tap** — A auto-accepts; "accept" is asserted via log markers + disk landing, not a button.

## Assertions
- A1: A receives the request — `file_request event received` (`ffi_chat_service.dart:2128`) → `Created pending message: msgID=…` (`:2201`); inbound bubble surfaces.
- A2 (auto-accept): small image → `Auto-accepting image file: s24_incoming.png` (`:2246`) → `acceptFileTransfer completed successfully` (`:2257`). Small non-image → `Auto-accepting small file` (`:2249`). Large file → `[FakeMessageProvider] P1-5 auto-accept large file` (`fake_msg_provider.dart:119`).
- A3 (completion): `file_done event START` (`:2280`) → `file_done event parsed: uid=<toxB>, …pathLength=<n>` (`:2298`) → `file_done event path: <path>` (`:2299`), `<path>` under A's file_recv dir (on-disk landing is the A4 proof).
- A4 (disk landing — primary): non-empty file under `getAccountFileRecvPath(toxA)` matching `<toxB>_<fileKind>_<fileNumber>_s24_incoming.png` (`fake_msg_provider_file_progress.dart:78`).
- A5 (UI): bubble flips pending→complete; `localUrl` set from `/file_recv/` (mapping recovery `fake_msg_provider_mapping.dart:357`/`228`).
- A6: `official.get_runtime_errors({})` matches Step-1 baseline both sessions.
- Negative grep: no `_markFileTransferFailed` (`:2897`/`2969`); no `acceptFileTransfer failed` (`:2260`).

## Notes
- Accept is AUTO, not manual: small files/images auto-accepted inside the request handler (`ffi_chat_service.dart:2242-2257`); large files auto-accepted by `FakeMessageProvider`'s P1-5 listener (`fake_msg_provider.dart:116-125`). Manual "tap to accept" UI is an unbuilt `TODO(P1-5)` (`fake_msg_provider.dart:114`) — when it lands, add an accept-button UiKey and convert Step 4 to a real tap.
- Multi-instance block: needs a real second toxee on the DHT to originate the send (`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`).
- Echo peer is NOT a substitute (§3.7): echoes c2c text, cannot originate a file transfer.
- Driving B's send (Step 2) hits the S21 `pickFiles` test-override blocker on the B instance.
- Wanted UiKeys (none today): `incomingFileAcceptButton` (only once P1-5 UI exists), `conv_<friendId>`, `messageItem_<msgId>`.
