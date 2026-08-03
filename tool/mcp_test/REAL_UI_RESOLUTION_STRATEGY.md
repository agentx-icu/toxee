# Real-UI campaign resolution strategy (2026-06-13)

> Durable methodology for driving the real-UI (real-app) test campaigns to GREEN.
> User directive (2026-06-13): solve every real-UI case, deep-root-cause every
> blocked item, reuse app startup aggressively, parallelize to go faster, and
> discuss tricky problems with codex. This file is the playbook any session
> follows; the per-campaign run state lives in `REAL_UI_GATES.md` and
> `REAL_UI_GATES.md`.

## Goal

1. **Every real-UI (real-app) case PASSES** — drive the production widget, not a
   hermetic stub. A case only "SKIPs" when its environment genuinely cannot be
   constructed (native OS picker, real mic/cam, OS notification click), and the
   skip is named with evidence.
2. **Every blocked item is deeply root-caused and fixed** at the correct layer
   (native/FFI → fork → app), never a surface patch that hides the symptom.
3. **Startup is reused** — one app-pair launch chains as many cases as possible
   (shared accounts + A↔B friendship), so we don't re-launch / re-register /
   re-friend per case.

## Parallelization strategy

Live runs are **inherently serial** on this machine: they drive the macOS
foreground (osascript) and share the `tool/mcp_test/.multi_instance_runtime/{A,B}`
instance state — two campaigns can't run at once. So parallelism goes into
*everything except the live run*:

- **Background subagents for investigation.** Spawn read-only agents (deep code
  traces, campaign surveys, verify-first case audits) concurrently while the main
  thread works a different fix. Agents return findings + ranked fix options; the
  main thread applies the edits (agents do NOT edit shared files — avoids
  conflicts in the fork / tim2tox).
- **Batch fixes into ONE build.** A macOS rebuild is ~minutes; never rebuild
  per-fix. Collect all root-cause fixes discovered in a round, apply them, then
  build once and run the broadest reuse-startup campaign that exercises them.
- **codex in parallel with edits.** Draft a fix → kick codex review → continue on
  the next fix while codex runs → apply codex findings. codex is mandatory on
  every change and is the partner for tricky root-causes (per user directive).

## Fix strategy (deep root-cause only)

1. **Verify-first.** Read the CURRENT code for the failing case — never trust a
   doc's "blocked / N-A / expected-fail" status; line numbers and behavior drift.
2. **Locate the true layer.** A rendered-list bug is usually fork (UIKit data
   services); a wire/persistence/preview bug is usually tim2tox
   (`FfiChatService` / `Tim2ToxSdkPlatform`); a startup/nav bug is usually toxee
   app. Fix it there, not in the harness — unless the harness is provably at
   fault (offstage duplicate-key, band-stall, synthetic-enterText SIGSEGV).
3. **Draft → codex → apply.** Bundle the diff, have codex verify correctness, ABI
   byte-match (for `dart_compat_*.cpp`), memory/ownership, and **mobile parity**.
   Apply findings before moving on. If codex is down: declare the skip,
   self-validate (code-reviewer agent + analyzer + touched tests), record the
   owed review.
4. **Mobile parity per fix.** Shared-Dart fix (fork widget, `lib/util`,
   `lib/sdk_fake`, `third_party/tim2tox/dart`) → already covers mobile, say so.
   Platform-specific fix → find/address the mobile twin or state the gap.

## Reuse-startup run strategy

Prefer the optimized single-launch bundles (they launch the pair once, establish
A↔B once, and reuse it across child sweeps):

- `rui-optimized-current` — broadest: A-only optimized chain THEN the friendship
  optimized chain, all under one launch. **Default first broad smoke.**
- `rui-c2c-optimized` — pair once + friendship once, reused across
  `sweep_conv` / `sweep_chat` / `sweep_c2c_extra` / `sweep_c2c_deep_extra`.
- `rui-friendship-optimized` — friendship-preserving sweeps (C2C + p1-chat +
  p2-reply/verify + p3 + group2 + member/deep extras + calls-misc).
- `rui-single-app-optimized` — A-only sweeps (settings2 / profile / login /
  p1-single / p1-extra / account-conf-extra / account-deep-extra).

**Must run standalone (state-poisoning / restart / native):** `rui-contacts`
(deletes friendship; remark live finding), `rui-p1-relaunch` + `rui-p2-keys`
(restart peers internally), `rui-native-boundary-guards` (designed OS/mobile
SKIPs). Verify with `--plan-json` that a campaign doesn't add unnecessary
launches before running it.

## Run protocol (the loop)

```bash
# 1. validate catalog (no app needed)
dart run tool/mcp_test/fixture_c_unified_runner.dart --validate-only
dart run tool/mcp_test/fixture_c_unified_runner.dart --plan-json --class=2proc-ui --real-ui-campaign=<name>
# 2. build (REQUIRED: l3 surface + fresh dylib; plain build_all/flutter build miss them)
MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh
# 3. run broad reuse-startup campaign first
dart run tool/mcp_test/fixture_c_unified_runner.dart --class=2proc-ui --real-ui-campaign=rui-optimized-current
# 4. narrow to the smallest failing campaign, root-cause, batch fixes, rebuild, re-run
```

Then: update the per-campaign Status + Batch log, codex-review the diff,
`gen_scenario_index.dart --check`, commit (fork → tim2tox → toxee push order so
pinned submodule SHAs exist on remotes; bootstrap is safe now that origin/v2
carries the keys).

## Standing hazards (carry forward every session)

- Build ONLY via `MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh` (l3 surface
  compiled via `--dart-define=TOXEE_L3_TEST=true`; build_all omits it →
  `l3_dump_state` "Method not found" silently breaks every assertion).
- `Inst.focusType` types via REAL osascript keystrokes (synthetic `enterText`
  SIGSEGVs the macOS engine's `setEditingState`); composer sends via `osaPaste`
  (keystrokes mangle chars); account-card login uses `tryTapKey` (raw tapAt
  doesn't fire the InkWell).
- flutter_skill matches OFFSTAGE `IndexedStack` / measurement-copy subtrees →
  duplicate-key false hits; use `resolveKeyCenter` / `keyed:false` on offstage
  copies / `homeShellTab` for tab detection.
- macOS freeze → check `/Library/Logs/DiagnosticReports/*.hang` stackshots FIRST.
- Same-host cross-process NGC join relies on flaky DHT → PRIVATE group + invite +
  full-mesh local bootstrap; residual misses are an environment limit.
