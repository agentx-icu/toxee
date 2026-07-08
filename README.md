# toxee

> Language: **English** | [简体中文](README.zh-CN.md)
>
> Flutter chat client / example app built on Tim2Tox

---

## Understand this project in 5 minutes

- **What toxee is**: a runnable Flutter chat app that uses Tencent Cloud Chat UIKit for UI and **tox** as the backend over the Tox P2P network.
- **What Tim2Tox is**: the compatibility layer / framework that bridges UIKit-style APIs to tox (located in `third_party/tim2tox`, upstream repo: [agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)); it is not the chat application itself.
- **One-line architecture summary**: toxee integrates Tim2Tox with a hybrid approach of "binary replacement + Platform", where most SDK calls still go through `NativeLibraryManager -> Dart*`, while history, polling, calling, and some stateful flows are implemented through `Tim2ToxSdkPlatform -> FfiChatService`.
- **Shortest path to run it**: clone -> `dart run tool/bootstrap_deps.dart` -> `flutter pub get` -> `./build_all.sh --platform macos --mode debug` or `./run_toxee.sh`.

For deeper implementation details and role-based reading paths, see [doc/README.en.md](doc/README.en.md).

---

## Project overview

**toxee** is a **Flutter chat client / example app built on tox**. It shows how to integrate tox with Tencent Cloud Chat UIKit to build a decentralized P2P chat experience: account flows, conversations, messages, contacts, groups, Bootstrap, optional calling, and extension points are all implemented or wired up in this repository.

**Clearly defined**:

- **It is**: a runnable Flutter application for developers who want to get something working quickly, and for maintainers who want to understand the relationship between a client app and Tim2Tox. It also serves as a reference implementation for integrating Tim2Tox.
- **It is not**: the low-level protocol library (protocol behavior and V2TIM mapping live in Tim2Tox).
- **It is not**: a general-purpose SDK (UI, account flows, Bootstrap configuration, calling bridge, and app-level wiring are toxee-specific and must be adapted for other clients).

---

## Screenshots

The real app, one Flutter codebase, on **desktop (macOS), Android, iPad, and iOS** (click any image for full resolution). All images live in [`doc/product/assets/`](doc/product/assets); the self-contained product page **[`doc/product/index.html`](doc/product/index.html)** has the full tour.

**The same 1:1 chat, on every platform:**

| Desktop | iPad | Android | iOS |
| :---: | :---: | :---: | :---: |
| [![Toxee chat on macOS](doc/product/assets/desktop/c2c.png)](doc/product/assets/desktop/c2c.png) | [![Toxee chat on iPad](doc/product/assets/ipad/c2c.png)](doc/product/assets/ipad/c2c.png) | [![Toxee chat on Android](doc/product/assets/android/c2c.png)](doc/product/assets/android/c2c.png) | [![Toxee chat on iOS](doc/product/assets/ios/c2c.png)](doc/product/assets/ios/c2c.png) |

**More (desktop):**

| Group chat | New contacts | Profile & Tox ID QR | Settings |
| :---: | :---: | :---: | :---: |
| [![Group chat](doc/product/assets/desktop/group_chat.png)](doc/product/assets/desktop/group_chat.png) | [![New friend request](doc/product/assets/desktop/new_application.png)](doc/product/assets/desktop/new_application.png) | [![Profile and Tox ID QR card](doc/product/assets/desktop/self_profile.png)](doc/product/assets/desktop/self_profile.png) | [![Settings](doc/product/assets/desktop/settings.png)](doc/product/assets/desktop/settings.png) |

> These screenshots are generated from the running app by `./tool/screenshots/capture.sh` — see [`tool/screenshots/README.md`](tool/screenshots/README.md).

---

## What problem this project solves

- **For users of the codebase**: it provides a ready-to-run Tox chat client with UIKit-based screens and interactions, so you do not need to build the UI from scratch.
- **For integrators**: it demonstrates dependency bootstrap (submodules, SDK fetch + patching, `pubspec_overrides`), Tim2Tox interface injection (preferences, logger, Bootstrap, and related adapters), and the startup sequence of `init -> login -> startPolling -> Platform`.
- **For maintainers**: it explains why the current hybrid architecture exists, what binary replacement and Platform each own, and where to inspect call chains and logs when debugging or extending the app.

