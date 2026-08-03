[简体中文](./DEPENDENCY_BOOTSTRAP.zh-CN.md)

# Dependency bootstrap
> Language: [中文](DEPENDENCY_BOOTSTRAP.md) | [English](DEPENDENCY_BOOTSTRAP.md)

This document describes the exact bootstrap order and how to get from a fresh clone to a buildable tree.

## Bootstrap order

Run from the **toxee repo root**:

```bash
dart run tool/bootstrap_deps.dart
```

The tool performs these steps in order:

1. **Initialize submodules** — `git submodule sync --recursive` and `git submodule update --init --recursive` for `third_party/tim2tox` and `third_party/chat-uikit-flutter`. If the repo does not yet have submodules registered (no gitlink entries), it clones those repositories from the URLs in `.gitmodules` into `third_party/`.
2. **Vendor the SDK** — Downloads the tencent_cloud_chat_sdk archive from the URL in `third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json` (config lives in tim2tox repo), verifies SHA-256 if present, and unpacks it into `third_party/tencent_cloud_chat_sdk`. Skips if already present and version matches (use `--force` to re-vendor).
3. **Apply SDK patches** — Calls tim2tox's `dart run tool/apply_sdk_patches.dart --sdk-dir=...`, which reads the lock and patch series from the tim2tox repo and applies patches to the vendored SDK. Skips if patches were already applied (tracked in toxee's `tool/vendor_state.json`).
4. **Generate pubspec_overrides.yaml** — Writes overrides so that `tim2tox_dart`, `tencent_cloud_chat_sdk`, and all UIKit packages resolve to paths under `third_party/`. This file is gitignored and regenerated on every bootstrap.
5. **You then run** — `flutter pub get` (and any build). Build scripts (`build_all.sh`, `run_toxee.sh`, etc.) and CI run bootstrap before `flutter pub get` automatically.

## One-time setup for a fresh clone

```bash
git clone <toxee-repo> toxee
cd toxee
dart run tool/bootstrap_deps.dart
flutter pub get
./build_all.sh --platform macos --mode debug   # or run_toxee.sh, etc.
```

## Options

- **`--offline-check-only`** — Only verify that lock file, submodule dirs, and vendored SDK exist; exit 0/1. No network, no writes.
- **`--force`** — Re-vendor the SDK (delete and re-download/unpack) and re-apply patches. Use when upgrading the SDK version or after changing the lock file.

## See also

- [DEPENDENCY_LAYOUT.md](DEPENDENCY_LAYOUT.md) — Target directory layout and legacy assumptions.
- [PATCH_MAINTENANCE.md](PATCH_MAINTENANCE.md) — Who owns what and how to upgrade submodules/SDK/patches.
