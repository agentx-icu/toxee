[简体中文](./MCP_UI_TEST_PLAYBOOK.zh-CN.md)

# MCP UI Automation Playbook — toxee

How an AI agent (Claude, Cursor, Codex, …) drives **Layer 3** UI tests
against toxee using the MCP tools we evaluated on 2026-05-28
(`../../tool/mcp_test/REAL_UI_GATES.md`).

> **Layering authority.** The three-layer model (L1 widget seam / L2
> host-bundle lifecycle / L3 MCP playbook) and the promotion protocol
> for graduating MCP-discovered bugs into stable regressions live in
> **[`doc/architecture/UI_TEST_LAYERING.md`](UI_TEST_LAYERING.md)**.
> This document is the L3 routing + scenario reference. When the two
> disagree, the layering doc wins; file a fix here.

**Scope.** Layer 3 only: driving a real toxee binary, real Tox network,
real disk state. For L1 widget-seam smokes use `test/`; for L2
host-bundle lifecycle flows use `integration_test/`. The layering doc
§3 has the routing table for "which layer does this flow belong in?".

**Inclusion test for §5.** A scenario stays in this catalog only if
the answer to "would this scenario test something L2 (host bundle)
cannot deterministically pin down?" is **yes**. Concretely: live DHT
handshakes, two-process interop, native dialogs, OS permission gates,
or other OS integration. Everything else — single-process Prefs,
profile-on-disk lifecycle, theme/locale propagation, picker-stubbable
flows — belongs in `../../tool/mcp_test/REAL_UI_GATES.md` as an L2 backlog
candidate. See the "Moved to L2 backlog" list at the end of §5.

## 1. The decision rules

The decision tree is one column: **what does the flow depend on?**
The layering doc §3 has the full table. The short form:

| Minimum-dependency the flow needs | Layer | Where |
|---|---|---|
| Pure Dart + mocked channels + a constructor seam | L1 | `test/...` |
| Real Hive bootstrap, real `libtim2tox_ffi`, real `path_provider` (but no live network) | L2 | `integration_test/...` (tag `needs-native`) |
| Live Tox DHT, two toxee processes, native file picker, microphone/camera permission | L3 | this playbook |

If you can express the flow without the L3-only deps, **promote it
out of this playbook**. Heavy L3 playbooks have a maintenance cost
that thin L1/L2 regressions don't.

## 2. MCP routing matrix

> **Which binding? `skill` — not `marionette`.** `MCP_BINDING` accepts
> `skill | marionette | stock` (`run_toxee.sh` whitelist; `lib/main.dart`
> defaults to `skill`). **`skill` is the current recommendation and what
> every non-macOS launcher hardcodes** (`run_toxee_linux.sh`,
> `run_toxee_android.sh`, `launch_toxee_ios_instance.sh`,
> `launch_*_fixture_c_pair.sh` all default to `MCP_BINDING=skill`): it is
> *additive* — it layers `ext.flutter.flutter_skill.{tap,enterText,
> pressKey,tapAt,waitForElement,interactiveStructured,getWidgetTree,
> screenshot}` on the stock binding, which is the full real-widget
> driving API the L3 runner and the two-process drivers use.
> `marionette` **replaces** `WidgetsFlutterBinding` and
> [`REAL_UI_TWO_PROCESS.md` §"The driving channel"](../../tool/mcp_test/REAL_UI_TWO_PROCESS.md)
> reports it hanging at startup. Use it only if you specifically need
> marionette's own MCP tools, and expect to debug the hang.
>
> **You must still set `MCP_BINDING` explicitly on macOS.** `run_toxee.sh`
> only appends `--dart-define=TOXEE_L3_TEST=true` **inside** the
> `if [[ -n "${MCP_BINDING:-}" ]]` branch, so a bare `./run_toxee.sh`
> builds *without* the `ext.mcp.toolkit.l3_*` tool surface. The canonical
> macOS L3 launch is therefore **`MCP_BINDING=skill ./run_toxee.sh`**.
> (Historical note: this document and `CLAUDE.md` previously said
> `MCP_BINDING=marionette`; that was the 2026-05-28 F7 routing, before
> `flutter_skill` existed. Both are updated as of 2026-08-07.)

| Operation | Tool | Why |
|---|---|---|
| Launch app under test | shell (`MCP_BINDING=skill ./run_toxee.sh`) — **NOT official MCP** | official MCP uses `flutter run` which interposes DDS; DDS rejects the marionette/arenukvern WebSocket upgrade and swallows the bare VM URI. The script also sets `FLUTTER_ENGINE_SWITCHES`/`FLUTTER_ENGINE_SWITCH_*` env vars so the Dart engine announces a bare auth-code-free VM URI on stdout (see `run_toxee.sh` + F5 in `../../tool/mcp_test/REAL_UI_GATES.md`). |
| **Drive real widgets** (tap / type / key / wait) | `ext.flutter.flutter_skill.*` over raw `vm_service.callServiceExtension` | The `skill` binding's own API — by `ValueKey`, visible text, or coordinates. This is what `drive_real_ui_pair.dart` and `run_l3_scenarios.dart` use. `tool/mcp_test/_scratch/skill_call.dart <ws> <ext.method> '<json>'` is the one-shot probe. |
| Find VM service URI | `cat build/vm_service_uri.txt` | `run_toxee.sh:392-410` tees the engine's stdout/stderr into `build/toxee_stdio.log`, greps the announcement line, normalises the URI to `ws://…/ws`, and writes it to `build/vm_service_uri.txt`. The URI does **NOT** appear in `flutter_client.log` — the engine prints it to stdout (not stderr), and `AppLogger`'s probe in `logging_bootstrap.dart:45` truncates `flutter_client.log` with `FileMode.write` (F2 + F5 corrected the earlier "grep flutter_client.log" recipe). |
| Connect | `marionette.connect` + `arenukvern.fmt_connect_debug_app` (both, on raw VM URI ending in `/ws`) | Use both: marionette for synthetic gestures, arenukvern for semantic snapshot + screenshots |
| Take screenshot | `arenukvern.fmt_get_screenshots` (mode=`flutter_layer`, compress=true) | Works in any binding mode; `flutter_layer` avoids macOS screen-recording permission. Marionette's `take_screenshots` also works. |
| Locate interactive widgets | `arenukvern.fmt_semantic_snapshot` | Cleanest output (~6-30 nodes). Use refs `s_N` for tap. Compare with marionette's `get_interactive_elements` which returns 30-60 nodes — noisier but with bounds and font info. |
| **Tap a Material widget** (button, card, list tile, dialog action) | `arenukvern.fmt_tap_widget(ref="s_N", snapshotId=…)` | Semantic-action tap; works on InkWell-backed surfaces (which is most of toxee). Verified on LoginPage account cards, sidebar tabs (via UiKeys), settings dialog buttons. |
| **Tap a non-Semantics widget** (raw `GestureDetector`, custom hit-testing) | `marionette.tap(key: 'ui_key_string')` or `(text: '...')` | Marionette injects real pointer events. Required when arenukvern's semantic tap silently no-ops (e.g. some sidebar items in older builds). |
| Type into TextField | `marionette.enter_text(key: ..., input: ...)` or `arenukvern.fmt_enter_text` | Both work for standard `TextField`. Prefer the one that matches your tap source. |
| Read widget tree (debugging) | `official.get_widget_tree(summaryOnly=true)` | Returns full tree with `textPreview` for `Text` widgets. Cheap. |
| Read recent print/log output | `arenukvern.fmt_get_recent_logs` OR tail `logs/app_*.log` | Marionette's `get_logs` is broken ("Server error"). |
| Read runtime errors | `official.get_runtime_errors` + tail logs | Note: official only catches `FlutterError.onError` exceptions, NOT errors rendered into the widget tree as text. |
| Coord → source location | `arenukvern.fmt_inspect_widget_at_point(x, y)` | Unique to arenukvern. Returns `file:line` for the widget at that point. |
| Hot reload | **none** | **No official hot reload support in L3.** The L3 canonical session launches the standalone bundle directly (no `flutter run`), so there is no DDS for `official.hot_reload` to attach to. For dev iteration use `flutter run` in a separate session — that's not L3. See `../../tool/mcp_test/REAL_UI_GATES.md`. |
| Stop app | `kill <pid>` of the Toxee binary (NOT the bash wrapper) | Killing the script's bash subshell leaves the Toxee binary orphaned to launchd. |

