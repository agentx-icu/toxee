[简体中文](./BUILD_AND_DEPLOY.zh-CN.md)

# toxee Build and Deploy

This document covers the current build and packaging flow for toxee: local development builds, local packaging, and the GitHub Actions workflow that publishes GitHub Releases. For build failures, startup crashes, bootstrap issues, or runtime debugging, start with [TROUBLESHOOTING.md](../TROUBLESHOOTING.md).

## Contents

- [Environment requirements](#environment-requirements)
- [Quick paths](#quick-paths)
- [Local build flow](#local-build-flow)
- [Package outputs](#package-outputs)
- [GitHub Actions packages and releases](#github-actions-packages-and-releases)
- [Signing and native-library gating](#signing-and-native-library-gating)
- [Useful commands](#useful-commands)
- [Related docs](#related-docs)

## Environment requirements

### Core tools

- **Flutter**: use Flutter `3.41.x` or newer compatible with the checked-in lockfile. The current CI workflows use `3.41.9`, and `pubspec.lock` currently requires Flutter `>=3.41.9`.
- **Dart**: use the Dart SDK bundled with the selected Flutter version.
- **Git**: required for submodules and dependency bootstrap.
- **CMake**: `3.16+` is the safest baseline. Parts of the tree build with lower minimums, but Tim2Tox and the Windows installer path both use `3.16`.

### Platform-specific requirements

- **macOS**: Xcode, Command Line Tools, Homebrew and `libsodium`; the current CI package is a PKG.
- **Linux**: `build-essential`, `cmake`, `libgtk-3-dev`, `libsodium-dev`, `pkg-config`, `patchelf`, CPack and RPM/DEB packaging tools.
- **Windows**: Visual Studio 2019/2022, PowerShell, CMake, and WiX Toolset v3 if you want `.msi` packaging. `vcpkg` is used in CI to install `libsodium`.
- **Android**: Android SDK, Android NDK, and Java 17.
- **iOS**: Xcode and CocoaPods. For a distributable IPA you also need signing materials (certificate + provisioning profile).

## Quick paths

### Fastest local run

From the repository root:

```bash
dart run tool/bootstrap_deps.dart
flutter pub get
./run_toxee.sh
```

`run_toxee.sh` is the shortest path for local macOS development. It bootstraps dependencies when needed, builds the native pieces, launches the app, and writes logs such as:

- `build/native_build.log`
- `build/flutter_build.log`
- `build/flutter_client.log`

### Fastest cross-platform local build

```bash
./build_all.sh --platform macos --mode debug
./build_all.sh --platform linux --mode release
./build_all.sh --platform windows --mode release
./build_all.sh --platform android --mode release
./build_all.sh --platform ios --mode release
```

`build_all.sh` builds the Tim2Tox native library first, runs dependency bootstrap, and then executes the platform Flutter build.

### Fastest CI-backed release

- Push a tag such as `v1.2.3` to trigger [`.github/workflows/build-packages.yml`](../../.github/workflows/build-packages.yml).
- Or trigger `workflow_dispatch`, set `publish_release=true`, and provide `release_tag`.

## Local build flow

### 1. Bootstrap dependencies

Fresh clones and dependency updates must start here:

```bash
dart run tool/bootstrap_deps.dart
```

This initializes the required submodules, fetches and patches vendored SDK content, and refreshes `pubspec_overrides.yaml`.

### 2. Install Flutter packages

```bash
flutter pub get
```

### 3. Build for a platform

Examples:

```bash
# macOS
flutter build macos --debug

# Linux
flutter build linux --release

# Windows
flutter build windows --release

# Android
flutter build apk --release
flutter build appbundle --release

# iOS validation build
flutter build ios --release --no-codesign
```

If you already rely on the project scripts, `./build_all.sh` and `./run_toxee.sh` are the preferred entry points over manually repeating every step.

### 4. Package installables locally

After a successful platform build, you can package installables with:

```bash
bash tool/ci/package_artifacts.sh --target linux --mode release
bash tool/ci/package_artifacts.sh --target windows --mode release
bash tool/ci/package_artifacts.sh --target macos --mode release
bash tool/ci/package_artifacts.sh --target android --mode release
bash tool/ci/package_artifacts.sh --target ios --mode release
```

Those commands write outputs into `dist/<platform>/`.

## Package outputs

Current packaging outputs are:

| Platform | Main outputs | Notes |
| --- | --- | --- |
| **Windows** | `dist/windows/toxee-<version>-Windows-<AMD64|ARM64>.msi` | CPack + WiX |
| **macOS** | `dist/macos/toxee-<version>-Darwin-<x86_64|arm64>.pkg` | pkgbuild |
| **Linux** | `dist/linux/toxee-<version>-Linux-<x86_64|aarch64>.deb`, `.rpm` | CPack DEB/RPM |
| **Android** | `dist/android/toxee-<version>-Android-arm64.apk`, `.aab` | Development or explicit strict distribution preflight |
| **iOS** | `dist/ios/toxee-ios-release.ipa` | Development/device validation, not App Store export |

Desktop packaging also tries to bundle the Tim2Tox native library and `libsodium` into the packaged app output, and records the result in `dist/<platform>/NOTES.txt`.

## GitHub Actions packages and releases

The repository ships with [`.github/workflows/build-packages.yml`](../../.github/workflows/build-packages.yml). It runs on:

- `push` to `main` / `master`
- tag push for `v*`
- `pull_request`
- `workflow_dispatch`

It builds packages for:

- Windows
- Linux
- macOS
- Android
- iOS

Each platform job uploads `dist/<platform>/` as a workflow artifact. When the run is a version tag push, or when manual dispatch sets `publish_release=true`, the same workflow also:

- downloads the artifacts from the current run
- collects installables that passed release gating
- publishes them to GitHub Releases
- uploads `SHA256SUMS.txt`
- uploads merged platform notes as `BUILD-NOTES.txt`

The current desktop release assets are:

- **Windows**: `.msi`
- **macOS**: `.pkg`
- **Linux**: `.deb` and `.rpm`

## Signing and native-library gating

See [Store readiness](STORE_READINESS.md) for the actual signing inputs, final-artifact checks, policy sources, channel decisions and remaining owner/device evidence. Android signing secrets are optional for development builds; `android_distribution=true` requires all four Android secrets and the expected upload-certificate SHA-256. Strict local packaging enforces the same checks before copying artifacts. Ordinary debug-key release artifacts are development-only.

Unsigned iOS IPAs remain workflow validation artifacts and are skipped by GitHub Release publishing. The existing signed device-build path is not an App Store archive/export; strict distribution intent refuses that packager. Use `python3 tool/ci/ios_store_export.py --unsigned-archive` for unsigned Xcode archive validation, or the separate owner-approved manual local export described in [STORE_READINESS](STORE_READINESS.md#local-ios-archive-and-manual-export). Real signing, exported installation and store qualification remain owner gates. Final built Apple declarations and native payloads are inspected in CI. Desktop development outputs may be unsigned; trusted distribution and store qualification require their channel-specific evidence.

## Desktop runner native-library staging (dev builds)

The release packager (`tool/ci/package_artifacts.sh`) stages the Tim2Tox FFI library and `libsodium` for **all** desktop platforms. For **dev** builds run straight from `flutter build <platform>` (not through the packager), staging differs per platform — in every case the native library must be built first (`tool/ci/build_tim2tox.sh --target <platform>`, or `build_all.sh`):

- **Windows** — `windows/CMakeLists.txt` auto-stages `tim2tox_ffi.dll` + `libsodium.dll` next to the runner during the build, so the runner is directly runnable.
- **Linux** — `linux/CMakeLists.txt` auto-stages `libtim2tox_ffi.so` into `bundle/lib` and patchelf's its `RUNPATH` to `$ORIGIN`. It also bundles `libsodium.so*` when present in `build/native-artifacts/linux`; the `build_all.sh` path (`build_ffi.sh`) does not capture `libsodium`, so that bundle relies on the system `libsodium` via `ldconfig` — run `tool/ci/build_tim2tox.sh --target linux` for a fully self-contained bundle.
- **macOS** — `flutter build macos` does **not** stage the native library. Use `./run_toxee.sh` for dev (it copies `libtim2tox_ffi.dylib` + dependencies into `Toxee.app/Contents/MacOS` and rewrites install names via `install_name_tool`) or `tool/ci/package_artifacts.sh` for release. A raw `flutter build macos` artifact run on its own is missing the Tox native library **by design**: an Xcode build phase was deliberately not added, to avoid duplicating the `install_name_tool`/codesign logic those two scripts already own.

## Useful commands

```bash
# Dependency bootstrap
dart run tool/bootstrap_deps.dart

# Unified build
./build_all.sh --platform macos --mode debug

# Package local installables after a release build
bash tool/ci/package_artifacts.sh --target windows --mode release

# Prepare iOS signing in CI-like environments
bash tool/ci/prepare_ios_signing.sh

# Publish a prepared release artifact directory
RELEASE_TAG=v1.2.3 RELEASE_ARTIFACTS_DIR=$PWD/release-artifacts \
  bash tool/ci/publish_release.sh

# Packaging regression checks
bash tool/test_ci_packaging.sh
```

## Related docs

- [Main README](../../README.md) - project overview and high-level CI/release summary
- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - failures, logs, and runtime debugging
- [DEPENDENCY_BOOTSTRAP.md](DEPENDENCY_BOOTSTRAP.md) - bootstrap order and options
- [DEPENDENCY_LAYOUT.md](DEPENDENCY_LAYOUT.md) - `third_party/` layout and assumptions
- [getting-started.md](../getting-started.md) - shortest clone-to-run path
