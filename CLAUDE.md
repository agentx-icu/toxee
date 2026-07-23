# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**toxee** is a Flutter chat client that integrates Tencent Cloud Chat UIKit on top of **tox** (Tox P2P network) instead of Tencent Cloud IM. The bridge between UIKit-style APIs and tox lives in a separate framework called **Tim2Tox** (`third_party/tim2tox`, upstream `agentx-icu/tim2tox`). toxee depends on Tim2Tox; Tim2Tox does not depend on toxee.

## Common commands

CI pins Flutter **3.41.9** stable (see `.github/workflows/analyze.yml`); match that locally to avoid analyzer/lint drift. Bumped from 3.29.0 on 2026-05-28 because `mcp_toolkit ^3.0.0` requires Dart 3.11+ (Flutter 3.32+).

Run all commands from the repo root.

One-time per clone: run `./tool/install_git_hooks.sh` to opt into the in-tree pre-push hook. It catches the footgun of pushing a toxee commit whose submodule SHA (`third_party/tim2tox` or `third_party/chat-uikit-flutter`) has not been pushed to the submodule's own remote yet, which would break `git clone --recursive` for everyone else.

```bash
# Bootstrap dependencies (submodules + vendored Tencent SDK + patches + pubspec_overrides).
# REQUIRED after a fresh clone or when submodules / pubspec change.
dart run tool/bootstrap_deps.dart
# Re-vendor SDK and re-apply patches:
dart run tool/bootstrap_deps.dart --force
# Verify state offline only:
dart run tool/bootstrap_deps.dart --offline-check-only

flutter pub get

# Build (also builds the tim2tox FFI native library first via third_party/tim2tox/build.sh)
./build_all.sh --platform macos --mode debug
./build_all.sh --platform <macos|linux|windows|android|ios> --mode <debug|profile|release> [--clean]

# Build + launch (macOS dev loop; tails flutter_client.log)
./run_toxee.sh
# Platform-specific runners: ./run_toxee_ios.sh, ./run_toxee_ios_device.sh, ./run_toxee_android.sh

# Lint / static analysis (matches CI in .github/workflows/analyze.yml)
flutter analyze lib tool --no-fatal-warnings --no-fatal-infos
dart run tool/check_complexity.dart   # warns on files in lib/ > 500 LOC

# Tests
flutter test
flutter test test/call_bridge_service_test.dart            # single file
flutter test --plain-name 'sends signaling on accept'      # single test by name
flutter test integration_test/                              # E2E smoke (tagged `needs-native`; builds the host app first — needs libtim2tox_ffi built)
flutter test integration_test/ --exclude-tags=needs-native  # Same but skip smokes when the native lib isn't built locally

# Tim2Tox auto_tests local smoke (Tier 1; recommended before every push, ~2 min on M-series)
# Tiers 2/3/4 run in CI — see third_party/tim2tox/auto_tests/README.en.md "CI pipeline".
(cd third_party/tim2tox/auto_tests && RUN_VIRTUAL=1 ./run_tests_ordered.sh 1,3,12 14)
```

### L3 single-process MCP suite — same 46 specs on all five platforms

`tool/mcp_test/run_l3_scenarios.dart` is platform-agnostic: it attaches to ANY
reachable Dart VM service whose app was built with `--dart-define=TOXEE_L3_TEST=true`.
The per-platform launchers below build with that define, expose the VM service,
and write the ws URI to `build/vm_service_uri.txt`; the runner then attaches
**unchanged**. `--class=l3-gate` selects the hermetic (no-echo-peer) partition
that runs identically everywhere. Each launcher runs in its own OS context
(desktop builds are local to that OS; Android/iOS attach from a host with the
device).

