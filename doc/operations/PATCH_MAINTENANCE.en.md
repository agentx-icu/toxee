# Patch maintenance
> Language: [中文](PATCH_MAINTENANCE.md) | [English](PATCH_MAINTENANCE.en.md)

## Ownership

- **toxee** owns submodule pointers (e.g. `third_party/tim2tox`, `third_party/chat-uikit-flutter`) and bootstrap orchestration. It does not patch `chat-uikit-flutter`; UIKit customizations live as normal commits in the fork.
- **tim2tox** owns `tencent_cloud_chat_sdk` patches and the SDK lock/apply tooling: `tool/tencent_cloud_chat_sdk.lock.json` (version, archive URL, optional SHA-256) and `tool/apply_sdk_patches.dart` (applies the patch series to a given SDK dir). All SDK-only changes are stored under `patches/tencent_cloud_chat_sdk/<version>/` as a `series` file plus ordered `.patch` files.
- **chat-uikit-flutter** customizations are maintained in the fork (`agentx-icu/chat-uikit-flutter`). Consume them by updating the submodule pointer in toxee; no patch application for UIKit.

## SDK patch workflow

1. Bootstrap vendors the SDK from the lock file and applies the patch series from `third_party/tim2tox/patches/tencent_cloud_chat_sdk/<version>/`.
2. To change the SDK: edit files under `third_party/tencent_cloud_chat_sdk`, then run `tool/refresh_sdk_patch.sh` to regenerate patches into the tim2tox patches directory. Commit the new/updated patch files in the tim2tox repo (or in toxee if tim2tox is a submodule and you commit the submodule update).
3. `tool/refresh_sdk_patch.sh` writes only SDK patches under `third_party/tim2tox/patches/tencent_cloud_chat_sdk/`; it does not create or modify UIKit patches.

## Upgrade checklist

1. Update the desired fork commit in `third_party/chat-uikit-flutter` (e.g. `git -C third_party/chat-uikit-flutter fetch && git -C third_party/chat-uikit-flutter checkout <commit>` then record in superproject).
2. Update the desired tim2tox commit in `third_party/tim2tox`.
3. Bump SDK version and checksum in `third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json` if upgrading the SDK (config lives in tim2tox repo).
4. Refresh SDK patches in `third_party/tim2tox/patches/tencent_cloud_chat_sdk/<version>/` if the SDK version or patches changed (run toxee's `tool/refresh_sdk_patch.sh` or add patch files and update `series` in tim2tox).
5. Rerun bootstrap from scratch: `dart run tool/bootstrap_deps.dart --force`.
6. Rerun focused build verification (e.g. `./build_all.sh --platform macos --mode debug`).
