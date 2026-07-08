# 依赖目录结构
> 语言 / Language: [中文](DEPENDENCY_LAYOUT.md) | [English](DEPENDENCY_LAYOUT.en.md)

本文说明 toxee 使用的第三方依赖目录结构，以及如何通过 bootstrap 流程让新克隆的仓库可构建。

## 导致新克隆无法构建的旧假设

在引入 bootstrap 之前，新克隆的 toxee 无法解析依赖，因为：

- **tim2tox_dart** 只能通过 `../tim2tox/dart`（仓库外的兄弟目录）解析。
- **UIKit 包**（tencent_cloud_chat_common、tencent_cloud_chat_message 等）只能通过 `../chat-uikit-flutter/...` 解析。
- **tencent_cloud_chat_sdk** 只能通过 `../tencent_cloud_chat_sdk-8.7.7201` 解析。

以上路径均依赖事先准备好的兄弟仓库。bootstrap 流程已消除这一要求。

## 目标布局（bootstrap 之后）

```
toxee/
├── third_party/
│   ├── tim2tox/                 # git submodule (https://github.com/agentx-icu/tim2tox)
│   │   ├── tool/
│   │   │   ├── tencent_cloud_chat_sdk.lock.json   # SDK 版本与归档 URL
│   │   │   └── apply_sdk_patches.dart             # 将 patch 系列应用到 SDK 目录
│   │   └── patches/tencent_cloud_chat_sdk/<ver>/  # series 与 *.patch 文件
│   ├── chat-uikit-flutter/      # git submodule（agentx-icu/chat-uikit-flutter  fork）
│   └── tencent_cloud_chat_sdk/  # 生成：下载并打补丁后的 vendor 树
├── tool/
│   ├── bootstrap_deps.dart      # bootstrap CLI（协调 submodule、vendor，调用 tim2tox apply）
│   └── vendor_state.json        # 生成
└── pubspec_overrides.yaml       # 生成；将本地依赖指向 third_party/
```

- **third_party/tim2tox**（上游 [https://github.com/agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)）与 **third_party/chat-uikit-flutter** 为 git submodule，由 `dart run tool/bootstrap_deps.dart` 初始化与更新。
- **third_party/tencent_cloud_chat_sdk** 不入库，由 bootstrap 从锁定的归档下载并打补丁生成。
- **pubspec_overrides.yaml** 由 bootstrap 生成，使 `flutter pub get` 仅从 `third_party/` 下解析 tim2tox_dart、tencent_cloud_chat_sdk 及所有 UIKit 包。

## 新克隆的入口流程

1. `git clone <toxee-repo>`
2. `dart run tool/bootstrap_deps.dart` — 初始化 submodule、拉取并打补丁 SDK、生成 `pubspec_overrides.yaml`
3. `flutter pub get`
4. 构建（例如 `./build_all.sh --platform macos --mode debug`）

具体 bootstrap 顺序见 [DEPENDENCY_BOOTSTRAP.md](DEPENDENCY_BOOTSTRAP.md)，所有权与升级流程见 [PATCH_MAINTENANCE.md](PATCH_MAINTENANCE.md)。