```bash
# macOS (reference): build+launch writes build/vm_service_uri.txt, then attach.
MCP_BINDING=marionette ./run_toxee.sh        # in another shell / TOXEE_BUILD_ONLY=1 to build only
dart run tool/mcp_test/run_l3_scenarios.dart "$(cat build/vm_service_uri.txt)" --class=l3-gate

# Linux (run ON the Linux box) — one-shot: launch, run the hermetic suite, tear down.
./run_toxee_linux.sh --run-l3

# Android (run on a host with adb + a connected device/emulator; FFI .so in jniLibs first
# via tool/build_android_ffi.sh). flutter run --machine auto-forwards the device VM service.
./run_toxee_android.sh --action l3 --run-l3

# iOS Simulator (reuses the existing instance launcher; TOXEE_IOS_DEVICE_TYPE=tablet for iPad).
tool/mcp_test/launch_toxee_ios_instance.sh A   # writes .ios_runtime/A/instance.json (ws_uri)
dart run tool/mcp_test/run_l3_scenarios.dart "$(jq -r .ws_uri tool/mcp_test/.ios_runtime/A/instance.json)" --class=l3-gate
```

```powershell
# Windows (run ON the Windows host, PowerShell 5.1+).
powershell -ExecutionPolicy Bypass -File run_toxee_windows.ps1 -RunL3
```

If `flutter pub get` fails with a `package_config.json` parse error, run `dart tool/bootstrap_deps.dart` (note: no `run`) before retrying — `pubspec_overrides.yaml` must be generated before pub resolution.

Day-to-day development is centered on macOS. iOS/Android builds need extra platform setup (see `doc/operations/BUILD_AND_DEPLOY.en.md`).

## Architecture — the one thing to internalize

toxee runs a **hybrid architecture**. There are two paths from the UIKit/business layer down into Tim2Tox, and changes that ignore the split break message history, calls, or callbacks:

1. **Binary replacement path** — `main()` calls `setNativeLibraryName('tim2tox_ffi')` (in `lib/bootstrap/logging_bootstrap.dart`) so the Tencent SDK loads `libtim2tox_ffi` instead of `dart_native_imsdk`. Most SDK calls flow `TIMManager.instance → NativeLibraryManager → bindings.Dart*() → libtim2tox_ffi`. Cheap, preserves the SDK call surface.
2. **Platform path** — `Tim2ToxSdkPlatform` is installed as the `TencentCloudChatSdkPlatform.instance` and routes selected calls to a Dart-side `FfiChatService`. Used for **history (`getHistoryMessageList*`), `clearHistoryMessage`, group/quit/stored callbacks, calling, polling, Bootstrap, and other stateful flows** that cannot live purely in C++.

**Both paths must coexist** and must not both write history or both fire the same callback. That invariant is enforced by `BinaryReplacementHistoryHook`, which is initialized inside `HomePage` after `TimSdkInitializer.ensureInitialized()` completes.

### Startup ordering (don't reorder casually)

Conceptually: `FfiChatService.init → login → updateSelfProfile → FakeUIKit.startWithFfi → TIMManager.initSDK → startPolling → install Tim2ToxSdkPlatform → BinaryReplacementHistoryHook + call bridge + plugins`.

In code:
- `main()` (`lib/main.dart`) → `AppBootstrap.initialize()` (`lib/bootstrap/app_bootstrap.dart`) runs logging, prefs, runtime, desktop shell. **Platform is not yet installed here.**
- `_StartupGate` (auto-login) goes through `StartupSessionUseCase` → `AccountService.initializeServiceForAccount(..., startPolling: false)` → `AppBootstrapCoordinator.boot(service)` which calls `SessionRuntimeCoordinator.ensureInitialized()` (installs `Tim2ToxSdkPlatform`, wires FakeUIKit) → `TimSdkInitializer.ensureInitialized()` → `service.startPolling()`.
- `LoginPage` (manual login) goes through the same `AccountService` + `AppBootstrapCoordinator.boot()` path.
- `HomePage._initAfterSessionReady()` calls `SessionRuntimeCoordinator.ensureInitialized()` again (idempotent) and only then initializes `BinaryReplacementHistoryHook`, UIKit listeners, and the `tencent_cloud_chat_sticker / text_translate / sound_to_text` plugins. `CallServiceManager` registration depends on `Tim2ToxSdkPlatform` already being live.

Authoritative deep dive: `doc/architecture/HYBRID_ARCHITECTURE.en.md`. Maintainer constraints: `doc/architecture/MAINTAINER_ARCHITECTURE.en.md`.