---

## Relationship with Tim2Tox

| Dimension | Tim2Tox | toxee |
| --- | --- | --- |
| **Role** | Compatibility layer / framework: provides the C++ core, C FFI, Dart wrappers, and SDK Platform implementation that any Flutter client can integrate with. | Client app / example app: consumes Tim2Tox and implements account flows, UI, Bootstrap, history, calling bridge, and app-specific wiring. |
| **Location** | `third_party/tim2tox` (git submodule, upstream: [agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)). | Repository root. |
| **Dependency direction** | Tim2Tox does not depend on toxee; it receives capabilities such as preferences, logging, and Bootstrap through interfaces. | toxee depends on `tim2tox_dart`, implements the interfaces Tim2Tox expects, constructs `FfiChatService`, and configures the Platform path. |

**Call relationship (simplified)**:

```text
toxee (UI / account / Bootstrap / adapters)
    |
    |-- setNativeLibraryName('tim2tox_ffi') -> SDK loads libtim2tox_ffi
    |-- FfiChatService(prefs, logger, bootstrap, ...) -> Tim2Tox service layer
    |-- Tim2ToxSdkPlatform(ffiService) -> Platform path entry
    '-- FakeUIKit / FakeMessageManager / ... -> adapt Tim2Tox data into UIKit models
                    |
                    v
            Tim2Tox (dart / ffi / C++)
                    |
                    v
            c-toxcore (Tox P2P)
```

---

## Current architecture at a glance

The app currently uses a **hybrid architecture**: it keeps **binary replacement** (the SDK still reaches Tim2Tox through `NativeLibraryManager -> Dart*`) and also enables **`Tim2ToxSdkPlatform`** (history, some callbacks, calling, and stateful flows go through `FfiChatService`).

**Why hybrid instead of pure binary replacement or pure Platform?**

- **Pure binary replacement** keeps business code changes minimal, but history messages, `clearHistoryMessage`, `groupQuitNotification`, Bootstrap configuration, polling, and calling all need Dart-side state and persistence. Those flows are incomplete if implemented only with C++ callbacks; UIKit APIs such as `getHistoryMessageList` would fail or behave inconsistently.
- **Pure Platform** would route all SDK calls through Platform APIs, which means implementing many more methods and tracking SDK version changes closely. It is costly to migrate and maintain, and some SDK behavior still assumes the native library is loaded even when `isCustomPlatform` is enabled.
- **Hybrid** keeps the "swap the library, keep the call surface" benefits for most SDK usage, while moving the parts that must remain in Dart (history, polling, Bootstrap, calling bridge, and selected callbacks) into `Platform + FfiChatService`. That gives a better balance between compatibility and completeness. See [doc/architecture/HYBRID_ARCHITECTURE.en.md](doc/architecture/HYBRID_ARCHITECTURE.en.md).

**Call chain (ASCII)**:

```text
                    UIKit / app logic
                           |
         +-----------------+-----------------+
         |                                   |
   TIMManager.instance            getHistoryMessageList / ...
         |                                   |
   NativeLibraryManager              Tim2ToxSdkPlatform
   bindings.DartXXX()                       |
         |                                   |
         +-----------------+-----------------+
                           |
              libtim2tox_ffi (dart_compat_* / tim2tox_ffi_*)
                           |
              FfiChatService (polling, history, login state)
                           |
              V2TIM*Manager / ToxManager -> c-toxcore
```

---

## Repository structure

