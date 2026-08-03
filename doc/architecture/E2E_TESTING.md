[简体中文](./E2E_TESTING.zh-CN.md)

# End-to-end testing strategy for toxee

> Language: [Chinese](E2E_TESTING.md) | [English](E2E_TESTING.md)
>
> Generated 2026-05-20. Sibling docs: `HYBRID_ARCHITECTURE.md`, `MAINTAINER_ARCHITECTURE.md`, and the protocol-level test suite at `third_party/tim2tox/auto_tests/README.md`.
>
> See also: [`TESTING_OVERVIEW.md`](TESTING_OVERVIEW.md) — the one-stop map of all toxee test assets (inventory, execution-class taxonomy, cheap→expensive run order, CI status).

## Executive summary

**Recommendation: adopt stock Flutter `integration_test` as the primary E2E layer, with Patrol as a fallback for mobile flows that need native-OS interactions.**

`integration_test` is the only candidate that runs on **all five** target platforms (macOS, Linux, Windows, iOS, Android), runs the **real `libtim2tox_ffi`** binary that this app is built around, and integrates cleanly with the existing `bootstrap_deps.dart` + `build_all.sh` pipeline already wired into CI. Patrol covers exactly one capability `integration_test` lacks — driving native OS dialogs (camera/mic/notification permissions, the iOS app-switcher, Android `WebView`) — which is the only systematic gap on mobile. We intentionally do **not** recommend Maestro (no Flutter desktop support), Appium (heavy, two-driver schism, deprecated transport), or Detox (React Native only).

The hard insight: most "end-to-end" value for toxee is already covered by `third_party/tim2tox/auto_tests/` at the protocol layer (145 scenarios, virtual-clock + local-bootstrap + real-DHT tiers). What we are **missing** is verification that the Flutter UI on each platform correctly drives that protocol layer through the hybrid `Tim2ToxSdkPlatform` + binary-replacement path. That gap closes with `integration_test`, not with anything fancier.

## Existing coverage (avoid duplicating)

Before any new layer ships, recognize what is already tested. Adding tools "to be thorough" if they overlap one of these is waste.

| Layer | Tool | Scope | Where |
|---|---|---|---|
| Static analysis | `flutter analyze` (strict lints) | `lib/`, `tool/` | `.github/workflows/analyze.yml` |
| LOC guard | `tool/check_complexity.dart` | `lib/**.dart` > 500 LOC | same workflow |
| Unit + widget | `flutter test` (71 files) | Dart logic, providers, single-page widget trees | `test/` |
| **Protocol E2E** | tim2tox `auto_tests/` (145 scenarios, virtual + wall-clock + DHT) | TIM/UIKit API surface against both Platform and Binary-Replacement paths | `third_party/tim2tox/auto_tests/` |
| Bootstrap-from-scratch | `bootstrap_fresh.yml` | `dart run tool/bootstrap_deps.dart` from clean checkout | CI |
| Submodule remote sanity | `submodule_verify.yml` | submodule SHAs pushed | CI |
| Packaged build | `build-packages.yml` | `flutter build` succeeds on each target OS | CI |

The yawning gap is **UI-driven end-to-end on a real built app**: login -> home -> conversation -> send message -> receive message -> place call. None of the above exercises `lib/ui/**` against the real native stack. That's what this plan is about.

## Candidate survey

### Rating table

Ratings are 0-5, weighted for toxee's specific needs (hybrid FFI, five platforms, GitHub-hosted CI, two-peer flows).

| Candidate | Mobile (iOS/Android) | Desktop (mac/lin/win) | FFI-safe | Multi-peer support | CI cost | Maintenance | Closes gap | Overall |
|---|---|---|---|---|---|---|---|---|
| **`integration_test` (stock)** | 5 / 5 | 5 / 5 / 5 | yes, runs real binary | yes (two-instance via flutter test + separate data dirs) | low (Ubuntu OK, mac 10x) | low | high | **5** |
| **Patrol 4.5** | 5 / 5 | 4 / 0 / 0 | yes (wraps integration_test) | yes (same as above) | medium | medium | mobile-only native gap | **3.5** |
| **Maestro** | 5 / 5 | 0 / 0 / 0 | yes (black-box) | yes (two app installs) | low/medium | low (YAML) | mobile gap only | **2** |
| Appium + Flutter Driver | 4 / 4 | 3 / 2 / 2 | yes | yes | high (Appium server) | high (two drivers, deprecation churn) | overlap | 1.5 |
| Appium-Flutter-Integration-Driver | 4 / 4 | 3 (macOS only) / 0 / 0 | yes | yes | high | medium (small community, v2.0.3) | overlap | 1.5 |
| XCUITest / swift-testing | 3 / 0 | 3 / 0 / 0 | yes | hard (no Dart hooks) | medium | high (Swift glue) | partial | 1 |
| Espresso / UIAutomator | 0 / 3 | 0 / 0 / 0 | yes | hard | medium | high (Kotlin glue) | partial | 1 |
| Sikuli / image-based | 2 / 2 | 2 / 2 / 2 | yes | yes | medium | very high (image-fragile) | partial | 0.5 |
| Detox | 0 / 0 | 0 / 0 / 0 | no (RN-only) | n/a | n/a | n/a | none | 0 |

