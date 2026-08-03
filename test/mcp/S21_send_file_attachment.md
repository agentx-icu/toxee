# S21 — Send a file/image attachment to a friend

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(paired, both online) history=empty` + staged file on A
**Harness mode**: peerHarness=none (delivery needs a second toxee, not the echo peer — see Notes)
**Promotion target**: L3-pinned because delivery confirmation requires a second live toxee receiving over the real Tox DHT (Fixture C, `UI_TEST_LAYERING.en.md` §3/§6).
**Covered-by**: `test/ui/chat/media_message_bubbles_real_ui_test.dart` (UI half — the file message renders the real file bubble with filename + formatted size at both mobile and desktop sizes, and a tap drives the real `_openFile()` dispatch; the data-layer send/arrival stays gated by the two-process artifact below)
**Status**: covered by the two-process Fixture C gate `tool/mcp_test/run_fixture_c_file.sh` (A sends a small file via `l3_send_file` content→temp; asserts a sender-side file message exists with `filePath` basename==fileName and non-empty `mediaKind`; validated live 2026-06-01), AND at the widget layer (L1). `media_message_bubbles_real_ui_test.dart` pumps the real `TencentCloudChatMessage` list with a fixture file message and asserts the real file bubble renders the filename + the formatted size (`getCurrentFileFileSize`, e.g. `10 KB`) at both mobile (400x800) and desktop (1400x900); tapping the bubble drives the real `onTapUp → _openFile()` path, captured at the production `OpenFile.open` boundary via a `@visibleForTesting` seam on the file element widget (so it does not invoke the platform open plugin in the test). (`l3_send_file` writes a sandbox-safe temp source so there's no cross-sandbox source-readability problem.)

## Precondition
- A, B in separate macOS Containers with distinct `CFBundleIdentifier` (A=`com.toxee.app`, B=`com.toxee.b.app`) — same two-sandbox discipline as S26.
- A and B already friends and both Online (poll sidebar `<nick>\nOnline` ≤60s per side); else `sendFile` takes the offline-queue branch (`ffi_chat_service.dart:5717-5730`).
- Both plaintext profiles, `autoLogin=true`, `MCP_BINDING=marionette`.
- Staged small image at `/tmp/toxee_test/s21_attach.png` (< image/auto-accept limits so B auto-accepts).
- Send is wired: `enableSendFile: true` (`home_page_bootstrap.dart:374`); attach → `_sendMedia` (`home_page.dart:577`) → `FilePicker.platform.pickFiles` (`:587`) → `sendFile` (`:597`).

## Driver
1. On A: poll sidebar `\nOnline` ≤60s; baseline `official.get_runtime_errors({})`.
2. On A: tap `UiKeys.sidebarChats`; open B's conversation row (no `conv_<friendId>` key — match ref/label).
3. On A: open desktop attach bar (`_buildDesktopInputOptions`, `home_page.dart:675`); tap **Photo** (`:687-694`).
4. Inject path via the (not-yet-built) `pickFiles` test-override; `_sendMedia` calls `sendFile("<toxB>", "/tmp/toxee_test/s21_attach.png")` and shows the `"$label sent"` SnackBar (`:598`).
5. On B: poll snapshot ≤60s for the received image bubble. Do NOT `sleep`.

## Assertions
- A1: A takes the online-send branch, not offline — no `_queueOfflineFile` for this peer (`ffi_chat_service.dart:5726`). If present, fixture is wrong (B not Online).
- A2: A surfaces an outgoing bubble — `sendFile` builds local `ChatMessage(isSelf:true, …)` + `_appendHistory`.
- A3: FFI send succeeded — `sendFileNative` returned `> 0` (`:5741-5744`); `"$label sent"` SnackBar MUST appear, `failedToSendFile` (`home_page.dart:641`) MUST NOT.
- A4 (B-side): within 60s B's snapshot shows the image bubble; B auto-accepts: `Auto-accepting image file` (`:2246`) → `acceptFileTransfer completed successfully` (`:2257`).
- A5: file lands under B's `AppPaths.getAccountFileRecvPath(toxB)` (`app_paths.dart:345`, wired `account_service.dart:278`) — non-empty `<toxA>_<kind>_<num>_s21_attach.png`.
- A6: `official.get_runtime_errors({})` matches Step-1 baseline both sessions.

## Notes
- Native macOS picker is undriveable by MCP (§7b): `_sendMedia` has no `filePathOverride` seam today (unlike S9's `login_page_controller.dart:340`). Required source change: add `@visibleForTesting filePathOverride` to `_sendMedia` bypassing `pickFiles`, mirroring S9 — until then Step 4 is undriveable.
- Echo peer is NOT a substitute (§3.7): it echoes c2c text, not file transfers; cannot unblock S21.
- Multi-instance block: delivery needs a real second toxee on the DHT (`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`).
- Wanted UiKeys (none today): attach/Photo option key, `conv_<friendId>`, `messageItem_<msgId>`.
- C2C only — `_sendMedia` rejects groups with `sendingToGroupsNotSupported` (`home_page.dart:583`).
