[简体中文](./UI_TEST_LAYERING.zh-CN.md)

# UI Test Layering — toxee

**Status**: source of truth as of 2026-05-28.
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
| **L3 — MCP playbook** | `test/mcp/Snn_*.md` (driven by an AI agent over MCP) | Real standalone bundle, no DDS, no harness | Everything L2 has PLUS live Tox DHT, real microphone/camera, multi-instance, native file picker, OS notification, drag-and-drop. | Things L2 can't deterministically pin down: live-network handshakes, voice/video paths, OS-permission gates, multi-instance interop (gated by the Fixture C spike, see §6). |

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
| A second running toxee process | L3 only (gated by spike, §6) |
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

### Open promotion backlog (3 in flight, 2026-05-28)

These three protocol invocations are mid-flight: each found a bug,
each has a fix candidate, **none has a landed L2 regression test
yet**. They appear here as worked examples of the protocol's own
gaps — until column "Promotion landed?" reads a PR number, the
playbook on the right stays heavy.

| Bug | Found by | Minimal deps | Promotion landed? | Owner | Target |
|---|---|---|---|---|---|
| `initializeServiceForAccount` doesn't reset global `nickname/statusMessage/avatarPath` Prefs on switch | S3 (MCP playbook, user manual repro) | Real Hive + real `Prefs` + stub `FfiChatService` (L2) | pending — issue TBD | TBD | TBD |
| `showSelfProfile.onSave` doesn't mirror nickname into `account_list` | codex review #2 + S8 | Same as above (L2) | pending — issue TBD | TBD | TBD |
| Password handling: `SessionPasswordStore` drift + post-remove re-encrypt + autoLogin failure paths | S40 (MCP playbook research) | Real Hive + real Tox encryption + real `Prefs` (L2; L3 if encryption needs FFI rebuild) | pending — issue TBD | TBD | TBD |

**Protocol rule.** The bug-fix PR description MUST contain a
`Promotion decision:` checklist with the layer + regression-test PR#
(even if "pending — issue #X"). A bug fix without a promotion
decision is a fix that's still incubating the bug.

These are the three "heavies" in §5. Every other playbook stays
thin and uses the promotion protocol when it earns a bug.

## 5. Heavy playbook list (and thin-spec rule)

We retain **three** heavy playbooks today, all earned a bug:

- `test/mcp/S3_account_switch.md` — the 2026-05-28 regression
- `test/mcp/S8_profile_edit.md` — codex review #2 sibling bug
- `test/mcp/S40_set_password.md` — three independent password bugs

All other playbooks (37 of them as of 2026-05-28) use the **thin spec
template** in §7. Codex's specific guidance, which we adopt:

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

## 6. Fixture C (multi-instance) is gated on a spike

The "two toxees on one machine" pattern that S46/S47/S59 and the
S61-S70 multi-instance block depend on has **never been validated
end-to-end as test infrastructure**. The 2026-05-28 codex review:

> 多实例 E2E 目前仍是战略假设，不是已验证基础设施 […]. 这里应该先做
> 一个唯一目标的 spike：只证明 C 能稳定跑 launch A + launch B + add
> friend + ping/pong + teardown. 这个 spike 不过，后面所有基于 C 的
> catalog 都应降级成 backlog.

Spike requirements + acceptance criteria are in
`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`. **Until that spike passes,
all multi-instance scenarios are tracked as `backlog`, not `covered`.**
They keep their thin specs (so the desired flow is recorded), but
the playbook header reads `Status: blocked on Fixture C spike`.

## 7. Thin playbook template

```markdown
# Snn — <title>

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online window=default`
**Harness mode**: peerHarness=<none|echo_seeded|echo_live>
**Promotion target**: L2 if [conditions met] | L3-pinned because [reason]
**Status**: covered | blocked on Fixture C spike | blocked on media spike | informational only

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

`blocked on media spike` covers the voice/video entries (S65-S70) that
depend on mic/camera permission under automation + the ToxAV call
lifecycle (the separate media spike referenced in
`doc/architecture/MCP_UI_TEST_PLAYBOOK.md` §5a). A scenario blocked by more than
one spike combines them, e.g. `blocked on Fixture C spike + media spike`
(needs both a second toxee and the media stack).

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
  old "Fixture C"; **blocked on the multi-instance spike**)

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
(`paired_for_e2e`, two toxee processes on one host) remains **blocked
on the multi-instance spike** in
[`../../tool/mcp_test/REAL_UI_TWO_PROCESS.md`](../../tool/mcp_test/REAL_UI_TWO_PROCESS.md).
The echo peer is a single non-toxee process speaking Tox protocol;
it unblocks single-instance scenarios that need a real peer to talk to,
but it does **not** unblock any scenario that requires two toxees
(S46/S47/S59, S61-S70). Those stay `Status: blocked on Fixture C
spike` regardless of echo peer availability.

## 9. What to read next

- `doc/architecture/MCP_UI_TEST_PLAYBOOK.md` — the MCP routing matrix, the
  no-DDS launcher contract, and the L3 scenario catalog.
- `../../tool/mcp_test/REAL_UI_GATES.md` — current L1/L2/L3 test
  inventory and the next L2 conversions to land.
- `../../tool/mcp_test/REAL_UI_TWO_PROCESS.md` — spike contract for
  Fixture C (multi-instance) work.
- `../../tool/mcp_test/REAL_UI_GATES.md` — why L3 must
  launch via standalone bundle, not `flutter run`.