| Path | Responsibility |
| --- | --- |
| `lib/` | App Dart code: UI, startup flow, adapters, utilities. |
| `lib/bootstrap/` | Earliest startup work: logging, paths, `setNativeLibraryName('tim2tox_ffi')`, native log file setup. |
| `lib/adapters/` | Tim2Tox interface implementations: preferences, logger, Bootstrap, event bus, conversation manager, and related adapters injected into `FfiChatService`. |
| `lib/sdk_fake/` | Data adaptation layer that converts Tim2Tox / `FfiChatService` data into the fake UIKit models/providers expected by Tencent Cloud Chat UIKit. |
| `lib/ui/` | Pages and widgets: login, home, conversations, settings, Bootstrap, and related UI. Mostly UIKit-based with a small number of custom pages. |
| `lib/util/` | Shared helpers such as `AppLogger`, preferences, Bootstrap node lists, theme, and language utilities. |
| `lib/startup/` | Startup orchestration: account restore, Bootstrap decisions, `init -> login -> startPolling`, plus timeout and error handling. |
| `lib/call/` | Calling UI and effects, including TUICallKit integration and incoming-call overlay behavior. |
| `tool/` | Dependency bootstrap tooling, especially `bootstrap_deps.dart` for submodules, SDK fetch, patching, and `pubspec_overrides`. |
| `third_party/` | Vendored dependencies: Tim2Tox, Tencent Cloud Chat SDK, chat-uikit-flutter, and related assets fetched by scripts or submodules. |
| `doc/` | Architecture, build, troubleshooting, integration, and maintainer documentation. |

---

## Quick start

**Shortest path from a fresh clone** (run in the repository root):

```bash
# 1. Clone the repo (if you have not already)
git clone <repo-url> toxee && cd toxee

# 2. Bootstrap dependencies: submodules, SDK fetch + patching,
#    and pubspec_overrides generation
dart run tool/bootstrap_deps.dart

# 3. Fetch Dart / Flutter dependencies
flutter pub get

# 4. Build and run (this also builds the tim2tox FFI library)
./build_all.sh --platform macos --mode debug

# Or use the convenience runner (build + launch + optional log tail)
./run_toxee.sh
```

If you hit a `package_config.json` parse error, run `dart tool/bootstrap_deps.dart` first (without `run`), then run `flutter pub get`. Full setup steps and common issues are documented in [doc/getting-started.en.md](doc/getting-started.en.md) and [doc/operations/DEPENDENCY_BOOTSTRAP.en.md](doc/operations/DEPENDENCY_BOOTSTRAP.en.md).

---

## Build and run

- **Unified build**: `./build_all.sh --platform <macos|ios|android|...> --mode <debug|release>`
- **Run only**: `./run_toxee.sh` (other platform helpers include `run_toxee_ios.sh`, `run_toxee_android.sh`, and related scripts)
- For detailed platform steps, dependency layout, and deployment notes, see [doc/operations/BUILD_AND_DEPLOY.en.md](doc/operations/BUILD_AND_DEPLOY.en.md), [doc/operations/DEPENDENCY_BOOTSTRAP.en.md](doc/operations/DEPENDENCY_BOOTSTRAP.en.md), and [doc/operations/DEPENDENCY_LAYOUT.en.md](doc/operations/DEPENDENCY_LAYOUT.en.md). For debugging issues, see [doc/TROUBLESHOOTING.en.md](doc/TROUBLESHOOTING.en.md).

## GitHub Actions packages

The repository now includes [`.github/workflows/build-packages.yml`](.github/workflows/build-packages.yml), which runs on push, pull request, tag push, and manual dispatch. It builds and uploads artifacts for:

- **Windows**
- **Linux**
- **macOS**
- **Android**
- **iOS**

