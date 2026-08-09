[简体中文](./UI_TEST_LAYERING.zh-CN.md)

# UI Test Layering — toxee

**Status**: source of truth as of 2026-05-28; §4/§5/§6/§7/§8 fact-refreshed
2026-08-07 (the Fixture C spike passed — §6 no longer gates anything).
**Supersedes**: the "Track 1 / Track 2" split in earlier drafts of
`../../tool/mcp_test/REAL_UI_GATES.md` and the "shell + raw VM URI + marionette/arenukvern"
routing fragments in `doc/architecture/MCP_UI_TEST_PLAYBOOK.md` (those docs now point here).

This is the canonical answer to "where does this UI test belong?" and
"when does an MCP-discovered bug graduate into a stable regression
asset?". Codex review on 2026-05-28 flagged that the previous track
split was drawn on the wrong axis (CI vs AI / simulated user vs not).
The actual fault line is **dependency surface**, and that gives us
three layers, not two.

## 1. The three layers

| Layer | Lives in | Binding | Allowed deps | Use for |
|---|---|---|---|---|
| **L1 — Widget / seam** | `test/` | `TestWidgetsFlutterBinding` + mocked channels | Pure Dart, mocked platform channels, stub `FfiChatService`, stub `StartupSessionUseCase` | Single-screen flows behind a constructor seam: dialog state machines, form validation, button-enabled gating, sidebar key plumbing, individual use-case classes. |
| **L2 — Host-bundle / lifecycle** | `integration_test/` (tag `needs-native`) | Real host binary with `libtim2tox_ffi` loaded | Real Flutter engine, real native lib, real Hive, real `path_provider`, real `SharedPreferences`, real `SessionRuntimeCoordinator`. **No live DHT network** — friend state must be pre-seeded on disk. | Whole-app lifecycle flows: cold start → LoginPage → HomePage; account switch; profile-edit-then-switch; password lifecycle; theme/locale persistence across restart; window-bounds restore. |
| **L3 — MCP playbook** | `test/mcp/Snn_*.md` (driven by an AI agent over MCP) | Real standalone bundle, no DDS, no harness | Everything L2 has PLUS live Tox DHT, real microphone/camera, multi-instance, native file picker, OS notification, drag-and-drop. | Things L2 can't deterministically pin down: live-network handshakes, voice/video paths, OS-permission gates, multi-instance interop (Fixture C — the spike has landed, see §6). |

The layers are **nested**, not parallel. A test belongs in the
**lowest** layer that can express it. If a flow can be driven by
mocked channels + a constructor seam, it goes in L1; if it needs the
real Hive bootstrap and `libtim2tox_ffi`, it goes in L2; if it needs
the live DHT or a sibling process, it goes in L3.

**Don't draw the line "AI explores ↔ CI gates".** Both L1 and L2 are
CI-gateable; L3 is not (today). But the gating property follows from
the dependency surface, not the other way around.

## 2. Why the previous Track-1/Track-2 split was wrong

The previous draft tried to split tests by who would run them:

- "Track 1 = `flutter_test` / `integration_test`, CI-gated."
- "Track 2 = MCP-driven, AI explores."

Two problems showed up almost immediately:

1. **The cold-start smoke escaped Track 1 into Track 2.** It hung at
   `TencentCloudChatMaterialApp._getLocale → cache.init` (Hive) under
   `TestWidgetsFlutterBinding` because Hive bootstrap needs more than
   path-provider channel mocks. That's not an exploratory flake — it's
   a hard dependency-surface boundary. Track 1 couldn't take it, so it
   was sent to Track 2 by exception. With three layers, it just goes
   to L2 by rule.
2. **MCP playbooks accumulated "really should be in CI" content.**
   S3 (account switch), S8 (profile edit), S40 (password lifecycle)
   all caught real bugs; the natural follow-up is "lock that in", and
   "lock that in" needs a layer that doesn't depend on the live DHT.
   That layer is L2. The old split didn't have a place for it.

The 2026-05-28 codex review's specific guidance:

> Track 1 和 Track 2 的边界现在画错了 […]. 真正的分界不是"CI vs AI"或"模拟用户 vs 不模拟用户"，而是"依赖面"。建议重画成 3 层：`test/` 做纯 Dart/widget seams, `integration_test/` 做 host-bundle 但尽量 deterministic 的 app/session/lifecycle flows, MCP playbook 只做真实网络、真实多实例、原生弹窗、复杂回归复现。

This document is the answer.

## 3. Which layer does <flow> belong in?

The decision is purely about dependencies, not "is it a user flow".

| If the flow needs… | Layer |
|---|---|
| Real Hive bootstrap | L2 or L3 (never L1) |
| Real `libtim2tox_ffi` `dlopen` | L2 or L3 |
| Real `path_provider` writing to a disk path | L2 or L3 |
| Real `window_manager` window | L2 (macOS) or L3 |
| Real platform channels for `tencent_cloud_chat_*` plugins | L2 or L3 |
| Live Tox DHT handshake | L3 only |
| A second running toxee process | L3 only (Fixture C harness, §6) |
| Native file picker | L3 only |
| Microphone / camera / OS notification permission | L3 only |
| OS clipboard cross-process verification | L3 only |
| Drag-and-drop file into the window | L3 only |
| None of the above | L1 |

This is also the **promotion compass**: when an L3 playbook finds a
real bug, drop the "none of the above" items off the list above; if
the remaining set fits L2, the regression test belongs in L2 and the
playbook can be slimmed to one-line repro pointer.

## 4. Promotion protocol

This is the part that was missing and let knowledge re-evaporate into
investigation memos. Every time an MCP playbook surfaces a real bug,
you must produce a **promotion decision** before the bug fix lands:

1. Identify the **minimal dependency set** the regression test needs.
   (Walk the table in §3 from top to bottom; first match wins.)
2. Pick the target layer from that minimal set.
3. Land the fix + a regression test in the target layer, in the same
   PR (or as the immediate follow-up). The regression test is what
   makes the bug stop coming back; the playbook is what found it.
4. Slim the playbook to a one-paragraph repro pointer + link to the
   regression test. Don't keep maintaining the 300–700-line
   investigation memo once a stable assertion exists.

Promotion decisions live in the bug-fix PR description and reference
this protocol. If a promotion is **not possible** (the regression can
only be detected over the live DHT, say), the playbook stays heavy
but must call out the L3-pin reason in its `Notes` section so
maintainers don't expect the L1/L2 conversion later.

### Promotion backlog — the original 3 have all landed (2026-05-29)

The three protocol invocations that this section used to track as
"in flight" now all have a landed regression test. They stay here as
worked examples of the protocol running end-to-end.

| Bug | Found by | Regression test | Status |
|---|---|---|---|
| `initializeServiceForAccount` doesn't reset global `nickname/statusMessage/avatarPath` Prefs on switch | S3 (MCP playbook, user manual repro) | `test/account_switch_resets_global_prefs_test.dart` | landed — asserts post-switch nickname/status/current-toxId globals are B's, and that A's avatar path does not leak |
| `showSelfProfile.onSave` doesn't mirror nickname into `account_list` | codex review #2 + S8 | `test/ui/profile_edit_persists_to_account_list_test.dart` | landed — drives the real `showSelfProfile` → `ProfilePage._handleSave` → `onSave` closure and asserts the `account_list` mirror |
| Password handling: `SessionPasswordStore` drift + post-remove re-encrypt + autoLogin failure paths | S40 (MCP playbook research) | `test/account_password_lifecycle_test.dart` | landed — one group per bug (store keyed under the canonical toxId; remove-password leaves the profile plaintext; encrypted profile + autoLogin routes to `StartupShowLogin`). Skips only when the FFI dylib is unloadable. |

**Honest deviation from the protocol: all three landed at L1, not L2.**
The protocol says "real `libtim2tox_ffi` ⇒ L2 (`integration_test/`)",
and all three were scoped as L2 candidates above. In practice two of
them (`account_switch_resets_global_prefs`, `account_password_lifecycle`)
use a **third shape the L1/L2 definitions don't name**: they `dlopen`
the real `libtim2tox_ffi` and run real `init`/`login`/Tox encryption,
but they never pump `TencentCloudChatMaterialApp`, so they never touch
the Hive `_getLocale` bootstrap that forced the L2 split in the first
place. That makes them runnable under plain `flutter test` with an
`_ffiAvailable()` skip-guard instead of a `needs-native` host bundle.
The third (`profile_edit_persists_to_account_list`) is a pure widget
test with a stub `FfiChatService` — genuinely L1.

