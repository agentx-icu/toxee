[English](./getting-started.md)

# 从克隆到跑起来

> 语言 / Language: [中文](getting-started.md) | [English](getting-started.md)

本文是「第一次跑 toxee」的单页指引，统一从克隆到可运行的最短路径。详细依赖顺序与选项见 [operations/DEPENDENCY_BOOTSTRAP.md](operations/DEPENDENCY_BOOTSTRAP.md)。

## 前置要求

- Git、Flutter SDK（>= 3.22）、Dart SDK（>= 3.5）、CMake（>= 3.4.1）
- 各平台额外要求见 [operations/BUILD_AND_DEPLOY.md](operations/BUILD_AND_DEPLOY.md)

## 最短路径（仓库根目录执行）

```bash
# 1. 克隆（若尚未克隆）
git clone <repo-url> toxee && cd toxee

# 2. 依赖引导：submodule、SDK 拉取与打补丁、生成 pubspec_overrides
dart run tool/bootstrap_deps.dart

# 3. 拉取 Dart/Flutter 依赖
flutter pub get

# 4. 构建并运行（会先构建 tim2tox FFI 库）
./build_all.sh --platform macos --mode debug
# 或：构建 + 启动
./run_toxee.sh
```

其他平台示例：`--platform ios`、`--platform android`；仅运行见 `./run_toxee_ios.sh`、`./run_toxee_android.sh` 等。

## 常见问题

- **`package_config.json` 解析错误**：先执行 `dart tool/bootstrap_deps.dart`（不用 `run`），再执行 `flutter pub get`。
- **依赖或构建失败**：见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。
- **bootstrap 做了什么**：见 [operations/DEPENDENCY_BOOTSTRAP.md](operations/DEPENDENCY_BOOTSTRAP.md) 的 Bootstrap order；升级/重打补丁可用 `dart run tool/bootstrap_deps.dart --force`。

## 下一步

- 项目与架构概览：[主 README](../README.zh-CN.md)、[architecture/ARCHITECTURE.md](architecture/ARCHITECTURE.md)
- 按角色继续阅读：[doc/README 推荐阅读路径](README.md#推荐阅读路径按角色)
