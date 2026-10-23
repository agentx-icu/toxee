[English](./BUILD_AND_DEPLOY.md)

# toxee 构建与部署

本文档说明 toxee 当前真实可用的构建与打包流程：本地开发构建、本地安装包打包，以及通过 GitHub Actions 发布 GitHub Releases。遇到构建失败、启动崩溃、bootstrap 异常或运行时排障时，请先看 [../TROUBLESHOOTING.md](../TROUBLESHOOTING.md)。

## 目录

- [环境要求](#环境要求)
- [最快路径](#最快路径)
- [本地构建流程](#本地构建流程)
- [安装包产物](#安装包产物)
- [GitHub Actions 打包与发布](#github-actions-打包与发布)
- [签名与原生库门禁](#签名与原生库门禁)
- [常用命令](#常用命令)
- [相关文档](#相关文档)

## 环境要求

### 核心工具

- **Flutter**：建议使用 `3.41.x` 或与当前 lockfile 兼容的更高版本。当前 CI workflow 固定使用 `3.41.9`，`pubspec.lock` 当前也要求 Flutter `>=3.41.9`。
- **Dart**：使用所选 Flutter 自带的 Dart SDK。
- **Git**：bootstrap、submodule 与依赖拉取都需要。
- **CMake**：建议 `3.16+`。仓库中有些路径最低要求更低，但 Tim2Tox 和 Windows 安装包链路都使用到 `3.16`。

### 平台要求

- **macOS**：Xcode、Command Line Tools、Homebrew、`libsodium`；当前 CI 生成 PKG。
- **Linux**：`build-essential`、`cmake`、`libgtk-3-dev`、`libsodium-dev`、`pkg-config`、`patchelf`、CPack 及 RPM/DEB 打包工具。
- **Windows**：Visual Studio 2019/2022、PowerShell、CMake；如果要打 `.msi`，还需要 WiX Toolset v3。CI 使用 `vcpkg` 安装 `libsodium`。
- **Android**：Android SDK、Android NDK、Java 17。
- **iOS**：Xcode、CocoaPods；如果要产出正式可分发 IPA，还需要证书和 provisioning profile。

## 最快路径

### 最快本地运行

在仓库根目录执行：

```bash
dart run tool/bootstrap_deps.dart
flutter pub get
./run_toxee.sh
```

`run_toxee.sh` 是当前 macOS 本地开发最短路径。它会在需要时做 bootstrap、构建原生依赖并启动应用，同时生成：

- `build/native_build.log`
- `build/flutter_build.log`
- `build/flutter_client.log`

### 最快跨平台本地构建

```bash
./build_all.sh --platform macos --mode debug
./build_all.sh --platform linux --mode release
./build_all.sh --platform windows --mode release
./build_all.sh --platform android --mode release
./build_all.sh --platform ios --mode release
```

`build_all.sh` 会先构建 Tim2Tox 原生库，再执行 bootstrap 和对应平台的 Flutter 构建。

### 最快 CI 发版路径

- 推送 `v1.2.3` 这样的 tag，会触发 [`.github/workflows/build-packages.yml`](../../.github/workflows/build-packages.yml) 自动构建并发布。
- 或手动执行 `workflow_dispatch`，把 `publish_release` 设为 `true`，并填写 `release_tag`。

## 本地构建流程

### 1. 依赖引导

首次克隆或依赖变化后，先执行：

```bash
dart run tool/bootstrap_deps.dart
```

它会初始化所需 submodule、拉取并打补丁 vendored SDK 内容，并刷新 `pubspec_overrides.yaml`。

### 2. 安装 Flutter 依赖

```bash
flutter pub get
```

### 3. 执行平台构建

示例：

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

# iOS 未签名校验构建
flutter build ios --release --no-codesign
```

如果你已经在使用仓库脚本，优先推荐 `./build_all.sh` 和 `./run_toxee.sh`，不要手工重复拼所有步骤。

### 4. 本地打安装包

平台构建完成后，可用下面的脚本把产物整理到 `dist/<platform>/`：

```bash
bash tool/ci/package_artifacts.sh --target linux --mode release
bash tool/ci/package_artifacts.sh --target windows --mode release
bash tool/ci/package_artifacts.sh --target macos --mode release
bash tool/ci/package_artifacts.sh --target android --mode release
bash tool/ci/package_artifacts.sh --target ios --mode release
```

## 安装包产物

当前打包脚本会生成这些产物：

| 平台 | 主要产物 | 说明 |
| --- | --- | --- |
| **Windows** | `dist/windows/toxee-<version>-Windows-<AMD64|ARM64>.msi` | CPack + WiX |
| **macOS** | `dist/macos/toxee-<version>-Darwin-<x86_64|arm64>.pkg` | pkgbuild |
| **Linux** | `dist/linux/toxee-<version>-Linux-<x86_64|aarch64>.deb`, `.rpm` | CPack DEB/RPM |
| **Android** | `dist/android/toxee-<version>-Android-arm64.apk`, `.aab` | Development or explicit strict distribution preflight |
| **iOS** | `dist/ios/toxee-ios-release.ipa` | Development/device validation, not App Store export |

桌面端打包还会尽量把 Tim2Tox FFI 和 `libsodium` 一起带进安装包，并把结果写进 `dist/<platform>/NOTES.txt`。

## GitHub Actions 打包与发布

仓库内置了 [`.github/workflows/build-packages.yml`](../../.github/workflows/build-packages.yml)。它会在以下场景执行：

- `push` 到 `main` / `master`
- 推送 `v*` tag
- `pull_request`
- `workflow_dispatch`

它会为这些平台构建并上传 artifact：

- Windows
- Linux
- macOS
- Android
- iOS

每个平台 job 都会上传 `dist/<platform>/`。当本次 run 是版本 tag，或者手动触发时设置了 `publish_release=true`，同一个 workflow 还会：

- 下载当前 run 的各平台 artifact
- 只收集通过发布门禁的安装包
- 发布到 GitHub Releases
- 额外上传 `SHA256SUMS.txt`
- 额外上传合并后的平台说明 `BUILD-NOTES.txt`

当前桌面端 Release 资产类型为：

- **Windows**：`.msi`
- **macOS**：`.pkg`
- **Linux**：`.deb` + `.rpm`

## 签名与原生库门禁

签名输入、最终制品门禁、官方政策、渠道选择和剩余负责人/真机证据统一见[商店上架准备](STORE_READINESS.zh-CN.md)。Android secrets 对开发构建可选；`android_distribution=true` 要求全部四项 secrets 和预期上传证书 SHA-256。本地 strict 入口在复制制品前执行相同门禁；普通 debug-key release 属于开发验证。

未签名 iOS IPA 仅保留为 workflow 验证制品，不进入 GitHub Release。已有带签名的设备构建不等于 App Store archive/export；在合格 export 流程实现前，strict 分发意图会被该打包入口拒绝。CI 检查最终 built Apple 声明和原生 payload。桌面开发包可以未签名，正式分发及商店提交仍需各渠道的信任/验收证据。

## 桌面端 runner 原生库装载（开发构建）

打包脚本（`tool/ci/package_artifacts.sh`）会为**所有**桌面平台装载 Tim2Tox FFI 库和 `libsodium`。对于直接用 `flutter build <platform>`（不经过打包脚本）的**开发**构建，各平台的装载方式不同——无论哪种，都必须先构建原生库（`tool/ci/build_tim2tox.sh --target <platform>`，或 `build_all.sh`）：

- **Windows** — `windows/CMakeLists.txt` 会在构建时把 `tim2tox_ffi.dll` + `libsodium.dll` 自动装载到 runner 旁，因此 runner 可直接运行。
- **Linux** — `linux/CMakeLists.txt` 会把 `libtim2tox_ffi.so` 自动装载到 `bundle/lib`，并用 patchelf 把它的 `RUNPATH` 改为 `$ORIGIN`。当 `build/native-artifacts/linux` 中存在 `libsodium.so*` 时也会一并装载；`build_all.sh` 路径（`build_ffi.sh`）不会捕获 `libsodium`，因此那种 bundle 依赖系统 `libsodium`（经 `ldconfig`）——需要完全自包含的 bundle 请运行 `tool/ci/build_tim2tox.sh --target linux`。
- **macOS** — `flutter build macos` **不会**装载原生库。开发请用 `./run_toxee.sh`（它会把 `libtim2tox_ffi.dylib` 及依赖复制进 `Toxee.app/Contents/MacOS`，并用 `install_name_tool` 改写 install name），发布用 `tool/ci/package_artifacts.sh`。单独运行 `flutter build macos` 的产物**按设计**会缺少 Tox 原生库：刻意没有添加 Xcode build phase，以避免重复这两个脚本已经维护的 `install_name_tool`/签名逻辑。

## 常用命令

```bash
# 依赖引导
dart run tool/bootstrap_deps.dart

# 统一构建
./build_all.sh --platform macos --mode debug

# 本地安装包打包
bash tool/ci/package_artifacts.sh --target windows --mode release

# 在类 CI 环境里准备 iOS 签名
bash tool/ci/prepare_ios_signing.sh

# 发布已准备好的 release-artifacts 目录
RELEASE_TAG=v1.2.3 RELEASE_ARTIFACTS_DIR=$PWD/release-artifacts \
  bash tool/ci/publish_release.sh

# 打包链路回归测试
bash tool/test_ci_packaging.sh
```

## 相关文档

- [主 README](../../README.zh-CN.md) - 项目总览与高层 CI/Release 说明
- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - 失败排查、日志与运行时调试
- [DEPENDENCY_BOOTSTRAP.md](DEPENDENCY_BOOTSTRAP.md) - bootstrap 顺序与选项
- [DEPENDENCY_LAYOUT.md](DEPENDENCY_LAYOUT.md) - `third_party/` 布局与约束
- [getting-started.md](../getting-started.md) - 从克隆到跑起来的最短路径