The operative rule is therefore narrower than §1's table suggests:
**"real FFI" alone does not force L2 — "pumps the full host
MaterialApp" does.** Until §1 is re-cut, treat "real FFI + no
MaterialApp pump" as an L1 sub-shape and say so in the test header
(all three do).

**Protocol rule.** The bug-fix PR description MUST contain a
`Promotion decision:` checklist with the layer + regression-test PR#
(even if "pending — issue #X"). A bug fix without a promotion
decision is a fix that's still incubating the bug.

These are the three "heavies" in §5. Every other playbook stays
thin and uses the promotion protocol when it earns a bug.

## 5. Heavy playbook list (and thin-spec rule)

We retain **three** heavy playbooks today, all earned a bug (they are
also the only three `test/mcp/S*.md` files over 100 lines):

- `test/mcp/S3_account_switch.md` — the 2026-05-28 regression
- `test/mcp/S8_profile_edit.md` — codex review #2 sibling bug
- `test/mcp/S40_set_password.md` — three independent password bugs

All other playbooks (**175** of the 178 that exist as of 2026-08-07;
numbering runs S2–S185 with gaps) use the **thin spec template** in §7.
Don't hand-maintain that count anywhere else — `test/mcp/INDEX.md` is
generated from the playbook headers and its freshness is CI-gated by
`gen_scenario_index.dart --check`. Codex's specific guidance, which we
adopt:

> 保留 5-10 个高价值 scenario 用这种重模板，其他场景降成薄规格，
> 只保留 precondition/driver/assertions。把"Required source changes /
> Blockers / Runtime / bug theory"移到 companion note，不要每个
> scenario 都变成半篇设计文档。

Three is below codex's 5-10 range. The honest reason: those are the
only three that have actually yielded a bug. The playbook becomes
heavy *when it earns it*, not by ambition.

When a thin playbook earns a bug, choose:
- Bug is L1- or L2-promotable → write the regression at that layer,
  leave the playbook thin with a one-line "this caught
  `<bug-link>` 2026-MM-DD".
- Bug is L3-pinned → upgrade the playbook to heavy and add a `Notes`
  section explaining the L3-pin reason.

## 6. Fixture C (multi-instance) — the spike passed; it is shipped harness

**Superseded 2026-08-07.** This section used to say that "two toxees on
one machine" had *never been validated end-to-end as test
infrastructure*, and that all multi-instance scenarios were therefore
tracked as `backlog`, not `covered`. That is no longer true, and the
old wording was the upstream source of ~20 stale
`blocked on Fixture C spike` rows downstream. The 2026-05-28 codex
review that demanded the spike:

> 多实例 E2E 目前仍是战略假设，不是已验证基础设施 […]. 这里应该先做
> 一个唯一目标的 spike：只证明 C 能稳定跑 launch A + launch B + add
> friend + ping/pong + teardown. 这个 spike 不过，后面所有基于 C 的
> catalog 都应降级成 backlog.

The spike passed and grew into a real harness. Current state:

- **29 manifest entries** in `tool/mcp_test/fixture_c_manifest.json`
  (28 `2proc-l3` + 1 `2proc-ui`), each naming its base fixture, driver,
  cost, and media/destructive flags.
- **28 per-scenario `run_fixture_c_*.sh` wrappers** referenced by the
  manifest (plus `run_fixture_c_suite.sh` = 29 shell files on disk) and
  **27 `drive_fixture_c_*.dart` drivers**; the `2proc-ui` entry is
  driven by `drive_real_ui_pair.dart` instead of a shell wrapper.
- All of it is planned and executed through the single
  `tool/mcp_test/fixture_c_unified_runner.dart` entrypoint; the shell
  wrappers are compatibility shims.
