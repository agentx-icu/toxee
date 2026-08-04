[简体中文](./getting-started.zh-CN.md)

# Clone to run


This page is the single-path guide for “running toxee for the first time”: from clone to a runnable app. For detailed dependency order and options, see [operations/DEPENDENCY_BOOTSTRAP.md](operations/DEPENDENCY_BOOTSTRAP.md).

## Prerequisites

- Git, Flutter SDK (>= 3.22), Dart SDK (>= 3.5), CMake (>= 3.4.1)
- Per-platform requirements: [operations/BUILD_AND_DEPLOY.md](operations/BUILD_AND_DEPLOY.md)

## Short path (run from repo root)

```bash
# 1. Clone (if not already)
git clone <repo-url> toxee && cd toxee

# 2. Dependency bootstrap: submodules, SDK fetch & patch, pubspec_overrides
dart run tool/bootstrap_deps.dart

# 3. Fetch Dart/Flutter dependencies
flutter pub get

# 4. Build and run (builds tim2tox FFI first)
./build_all.sh --platform macos --mode debug
# Or: build + launch
./run_toxee.sh
```

Other platforms: `--platform ios`, `--platform android`; run-only scripts: `./run_toxee_ios.sh`, `./run_toxee_android.sh`, etc.

## FAQ

- **`package_config.json` parse error**: Run `dart tool/bootstrap_deps.dart` (without `run`) first, then `flutter pub get`.
- **Dependency or build failure**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
- **What bootstrap does**: See [operations/DEPENDENCY_BOOTSTRAP.md](operations/DEPENDENCY_BOOTSTRAP.md) (Bootstrap order); use `dart run tool/bootstrap_deps.dart --force` to re-vendor and re-apply patches.

## Next steps

- Project and architecture overview: [Main README](../README.md), [architecture/ARCHITECTURE.md](architecture/ARCHITECTURE.md)
- Reading path by role: [doc/README – Recommended reading path](README.md)