## 3. Pre-flight: getting toxee into a test-ready state

```bash
# (a) Clean up any orphan Toxee processes from prior runs.
ps -ef | grep "Debug/Toxee.app" | grep -v grep | awk '{print $2}' | xargs -r kill

# (b) Build with the skill binding (additive; gives ext.flutter.flutter_skill.*
#     real-widget driving) AND — because run_toxee.sh only defines
#     TOXEE_L3_TEST when MCP_BINDING is set — the ext.mcp.toolkit.l3_* tools.
#     mcp_toolkit's extensions are always layered on top in kDebugMode.
MCP_BINDING=skill ./run_toxee.sh   # this also bundles native dylibs
```

After `MCP_BINDING=skill ./run_toxee.sh` launches the standalone bundle
(≤30s on M-series), the script prints the canonical VM URI to stdout AND
writes it to `build/vm_service_uri.txt`. Grab it:

```bash
URI=$(cat build/vm_service_uri.txt)
echo "$URI"   # → ws://127.0.0.1:<port>/ws (or ws://127.0.0.1:<port>/<authCode>/ws if env switches were dropped)
```

Then in the MCP layer:

```
arenukvern.fmt_connect_debug_app({mode: "uri", uri: "$URI"})
marionette.connect(uri="$URI")
```

### 3.5 Working routing — empirically validated 2026-05-28

The four sequential steps below were run end-to-end against toxee on
2026-05-28 (F7 in `../../tool/mcp_test/REAL_UI_GATES.md`). The
**launch + URI-extraction half (steps 1-2) is still the canonical L3
entry**; steps 3-4 are the marionette-specific tail, which the
`flutter_skill` driving API (§2) has since superseded — swap
`MCP_BINDING=marionette` for `MCP_BINDING=skill` and drive via
`ext.flutter.flutter_skill.*`:

1. `MCP_BINDING=skill ./run_toxee.sh` — sets
   `FLUTTER_ENGINE_SWITCHES=2` + `FLUTTER_ENGINE_SWITCH_1=vm-service-port=0`
   + `FLUTTER_ENGINE_SWITCH_2=disable-service-auth-codes` (the canonical
   engine-switch mechanism on macOS desktop — argv goes to
   `dartEntrypointArguments`, NOT engine switches, so command-line
   flags don't work; this is the env-var route the embedder's
   `engine_switches.cc` reads).
2. `URI=$(cat build/vm_service_uri.txt)` once the script settles.
3. `marionette.connect(uri="$URI")` — succeeds; no DDS in the way
   because the standalone bundle never calls `_yieldControlToDDS`.
4. `marionette.get_interactive_elements()` — returns the live widget
   tree (≈39 nodes on LoginPage in F7's run, including the existing
   `login_page_restore_from_tox_file` UiKey).

Any deviation (e.g. `flutter run` launch, official `launch_app`,
grepping `flutter_client.log` for the URI) is **not** the documented
L3 routing.

**State isolation.** Each test run inherits the disk state of the last:
- `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/profiles/*` — Tox profiles
- `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/account_data/*` — per-account data
- SharedPreferences (current account, nickname, auto-login flag, etc.)

For tests that need a fresh slate: snapshot+restore those dirs before/after
the test. For tests that need a specific account preloaded: copy a known
`.tox` profile into the right place before launch.

### 3.6 Echo peer helper

Some L3 scenarios need a real Tox endpoint to talk to without paying
the cost of standing up a second toxee process (see §3.7). The **echo peer** is a
single-binary, non-toxee Tox node that auto-accepts friend requests
and auto-echoes any c2c text message back to its sender. That is
enough to drive AddFriend, message-send, offline-queue, and
reconnect flows end-to-end.

**Binary.** Pre-built at `tool/mcp_test/echo_peer_src/build/echo_peer`.
Build from source:

```bash
cd tool/mcp_test/echo_peer_src
cmake -B build
cmake --build build
```

**Helpers.**

| Script | Use |
|---|---|
| `tool/mcp_test/ensure_echo_peer.sh` | Idempotent daemon launcher. Starts the echo peer if not already running, writes its canonical contract to `tool/mcp_test/echo_peer.json` (read `peer_id` from there — that is the 76-char Tox address you give to AddFriend). |
| `tool/mcp_test/stop_echo_peer.sh` | Graceful stop. |
| `tool/mcp_test/run_echo_peer_foreground.sh` | Ad-hoc foreground run for dev only; not for scenario pre-flight. |
| `tool/mcp_test/regen_echo_peer_seed.sh` | First-run only: generates the cached fixture snapshot for `echo_seeded` scenarios. |
| `tool/mcp_test/restore_echo_peer_seed.sh` | Populates Containers + Prefs from the cached snapshot. Fast; per-maintainer-machine. Seeded account name is `echo_seeded_test`. |

