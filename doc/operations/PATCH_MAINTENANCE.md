# 补丁维护
> 语言 / Language: [中文](PATCH_MAINTENANCE.md) | [English](PATCH_MAINTENANCE.en.md)

## 所有权

- **toxee** 拥有 submodule 指针（如 `third_party/tim2tox`、`third_party/chat-uikit-flutter`）及 bootstrap 编排。不对 `chat-uikit-flutter` 打补丁；UIKit 定制以普通提交存在于 fork 中。
- **tim2tox** 拥有 `tencent_cloud_chat_sdk` 补丁及 SDK lock/应用工具：`tool/tencent_cloud_chat_sdk.lock.json`（版本、归档 URL、可选 SHA-256）与 `tool/apply_sdk_patches.dart`（将补丁系列应用到指定 SDK 目录）。所有仅针对 SDK 的修改存放在 `patches/tencent_cloud_chat_sdk/<version>/` 下，以 `series` 文件及有序的 `.patch` 文件形式存在。
- **chat-uikit-flutter** 的定制在 fork（`agentx-icu/chat-uikit-flutter`）中维护。在 toxee 中更新 submodule 指针即可使用；UIKit 不做补丁应用。

## SDK 补丁流程

1. Bootstrap 根据 lock 文件拉取 SDK，并应用来自 `third_party/tim2tox/patches/tencent_cloud_chat_sdk/<version>/` 的补丁系列。
2. 修改 SDK：在 `third_party/tencent_cloud_chat_sdk` 下编辑文件，然后执行 `tool/refresh_sdk_patch.sh` 将补丁重新生成到 tim2tox 的 patches 目录。在 tim2tox 仓库中提交新增/更新的补丁文件（若 tim2tox 为 submodule 且你提交 submodule 更新，则在 toxee 中提交）。
3. `tool/refresh_sdk_patch.sh` 仅向 `third_party/tim2tox/patches/tencent_cloud_chat_sdk/` 写入 SDK 补丁；不创建或修改 UIKit 补丁。

## 升级检查清单

1. 在 `third_party/chat-uikit-flutter` 中更新目标 fork 提交（例如 `git -C third_party/chat-uikit-flutter fetch && git -C third_party/chat-uikit-flutter checkout <commit>`，再在父项目中记录）。
2. 在 `third_party/tim2tox` 中更新目标 tim2tox 提交。
3. 若升级 SDK，在 `third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json` 中更新 SDK 版本与校验和（配置在 tim2tox 仓库）。
4. 若 SDK 版本或补丁有变更，刷新 `third_party/tim2tox/patches/tencent_cloud_chat_sdk/<version>/` 下的补丁（在 toxee 中运行 `tool/refresh_sdk_patch.sh`，或在 tim2tox 中新增补丁文件并更新 `series`）。
5. 从头重新执行 bootstrap：`dart run tool/bootstrap_deps.dart --force`。
6. 重新执行针对性构建验证（例如 `./build_all.sh --platform macos --mode debug`）。
