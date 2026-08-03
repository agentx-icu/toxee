[English](./DEPENDENCY_BOOTSTRAP.md)

# 依赖 Bootstrap
> 语言 / Language: [中文](DEPENDENCY_BOOTSTRAP.md) | [English](DEPENDENCY_BOOTSTRAP.md)

本文说明 bootstrap 的精确执行顺序，以及如何从新克隆得到可构建的目录树。

## Bootstrap 顺序

在 **toxee 仓库根目录** 执行：

```bash
dart run tool/bootstrap_deps.dart
```

工具按以下顺序执行：

1. **初始化 submodule** — 对 `third_party/tim2tox` 与 `third_party/chat-uikit-flutter` 执行 `git submodule sync --recursive` 和 `git submodule update --init --recursive`。若仓库尚未注册 submodule（无 gitlink），则根据 `.gitmodules` 中的 URL 克隆到 `third_party/`。
2. **拉取 SDK（vendor）** — 从 `third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json` 中的 URL 下载 tencent_cloud_chat_sdk 归档（配置在 tim2tox 仓库），如有 SHA-256 则校验，并解压到 `third_party/tencent_cloud_chat_sdk`。若已存在且版本一致则跳过（使用 `--force` 可强制重新拉取）。
3. **应用 SDK 补丁** — 调用 tim2tox 的 `dart run tool/apply_sdk_patches.dart --sdk-dir=...`，从 tim2tox 仓库读取 lock 与 patch 系列，对已拉取的 SDK 打补丁。若补丁已应用（由 toxee 的 `tool/vendor_state.json` 记录）则跳过。
4. **生成 pubspec_overrides.yaml** — 写入 override，使 `tim2tox_dart`、`tencent_cloud_chat_sdk` 及所有 UIKit 包解析到 `third_party/` 下的路径。该文件被 gitignore，每次 bootstrap 都会重新生成。
5. **随后由你执行** — `flutter pub get`（及任意构建）。构建脚本（`build_all.sh`、`run_toxee.sh` 等）与 CI 会在 `flutter pub get` 前自动执行 bootstrap。

## 新克隆的一次性准备

```bash
git clone <toxee-repo> toxee
cd toxee
dart run tool/bootstrap_deps.dart
flutter pub get
./build_all.sh --platform macos --mode debug   # 或 run_toxee.sh 等
```

## 选项

- **`--offline-check-only`** — 仅校验 lock 文件、submodule 目录与已拉取的 SDK 是否存在；退出码 0/1。不访问网络、不写入。
- **`--force`** — 重新拉取 SDK（删除后重新下载/解压）并重新应用补丁。升级 SDK 版本或修改 lock 后使用。

## 参见

- [DEPENDENCY_LAYOUT.md](DEPENDENCY_LAYOUT.md) — 目标目录布局与旧假设说明。
- [PATCH_MAINTENANCE.md](PATCH_MAINTENANCE.md) — 所有权归属与 submodule/SDK/补丁升级方式。