- **Pair launchers exist for all five platforms**:
  `launch_fixture_c_pair.sh` (macOS), `launch_ios_fixture_c_pair.sh`,
  `launch_android_fixture_c_pair.sh`, `launch_linux_fixture_c_pair.sh`,
  `launch_windows_fixture_c_pair.ps1` (+ `launch_mixed_macos_ios_pair.sh`).
- Most multi-instance playbooks that used to read
  `Status: blocked on Fixture C spike` now read
  `covered by executable Fixture C gate … validated live 2026-06-01`.
  `test/mcp/INDEX.md` is the generated, CI-gated truth for per-scenario
  status — read it, don't trust a hand-written table.

**Residual gaps (honest).** "The harness exists" is not "every platform
is live-green":

- **Android `paired_for_e2e` restore has never had its first live
  two-emulator validation run.** The implementation is there (the
  runner's old planning-time Android reject was removed 2026-07-12; the
  snapshot is streamed into the debug app's sandbox via
  `adb exec-in run-as com.toxee.app tar -x`), but per
  `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md` §"platform" table: *do not
  report friendship scenarios as android-green until that run lands.*
- Live two-process runs are a **local point-in-time gate**, not CI. No
  `2proc-*` class runs in CI today.
- A handful of scenarios stay genuinely non-green for reasons that were
  never about the spike: S47/S81 (native NGC invite-delivery timing),
  S63 (read receipts need a tim2tox msgID round-trip), S37 role-change
  (unwired), S79-adjacent native-picker seams, and anything gated on an
  OS TCC grant (mic/camera/notification).

Harness contract, per-platform launcher details, and the restore
semantics are in `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`.

## 7. Thin playbook template

