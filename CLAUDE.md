# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**toxee** is a Flutter chat client that integrates Tencent Cloud Chat UIKit on top of **tox** (Tox P2P network) instead of Tencent Cloud IM. The bridge between UIKit-style APIs and tox lives in a separate framework called **Tim2Tox** (`third_party/tim2tox`, upstream `anonymoussoft/tim2tox`). toxee depends on Tim2Tox; Tim2Tox does not depend on toxee.

## Common commands

Run all commands from the repo root.

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
- `lib/i18n/`, `lib/l10n/` — app localizations (UIKit has its own delegate; both are registered in `main.dart`).
- `tool/` — `bootstrap_deps.dart` (the single source of truth for "what must happen before `flutter pub get`"), `check_complexity.dart`, `ci/` helpers used by GitHub Actions.
- `third_party/` — vendored deps. `tim2tox` and `chat-uikit-flutter` are git submodules; the Tencent Cloud Chat SDK is fetched + patched into `pubspec_overrides.yaml` by the bootstrap tool. Never edit `third_party/` without understanding the patch flow (`doc/operations/PATCH_MAINTENANCE.en.md`).

### Logging

`main()` wraps everything in `runZonedGuarded` and replaces `print` with `AppLogger`. TCCF-formatted lines from the Tencent SDK are parsed back into structured log records — don't rip out `_routePrintToLogger` unless you mean to. `FlutterError.onError` and `PlatformDispatcher.instance.onError` both log via `AppLogger.logError`. The fallback `stderr.writeln` in the zone error handler exists specifically to survive `StackOverflow` in the logger itself.

## Constraints worth remembering

- **`flutter analyze`** is configured with strict lints in `analysis_options.yaml` (`avoid_print`, `unawaited_futures`, `use_build_context_synchronously`, `cancel_subscriptions`, `close_sinks`, `always_declare_return_types`, etc.). Treat lint output as a hard gate.
- **Complexity guard**: `tool/check_complexity.dart` warns when any `lib/**.dart` exceeds 500 LOC. It currently only warns, but the long-term direction is enforcement; don't add huge new files.
- **Message history ownership**: history is persisted on the Dart side (`FfiChatService` / `MessageHistoryPersistence`). Both binary-replacement and Platform paths must not both write or both emit callbacks for the same event — `BinaryReplacementHistoryHook` mediates this.
- **`startPolling` is explicit**: nothing on the native side will pump file requests, connection status, or ToxAV events until `FfiChatService.startPolling()` is called after login. Don't move it earlier or later without checking `AppBootstrapCoordinator.boot()`.
- **Singleton flow**: toxee uses Tim2Tox's default singleton model. Multi-instance support exists for Tim2Tox auto tests, not for clients — don't design around it.
- **No Tencent Cloud IM**: backend is Tox P2P. Anything that assumes a Tencent IM server is wrong for this repo.