Sources: Patrol's pub.dev platform tags list Android, iOS, macOS, web only (no Linux/Windows); Maestro docs explicitly state "Maestro does not yet support Flutter for Desktop"; appium-flutter-driver upstream confirms `flutter_driver` is on deprecation path and the integration-driver fork (v2.0.3, Oct 2025) only adds macOS as a desktop target; Detox is hardcoded to the React Native JS bridge. See [Sources](#sources) below.

### Per-platform feasibility

| Tool x Platform | macOS | Linux | Windows | iOS | Android |
|---|---|---|---|---|---|
| `integration_test` (stock) | works, `flutter test integration_test -d macos` | needs `xvfb-run` in CI | works, `-d windows` | simulator on macos-14, device via Xcode Cloud | emulator (slow on GH) or Firebase Test Lab |
| Patrol | macOS native dialogs supported | not supported | not supported | full | full |
| Maestro | not supported | not supported | not supported | full | full |
| Appium-Flutter-Driver | macOS only via flutter-integration-driver | no | no | full | full |
| Detox | n/a | n/a | n/a | n/a | n/a |

Implication: **only stock `integration_test` is a single tool that spans every toxee target platform**. Anything else is multi-tool.

## Multi-peer test strategy

A core feature surface in toxee — friend add, messaging, calls — needs **two tox peers chatting**. There are four legitimate ways to stand that up; only some are appropriate for CI.

| Strategy | How | Latency in CI | Determinism | Verdict for toxee E2E |
|---|---|---|---|---|
| **Two-app-instance (recommended)** | Run two `flutter test integration_test` processes on the same host, each with `HOME`/`XDG_DATA_HOME`/`%APPDATA%` pointed at a private dir. Pair them via local bootstrap (no DHT). | seconds | high | **primary** — mirrors `auto_tests/` design, no internet needed |
| Virtual clock | The `*_virtual_test.dart` mode used by `auto_tests/`. Time is advanced programmatically. | sub-second | very high | **already in use at the protocol layer**; **not** suitable for UI E2E because Flutter's frame scheduler does not honor the virtual clock |
| Local bootstrap | Stand up one Tox bootstrap node on `127.0.0.1` and point both peers at it. Same pattern `auto_tests/` ships with. | seconds | high | bundled with the two-app-instance strategy above |
| Real DHT | Bootstrap against the public DHT; let the peers find each other on the open internet. | tens of seconds, flaky | low | **avoid for PR CI**; acceptable only for a nightly/pre-release tier (mirror `auto_tests_nightly.yml`) |

Concretely the recommendation is: **two-app-instance + local bootstrap for PR-tier E2E**, plus a **real-DHT tier in `auto_tests_nightly.yml`-style scheduling** for one or two canary scenarios.

## Recommendation

**Primary: stock `integration_test`** (`package:integration_test` + `flutter test integration_test`).

- Single tool, all five platforms.
- Runs the real `libtim2tox_ffi` produced by `./build_all.sh`. Existing bootstrap (`tool/bootstrap_deps.dart`) already handles the vendored SDK + patches; no new install steps.
- Cooperates with `flutter_test` matchers, so the project's existing `test/` style transfers directly.
- Two-app-instance pattern: launch two `integration_test` processes from a host harness, each with isolated data dirs, paired via a single in-process bootstrap node. Use `127.0.0.1:33445` (the convention used by `auto_tests/`).
- CI: ubuntu-24.04 with `xvfb-run` for Linux, macos-14 for macOS+iOS, windows-latest for Windows, gated behind a new `ci:e2e` label or a separate workflow to keep PR latency bounded.