**Behavior.** The binary auto-accepts inbound friend requests and
auto-echoes c2c text. It emits its 76-char Tox address on stdout as
`ECHO_PEER_TOX_ID:<address>` for log-grep harnesses; the canonical
caller contract is `tool/mcp_test/echo_peer.json::peer_id`. Persistent
peer state lives under `tool/mcp_test/echo_peer_state/`.

**Routing for scenarios.**

- `peerHarness=echo_live` — in pre-flight, call
  `tool/mcp_test/ensure_echo_peer.sh`, read `peer_id` from
  `tool/mcp_test/echo_peer.json`, then use it as the AddFriend target
  in the driver. Tear down with `tool/mcp_test/stop_echo_peer.sh` if
  the scenario asserts post-shutdown state.
- `peerHarness=echo_seeded` — in pre-flight, call
  `tool/mcp_test/restore_echo_peer_seed.sh`; this drops the
  pre-recorded `account_data/`, `profiles/`, and scoped Prefs from
  cache so toxee comes up already showing the seeded friend and chat
  history. The echo peer process is NOT launched. First-time-per-host
  callers must run `tool/mcp_test/regen_echo_peer_seed.sh` once to
  populate the cache; subsequent restores are fast.

The harness-mode axis is defined in
[`UI_TEST_LAYERING.md` §8.1](UI_TEST_LAYERING.md#81-harness-modes)
and is orthogonal to the §4 state vector.

### 3.7 Echo peer is NOT Fixture C

Fixture C (`paired_for_e2e`) is a **two-toxee-process** model: two
full toxee binaries on the same host with paired profiles, exchanging
messages over the local DHT. That model is **shipped harness** today —
29 manifest entries, 27 `drive_fixture_c_*.dart` drivers, and pair
launchers for all five platforms, all planned through
`tool/mcp_test/fixture_c_unified_runner.dart`
(`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`; see
[`UI_TEST_LAYERING.md` §6](UI_TEST_LAYERING.md#6-fixture-c-multi-instance--the-spike-passed-it-is-shipped-harness)).

The echo peer is a **single non-toxee process** that speaks Tox
protocol. From toxee's perspective it is one external peer; the
scenario still has only one toxee instance. This is structurally
different from Fixture C and is **not a substitute**.

Concretely:

- Scenarios that genuinely need two toxees on one host (S46/S47/S59
  and the S61-S70 multi-instance block in §5a) **cannot** use the
  echo peer. Route them through the unified runner's `2proc-l3` /
  `2proc-ui` classes instead.
- Scenarios that only need a real peer endpoint to AddFriend / echo
  back / reconnect against (e.g. live-DHT smokes) CAN use
  `peerHarness=echo_live` and unblock today.
- Scenarios that need the *appearance* of a paired peer (a friend row,
  chat history on disk) without live DHT participation can use
  `peerHarness=echo_seeded`.

If you find yourself reaching for the echo peer to drive a
two-toxee-only flow, stop — that is a sign the scenario actually
needs Fixture C, which is available.

## 4. Fixtures — state vectors

The previous "Fixture A / B / C" named-template approach was too coarse
once playbooks started escaping into "A2 with a specific autoLogin
state", "C minus password but plus seeded conversation", etc.
The authority is now the **state-vector** language defined in
[`UI_TEST_LAYERING.md` §8](UI_TEST_LAYERING.md#8-state-vectors-replaces-fixtures-abc):

```
accounts={0|1|N}
current={none|<toxId>}
profileCrypt={plain|pwd:<password>}
autoLogin={on|off}
network={online|offline}
window={default|<W>x<H>+<X>+<Y>}
sessionPwd={none|cached}
history={empty|seeded}
dhtCache={cold|warm}
friends={0|1|N}    (per-account)
```

Each scenario lists a `Fixture vector:` line with only the axes it
actually cares about; the rest inherit from the running environment.

Three named **convenience snapshots** wrap common vectors:

- `single_signed_in` — `accounts=1 current=A1 autoLogin=on network=online`
  (formerly "Fixture A")
- `two_saved_none_signed_in` — `accounts=2 current=none autoLogin=off`
  (formerly "Fixture B")
- `paired_for_e2e` — `accounts=2 current=A1 friends=1 sessionPwd=none`
  + a paired profile staged for a second toxee process (formerly
  "Fixture C"). **Available**: restore is wired on all five platforms
  through the pair launchers; the unified runner stages it for you
  (`--base=paired_for_e2e`). The Android path is implemented but has
  not had its first live two-emulator validation run — don't call
  friendship scenarios android-green yet.

Pre-staged snapshots will live under `tool/mcp_test/fixtures/`. Until
that toolchain lands, hand-stage by editing
`~/Library/Containers/com.toxee.app/Data/...` directly, or let
`tool/mcp_test/restore_fixture_c_pair.sh` do it.

**Why this changed.** Codex's 2026-05-28 review:

> A/B/C 这个 fixture 抽象太粗 […]. 不要继续把 fixture 当成 3 个命名
> 模板，而要改成可组合状态向量, 至少拆成"账号数/当前账号/磁盘加密
> /autoLogin/网络/窗口/会话密码/历史数据"几个维度, 再落成可还原的
> seed snapshot. 否则 73 个场景最后会被 cross-test interference 吃掉.

("73 个场景" was the 2026-05-28 catalog size. As of 2026-08-07 there
are **178** playbooks, numbered S2–S185 with gaps — the argument only
got stronger.)

The named snapshots cover ~80% of scenarios so the muscle-memory of
"set up Fixture A and go" still works; the vector language is the
fallback for the 20% that escape.

## 5. Scenario catalog

> **⚠ Coverage authority is [`test/mcp/INDEX.md`](../../test/mcp/INDEX.md), not this section.**
> `INDEX.md` is **generated** by `tool/mcp_test/gen_scenario_index.dart`
> from three sources of truth (the scenario JSONs, `fixture_c_manifest.json`,
> and each playbook's own `**Status**` header) and its freshness is
> CI-gated by `gen_scenario_index.dart --check` in
> `.github/workflows/mcp_harness_smoke.yml`. The tables below are
> **hand-written routing notes** — they record *why* a scenario is
> L3-pinned and which MCP tools drive it. They are not, and cannot be,
> a coverage claim.
>
> Concretely, as of 2026-08-07 the tables below cover only **S2–S125**,
> while the catalog runs **S2–S185 (178 playbooks, gaps at S1/S6/S7/
> S41/S42/S50/S73)**. The whole **S126–S185 group + conference block**
> has no row here at all, and four rows below (S1, S6, S7, S73) are
> **ghosts** — the playbook file was never written or has been deleted.
> Deliberate decision: rather than hand-transcribe 60 more rows that
> will drift again within a month, this section stays scoped to the
> original L3-pin rationale set and defers everything else to the
> generated index. If you need "is Snn covered?", read `INDEX.md`.

This catalog is **L3-only**: every entry here describes a flow whose
minimum dependency set includes at least one of `{ live Tox DHT, two
toxee processes, native dialog the picker can't stub, OS permission
gate, OS clipboard cross-process }`. Everything else has been moved
to the L2 backlog at the bottom of this section.

Each retained entry is a one-line pointer to a heavy companion file
under `test/mcp/`. The companion holds the precondition/driver/
assertions; this catalog holds the routing.

### 5a. L3-only scenarios (live DHT / multi-instance / native dialog / OS gates)

| ID | Title | Companion | L3-pin reason |
|---|---|---|---|
| S2 | Login with saved account → HomePage | `test/mcp/S2_login_saved_account.md` | Live DHT bootstrap (5-30s); only L3 has the real network |
| S5 | Add friend dialog → send request | `test/mcp/S5_add_friend_dialog.md` | Live DHT delivery + offline-queue interaction |
| S9 | Restore from .tox file (native picker path) | `test/mcp/S9_restore_from_tox_file.md` | Native file picker; L3 can hand-stage, L2 cannot |
| S10 | Reconnect after going offline | `test/mcp/S10_reconnect_after_offline.md` | Real network state transitions |
| S25 | Send offline → queue → reconnect → delivered | `test/mcp/S25_offline_queue.md` | Live DHT delivery confirmation |
| S31 | Self-ID copy → OS clipboard | `test/mcp/S31_self_id_copy.md` | Cross-process clipboard verification |
| S43 | Export account → native save dialog | `test/mcp/S43_export_account.md` | Native save dialog |
| S46 | Auto-accept friend request toggle | `test/mcp/S46_auto_accept_friend_toggle.md` | Multi-instance — executable gate `run_fixture_c_autoaccept_friend.sh` (live 2026-06-01) |
| S47 | Auto-accept group invite toggle | `test/mcp/S47_auto_accept_group_toggle.md` | Multi-instance + native invite-delivery / knownGroups propagation residual; invite send is no longer stubbed |
| S58 | Window lifecycle (minimize/restore) | `test/mcp/S58_window_lifecycle.md` | OS window-server interaction; macOS-specific |
| S59 | Notification permission revoke/regrant | `test/mcp/S59_notification_permission.md` | Only the OS TCC **grant** is irreducible; the deny→no-banner / allow→banner CONSEQUENCE is L1 (`test/notifications/notification_permission_gate_test.dart`, 2026-06-08) |
| S61 | Friend handshake (two processes) | `test/mcp/S61_friend_handshake.md` | Multi-instance — executable Fixture C state driver `run_fixture_c_non_media.sh` (UI accept surface is S26) |
| S62 | Real-time message delivery (two processes) | `test/mcp/S62_realtime_message_delivery.md` | Multi-instance — executable Fixture C state driver `run_fixture_c_non_media.sh` |
| S63 | Read receipt / typing indicator | `test/mcp/S63_read_receipt_typing.md` | **Partial.** Typing leg gated by `run_fixture_c_typing.sh` (live). Read receipts send but don't land: the receipt references a msgID that doesn't correlate across instances — needs a tim2tox msgID round-trip fix |
| S64 | Concurrent send (two processes) | `test/mcp/S64_concurrent_send.md` | Multi-instance — executable gate `run_fixture_c_concurrent.sh` (no-loss / no-dup / ordering; live 2026-06-01) |
| S65 | Initiate voice call | `test/mcp/S65_initiate_voice_call.md` | OS mic permission + media stack — executable Fixture C gate exists; TCC remains the live precondition |
| S66 | Initiate video call | `test/mcp/S66_initiate_video_call.md` | OS camera/mic permission + media stack — executable Fixture C gate exists; TCC remains the live precondition |
| S67 | Accept incoming call | `test/mcp/S67_accept_incoming_call.md` | Multi-instance + media stack — executable Fixture C gate exists |
| S68 | Decline incoming call | `test/mcp/S68_decline_incoming_call.md` | Multi-instance + media stack — executable Fixture C gate exists |
| S69 | Call mid-ring rejection by network drop | `test/mcp/S69_call_network_drop.md` | Multi-instance + media stack — executable gate `run_fixture_c_network_drop.sh` (8s reconnect grace; live 2026-06-01) |
| S70 | Call duration timeout | `test/mcp/S70_call_duration_timeout.md` | Reclassified 2026-06-08: the product has **no** duration auto-end, and that invariant is now L1 (`test/call/call_duration_no_timeout_test.dart`, `fakeAsync`). Real timeouts live in S77 (unanswered ring) and S69 (network drop) |
| S13 | Resend a failed / queued outbound message | `test/mcp/S13_resend_failed_message.md` | Live DHT delivery confirmation (auto-drain on reconnect + tap-to-resend on SEND_FAIL) |
| S16 | Copy message text → OS clipboard | `test/mcp/S16_copy_message_text.md` | Cross-process clipboard verification (`pbpaste`) |
| S21 | Send a file/image attachment | `test/mcp/S21_send_file_attachment.md` | Native file picker + live DHT transfer — sender half gated by `run_fixture_c_file.sh` (live 2026-06-01); bubble render/open also L1 |
| S24 | Receive an (auto-accepted) incoming file | `test/mcp/S24_accept_incoming_file.md` | Multi-instance + DHT transfer — receiver half gated by `run_fixture_c_file.sh` (live 2026-06-01); explicit manual-accept (`l3_accept_file`) is still a TODO |
| S34 | Group message send/receive (two processes) | `test/mcp/S34_group_message_two_process.md` | Multi-instance — executable gate `run_fixture_c_group.sh` (public NGC join by chat-id + A↔B roundtrip; live 2026-06-01) |
| S37 | Group member moderation (kick / role) | `test/mcp/S37_group_member_moderation.md` | Multi-instance + moderation surface — kick path has an executable Fixture C gate; role-change remains unwired |
| S51 | Friend online/offline presence indicator | `test/mcp/S51_friend_presence_indicator.md` | Multi-instance + live presence events — executable gate `run_fixture_c_presence.sh` (online → stop B → relaunch; live 2026-06-01) |
| S52 | Self profile change propagates to a friend | `test/mcp/S52_self_profile_propagation.md` | Multi-instance + profile broadcast over DHT — executable gates `run_fixture_c_self_profile.sh` (nickname) + `run_fixture_c_avatar.sh` (avatar); live 2026-06-01 |
| S53 | Notification tap → opens the conversation | `test/mcp/S53_notification_tap_opens_conversation.md` | OS notification interaction — the routing half is gated by `run_fixture_c_notification_tap.sh` (live 2026-06-01); the OS banner POST + real OS tap stay OS-gated |
| S54 | Friend request custom message round-trip | `test/mcp/S54_friend_request_custom_message.md` | Multi-instance + live DHT friend-request delivery — executable gate `run_fixture_c_custom_message.sh` (live 2026-06-01) |
| S74 | In-call microphone mute / unmute | `test/mcp/S74_in_call_mute_toggle.md` | ToxAV media stack + connected call — executable Fixture C gate exists |
| S75 | In-call camera (video) toggle | `test/mcp/S75_in_call_camera_toggle.md` | Camera permission + ToxAV media stack + connected call — executable Fixture C gate exists |
| S76 | Hang up an active call | `test/mcp/S76_in_call_hangup.md` | ToxAV media stack + connected call — executable Fixture C gate exists |
| S77 | Missed incoming call → record + notification | `test/mcp/S77_missed_incoming_call.md` | Multi-instance + media stack — executable gate `run_fixture_c_missed_call.sh` (live 2026-06-01). NOTE: ToxAV has no ring auto-timeout, so "missed" is realized by caller-cancel |
| S78 | Record + send a voice message | `test/mcp/S78_voice_message_record_send.md` | Mic capture + live DHT delivery — executable gate `run_fixture_c_voice_msg.sh` (live 2026-06-01); the mobile record-UI half is additionally L1 with the `record` MethodChannel stubbed |
| S79 | Set self avatar via native image picker | `test/mcp/S79_set_avatar_native_picker.md` | Native image picker — executable gate `run_fixture_c_avatar_picker.sh` (`l3_pick_avatar` bypasses NSOpenPanel via an override seam and runs the REAL `pickAndPersistAvatar`; live 2026-06-01) |
| S80 | Add a friend by scanning a QR code | `test/mcp/S80_add_friend_by_qr_scan.md` | OS camera permission + QR parse (mobile only — desktop has no scanner) |
| S81 | Invite a friend to a group (two processes) | `test/mcp/S81_invite_friend_to_group.md` | Multi-instance — invite send is no longer stubbed; residual native delivery / propagation timing remains |
| S82 | Custom / failover DHT bootstrap node → connect | `test/mcp/S82_custom_bootstrap_node.md` | Live DHT bootstrap (single client, no peer) |
| S83 | Mute a conversation → notification suppressed | `test/mcp/S83_mute_conversation_notifications.md` | OS notification suppression — mute STATE gated by `run_fixture_c_mute.sh` (live 2026-06-01); the suppression DECISION is L1 (`test/ui/notification_mute_suppression_test.dart`, 2026-06-08). Only the OS-banner-absence proof stays OS-gated |

**No row above is "blocked on the Fixture C spike" any more** (updated
2026-08-07). That status value is retired — the spike passed and became
the shipped two-process harness
([`UI_TEST_LAYERING.md` §6](UI_TEST_LAYERING.md#6-fixture-c-multi-instance--the-spike-passed-it-is-shipped-harness)).
Every multi-instance row now names its executable
`run_fixture_c_*.sh` gate. What genuinely remains is a much shorter,
different list, and none of it is about missing test infrastructure:

- **OS-gated**: TCC mic/camera grants (S65/S66/S74/S75), the OS
  notification banner POST and real OS tap (S53/S59), OS-level banner
  absence (S83). These need a one-time manual/`tccutil` grant on the
  host, not a harness.
- **Product gaps**: S63 read receipts (msgID doesn't round-trip),
  S37 role-change (unwired), S47/S81 native NGC invite-delivery timing.
- **Platform**: Android `paired_for_e2e` restore is implemented but has
  never had its first live two-emulator run — don't call friendship
  scenarios android-green yet.

Per-scenario truth is in [`test/mcp/INDEX.md`](../../test/mcp/INDEX.md)
and each playbook's own `**Status**` header.

### 5b. Moved to L2 backlog

These scenarios have an L2-deterministic minimum dependency set —
real Hive + real `libtim2tox_ffi` + real `Prefs`, but no live DHT and
no second process. They live in `../../tool/mcp_test/REAL_UI_GATES.md` as
L2 candidates. The heavy investigation memos under `test/mcp/Snn_*.md`
that remain are the three earned heavies plus the thin specs the L2
work hasn't displaced yet.

> **Four rows below are ghosts.** `test/mcp/S1_*.md`, `S6_*.md`,
> `S7_*.md`, and `S73_*.md` **do not exist** (the playbook numbering
> also skips S41/S42/S50). They are kept as "L2 candidate — see
> roadmap" placeholders only so the S-numbers aren't silently reused;
> they are not covered and never had a spec. Verify with
> `ls test/mcp/S*.md` or [`INDEX.md`](../../test/mcp/INDEX.md), which
> lists only the 178 playbooks that actually exist.

| ID | Title | Pointer |
|---|---|---|
| S1 | Cold start → LoginPage renders | ghost — no playbook file; L2 candidate, see roadmap |
| S3 | Account switch | `test/mcp/S3_account_switch.md` (heavy) — **promotion landed**: `test/account_switch_resets_global_prefs_test.dart` |
| S4 | Register new account → HomePage | L2 candidate — see roadmap |
| S6 | Sidebar tab switching | ghost — no playbook file; L2 candidate, see roadmap |
| S7 | Settings: theme toggle | ghost — no playbook file; L2 candidate, see roadmap |
| S8 | Profile edit roundtrip | `test/mcp/S8_profile_edit.md` (heavy) — **promotion landed**: `test/ui/profile_edit_persists_to_account_list_test.dart` |
| S11 | Open a conversation from chat list | `test/mcp/S11_open_conversation.md` (thin) |
| S12 | Send a text message | `test/mcp/S12_send_text_message.md` (thin) |
| S14 | Message history persistence across relaunch | `test/mcp/S14_message_history_persistence.md` (thin) |
| S15 | Long-press message → menu | `test/mcp/S15_long_press_message_menu.md` (thin) |
| S17 | Forward a message | `test/mcp/S17_forward_message.md` (thin) |
| S18 | Reply / quote a message | `test/mcp/S18_reply_quote_message.md` (thin) |
| S19 | Mark conversation as read | `test/mcp/S19_mark_conversation_read.md` (thin) |
| S20 | Delete entire conversation | `test/mcp/S20_delete_conversation.md` (thin) |
| S22 | Emoji panel insertion | `test/mcp/S22_emoji_panel_insert.md` (thin) |
| S23 | Sticker panel insertion | `test/mcp/S23_sticker_panel_insert.md` (thin) |
| S26 | Accept incoming friend request | `test/mcp/S26_accept_friend_request.md` (thin) |
| S27 | Decline incoming friend request | `test/mcp/S27_decline_friend_request.md` (thin) |
| S28 | Remove a friend | `test/mcp/S28_remove_friend.md` (thin) |
| S29 | Block + unblock a user | `test/mcp/S29_block_unblock.md` (thin) |
| S30 | Edit friend alias | `test/mcp/S30_edit_friend_alias.md` (thin) |
| S32 | Create group chat | `test/mcp/S32_create_group_chat.md` (thin) |
| S33 | Join group by ID | `test/mcp/S33_join_group_by_id.md` (thin) |
| S35 | Leave a group | `test/mcp/S35_leave_group.md` (thin) |
| S36 | Group member list | `test/mcp/S36_group_member_list.md` (thin) |
| S38 | Language switch (zh/en/ja/ko/ar) | `test/mcp/S38_language_switch.md` (thin) |
| S39 | Auto-login toggle | `test/mcp/S39_auto_login_toggle.md` (thin) |
| S40 | Set account password (encrypt) | `test/mcp/S40_set_password.md` (heavy) — **promotion landed**: `test/account_password_lifecycle_test.dart` (one group per bug) |
| S44 | Logout | `test/mcp/S44_logout.md` (thin) |
| S45 | Delete account | `test/mcp/S45_delete_account.md` (thin) |
| S48 | Conversation list search | `test/mcp/S48_conversation_list_search.md` (thin) |
| S49 | Contact list search | `test/mcp/S49_contact_list_search.md` (thin) |
| S55 | Add self as friend (guard) | `test/mcp/S55_add_self_as_friend.md` (thin) |
| S56 | Add duplicate friend (guard) | `test/mcp/S56_add_duplicate_friend.md` (thin) |
| S57 | Theme switch in chat | `test/mcp/S57_theme_switch_in_chat.md` (thin) |
| S60 | Responsive layout | `test/mcp/S60_responsive_layout.md` (thin) |
| S71 | Import-then-auto-switch (single host) | `test/mcp/S71_import_then_switch.md` (thin) |
| S72 | Multi-account state isolation (single host) | `test/mcp/S72_multi_account_isolation.md` (thin) |
| S73 | Logout + re-login restores state | ghost — no playbook file; L2 candidate, see roadmap |

S71/S72/S73 are explicitly NOT multi-instance — they cover the
single-host multi-account portability work and belong in L2. See
[`REAL_UI_TWO_PROCESS.md`](../../tool/mcp_test/REAL_UI_TWO_PROCESS.md) §6.
(S73 has no playbook file; only S71 and S72 exist.)

### 5c. UI-control coverage batch — S96–S125 (added 2026-06-03)

30 scenarios that each drive ONE already-landed `UiKeys` control via real
taps/inputs (the plan
[`docs/plans/2026-06-03-ui-automation-coverage-expansion.md`](../../docs/plans/2026-06-03-ui-automation-coverage-expansion.md)).
Unlike §5a, this batch is **mixed-disposition**: many are single-instance
surfaces that are **L1 WidgetTester candidates** (the proven executable form per
[`tool/mcp_test/REAL_UI_GATES.md`](../../tool/mcp_test/REAL_UI_GATES.md)), not pure
L3 — each spec's own header carries the authoritative Layer/Status/Promotion. The
data-half of most controls is already a hermetic runner gate (cross-referenced,
not duplicated); the new artifact is the **real-UI tap** angle. 4 novel `tap`-based
runner gates (`l3_settings_*_tap.json`) were authored **`nonBlocking` + unvalidated**
(no scenario has ever used `tap`; the marionette-ext-vs-binding question is
unresolved; the runner has no scroll action) — they OWE live-validation; their
proven data-half (`l3_*_toggle` / `l3_session_settings`) is what passes today.

| ID | Control (key) | Disposition / executable gate |
|---|---|---|
| S96 | `settingsAutoLoginSwitch` | L1 cand; `l3_settings_autologin_tap.json` (nonBlocking, unvalidated) + **READ-ONLY** data `l3_session_settings` (`l3_set_setting` REJECTS `autoLogin` — no write round-trip gate) |
| S97 | `settingsNotificationSoundSwitch` | L1 cand; `l3_settings_notifsound_tap.json` (nonBlocking) + data-half `l3_notification_sound_toggle` (S86) |
| S98 | `settingsDownloadLimitField`/`…SaveButton` | L1 cand; `l3_settings_downloadlimit_tap.json` (nonBlocking) + data-half `l3_download_limit_toggle` (S87) |
| S99 | `settingsBootstrapModeManual/Auto/Lan` | L1 cand; `l3_settings_bootstrap_mode_tap.json` (nonBlocking) + data-half `l3_bootstrap_mode_toggle` (S85) |
| S100 | `settingsCopyToxIdButton` | L3 clipboard (`pbpaste`); data-half `l3_self_id` (S31) |
| S101 | `profileEditToggle` | L1 cand; data-half `l3_self_profile_toggle` (statusMessage) |
| S102 | `profileToxIdCopyButton` | L3 clipboard (`pbpaste`); data-half `l3_self_id` |
| S103 | `profileQrCopyButton` | L3 — copies a PNG via `image_clipboard` (assert `osascript clipboard info`, not `pbpaste`); no data-half |
| S104 | `sidebarUserAvatar` | L1 cand (snapshot: profile widgets mount); no data field |
| S105 | `settingsExportProfileToxOption`/`…FullBackupOption` | chooser = L1 cand; native save dialog = L3 (S43) |
| S106 | `contactNewContactsTab`/`…GroupNotificationsTab`/`…BlockedUsersTab` | L1 cand (proven by `contact_application_anchors_test.dart`) |
| S107 | `contactBlockedUsersTab` + unblock | data-half S29 (`l3_block_toggle`/`run_fixture_c_block.sh`); row has no inline unblock key (opens profile) |
| S108 | `contactApplicationDetailAcceptButton(<uid>)` | two-process; accept data-path = `run_fixture_c_accept.sh` (S26); detail-tap spec-only |
| S109 | `contactApplicationsListEmpty` | L1 cand (proven by anchors test) |
| S110 | `contactGroupNotificationsTab` | surface L1 cand; live content L3-pinned (Fixture C, S47) |
| S111 | `userProfileClearHistoryButton`/`…ConfirmButton` | data-half `l3_clear_history`; UI tap L3/L1 |
| S112 | `userProfileDeleteFriendButton` | **no `l3_*` delete-friend tool**; data-half S28 (manual/two-process) |
| S113 | `userProfileEditRemarkButton`→dialog→`…ConfirmButton` | data-half `l3_friend_remark_toggle` (S30); real-dialog = L1 cand |
| S114 | `userProfileConversationMuteSwitch` | data-half `l3_recvopt_mute_toggle` (S83); banner-suppress two-process `run_fixture_c_mute.sh` |
| S115 | `friendProfileSendMessageButton` | UI nav (covered, not executable); no data-half |
| S116 | `conversationContextMenuPinItem`/`…UnpinItem` | data-half `l3_pin_toggle` (S84); menu-tap L3/L1 (REAL_UI_GATES #4) |
| S117 | conversation context-menu surface (4 items) | L1 cand (REAL_UI_GATES #4); the S15 analog for conversation rows |
| S118 | `conversationContextMenuMarkReadItem` | **EXPECTED-FAIL via menu** — `cleanConversationUnreadMessageCount` is a Tim2Tox no-op; working mark-read is S19; carries S19 nonBlocking race |
| S119 | `conversationContextMenuDeleteItem`→`deleteConversationConfirmButton` | **removal non-gateable** (friend-driven list, S20) — only clears history; menu+confirm surface = L1 cand |
| S120 | `chatInputTextField` (+ unattached `chatSendButton`) | **covered** — L1 WidgetTester gate #1 (typing+Enter→send, `chat_core_real_ui_test.dart`); live send L3; desktop needs real OS Return |
| S121 | `groupProfileMembersEntry` | entry = L1 cand; multi-member content = two-process `run_fixture_c_member_list.sh` (S36) |
| S122 | `groupProfileClearHistoryButton` | **no data-half** (`l3_clear_history` is C2C-only, rejects group ids); needs-new-tool / L1 |
| S123 | `groupProfileLeaveButton` | data-half `l3_leave_group` (S35); hermetic single-instance; UI tap L3/L1 |
| S124 | `groupAddMemberButton`→`groupMemberInviteConfirmButton` | two-process `run_fixture_c_group_invite.sh` (S81); native NGC residual; picker rows unkeyed |
| S125 | `manualNodeInputButton`/host/port/pubkey/`…TestButton` | form = L1 (`bootstrap_settings_section_test.dart`); live-connect = L3; add-path `l3_add_bootstrap_node`/`l3_dht_info` (S89) |

## 6b. Required ValueKey additions

> **Stale-by-construction, and scoped to S11–S70.** This table was
> written when `ui_keys.dart` was nearly empty; it holds ~150
> `static const` keys today, and many names below were landed under a
> different spelling (e.g. `chatInputTextField`, not
> `messageInputField`). There are **no rows here for S71+**, i.e. none
> of the S96–S125 control batch (§5c names those keys inline) and none
> of the S126–S185 group/conference block. Treat this as a historical
> wish-list; **`lib/ui/testing/ui_keys.dart` is the only authority for
> which keys exist**, and each playbook's `Driver` section names the
> keys it actually uses.

Add to `lib/ui/testing/ui_keys.dart` as you implement each scenario.
The high-priority ones:

| Scenario block | Keys to add |
|---|---|
| S11-S25 messaging | `messageInputField`, `messageSendButton`†, `messageEmojiButton`, `messageStickerButton`, `messageRecordButton`, `messageItem_<msgId>` (dynamic), `conv_<friendId>` (dynamic) |
| S26-S31 friend mgmt | `applicationItem_<reqId>` (dynamic), `acceptFriendButton_<reqId>`, `declineFriendButton_<reqId>`, `removeFriendButton`, `blockFriendButton`, `unblockFriendButton`, `editAliasField`, `copySelfIdButton` |
| S32-S37 groups | `addGroupSubmitButton`, `joinGroupSubmitButton`, `groupHeaderTap`, `groupMemberListButton`, `leaveGroupButton`, `groupAliasField` |
| S38-S47 settings | `settingsLanguageRow`, `settingsAutoLoginToggle`, `settingsSetPasswordButton`, `settingsChangePasswordButton`, `settingsExportAccountButton`, `settingsLogoutButton`, `settingsDeleteAccountButton`, `settingsAutoAcceptFriendToggle`, `settingsAutoAcceptGroupToggle` |
| S48-S50 search | `chatListSearchField`, `contactListSearchField` |
| S57-S60 robustness | (mostly no new keys — use existing structural assertions) |
| S65-S70 calls | `chatCallVoiceButton`, `chatCallVideoButton`, `callAcceptButton`, `callDeclineButton`, `callHangupButton`, `callMicMuteButton`, `callCameraToggleButton` |

Keep the snake_case convention (`message_input_field` etc.) and group by
screen in `ui_keys.dart`.

> **† `messageSendButton` does not exist on desktop.** The desktop input
> (`tencent_cloud_chat_message_input_desktop.dart`) is **Enter-to-send**
> with no tappable send affordance (Slack/Discord pattern). There is no
> widget to key, and synthetic Enter does not reach its legacy
> `RawKeyEvent.onKey` handler (see §7b "Message send via Enter key").
> Drive send-dependent assertions at L1/L2 via `sendTextMessage`, not by
> tapping a non-existent button. The key may still be relevant on a future
> mobile input layout.

## 7b. MCP limitations cheat sheet (what you can NOT drive)

> The "Affected scenarios" column only enumerates **S9–S66**; it was
> never extended past S70. The *limitations* themselves are still
> accurate and still apply to every later scenario that touches the
> same surface — read the left column, not the S-numbers. Several
> entries have since been softened by debug-only seams (the file
> picker is overridable via `l3_pick_avatar` /
> `run_fixture_c_avatar_picker.sh`; the notification tap is injectable
> via `l3_simulate_notification_tap`).

| Limitation | Affected scenarios | Workaround |
|---|---|---|
| Native file picker (`file_picker` package) | S9, S21-S22, S43, S47 | Test-override the call in the source: replace `FilePicker.platform.pickFiles(...)` with a stubbed call in debug-only mode, gated by an env var or a build-time const. |
| macOS permission prompts (Microphone / Camera / Screen Recording / Notification) | S59, S65-S66 | Grant permissions ahead of test run via `tccutil` or do a one-time manual approval; then test runs see the granted state. |
| `Clipboard.getData(...)` cross-process | S31 copy-id assertion | Read from `pbpaste` via shell after the tap. |
| Drag-and-drop file into window | S21-S22 alternative | Out of scope; not in toxee's spec anyway. |
| Native context menus (right-click) | S15 desktop menu | Toxee uses Flutter's PopupMenuButton, so this IS testable — just confirm via semantic_snapshot. |
| OS notification toast verification | S59 | Read macOS Notification Center via AppleScript / `osascript -e 'tell app "Notification Center" to ...'` if accessibility permission granted; otherwise skip. |
| **Message send via Enter key** (desktop input is Enter-to-send; there is no tappable send button) | S12, S17, S18, S25, S62, S64 — anything that sends a message | Empirically (2026-05-29 run): synthetic key events from `arenukvern.fmt_press_key` reach Flutter's *new* `KeyEvent`/`Shortcuts` path (`Escape`→dismiss dialog and `Cmd+A`→select-all both work) but do **not** invoke the *legacy* `RawKeyEvent` `FocusNode.onKey` callback that `tencent_cloud_chat_message_input_desktop.dart::_handleKeyEvent` uses to call `sendTextMessage` (it requires `event.runtimeType == RawKeyDownEvent` + `physicalKey == enter`). So typing works (`fmt_enter_text`/`setText`) but the synthetic Enter never sends. **WORKAROUND (validated 2026-05-29 against the echo peer): inject a REAL OS-level Return.** Type via `fmt_enter_text`, then: `osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "Toxee") to true' -e 'delay 0.5' -e 'tell application "System Events" to key code 36'`. The real key event flows through `RawKeyboard` → `onKey` → `sendTextMessage`, delivers over the live DHT, and (with `peerHarness=echo_live`) the echo returns. Requires the terminal to have macOS Accessibility permission (System Events). This is how S12/S62 send-and-receive were driven end-to-end. The deterministic send→bubble→persist assertion still belongs at **L1/L2** (drive `FfiChatService.sendTextMessage` directly) — the osascript path is for live-DHT L3 round-trips that L2 can't do. |

## 6. Test orchestrator skeleton

A test scenario in this framework is a sequence of MCP calls + assertions.
The simplest "orchestrator" is the AI agent itself (you, Claude) following
this playbook in conversation. For repeatable runs, wrap into a script:

```typescript
// orchestrator pseudocode
async function runScenario(name: string, steps: Step[]) {
  await ensureFixture(name);
  const uri = await launchAndGetVmUri();
  await marionette.connect(uri);
  await arenukvern.connect(uri);
  for (const step of steps) {
    await step.run({ marionette, arenukvern, dartOfficial });
    await step.assert();
  }
  await teardown();
}
```

Or in shell:

```bash
./test/mcp/run_scenario.sh S3_account_switch
```

backed by a per-scenario JSON / YAML describing taps, expected labels, and
timeouts.

## 7. Pain points + workarounds

| Pain | Workaround |
|---|---|
| VM service URI not in `flutter_client.log` (engine prints it to stdout, AppLogger truncates the file with `FileMode.write`) | `MCP_BINDING=skill ./run_toxee.sh` tees engine stdio to `build/toxee_stdio.log` and writes the normalised URI to `build/vm_service_uri.txt`. Wait ≤30s after launch, then `URI=$(cat build/vm_service_uri.txt)`. See F2 + F5 in `../../tool/mcp_test/REAL_UI_GATES.md`. |
| DDS interposes when launched via `flutter run` (blocks marionette + arenukvern WebSocket upgrade) | Always launch via standalone bundle (`./run_toxee.sh`), never `flutter run` for MCP-driven tests. |
| Hive boot can deadlock under hermetic `TestWidgetsFlutterBinding` (proven on 2026-05-28 startup smoke move) | Don't try to hermetic-ize app-level smokes. Use `integration_test/` with `needs-native` tag OR run real binary via MCP. |
| Tox DHT bootstrap is 5-30s | All `wait until online` assertions need timeouts of ≥60s. Don't sleep — poll `semantic_snapshot` for the state change. |
| `arenukvern.fmt_tap_widget` silently no-ops on widgets without Semantics.onTap | Fall back to `marionette.tap` (synthetic gesture) for any widget that fails. Or add `Semantics(onTap: ...)` wrapper. |
| Native file picker can't be driven by MCP | Test override the file-picker call in the source. Or accept the scenario is out of scope. |
| Orphan Toxee processes after kill (binary survives bash subshell death) | Always kill by Toxee PID from `pgrep -fl "Debug/Toxee.app"`, never trust `kill <bash_pid>`. |

## 8. Playbook policy — thin vs heavy

Codex's 2026-05-28 review's specific guidance:

> 现在的 playbook 更像高质量 investigation memo, 不像可持续 regression
> asset […]. 保留 5-10 个高价值 scenario 用这种重模板, 其他场景降成
> 薄规格, 只保留 precondition/driver/assertions. 把"Required source
> changes / Blockers / Runtime / bug theory"移到 companion note,
> 不要每个 scenario 都变成半篇设计文档.

The retention policy is in
[`UI_TEST_LAYERING.md` §5](UI_TEST_LAYERING.md#5-heavy-playbook-list-and-thin-spec-rule).
Today's heavy playbooks: **S3, S8, S40** — and only because each
earned a real bug. Everything else uses the thin spec template in
§7 of the layering doc.

A playbook becomes heavy *when it earns it*, not by ambition.

## 9. Promotion protocol — how MCP-found bugs become stable

Every MCP-discovered bug must produce a **promotion decision** before
the fix lands. The protocol is canonical in
[`UI_TEST_LAYERING.md` §4](UI_TEST_LAYERING.md#4-promotion-protocol).
The short form:

1. Find minimal dependency set the regression test needs (layering
   doc §3).
2. Pick the target layer from that minimal set (L1 if possible).
3. Land fix + regression test at the target layer in the same PR.
4. Slim the L3 playbook to one-paragraph repro + link to the
   regression test.

If the regression can **only** be detected with L3-only deps (live
DHT, two processes, native dialog), the playbook stays heavy and the
`Notes` section calls out the L3-pin reason.

This is the only piece that keeps the MCP layer from re-evaporating
bugs into 300-line investigation memos.

## 10. Concrete handoff to follow-up work

1. `tool/mcp_test/launch_and_uri.sh` — encapsulates the standalone
   build + VM URI extraction in a single script that prints
   `URI=ws://…/ws` on stdout.
2. `tool/mcp_test/fixtures/single_signed_in/` and `two_saved_none_signed_in/`
   — pre-staged disk states for the two single-instance convenience
   snapshots from §4. (`paired_for_e2e` is already staged for you by
   the pair launchers / `restore_fixture_c_pair.sh`.)
3. ~~L2 regression tests for the three earned heavies (S3, S8, S40).~~
   **Done 2026-05-29** — see the promotion table in
   [`UI_TEST_LAYERING.md` §4](UI_TEST_LAYERING.md#4-promotion-protocol).
   All three landed at L1 rather than L2; that deviation is documented
   there. The playbooks have not yet been slimmed to repro pointers.
4. ~~The Fixture C spike.~~ **Done** — it became the shipped
   two-process harness (`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`).
   Remaining follow-up: the first live **two-emulator Android**
   `paired_for_e2e` validation run.
5. Re-cut §5a/§5b/§5c or delete them in favour of
   [`test/mcp/INDEX.md`](../../test/mcp/INDEX.md). They stop at S125
   while the catalog runs to S185, and they carry four ghost rows
   (S1/S6/S7/S73). The generated index has no such drift.