Each job uploads the contents of `dist/<platform>/` as a GitHub Actions artifact. Desktop jobs build the host Tim2Tox FFI library and bundle it into the packaged app output. Android builds both `app-release.apk` and `app-release.aab`; if the secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` are present, the workflow uses them for release signing, otherwise it falls back to the project's existing debug-key release signing.

For the desktop platforms, the packaged installables are:

- **Windows**: `toxee-windows-x64-release.msi` (plus a `.zip` bundle)
- **macOS**: `toxee-macos-release.dmg` (plus a `.zip` bundle)
- **Linux**: `toxee-linux-x64-release.AppImage` (plus a `.tar.gz` bundle)

iOS now has two modes:

- With `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`, and `IOS_PROVISIONING_PROFILE_BASE64` configured, the workflow performs a signed `flutter build ios --release` and packages a real `.ipa`.
- Without those secrets, the iOS job still runs as an unsigned validation build, but it does **not** publish that IPA to GitHub Releases. Instead, `dist/ios/NOTES.txt` explains that signing was not configured.

Mobile jobs also write `dist/<platform>/NOTES.txt` when Tim2Tox mobile native artifacts were not available in the workspace. In release publishing mode, Android APK/AAB assets are skipped when the JNI `libtim2tox_ffi.so` set was not staged, so GitHub Releases only receives Android assets that passed that native-library check.

Publishing to **GitHub Releases** is built into the same workflow:

- Push a tag like `v1.2.3` to build all platforms and publish a GitHub Release automatically.
- Or run `workflow_dispatch`, set `publish_release=true`, and provide `release_tag` (optionally `prerelease=true`).
- The publish job downloads the artifacts from the current run, uploads only the packaged installables that passed release gating to the Release, and adds a generated `SHA256SUMS.txt`.
- Release notes use GitHub's `--generate-notes` flow, while platform-specific packaging caveats are merged into the uploaded build-note assets.

---

## Documentation hub

For the full documentation index and role-based reading paths (new users / integrators / maintainers), start with [doc/README.en.md](doc/README.en.md).

Common entry points:

- [Dependency bootstrap](doc/operations/DEPENDENCY_BOOTSTRAP.en.md)
- [Troubleshooting](doc/TROUBLESHOOTING.en.md)
- [Hybrid architecture](doc/architecture/HYBRID_ARCHITECTURE.en.md)
- [Integration guide](doc/integration/INTEGRATION_GUIDE.en.md)
- [Maintainer view](doc/architecture/MAINTAINER_ARCHITECTURE.en.md)

---

## Good fits and non-goals

**Good fits**:

- You want to quickly run a Flutter chat app on top of Tox.
- You want a reference for integrating Tim2Tox into a client, including dependency bootstrap, interface injection, startup order, and the hybrid architecture split.
- You plan to extend or customize toxee itself (UI, Bootstrap, calling, plugins, or related features).

**Non-goals**:

- You only need the Tox protocol library or a general-purpose IM SDK. In that case, use Tim2Tox or c-toxcore instead of toxee.
- You need interoperability with Tencent Cloud IM server-side services. toxee uses Tox P2P as its backend and does not connect to Tencent Cloud IM.

---

## Known limitations

- **Platform focus**: day-to-day build and development are primarily centered on macOS. iOS and Android require platform-specific setup and script validation.
- **History and callback ownership**: message history lives on the Dart side (`FfiChatService` / `MessageHistoryPersistence`). In the hybrid architecture, binary replacement and Platform paths must not both write history or emit duplicate callbacks; that split is enforced by conventions such as `BinaryReplacementHistoryHook`.
- **Multiple instances**: toxee uses Tim2Tox's default singleton-style flow. Multi-instance support mainly exists for Tim2Tox auto tests and is not part of the default client workflow.
- **Dependencies**: the project depends on submodules plus SDK/UIKit content fetched by scripts. After a fresh clone or dependency changes, you must run `dart run tool/bootstrap_deps.dart` before `flutter pub get`.

---

## New contributor onboarding

- Follow the quick start once on your own machine and verify you can log in, send a message, and see the conversation list.
- Read this README's "Understand this project in 5 minutes", "Relationship with Tim2Tox", and "Current architecture at a glance" sections, then follow the role-based reading path in [doc/README.en.md](doc/README.en.md).
- If you are touching startup, logging, or dependency bootstrap, start with `lib/main.dart`, `lib/bootstrap/logging_bootstrap.dart`, and `tool/bootstrap_deps.dart`.
- If you are touching messages, conversations, or history, start with `lib/sdk_fake/` and [doc/architecture/HYBRID_ARCHITECTURE.en.md](doc/architecture/HYBRID_ARCHITECTURE.en.md).
- If you need to change Tim2Tox itself, work in `third_party/tim2tox` (upstream: [agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)) and use [third_party/tim2tox/doc/README.en.md](third_party/tim2tox/doc/README.en.md) as the local documentation entry point.

---

## License

See [LICENSE](LICENSE).