**Fallback (mobile-only): Patrol 4.5**.

- Use **only** for tests that must drive a native OS dialog (microphone permission for calls, camera permission for QR-pairing, notification permission, iOS PIP). The `permission_handler` flows in `lib/call/permission_helper.dart` are the obvious targets.
- Keep Patrol confined to a single sub-suite (`integration_test/native/`); do not let it become the default. The CLI fork (`patrol_cli`) is heavier and slower than `flutter test`.
- Do **not** invest in Patrol desktop: it does not list Linux/Windows in its pub.dev platform tags, and macOS-only desktop coverage would just shadow the `integration_test` flow we already need.

Why not the others, in one line each:

- **Maestro**: zero Flutter desktop support; would fragment our story between mobile (Maestro) and desktop (integration_test).
- **Appium-Flutter-Driver**: tied to deprecated `flutter_driver`. The newer `appium-flutter-integration-driver` is a half-built fork (v2.0.3, ~50 stars, mac-only on desktop) with no advantage over running `flutter test integration_test` directly.
- **XCUITest / Espresso**: forces us to maintain Swift and Kotlin test sources for behavior already expressible in Dart. The reach into `libtim2tox_ffi` state requires either platform channels or screen scraping — both are friction.
- **Detox**: React Native only; reading the source confirms a hard dependency on the JS bridge.
- **Sikuli / image-based**: any green/red badge change in the UIKit fork breaks every screenshot. Maintenance cost dwarfs the value.

## 3-step incremental rollout

The plan below is intentionally narrow. Each step lands as one PR; nothing later in the list assumes anything earlier than the previous step.

### Step 1 — Local smoke (no CI yet)

Add `integration_test` as a dev dep, a single happy-path smoke, and a runner script. macOS-only at first, because that's where day-to-day dev happens (see `CLAUDE.md`).

```bash
# pubspec.yaml: add under dev_dependencies
#   integration_test:
#     sdk: flutter
flutter pub get

mkdir -p integration_test
# Author integration_test/smoke_login_to_home_test.dart: bootstrap test profile,
# pump app, expect login -> auto-login -> home screen rendered, send one
# C2C message to a second on-host peer via local bootstrap.

# Local runner
./tool/run_e2e_macos.sh    # new: wraps `flutter test integration_test -d macos`
```

Gate: green run on the maintainer's macOS dev box. No CI changes yet. This step proves the FFI library loads under `integration_test` and that `Tim2ToxSdkPlatform` is installed correctly under a test driver — both of which are non-obvious because of the binary-replacement step in `lib/bootstrap/logging_bootstrap.dart`.

### Step 2 — CI tier, opt-in by label

New workflow `.github/workflows/e2e.yml` that runs the macOS smoke from Step 1 plus a Linux smoke under `xvfb-run`. Gate on a PR label so it does not bloat every PR.

```yaml
# .github/workflows/e2e.yml (sketch)
on:
  pull_request:
    types: [labeled, synchronize]
jobs:
  e2e-macos:
    if: contains(github.event.pull_request.labels.*.name, 'ci:e2e')
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.41.9', channel: 'stable' }
      - run: dart run tool/bootstrap_deps.dart
      - run: flutter pub get
      - run: ./build_all.sh --platform macos --mode debug
      - run: flutter test integration_test -d macos
  e2e-linux:
    if: contains(github.event.pull_request.labels.*.name, 'ci:e2e')
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.41.9', channel: 'stable' }
      - run: sudo apt-get update && sudo apt-get install -y xvfb libsodium-dev libopus-dev libvpx-dev libsqlite3-dev ninja-build libgtk-3-dev
      - run: dart run tool/bootstrap_deps.dart
      - run: flutter pub get
      - run: ./build_all.sh --platform linux --mode debug
      - run: xvfb-run -a flutter test integration_test -d linux
```

Add a `ci:e2e-required` rule to `CODEOWNERS` once the suite stabilizes. Until then, keep it advisory.

### Step 3 — Mobile + multi-peer expansion

Add iOS simulator (macos-14) and Android emulator (`reactivecircus/android-emulator-runner@v2`) jobs. Introduce the two-app-instance harness and a Patrol sub-suite for permission dialogs.