```markdown
# Snn — <title>

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online window=default`
**Harness mode**: peerHarness=<none|echo_seeded|echo_live>
**Promotion target**: L2 if [conditions met] | L3-pinned because [reason]
**Status**: covered | covered by executable Fixture C gate <script> | partial (<what's missing>) | informational only

## Precondition
- One bullet per state-vector axis that matters.
- No prose. State assertions, not setup recipes.

## Driver
1. Numbered taps / inputs / waits. One MCP call per step.
2. Reference UiKeys by Dart field name (`UiKeys.sidebarChats`),
   not raw string.

## Assertions
- One bullet per observable. Either a semantic-snapshot label, a
  widget-tree query, a log line, or a Prefs/disk-state check.

## Notes
- ≤5 lines. Known flakiness, L3-pin reason if any, linked bug if
  this playbook ever earned one.
```

The old `blocked on Fixture C spike` / `blocked on media spike` status
values are **retired** (§6). The voice/video entries S65–S70, S74–S78
all have executable Fixture C call gates today
(`run_fixture_c_call.sh`, `run_fixture_c_missed_call.sh`,
`run_fixture_c_voice_msg.sh`, `run_fixture_c_network_drop.sh`); what
remains for them is an OS TCC mic/camera grant, which belongs in the
`Notes` section as a live precondition, not in the `Status` header.
If a scenario genuinely cannot run, say `partial (…)` and name the
concrete missing thing.

If a playbook can't be expressed in this template, that's a signal
it's actually doing investigation work — either promote it to heavy
(with a stated reason) or split it into two thin specs.

## 8. State vectors (replaces "Fixtures A/B/C")

A fixture is now expressed as a vector of independent state axes,
not a named template. The composable axes (fenced for pipe-safe
rendering — table-form versions of this kept escaping markdown):

```
axis            values                              persistence
─────────────   ─────────────────────────────────   ────────────────────────────────
accounts        <int>  (0 / 1 / N)                  ~/.../profiles/p_*
current         none | <toxId>                       Prefs.currentAccountToxId
profileCrypt    plain | pwd:<password>               encrypted .tox blob
autoLogin       on | off                             per-account row in account_list
network         online | offline                     env / external
window          default | geom:<W>x<H>+<X>+<Y>       Prefs.windowBounds
sessionPwd      none | cached                        SessionPasswordStore
history         empty | seeded                       MessageHistoryPersistence SQLite
dhtCache        cold | warm                          ~/.../tox_data/dht_cache.json
friends         <int>  (per-account)                 per-account state dir
theme           light | dark                         Prefs.themeMode
locale          zh | en | ja | ko | ar               Prefs.languageCode
```

A playbook's "Fixture vector" line is a comma-separated subset of
these — only axes that the scenario *cares* about. Other axes are
"don't care" and inherit from the running test environment.

For three pre-seeded common compositions, `tool/mcp_test/fixtures/`
(planned) will ship snapshots:

- `single_signed_in` — `accounts=1 current=A1 autoLogin=on network=online`
  (replaces the old "Fixture A")
- `two_saved_none_signed_in` — `accounts=2 current=none autoLogin=off`
  (replaces the old "Fixture B")
- `paired_for_e2e` — `accounts=2 current=A1 friends=1 sessionPwd=none`
  + a paired profile staged for a second toxee process (replaces the
  old "Fixture C"). **Shipped**, not blocked: restore is wired on all
  five platforms via the pair launchers, with the Android first-live
  two-emulator validation still outstanding (§6).

The named compositions are convenience wrappers over the vector
language, not a replacement for it.

## 8.1 Harness modes

A **harness mode** describes the external test infrastructure a scenario
opts into. It is **orthogonal** to the §8 state vector — the state
axes (`accounts/current/friends/history/…`) say what's on disk; the
harness mode says what else is running alongside toxee during the test.
Scenarios are encouraged to declare both axes independently.

```
axis            values                              persistence
─────────────   ─────────────────────────────────   ────────────────────────────────
peerHarness     none | echo_seeded | echo_live      external process / fixture cache
```

- `none` — no echo peer involvement; the scenario is single-instance
  + single-account (or single-instance + multi-account on disk) and
  doesn't need a second Tox endpoint to talk to.
- `echo_seeded` — echo peer is **NOT running** during the test; the
  state vector inherits a friend + chat-history snapshot produced by
  `tool/mcp_test/restore_echo_peer_seed.sh` (first-time generation:
  `tool/mcp_test/regen_echo_peer_seed.sh`). Use when the scenario only
  needs *the appearance of having paired with someone* (a friend row,
  a chat history, an offline-queue entry) without any live network
  participation. Fast and deterministic; the snapshot is cached
  per-maintainer-machine.
- `echo_live` — echo peer **IS running** during the test (launched via
  `tool/mcp_test/ensure_echo_peer.sh`; the canonical peer ID is read
  from `tool/mcp_test/echo_peer.json::peer_id`). Use when the scenario
  needs a real DHT handshake (AddFriend), real echo arrival, or real
  offline-queue reconnect against a genuine Tox endpoint.

**Echo peer modes are NOT a substitute for Fixture C.** Full Fixture C
(`paired_for_e2e`, two toxee processes on one host) is a different
harness and now a **shipped** one — see §6 and
[`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`](../../tool/mcp_test/REAL_UI_TWO_PROCESS.md).
The echo peer is a single non-toxee process speaking Tox protocol;
from toxee's perspective it is one external peer, so it can stand in
for AddFriend / echo-arrival / reconnect flows but never for a
scenario that genuinely needs two toxees (S46/S47/S59, S61–S70).
Route those through the unified runner's `2proc-*` classes, not the
echo peer.

## 9. What to read next

- `doc/architecture/MCP_UI_TEST_PLAYBOOK.md` — the MCP routing matrix, the
  no-DDS launcher contract, and the L3 scenario catalog.
- `../../tool/mcp_test/REAL_UI_GATES.md` — current L1/L2/L3 test
  inventory and the next L2 conversions to land.
- `../../test/mcp/INDEX.md` — the **generated** per-scenario coverage
  index (layer, execution class, executable artifacts, status).
  CI-gated for freshness by `gen_scenario_index.dart --check`. This is
  the authority for "is Snn covered?"; no hand-written table is.
- `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md` — the Fixture C
  (multi-instance) harness contract: launchers, restore semantics,
  per-platform status.
- `../../tool/mcp_test/REAL_UI_GATES.md` — why L3 must
  launch via standalone bundle, not `flutter run`.
