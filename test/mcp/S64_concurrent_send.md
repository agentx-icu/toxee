# S64 — Concurrent send (two processes)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(paired) history=empty` (the `paired_for_e2e` snapshot)
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because two live toxees must both `sendMessage` simultaneously over the real DHT — the loss/dup/ordering invariant only manifests when both processes' receive + history-write paths interleave on the network, which L2 (no live DHT, single process) cannot reproduce. Sibling of S62 (one-directional real-time delivery); S64 is the bidirectional-concurrent stressor.
**Status**: covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_concurrent.sh` (drive_fixture_c_concurrent.dart interleaves N sends each way and asserts count==2N, no-loss, no-dup msgID, per-stream timestamp ordering on both sides). Validated live 2026-06-01.

## Precondition
- Two toxee instances in separate macOS Containers (distinct `CFBundleIdentifier`, e.g. `Toxee_B.app` id `com.toxee.b.app`) so `SharedPreferences`/`flutter_client.log`/`account_data` don't clobber
- A and B already paired friends (no pending application); both plaintext profiles, `autoLogin=true`
- `history=empty` both sides — the per-account history file (`<appSupport>/account_data/<toxX_prefix16>/chat_history/<toxPeer_64>.json`, see path derivation below) absent or `messages: []` — clean count baseline. On-disk shape, verified against source: the account root is `account_data/<first-16-hex-of-toxId>` (`AppPaths.getAccountDataRoot`/`getAccountChatHistoryPath`, `lib/util/app_paths.dart:304-330`), and the history FILENAME is `ConversationIdUtils.sanitizeForFilename(ConversationIdUtils.normalize(peerId)) + '.json'` (`message_history_persistence.dart:130-136`). `normalize` STRIPS the `c2c_`/`group_` prefix and truncates to 64 chars (`conversation_id_utils.dart:27-46`), so a C2C peer file is `<peer64>.json` — NOT `c2c_<peer>.json`. Persistence is plain JSON (`{conversationId, messages:[...], ...}`), not SQLite (the UI_TEST_LAYERING doc's "SQLite" wording is stale).
- Both reach Online before driving (poll `<nick>\nOnline` ≤60s per side)
- `MCP_BINDING=marionette`; two VM service URIs (one per process, distinct ports — see spike Q3)
- Choose N (e.g. N=10) messages each way; A sends `A-msg-001`..`A-msg-010`, B sends `B-msg-001`..`B-msg-010`

## Driver
1. Connect marionette + arenukvern to A's URI and to B's URI independently
2. On each side: tap `UiKeys.sidebarChats` (`sidebar_chats_tab`), open the peer's conversation row, confirm `TencentCloudChatMessageHeader` mounted; baseline `official.get_runtime_errors({})` per side
3. **Interleave the sends** (no per-side serialization): alternate one `enter_text` + send (`fmt_press_key({key:"Enter"})`, fallback `\n`) on A then on B, walking `A-msg-001`/`B-msg-001`, `A-msg-002`/`B-msg-002`, … so both `sendMessage` paths fire roughly concurrently. Use `UiKeys.chatInputTextField` (`chat_input_text_field`) first; if the wrapper key cannot directly focus the descendant field in this harness, drive the unique chat-panel text-field ref like S12 Step 4–5.
4. After all 2N sends issued, poll each side's snapshot up to 60s until the peer's last message (`A-msg-010` on B, `B-msg-010` on A) appears
5. On each side, kill the process (`pkill -KILL -f "Debug/<bundle>.app/Contents/MacOS/<bin>"`), `jq '.messages | length' <peer64>.json` per side (the history file under `account_data/<prefix16>/chat_history/`, named `<peer64>.json` — see Precondition)

## Assertions
- A1 (count integrity, primary): each side's `<peer64>.json` holds exactly `2N` entries (own N + peer's N); snapshot bubble count agrees
- A2 (no loss): the set of `A-msg-001`..`A-msg-010` AND `B-msg-001`..`B-msg-010` all present on BOTH sides
- A3 (no dup): no `msgID` appears twice in either `<peer64>.json` — `jq '[.messages[].msgID] | length == (unique | length)'` is `true`. Dedup is enforced at `appendHistory` (`third_party/tim2tox/dart/lib/utils/message_history_persistence.dart:806`: msgID match → `_mergeMessages` line 815, else content+timestamp match line 829, else append) and again on load (`:504-538` builds a `Map<String,ChatMessage>` keyed by `msgID`)
- A4 (ordering coherence): within each side's view, messages are timestamp-ascending (`message_history_persistence.dart:544` `sort((a,b)=>a.timestamp.compareTo(b.timestamp))`; stream side re-sorts at `lib/sdk_fake/fake_msg_provider_routing.dart:94`). A side's OWN 10 stay in 001→010 order; peer's 10 stay in 001→010 order; interleave order between the two streams may differ per side but each side is internally monotonic
- A5 (no double-write): log on each side does NOT show a second persistence write for an already-stored peer msgID — `BinaryReplacementHistoryHook` guards this (hook only saves messages NOT already saved by `FfiChatService._appendHistory`; "Check if message already exists in persistence to avoid duplicates", `third_party/tim2tox/dart/lib/utils/binary_replacement_history_hook.dart:152-213`)
- A6 (send path, both sides): log contains `[Tim2ToxSdkPlatform] sendMessage called: id=` (`tim2tox_sdk_platform.dart:4953`, unconditional `print`) → `Found message: msgID=` (`:4992`, unconditional `print`) for each outgoing message. The intermediate `Looking for message in targetID:` (`:4969`) is gated behind `_debugLog` (`:135` `static const bool _debugLog = false`) and MUST NOT be required unless the build sets `_debugLog=true`; treat it as debug-only. The two unconditional lines are the guaranteed send-path signal.
- A7 (negative): `[Tim2ToxSdkPlatform] sendMessage failed:` (`tim2tox_sdk_platform.dart:5064/5507`) and `[MessageHistoryPersistence] post-load save failed` (`:746`) MUST NOT appear on either side
- A8: `official.get_runtime_errors({})` matches Step-2 baseline on both sessions

## Notes
- BLOCKED on the multi-instance (Fixture C) spike — two OS processes side-by-side over the live DHT is unproven test infra (sandbox isolation Q1, native reentrancy Q2, port collision Q3, log interleave Q4, same-host DHT delivery Q5). See `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md` §2-§4; until it passes this is `backlog`, not coverage.
- The legacy `message_input_field` / `message_send_button` names are not the shipped contract. Toxee exports `chat_input_text_field`, while desktop send remains Enter-driven rather than a separate tappable button.
- The synthetic dedup fallback key `${timestamp.millisecondsSinceEpoch}_${fromUserId}` (`message_history_persistence.dart:538`) is fragile under concurrency — if any message lands without a `msgID`, A3 can false-pass; require real `msgID`s.
- `appendHistory` debounces writes 200ms (`message_history_persistence.dart:95`); poll/settle ≥300ms after the last send before the kill+`jq` count, or A1 undercounts.