```bash
# 3a. Two-app-instance harness on macOS / Linux
./tool/run_e2e_pair.sh     # new: launches two flutter test processes
                           # with TOXEE_DATA_DIR=$tmp/{alice,bob}, paired via
                           # an in-process local bootstrap node.

# 3b. Add Patrol for native permission dialogs (mobile only)
# pubspec.yaml: dev_deps += patrol: ^4.5.0
dart pub global activate patrol_cli
mkdir -p integration_test/native
# Author integration_test/native/permissions_test.dart that uses
# patrolTester.native2.{grantPermissionWhenInUse,grantNotificationsPermission}
# around the existing call flow.

patrol test --target integration_test/native/permissions_test.dart -d <device>

# 3c. Nightly real-DHT canary mirroring auto_tests_nightly.yml's cadence.
# .github/workflows/e2e_nightly.yml — schedule: cron '0 3 * * *', one scenario,
# tolerates flakes via 3x retry, posts a Slack/issue on persistent fail.
```

Gate: macOS + Linux green by PR, iOS sim green on a slower tier (Step 3a/3b can be on `ci:e2e-mobile` label only), nightly real-DHT advisory. Windows is best-effort on the same `ci:e2e` label as macOS/Linux; the Windows runner is the slowest of the three and the highest-flake risk.

## Open questions and risks

1. **Windows runner stability**. We have no production data on `flutter test integration_test -d windows` against `libtim2tox_ffi.dll` in GH Actions. Step 2 will reveal whether the runner can build + run; if not, fall back to "Windows is build-only, E2E happens on macOS/Linux."
2. **Android emulator on GH**. Patrol's own docs warn the GH Android emulator is "slow to start and unstable." The plan accepts this and pushes Android E2E to `ci:e2e-mobile`-labeled runs and the nightly tier; for daily signal, prefer Firebase Test Lab if/when budget permits.
3. **iOS device coverage**. macos-14 simulators are sufficient for UI flows but cannot validate true backgrounded behavior (the territory of `doc/architecture/MOBILE_BACKGROUND.md`). For that, the only credible automation is XCUITest on a real device — out of scope for v1 of this plan; revisit if/when call-receive-when-backgrounded becomes the dominant bug source.
4. **Test isolation under singleton flow**. `CLAUDE.md` flags that toxee uses Tim2Tox's default singleton model. The two-app-instance approach sidesteps this by running two **OS processes**, not two SDK instances in one process. Any contributor who tries to shortcut this by reusing one process for both peers will hit `ToxManager not initialized`-style failures — document the convention loudly in the harness script comment.
5. **Patrol on macOS desktop**. Patrol's pub.dev tags list macOS, but our research did not find a single open-source toxee-shaped project running Patrol on macOS in CI. Treat macOS Patrol as unproven and stick to stock `integration_test` there until the project demands native dialog work on the desktop.
6. **Coverage overlap with `auto_tests/`**. The line we are committing to: `auto_tests/` proves the **protocol** is correct, the new E2E layer proves the **UI** drives it correctly. Any scenario expressible purely as "two TIM SDKs talking" belongs in `auto_tests/`, not here.
7. **Flutter version pinning**. The plan inherits the 3.41.9 stable pin from `analyze.yml`. Patrol 4.5 supports current stable Flutter; verify on first install. If Patrol later requires a newer Flutter than CI uses, demote Patrol to "optional local-only" rather than upgrading CI for one tool.

## Sources

- [Patrol on pub.dev](https://pub.dev/packages/patrol) — platform tags (Android, iOS, macOS, web) and current version 4.5.0.
- [Patrol CI platforms doc](https://patrol.leancode.co/ci/platforms) — GH Actions Android caveat, macOS minute cost ratio.
- [Maestro Flutter platform doc](https://docs.maestro.dev/get-started/supported-platform/flutter) — explicit "Maestro does not yet support Flutter for Desktop".
- [appium-flutter-driver issue #210](https://github.com/appium/appium-flutter-driver/issues/210) — `flutter_driver` deprecation status.
- [appium-flutter-integration-driver](https://github.com/AppiumTestDistribution/appium-flutter-integration-driver) — v2.0.3, October 2025, macOS desktop only.
- [Maestro Detox-alternatives writeup](https://maestro.dev/insights/detox-alternatives) — confirms Detox is React-Native-bridge specific.
- [Flutter integration testing docs](https://docs.flutter.dev/testing/integration-tests) — xvfb requirement for Linux, `-d macos|linux|windows` flags.
- toxee in-tree: `CLAUDE.md`, `doc/architecture/HYBRID_ARCHITECTURE.md`, `third_party/tim2tox/auto_tests/README.md` (verified 2026-05-20).