### Code layout (responsibility, not file tree)

- `lib/bootstrap/` — earliest startup: logging, native lib name, prefs, runtime, desktop shell. `AppBootstrap.initialize()` is the entry orchestrator.
- `lib/adapters/` — Tim2Tox interface implementations (preferences, logger, Bootstrap, event bus, conversation manager) that get injected into `FfiChatService`. Tim2Tox is decoupled from toxee through these.
- `lib/sdk_fake/` — adapts Tim2Tox / `FfiChatService` data into the fake UIKit models, providers, and managers that Tencent Cloud Chat UIKit expects. `FakeUIKit.instance.startWithFfi(service)` is the entry.
- `lib/runtime/` — `SessionRuntimeCoordinator` (installs Platform + FakeUIKit, idempotent, supports re-init after logout), `TimSdkInitializer` (sets UIKit's `_isInitSDK`).
- `lib/startup/` — `StartupSessionUseCase` orchestrates account restore → init/login → connection wait → friends load. Returns a `StartupOutcome` sealed type consumed by `_StartupGate`.
- `lib/auth/` — `LoginUseCase` for the manual login flow.
- `lib/call/` — TUICallKit integration, call overlay, in-call view, signaling effects listener. Talks to `Tim2ToxSdkPlatform`.
- `lib/ui/` — pages and widgets (login, home, conversations, settings, Bootstrap). Mostly UIKit-driven.
- `lib/util/` — `AppLogger`, `AccountService`, theme/locale controllers, Bootstrap node lists.
- `lib/models/` — small shared value types (e.g. `AccountSummary`) used across startup, auth, and UI layers.
- `lib/i18n/`, `lib/l10n/` — app localizations (UIKit has its own delegate; both are registered in `main.dart`).
- `tool/` — `bootstrap_deps.dart` (the single source of truth for "what must happen before `flutter pub get`"), `check_complexity.dart`, `ci/` helpers used by GitHub Actions.
- `third_party/` — vendored deps. `tim2tox` and `chat-uikit-flutter` are git submodules; the Tencent Cloud Chat SDK is fetched + patched into `pubspec_overrides.yaml` by the bootstrap tool. Never edit `third_party/` without understanding the patch flow (`doc/operations/PATCH_MAINTENANCE.en.md`).
- `doc/` is the canonical documentation tree (architecture, integration, operations, reference). All new docs go here.

### Logging

`main()` wraps everything in `runZonedGuarded` and replaces `print` with `AppLogger`. TCCF-formatted lines from the Tencent SDK are parsed back into structured log records — don't rip out `_routePrintToLogger` unless you mean to. `FlutterError.onError` and `PlatformDispatcher.instance.onError` both log via `AppLogger.logError`. The fallback `stderr.writeln` in the zone error handler exists specifically to survive `StackOverflow` in the logger itself.

## Constraints worth remembering

- **`flutter analyze`** is configured with strict lints in `analysis_options.yaml` (`avoid_print`, `unawaited_futures`, `use_build_context_synchronously`, `cancel_subscriptions`, `close_sinks`, `always_declare_return_types`, etc.). Treat lint output as a hard gate.
- **Complexity guard**: `tool/check_complexity.dart` warns when any `lib/**.dart` exceeds 500 LOC. It currently only warns, but the long-term direction is enforcement; don't add huge new files.
- **Message history ownership**: history is persisted on the Dart side (`FfiChatService` / `MessageHistoryPersistence`). Both binary-replacement and Platform paths must not both write or both emit callbacks for the same event — `BinaryReplacementHistoryHook` mediates this.
- **`startPolling` is explicit**: nothing on the native side will pump file requests, connection status, or ToxAV events until `FfiChatService.startPolling()` is called after login. Don't move it earlier or later without checking `AppBootstrapCoordinator.boot()`.
- **Singleton flow**: toxee uses Tim2Tox's default singleton model. Multi-instance support exists for Tim2Tox auto tests, not for clients — don't design around it.
- **No Tencent Cloud IM**: backend is Tox P2P. Anything that assumes a Tencent IM server is wrong for this repo.
- **Mobile parity is mandatory** (移动端兼容). toxee targets iOS/Android as well as desktop — every solution/design MUST work on mobile, and **every bugfix MUST explicitly check whether the same bug exists on mobile** (and fix it there too, or state why it can't apply). When a fix lives in shared Dart (e.g. `lib/util/`, `lib/sdk_fake/`, `third_party/tim2tox/dart/`, fork widgets), it already covers mobile — say so. When a fix is platform-specific (desktop Enter-to-send `..._input_desktop.dart`, window/tray, native pickers, the raw-launch test harness), find and address the mobile counterpart (`..._input_mobile.dart`, mobile call/notification surfaces) or call out the gap. Default reviewer question for any change: "does mobile hit this too?"

## Working agreement (standing directives)

These are durable expectations for how work is done in this repo, not one-off instructions.

- **Deep root-cause fixes only.** Every problem found gets a real underlying fix at the correct layer (native/FFI, framework, or app), never a perfunctory surface patch or a workaround that hides the symptom. If the true fix is large, scope and state it — don't paper over it. "底层修复，不敷衍。"
- **Codex review is mandatory on every change** (code, FFI, fork, harness). Workflow: draft → codex second opinion → apply findings → proceed. Bundle diffs and have codex verify correctness, ABI byte-matching, memory/ownership, and mobile parity. Codex telemetry-off launch: `env -u OTEL_EXPORTER_OTLP_ENDPOINT codex exec -c otel.exporter=none -c otel.log_user_prompt=false …` (per-process; never edit `~/.codex/config.toml`).
- **Codex edits plan docs directly after confirmation** (user directive 2026-06-03). For 方案/plan documents: codex reviews read-only first → Claude vets/confirms the findings → codex is re-run with `--sandbox workspace-write` and the confirmed findings list, applying the edits to the plan file in place (appending a change-log section). Claude re-reads and stays responsible for the final content.
- **If codex is unavailable** (provider down / TLS errors): skip the review for now, explicitly declare the skip, self-validate (e.g. `feature-dev:code-reviewer` agent + tests/analyzer), and record that a codex review is still owed.
- **Use codex to resolve uncertainty — don't block on the user.** When unsure about a fix approach, or a decision needs confirmation, discuss it with codex first and follow the joint conclusion. Only if it's still unresolved after that discussion, proceed with your own recommendation and state it. Reserve user questions for genuine product/scope forks.
- **Test campaigns ("process Sxx–Syy until all pass").** Drive each scenario, prefer real-UI two-process driving where the request calls for it (直接驱动 UI 控件), fix the root cause of anything a scenario surfaces, and only **skip** a scenario whose environment genuinely cannot be constructed — naming which and why. The real-UI harness must tolerate exception startup states (e.g. `sc_load_account_fail`); see `tool/mcp_test/REAL_UI_TWO_PROCESS.md` and `drive_real_ui_pair.dart`.
- **Real-UI startup reuse is the default.** When adding new "真实 App + 真实控件" cases, keep the atomic scenario for focused debugging, but also place it in an existing domain sweep or an optimized bundle so broad runs reuse the same app launch, registered accounts, and A<->B friendship. Prefer extending `sweep_*` chains and `drive_real_ui_pair_optimized.dart` over creating isolated campaigns. Only split into a separate launch when the case intentionally poisons state (friend deletion), restarts a peer, needs native/OS picker automation, or has a conflicting state contract; document that exception in `REAL_UI_TWO_PROCESS.md` / the campaign anchor and verify `--plan-json` does not add unnecessary launches.
- **ABI is sacred.** Any `dart_compat_*.cpp` change must byte-match `native_imsdk_bindings_generated.dart` — arg count, pointer-vs-scalar, AND integer width/signedness (`int` vs `uint64`/`uint32`). `tool/mcp_test/abi_audit.py` catches count/ptr drift only; width/signedness drift needs codex/code-reviewer.

## Agent skills

Machine-read configuration for the engineering skill suite. These live under `docs/agents/` (the path the skills look for), not the `doc/` prose tree.

### Issue tracker

Issues live as GitHub issues in `agentx-icu/toxee`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.
