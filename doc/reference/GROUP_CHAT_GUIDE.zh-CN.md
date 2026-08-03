[English](./GROUP_CHAT_GUIDE.md)

# toxee 群聊功能
> 语言 / Language: [中文](GROUP_CHAT_GUIDE.md) | [English](GROUP_CHAT_GUIDE.md)


本文档详细说明 toxee 中群聊功能的实现、使用方法和关键流程。

## 目录

1. [概述](#概述)
2. [群聊生命周期](#群聊生命周期)
3. [核心功能](#核心功能)
4. [数据持久化](#数据持久化)
5. [映射关系管理](#映射关系管理)
6. [常见问题](#常见问题)
7. [调试指南](#调试指南)

## 概述

toxee 使用 Tim2Tox 实现基于 Tox 协议的 P2P 群聊功能。群聊功能完全去中心化，不依赖任何中央服务器。

### 关键概念

- **group_id**: 应用层群组标识符，格式为 `tox_<number>`（如 `tox_1`, `tox_2`）
- **group_number**: Tox 协议层的群组编号，由 Tox 分配
- **chat_id**: Tox 群组的唯一标识符（32 字节），用于重新加入群组（仅 Group 类型支持）
- **映射关系**: `group_id` ↔ `group_number` ↔ `chat_id` 之间的映射
- **groupType**: 群组类型，可以是 `"group"`（新 API）或 `"conference"`（旧 API）

### Group vs Conference

toxee 同时支持两种 Tox 群聊类型：

#### Group（新 API）
- **创建方式**: 使用 `tox_group_new` 创建
- **邀请方式**: 使用 `tox_group_invite_friend` 邀请
- **加入方式**: 使用 `tox_group_join` 通过 `chat_id` 加入
- **持久化**: 支持 `chat_id` 持久化，可通过 `chat_id` 重新加入
- **恢复机制**: Client 重启后通过 `chat_id` 调用 `tox_group_join` 恢复
- **功能**: 支持群公告（topic）、群昵称（peer name）、成员管理等完整功能

#### Conference（旧 API）
- **创建方式**: 使用 `tox_conference_new` 创建
- **邀请方式**: 使用 `tox_conference_invite` 邀请（需要是好友）
- **加入方式**: 使用 `tox_conference_join` 通过 `cookie` 加入
- **持久化**: 不支持 `chat_id`，依赖 Tox savedata 自动恢复
- **恢复机制**: Client 重启后从 savedata 自动恢复，需要手动匹配 `conference_number` 到 `group_id`
- **功能**: 功能相对简单，不支持群公告等高级功能

**选择建议**：
- 新群组建议使用 **Group** 类型，功能更完整，恢复更可靠
- 仅在与使用旧 API 的客户端兼容时才使用 **Conference** 类型

## 群聊生命周期

### 1. 创建群组

**调用路径**：
```
UI 层 (add_group_dialog.dart)
  ↓ createGroup(groupType: "group" | "conference")
Service 层 (ffi_chat_service.dart)
  ↓ createGroup(name, groupType)
FFI 层 (tim2tox_ffi.cpp)
  ↓ tim2tox_ffi_create_group()
C++ 层 (V2TIMGroupManagerImpl.cpp)
  ↓ V2TIMGroupManagerImpl::CreateGroup()
  ↓ tox_group_new() 或 tox_conference_new()
```

**流程**：
1. 用户在 UI 中选择群组类型（Group 或 Conference）
2. 生成唯一的 `group_id`（如果未提供）
3. 根据 `groupType` 调用对应的 API：
   - **Group**: 调用 `tox_group_new` 创建
   - **Conference**: 调用 `tox_conference_new` 创建
4. 获取 `group_number`（或 `conference_number`）
5. **仅 Group 类型**：获取 `chat_id` 并持久化
6. 持久化 `groupType` 到存储
7. 建立 `group_id` → `group_number` 映射
8. 将 `group_id` 添加到 `_knownGroups`
9. 触发 `onGroupCreated` 回调，更新 UI

**关键代码位置**：
- Dart: `tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:createGroup()`
- C++: `tim2tox/source/V2TIMManagerImpl.cpp:CreateGroup()`
- C++: `tim2tox/source/ToxManager.cpp:createGroup()`

### 2. 加入群组

**调用路径**：
```
UI 层
  ↓ joinGroup()
Service 层 (ffi_chat_service.dart)
  ↓ joinGroup()
C++ 层
  ↓ V2TIMGroupManagerImpl::JoinGroup()
  ↓ ToxManager::joinGroup()
  ↓ tox_group_join()
```

**流程**：
1. 使用 `chat_id` 调用 `tox_group_join`
2. Tox 异步处理加入请求（需要 DHT 发现 peer）
3. 成功加入后触发 `onGroupSelfJoin` 回调
4. 建立映射关系
5. 持久化 `chat_id`
6. 更新 `_knownGroups`

**注意事项**：
- `tox_group_join` 是异步的，需要等待 DHT 发现 peer
- 如果群组中没有其他在线 peer，加入可能无法完成
- `onGroupSelfJoin` 回调只有在成功加入后才会触发

### 3. 重新加入历史群组（Client 重启后）

**触发时机**：
- Client 启动后，Tox 初始化完成（InitSDK）
- Tox 连接建立且在线状态设置完成后（HandleSelfConnectionStatus）

**调用路径**：
```
V2TIMManagerImpl::InitSDK()
  ↓ RejoinKnownGroups()
V2TIMManagerImpl::HandleSelfConnectionStatus()
  ↓ (检测到连接建立)
  ↓ RejoinKnownGroups()
```

**恢复流程**：

#### Group 类型恢复
1. 从存储读取所有已知群组的 `groupType`
2. 对于 `groupType == "group"` 的群组：
   - 从 `SharedPreferences` 读取 `chat_id`
   - 调用 `tox_group_join(chat_id)` 重新加入
   - 成功后会触发 `onGroupSelfJoin` 回调重建映射

#### Conference 类型恢复
1. Tox 初始化时，conferences 会从 savedata 自动恢复
2. 在 `RejoinKnownGroups()` 中：
   - 查询 `tox_conference_get_chatlist()` 获取已恢复的 conferences
   - 对于 `groupType == "conference"` 的群组：
     - 查找未映射的 `conference_number`
     - 将 `conference_number` 映射到对应的 `group_id`
     - 重建映射关系

**关键点**：
- Group 类型通过 `chat_id` 主动恢复，更可靠
- Conference 类型依赖 savedata 自动恢复，需要手动匹配
- 两种类型的 `groupType` 都会持久化存储
3. 等待 `onGroupSelfJoin` 回调重建映射关系
4. 如果群组已不存在或无法连接，回调不会触发

**关键代码位置**：
- C++: `tim2tox/source/V2TIMManagerImpl.cpp:RejoinKnownGroups()`
- C++: `tim2tox/source/V2TIMManagerImpl.cpp:HandleSelfConnectionStatus()`

### 4. 退出群组

**调用路径**：
```
UI 层 (tencent_cloud_chat_group_profile_body.dart)
  ↓ handleQuitGroup()
UIKit SDK 层 (tencent_cloud_chat_group_sdk.dart)
  ↓ quitGroup()
SDK Adapter 层 (tim_manager.dart)
  ↓ DartQuitGroup() (直接调用 C++ 层)
C++ 层 (dart_compat_group.cpp)
  ↓ V2TIMGroupManagerImpl::QuitGroup()
  ↓ ToxManager::deleteGroup()
  ↓ tox_group_leave()
  ↓ DartNotifyGroupQuit() (通知 Dart 层)
Dart 层 (NativeLibraryManager)
  ↓ groupQuitNotification 回调
  ↓ ffiService.cleanupGroupState()
```

**流程**：
1. 查找 `group_id` 到 `group_number` 的映射
   - 如果映射不存在，尝试通过 `chat_id` 恢复映射
   - 如果仍找不到，记录警告但继续清理
2. 调用 `tox_group_leave` 离开 Tox 群组
3. 清理 C++ 层状态：
   - 从 `group_id_to_group_number_` 映射中删除
   - 从 `group_members_` 中删除
   - 从 `groups_` 和 `group_info_` 中删除
   - 删除会话缓存
4. 通知 Dart 层清理状态：
   - 从 `_knownGroups` 中删除
   - 添加到 `_quitGroups`
   - 清除消息历史（内存和持久化）
   - 清除离线消息队列
5. 更新 UI：
   - 从群组列表中删除
   - 从会话列表中删除
   - 触发 `FakeGroupDeleted` 事件

**关键代码位置**：
- Dart: `tim2tox/dart/lib/service/ffi_chat_service.dart:quitGroup()`
- Dart: `tim2tox/dart/lib/service/ffi_chat_service.dart:cleanupGroupState()`
- C++: `tim2tox/source/V2TIMGroupManagerImpl.cpp:QuitGroup()`
- C++: `tim2tox/ffi/dart_compat_group.cpp:DartNotifyGroupQuit()`

## 核心功能

### 群组列表管理

**获取已加入群组列表**：
```dart
final groups = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getJoinedGroupList();
```

**实现细节**：
1. 从 `ffiService.knownGroups` 获取所有已知群组
2. 过滤掉 `_quitGroups` 中的群组
3. 为每个群组获取名称和头像（从 `SharedPreferences`）
4. 返回 `V2TimGroupInfo` 列表

**关键代码位置**：
- Dart: `tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:getJoinedGroupList()`

### 群组消息

**发送群组消息**：
```dart
final message = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createTextMessage(text: "Hello");
await TencentImSDKPlugin.v2TIMManager.getMessageManager().sendMessage(
  msgID: message.msgID,
  receiver: groupID,
  groupID: groupID,
);
```

**接收群组消息**：
- 通过 `V2TIMAdvancedMsgListener.onRecvNewMessage` 回调接收
- 消息自动持久化到本地文件系统

### 群组成员管理

**获取群组成员列表**：
```dart
final members = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getGroupMemberList(
  groupID: groupID,
  filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
);
```

**实现细节**：
- 从 Tox 获取 peer 列表
- 转换为 `V2TimGroupMemberFullInfo` 格式
- 包含成员昵称、角色、在线状态等信息

## 数据持久化

### chat_id 持久化

**为什么需要 chat_id**：
- `group_number` 在每次加入时可能变化
- `chat_id` 是群组的唯一标识符，用于可靠地重新加入群组
- c-toxcore 官方推荐使用 `chat_id` 重新加入群组

**存储位置**：
- Dart 层：`SharedPreferences`，key 为 `group_chat_id_<group_id>`
- C++ 层：内存映射 `g_group_id_to_chat_id`

**存储时机**：
1. 创建群组时：`CreateGroup()` 获取 `chat_id` 后立即存储
2. 加入群组时：`HandleGroupSelfJoin()` 获取 `chat_id` 后存储
3. 被邀请加入时：`HandleGroupInvite()` 获取 `chat_id` 后存储

**恢复时机**：
1. Client 启动时：`ffi_chat_service.init()` 从 `SharedPreferences` 读取并同步到 C++ 层
2. 重新加入群组时：使用存储的 `chat_id` 调用 `tox_group_join`

**关键代码位置**：
- Dart: `toxee/lib/util/prefs.dart:setGroupChatId()`
- C++: `tim2tox/ffi/tim2tox_ffi.cpp:tim2tox_ffi_set_group_chat_id()`
- C++: `tim2tox/source/V2TIMManagerImpl.cpp:HandleGroupSelfJoin()`

### 群组列表持久化

**存储内容**：
- `_knownGroups`: 已知群组 ID 列表
- `_quitGroups`: 已退出群组 ID 列表

**存储位置**：
- `SharedPreferences`，key 分别为 `known_groups` 和 `quit_groups`

**恢复时机**：
- Client 启动时：`ffi_chat_service.init()` 读取并恢复

### 消息历史持久化

**存储位置**：
- `<appDir>/chat_history/group_<group_id>.json`

**存储格式**：
```json
{
  "conversationId": "group_tox_1",
  "messages": [
    {
      "msgID": "...",
      "text": "...",
      "timestamp": 1234567890,
      ...
    }
  ]
}
```

**清理时机**：
- 退出群组时：`cleanupGroupState()` 删除对应的历史文件

## 映射关系管理

### 映射关系类型

1. **group_id → group_number**: 用于调用 Tox API
2. **group_number → group_id**: 用于处理 Tox 回调
3. **group_id → chat_id**: 用于重新加入群组
4. **chat_id → group_id**: 用于通过 `chat_id` 查找群组

### 映射关系建立

**正常流程**：
1. 创建/加入群组时，`onGroupSelfJoin` 回调触发
2. `HandleGroupSelfJoin()` 建立映射关系
3. 存储 `chat_id` 到持久化存储

**恢复流程（Client 重启后）**：
1. `InitSDK()` 查询 Tox 中已存在的群组，手动调用 `HandleGroupSelfJoin()`
2. `RejoinKnownGroups()` 使用存储的 `chat_id` 重新加入群组
3. `onGroupSelfJoin` 回调触发，建立映射关系
4. `GetJoinedGroupList()` 如果映射为空，尝试通过 `chat_id` 重建映射

**恢复机制**：
- `QuitGroup()` 如果找不到映射，尝试通过 `chat_id` 恢复
- `GetJoinedGroupList()` 如果映射为空，尝试从 Dart 层重建映射

### 映射关系丢失问题

**可能原因**：
1. Client 重启后，Tox 群组尚未从 savedata 恢复
2. 群组已不存在，但 `chat_id` 仍存储在本地
3. 网络问题导致 `tox_group_join` 失败

**解决方案**：
1. 等待 Tox 连接建立后再重新加入群组
2. 实现映射恢复机制（已实现）
3. 定期清理无效的 `chat_id`（待实现）

## 常见问题

### 1. 退出群组后，UI 刷新仍然显示群组

**原因**：
- 群组未从 `_knownGroups` 中删除
- 会话未从会话列表中删除
- `getJoinedGroupList()` 未过滤 `_quitGroups`

**解决方案**：
- 确保 `cleanupGroupState()` 正确执行
- 确保 `getJoinedGroupList()` 过滤 `_quitGroups`
- 确保 UI 层正确处理 `quitGroup` 事件

### 2. Client 重启后，群组映射关系丢失

**原因**：
- Tox 群组尚未从 savedata 恢复
- `onGroupSelfJoin` 回调未触发（因为群组尚未真正加入）

**解决方案**：
- 使用 `chat_id` 重新加入群组（已实现）
- 等待 Tox 连接建立后再重新加入（已实现）
- 实现映射恢复机制（已实现）

### 3. 重新加入群组失败

**原因**：
- 群组已不存在（所有成员都已退出）
- 网络问题导致 DHT 无法发现 peer
- `chat_id` 无效或已过期

**解决方案**：
- 这是 Tox 协议的正常行为
- 如果群组已不存在，`onGroupSelfJoin` 回调不会触发
- 可以考虑添加超时机制，定期清理无效的 `chat_id`

### 4. 群组消息发送失败

**原因**：
- 群组映射关系丢失
- `group_number` 无效
- Tox 连接未建立

**解决方案**：
- 确保映射关系正确建立
- 检查 Tox 连接状态
- 实现消息重试机制（待实现）

## 调试指南

### 日志关键字

**群组创建**：
- `CreateGroup: ENTRY`
- `tox_group_new`
- `Stored chat_id for group`

**群组加入**：
- `RejoinKnownGroups: Attempting to rejoin`
- `tox_group_join`
- `onGroupSelfJoin`

**群组退出**：
- `DartQuitGroup: ENTRY`
- `tox_group_leave`
- `cleanupGroupState`

**映射关系**：
- `HandleGroupSelfJoin`
- `Rebuilt mapping`
- `group not found in mappings`

### 检查映射关系

**C++ 层**：
```cpp
// 在 V2TIMManagerImpl 中添加日志
V2TIM_LOG(kInfo, "Mapping: group_id_to_group_number_ size=%zu", group_id_to_group_number_.size());
```

**Dart 层**：
```dart
print('[FfiChatService] _knownGroups: ${_knownGroups.toList()}');
print('[FfiChatService] _quitGroups: ${_quitGroups.toList()}');
```

### 检查 chat_id 存储

**Dart 层**：
```dart
final chatId = await Prefs.getGroupChatId(groupId);
print('[Prefs] chat_id for $groupId: $chatId');
```

**C++ 层**：
```cpp
char stored_chat_id[65];
bool has_stored = (tim2tox_ffi_get_group_chat_id_from_storage(group_id, stored_chat_id, sizeof(stored_chat_id)) == 1);
V2TIM_LOG(kInfo, "Stored chat_id for %s: %s", group_id, has_stored ? stored_chat_id : "not found");
```

### 常见日志模式

**正常流程**：
```
CreateGroup: ENTRY
tox_group_new: success, group_number=0
Stored chat_id for group tox_1: ...
HandleGroupSelfJoin: group_number=0, groupID=tox_1
```

**映射恢复**：
```
QuitGroup: Group not found in mappings, attempting recovery via stored chat_id
Rebuilt mapping: groupID=tox_1 <-> group_number=0
```

**重新加入**：
```
RejoinKnownGroups: Attempting to rejoin group tox_1 using chat_id ...
tox_group_join: success, group_number=0
onGroupSelfJoin: group_number=0
HandleGroupSelfJoin: Rebuilt mapping from stored chat_id
```

## 问题分析和解决方案

### 退出群组流程问题

#### 问题描述

退出群组后，UI 刷新后仍然能看到该群组。从日志分析发现以下问题：

1. **调用路径问题**：Dart 层的 `ffi_chat_service.quitGroup` 可能没有被调用
2. **群组映射问题**：群组在映射中找不到，导致无法调用 `tox_group_leave`
3. **UI 刷新问题**：`getJoinedGroupList` 从 `ffiService.knownGroups` 获取群组列表，但退出群组后，`knownGroups` 没有被正确清理

#### 解决方案

**已修复**：实现了完整的退出群组流程：

1. **C++ 层清理**：
   - 查找 `group_id` 到 `group_number` 的映射（如果找不到，尝试通过 `chat_id` 恢复）
   - 调用 `tox_group_leave` 离开 Tox 群组
   - 清理所有 C++ 层状态（映射、成员、会话缓存）
   - 通过 `DartNotifyGroupQuit()` 通知 Dart 层

2. **Dart 层清理**：
   - 从 `_knownGroups` 中删除
   - 添加到 `_quitGroups`
   - 清除消息历史（内存和持久化）
   - 清除离线消息队列

3. **映射恢复机制**：
   - 在 `QuitGroup()` 中，如果找不到映射，尝试通过存储的 `chat_id` 重建映射
   - 确保即使重启后映射丢失，也能正确退出群组

**关键代码位置**：
- C++: `tim2tox/source/V2TIMGroupManagerImpl.cpp:QuitGroup()`
- Dart: `tim2tox/dart/lib/service/ffi_chat_service.dart:cleanupGroupState()`

### 群组映射恢复问题

#### 问题描述

退出群组时，日志显示群组在映射中找不到，导致无法调用 `tox_group_leave`。

**根本原因**：
- `group_id_to_group_number_` 映射存储在 C++ 层的内存中，**不会持久化**
- Client 重启后，映射丢失
- 映射的恢复是**延迟的**，只有在调用 `GetGroupMemberList`、`InviteUserToGroup` 或收到 `HandleGroupSelfJoin` 事件时才会重建

#### 解决方案

**已实现**：多层映射恢复机制：

1. **QuitGroup 中的恢复**：
   - 如果找不到映射，尝试通过存储的 `chat_id` 重建映射
   - 参考 `GetGroupMemberList` 中的恢复逻辑

2. **GetJoinedGroupList 中的恢复**：
   - 如果映射为空，尝试从 Dart 层重建所有已知群组的映射
   - 通过存储的 `chat_id` 在 Tox 中查找对应的群组
   - 如果找到，重建映射关系

3. **启动时的主动恢复**：
   - 在 `GetJoinedGroupList` 中，如果发现映射为空，自动为所有已知群组重建映射
   - 基于存储的 `chat_id`，确保映射正确

**关键代码位置**：
- C++: `tim2tox/source/V2TIMGroupManagerImpl.cpp:QuitGroup()`
- C++: `tim2tox/source/V2TIMGroupManagerImpl.cpp:GetJoinedGroupList()`

### 群组成员功能问题

#### 问题概述

在不修改 `chat-uikit-flutter` 的情况下，群成员列表页面和添加成员功能存在以下问题：

1. **空列表显示问题**：当群成员列表为空时，页面显示空白，没有提示信息
2. **数据同步问题**：
   - 成员列表不自动更新（只监听角色更新，不监听成员添加/删除）
   - 添加成员后不更新数据层缓存
   - 数据层 `addGroupMember` 的限制（如果缓存列表为空，新成员不会被添加）
3. **用户体验问题**：
   - 缺少加载状态
   - 缺少成功反馈
   - 缺少错误处理
   - 缺少页面标题

#### 解决方案

这些问题主要与 UIKit 的实现有关，toxee 作为示例应用，可以通过以下方式改进：

1. **自定义群成员列表页面**：实现完整的成员列表显示和添加功能
2. **数据同步**：确保添加/删除成员后正确更新数据层和 UI
3. **用户体验**：添加加载状态、成功反馈和错误处理

**注意**：这些问题不影响核心群聊功能，主要是 UI 体验问题。

## 相关文档

- [toxee 架构](../architecture/ARCHITECTURE.md) - 整体架构和恢复机制
- [实现细节](../architecture/MAINTAINER_ARCHITECTURE.md) - 详细实现说明
