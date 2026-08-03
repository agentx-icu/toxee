[English](./ACCOUNT_AND_SESSION.md)

# toxee 账号与会话
> 语言 / Language: [中文](ACCOUNT_AND_SESSION.md) | [English](ACCOUNT_AND_SESSION.md)


本文档说明 toxee 当前的账号生命周期实现，重点覆盖自动登录、手动登录、注册、切换账号、退出登录、删除账号，以及密码保护 profile 的处理方式。

## 1. 角色分工

- `AccountService`：统一封装账号初始化、注册、销毁、删除。
- `_StartupGate`：自动登录入口，负责首屏启动顺序与连接等待。
- `LoginPage`：已有账号快速登录、新账号入口、登录页删除账号。
- `AccountSwitcher`：设置页切换账号时复用 `AccountService`。
- `SettingsPage`：退出登录、导出、删除账号的 UI 入口。
- `SessionPasswordStore`：只在内存中保存本次会话密码，用于退出时重新加密 `tox_profile.tox`。

## 2. 账号初始化

当前已有账号的主入口是 `AccountService.initializeServiceForAccount(...)`。

核心步骤：

1. 设置当前账号 `toxId`。
2. 迁移旧目录到按账号隔离的存储结构。
3. 解析历史消息、离线队列、接收文件目录、头像目录。
4. 恢复或迁移 `tox_profile.tox`。
5. 如果账号有密码，先解密 profile，并把密码放入 `SessionPasswordStore`。
6. 创建 `FfiChatService`，注入 `SharedPreferencesAdapter`、`AppLoggerAdapter`、`BootstrapNodesAdapter`。
7. 执行 `init(profileDirectory: ...)`、`login(...)`、`updateSelfProfile(...)`。
8. 按调用方需要决定是否立刻 `startPolling()`。

## 3. 启动路径

### 自动登录

`main.dart` 中的 `_StartupGate._decide()` 当前顺序是：

1. 读取自动登录配置与当前账号。
2. 通过 `AccountService.initializeServiceForAccount(..., startPolling: false)` 恢复账号。
3. 调用 `FakeUIKit.startWithFfi(service)` 提前启动 UIKit 侧状态。
4. 调用 `_initTIMManagerSDK()`。
5. 调用 `service.startPolling()`。
6. 等待连接成功或超时。
7. 预加载好友与联系人状态。
8. 导航到 `HomePage(service)`。

### 手动登录

`LoginPage` 中已有账号优先复用 `AccountService.initializeServiceForAccount(...)`。只有历史兼容路径才会手动创建 `FfiChatService` 并执行 `init()`、`login()`、`updateSelfProfile()`、`startPolling()`。

## 4. 注册路径

`AccountService.registerNewAccount(...)` 当前流程：

1. 清空当前账号，确保新注册时加载空状态。
2. 在临时目录初始化 `FfiChatService`，生成新的 `toxId`。
3. 将临时 profile 目录重命名到正式账号目录。
4. 更新昵称和状态消息。
5. 写入账号列表、当前账号和元数据。
6. 如果设置了密码，先加密再解密 profile 做一次验证，然后按账号隔离目录重新初始化 service。
7. 最后启动 `startPolling()` 并返回新的 service。

## 5. 切换、退出与删除

### 切换账号

`AccountSwitcher.switchAccount(...)` 会：

1. 调用 `AccountService.teardownCurrentSession(...)` 销毁旧会话。
2. 校验目标账号密码。
3. 重新调用 `initializeServiceForAccount(...)` 恢复目标账号。
4. 导航到新的 `HomePage`。

### 退出登录

`SettingsPage._logout()` 会调用 `AccountService.teardownCurrentSession(service: widget.service)`，然后清空当前账号 ID 并返回登录页。

### 删除账号

- 设置页删除：调用 `AccountService.deleteAccountCompletely(...)`，会先 teardown，再清理 prefs、账号列表、profile 目录和账号数据目录。
- 登录页删除：调用 `AccountService.deleteAccountWithoutService(...)`，因为此时没有运行中的 service。

## 6. 会话销毁顺序

`AccountService.teardownCurrentSession(...)` 当前顺序如下：

1. `FakeUIKit.instance.dispose()`
2. 若当前 Platform 是 `Tim2ToxSdkPlatform`，先 `dispose()`，再恢复为默认 `MethodChannelTencentCloudChatSdk`
3. 清空 `ChatDataProviderRegistry` 与 `ChatMessageProviderRegistry`
4. 清理 `GroupMemberListDebouncer`、`IrcAppManager` 等静态缓存
5. `service.dispose()`
6. 如果当前会话使用密码，重新加密磁盘上的 `tox_profile.tox`
7. 清理 `SessionPasswordStore`

这个顺序的关键点是：`FakeUIKit` 必须先于 `Tim2ToxSdkPlatform` 销毁，否则通话桥和 signaling listener 的清理会丢失依赖。

## 7. 存储模型

每个账号都有独立的运行目录：

- `tox_profile.tox`
- `chat_history/`
- `offline_message_queue.json`
- `avatars/`
- `file_recv/`

这些路径由 `AppPaths` 统一生成，避免多个账号共享同一份历史数据或缓存。

完整账号备份使用 `.zip` 格式，包含 `tox_profile.tox`、`chat_history/`、`offline_message_queue.json`、`avatars/` 和 `metadata.json`。导出时会把账号目录下的头像路径改写为 `@account_data/...`，并会补齐缺失的 `friend_avatar_path_<friendId>` 元数据（包括 `friend_<id>_avatar_<timestamp>.<ext>` 这类运行期头像文件）。导入时会先校验 `chat_history/` 与 `avatars/` 内的归档路径，拒绝 `../`、绝对路径、Windows drive 前缀或反斜杠路径，确认安全后才写入 profile、历史、离线队列和 scoped prefs。

## 8. 密码与 profile 加密

- 密码哈希保存在持久化配置中，用于校验账号密码。
- 会话明文密码只放在 `SessionPasswordStore` 内存里，不落盘。
- 登录时如果发现 profile 已加密，会先解密。
- 退出登录时如果本次会话有密码，会重新加密 `tox_profile.tox`。
- 删除账号时不会重新加密，因为 profile 会被直接删除。

## 9. 相关文档

- [architecture/HYBRID_ARCHITECTURE.md](../architecture/HYBRID_ARCHITECTURE.md)
- [../architecture/MAINTAINER_ARCHITECTURE.md](../architecture/MAINTAINER_ARCHITECTURE.md)
- [CALLING_AND_EXTENSIONS.md](CALLING_AND_EXTENSIONS.md)
