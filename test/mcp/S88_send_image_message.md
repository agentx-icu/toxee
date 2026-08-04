# S88 — Send an image message to a friend

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(paired, both online) history=empty` (the `paired_for_e2e` snapshot)
**Harness mode**: peerHarness=none (delivery + receive-side `mediaKind` classification need a second live toxee, not the echo peer — see Notes)
**Promotion target**: L3-pinned because the image bubble + `mediaKind: "image"` only materializes once a second live toxee receives the transfer over the real DHT and the receive path classifies it (Fixture C, `UI_TEST_LAYERING.md` §3/§6). Sibling of S21 (generic file send) / S24 (auto-accept receive) — S88 is the IMAGE specialization (feature **D3**, 图片消息发送, `FakeMsgProvider.sendImage` reuses `sendFile`).
**Runner gate**: `tool/mcp_test/run_fixture_c_image.sh` (→ `drive_fixture_c_file.dart --image`)
**Covered-by**: `test/ui/chat/media_message_bubbles_real_ui_test.dart` (UI half — the image bubble renders the real `Image` widget at both mobile and desktop sizes; the data-layer `mediaKind: "image"` classification stays gated by the two-process artifacts below)
**Status**: covered at the data layer by the two-process gate AND at the widget layer (L1). The two-process gate `run_fixture_c_image.sh` reuses the S21/S24 paired harness with the `--image` mode of `drive_fixture_c_file.dart`: A `l3_send_file`s a `.png` and the receiver leg requires `mediaKind == "image"` (the default `.txt` path is byte-identical, so S21/S24 cannot regress); **live-validation of that two-process leg is still owed** (analyzer-clean + static-validated; not yet run on a live paired DHT this session). The UI half is now covered at the widget layer (L1): `media_message_bubbles_real_ui_test.dart` pumps the real `TencentCloudChatMessage` list with a fixture image message whose local path points at a real PNG and asserts the real image bubble (`Image.file`) materializes at both mobile (400x800) and desktop (1400x900). The tap→open-preview half (onTapUp → `showImage()` → `showDialog(MessageViewer)`) could NOT be driven at the widget layer: the image bubble only mounts its tappable `GestureDetector`+`Image` after an async image load, and the lazy `FlutterListView` then keeps that subtree offstage / non-hit-testable (four pointer-dispatch strategies all fail to reach `onTapUp`, verified via a temporary seam); it remains a two-process / screenshot concern, as this spec already records (no `messageItem_<msgId>` ValueKey). The sibling file/sound bubble tap handlers ARE driven at L1 in the same file, demonstrating the equivalent media-bubble onTapUp mechanism.

## Precondition
- `paired_for_e2e` restored: A and B in separate macOS Containers (distinct `CFBundleIdentifier`), already friends, both plaintext, `autoLogin=true` — same base `run_fixture_c_file.sh` uses (`tool/mcp_test/run_fixture_c_file.sh:23-24`).
- Both reach Online before driving (the driver's `waitForFriendOnline` both directions, `drive_fixture_c_file.dart:84-85`).
- A small `.png` payload (inline `content` → the app writes a sandbox-safe temp source, `l3_debug_tools.dart:1897-1905`) under the 50 MiB image auto-accept cap (`ffi_chat_service.dart:638`) so B auto-accepts without manual UI.
- `MCP_BINDING=marionette`; two VM service URIs (one per process).

## Driver
Reuses the `drive_fixture_c_file.dart` sequence verbatim, with an `.png` fileName and an image-tightened receiver assertion:
1. Connect A + B; `ensureReady` both (boots restored accounts); `waitForConnected`; `waitForFriendOnline` both ways; resolve `toxA`/`toxB`.
2. Build `fileName = s88-<nonce>.png` + inline `content` (any bytes — classification is by EXTENSION, see Assertions).
3. A: `l3_send_file(userId: toxB, fileName, content)` (`l3_debug_tools.dart:1913-1917`).
4. Send leg (S21-shape): poll A's C2C(toxB) for an `isSelf` message whose `filePath` basename == `fileName` and `mediaKind` non-empty (`drive_fixture_c_file.dart:255-281`).
5. Image receive leg (the S88 delta): poll B's C2C(toxA) ≤180s for a non-self message with our `.png` and `mediaKind == "image"`.

## Assertions
- A1 (send leg): A surfaces an outgoing file bubble — `mediaKind` set, `filePath` basename == `fileName` (same check S21 uses).
- A2 (image classification, headline): on B, `l3_dump_state(conversationId: toxA).messages[]` contains a `isSelf==false` row with `mediaKind == "image"`. Grounded: the receive/`file_done` path runs `_detectKind(fileName)` (`ffi_chat_service.dart:2908`), and `_detectKind` returns `'image'` for `.png/.jpg/.jpeg/.gif/.webp/.bmp/.heic` (`ffi_chat_service.dart:4966-4989`). Classification is by extension on the RECEIVING side — payload bytes are irrelevant. (The sender-side `mediaKind: kind` at `ffi_chat_service.dart:3866` also classifies for A's own bubble, covered by A1.)
- A3 (accept + write): the same B row has a non-empty `filePath` (B auto-accepted + wrote it). Auto-accept marker: `Auto-accepting image file: <name>` (`ffi_chat_service.dart:2308-2310`); images bypass the user size limit but are capped at `_imageAutoAcceptLimitBytes` 50 MiB (`:638`, `:2306`).
- A4 (image lands in avatars dir): received images are moved to the avatars directory, not Downloads (`ffi_chat_service.dart:2916-2924`) — so A3's `filePath` resolves under `avatars/` with a `_<epochMs>` suffix, distinct from the generic-file Downloads path S24 asserts.
- A5: `official.get_runtime_errors({})` baseline-clean both sessions; no `_markFileTransferFailed` / `acceptFileTransfer failed` (`ffi_chat_service.dart:2260`).

## Notes
- Cheapest promotion in the file family: the code-new artifacts are `run_fixture_c_image.sh` + the `--image` flag in `drive_fixture_c_file.dart` (swaps `.txt`→`.png` and adds the optional `expectMediaKind: "image"` to the receiver wait). No new L3 tool, no new dump field. Default (no `--image`) is byte-identical to the S21/S24 path.
- `FakeMsgProvider.sendImage` (D3) is the UIKit composer entry, but it funnels into the SAME `sendFile` path `l3_send_file` already exercises — so the gate covers the D3 send semantics without driving the un-driveable native image picker (that picker is the S79/`l3_pick_avatar` problem, separate surface).
- Echo peer is NOT a substitute (§3.7): it echoes c2c TEXT only, cannot receive/classify a file transfer.
- The composer-rendered image preview bubble (UIKit `messageItem_<msgId>` thumbnail) is NOT asserted here — there is no message-item ValueKey today (same gap S21 records); A2 asserts the data-layer `mediaKind`, which is the load-bearing classification.
- Wanted UiKeys (none today): `messageItem_<msgId>`, image-attach option key.
