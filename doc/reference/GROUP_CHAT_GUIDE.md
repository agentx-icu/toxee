[简体中文](./GROUP_CHAT_GUIDE.zh-CN.md)

# toxee Group Chat Guide


This document details the implementation, usage and key processes of the group chat function in toxee.

## Contents

1. [Overview](#overview)
2. [Group chat lifecycle](#group-chat-lifecycle)
3. [Core Function](#core-functions)
4. [Data persistence](#data-persistence)
5. [Mapping relationship management](#mapping-relationship-management)
6. [FAQ](#faq)
7. [Debugging Guide](#debugging-guide)

## Overview

toxee uses Tim2Tox to implement the P2P group chat function based on the Tox protocol. The group chat function is completely decentralized and does not rely on any central server.

### Key concepts

- **group_id**: Application layer group identifier, in the format of `tox_<number>` (such as `tox_1`, `tox_2`)
- **group_number**: The group number of the Tox protocol layer, assigned by Tox
- **chat_id**: Tox group's unique identifier (32 bytes), used to rejoin the group (only supported by Group type)
- **Mapping relationship**: Mapping between `group_id` ↔ `group_number` ↔ `chat_id`
- **groupType**: Group type, which can be `"group"` (new API) or `"conference"` (old API)

### Group vs Conference

toxee supports two Tox group chat types at the same time:

#### Group (new API)
- **Creation method**: Create using `tox_group_new`
- **Invitation method**: Use `tox_group_invite_friend` to invite
- **Joining Method**: Use `tox_group_join` to join via `chat_id`
- **Persistence**: Supports `chat_id` persistence and can be rejoined through `chat_id`
- **Recovery mechanism**: After the Client restarts, call `tox_group_join` to recover via `chat_id`
- **Function**: Supports complete functions such as group announcement (topic), group nickname (peer name), member management, etc.

#### Conference (old API)
- **Creation method**: Created using `tox_conference_new`
- **Invitation method**: Use `tox_conference_invite` to invite (need to be a friend)
- **Joining Method**: Use `tox_conference_join` to join via `cookie`
- **Persistence**: Does not support `chat_id`, relies on Tox savedata for automatic recovery
- **Recovery mechanism**: The Client automatically recovers from savedata after restarting, and needs to manually match `conference_number` to `group_id`
- **Function**: The function is relatively simple and does not support advanced functions such as group announcements.

**Selection Suggestions**:
- It is recommended to use the **Group** type for new groups, which has more complete functions and more reliable recovery.
- Only use the **Conference** type when compatible with clients using the old API

## Group chat lifecycle

### 1. Create a group

**Call path**:
```
UI layer (add_group_dialog.dart)
  ↓ createGroup(groupType: "group" | "conference")
Service layer (ffi_chat_service.dart)
  ↓ createGroup(name, groupType)
FFI layer (tim2tox_ffi.cpp)
  ↓ tim2tox_ffi_create_group()
C++ layer (V2TIMGroupManagerImpl.cpp)
  ↓ V2TIMGroupManagerImpl::CreateGroup()
  ↓ tox_group_new() or tox_conference_new()
```

**Process**:
1. The user selects the group type (Group or Conference) in the UI
2. Generate unique `group_id` (if not provided)
3. Call the corresponding API according to `groupType`:
   - **Group**: Created by calling `tox_group_new`
   - **Conference**: Created by calling `tox_conference_new`
4. Get `group_number` (or `conference_number`)
5. **Group type only**: Get `chat_id` and persist it
6. Persist `groupType` to storage
7. Create `group_id` → `group_number` mapping
8. Add `group_id` to `_knownGroups`
9. Trigger the `onGroupCreated` callback and update the UI

**Key code location**:
- Dart: `tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:createGroup()`
- C++: `tim2tox/source/V2TIMManagerImpl.cpp:CreateGroup()`
- C++: `tim2tox/source/ToxManager.cpp:createGroup()`

### 2. Join the group

**Call path**:
```
UI layer
  ↓ joinGroup()
Service layer (ffi_chat_service.dart)
  ↓ joinGroup()
C++ layer
  ↓ V2TIMGroupManagerImpl::JoinGroup()
  ↓ ToxManager::joinGroup()
  ↓ tox_group_join()
```

**Process**:
1. Use `chat_id` to call `tox_group_join`
2. Tox processes join requests asynchronously (requires DHT to discover peers)
3. Trigger `onGroupSelfJoin` callback after successful joining
4. Establish mapping relationship
5. Persistence `chat_id`
6. Update `_knownGroups`

**Note**:
- `tox_group_join` is asynchronous and needs to wait for DHT to discover the peer
- If there are no other online peers in the group, joining may not be completed
- `onGroupSelfJoin` callback will only be triggered after successful joining

### 3. Rejoin the historical group (after restarting the Client)

**Trigger time**:
- After the Client is started, Tox initialization is completed (InitSDK)
- After the Tox connection is established and the online status is set (HandleSelfConnectionStatus)

**Call path**:
```
V2TIMManagerImpl::InitSDK()
  ↓ RejoinKnownGroups()
V2TIMManagerImpl::HandleSelfConnectionStatus()
  ↓ (Connection established detected)
  ↓ RejoinKnownGroups()
```

**Recovery Process**:

#### Group type recovery
1. Read `groupType` of all known groups from storage
2. For `groupType == "group"`’s group:
   - Read `chat_id` from `SharedPreferences`
   - Call `tox_group_join(chat_id)` to rejoin
   - After success, the `onGroupSelfJoin` callback will be triggered to rebuild the mapping.

#### Conference type recovery
1. When Tox is initialized, conferences will be automatically restored from savedata.
2. In `RejoinKnownGroups()`:
   - Query `tox_conference_get_chatlist()` to obtain restored conferences
   - For `groupType == "conference"`'s group:
     - Find unmapped `conference_number`
     - Map `conference_number` to the corresponding `group_id`
     - Rebuild mapping relationship

**Key Points**:
- Group type is automatically restored through `chat_id`, which is more reliable
- Conference type relies on savedata for automatic recovery and needs to be manually matched
- Both types of `groupType` will be stored persistently
3. Wait for the `onGroupSelfJoin` callback to rebuild the mapping relationship
4. If the group no longer exists or cannot be connected, the callback will not be triggered.

**Key code location**:
- C++: `tim2tox/source/V2TIMManagerImpl.cpp:RejoinKnownGroups()`
- C++: `tim2tox/source/V2TIMManagerImpl.cpp:HandleSelfConnectionStatus()`

### 4. Exit the group

**Call path**:
```
UI layer (tencent_cloud_chat_group_profile_body.dart)
  ↓ handleQuitGroup()
UIKit SDK layer (tencent_cloud_chat_group_sdk.dart)
  ↓ quitGroup()
SDK Adapter layer (tim_manager.dart)
  ↓ DartQuitGroup() (directly calling the C++ layer)
C++ layer (dart_compat_group.cpp)
  ↓ V2TIMGroupManagerImpl::QuitGroup()
  ↓ ToxManager::deleteGroup()
  ↓ tox_group_leave()
  ↓ DartNotifyGroupQuit() (notify Dart layer)
Dart layer (NativeLibraryManager)
  ↓ groupQuitNotification callback
  ↓ ffiService.cleanupGroupState()
```**Process**:
1. Find the mapping from `group_id` to `group_number`
   - If the mapping does not exist, try to restore the mapping via `chat_id`
   - If still not found, log a warning but continue cleaning
2. Call `tox_group_leave` to leave the Tox group
3. Clean up the C++ layer state:
   - Removed from `group_id_to_group_number_` mapping
   - Removed from `group_members_`
   - Removed from `groups_` and `group_info_`
   - Delete session cache
4. Notify the Dart layer of cleanup status:
   - Removed from `_knownGroups`
   - Added to `_quitGroups`
   - Clear message history (memory and persistence)
   - Clear offline message queue
5. Update UI:
   - Remove from group list
   - Remove from conversation list
   - Trigger `FakeGroupDeleted` event

**Key code location**:
- Dart: `tim2tox/dart/lib/service/ffi_chat_service.dart:quitGroup()`
- Dart: `tim2tox/dart/lib/service/ffi_chat_service.dart:cleanupGroupState()`
- C++: `tim2tox/source/V2TIMGroupManagerImpl.cpp:QuitGroup()`
- C++: `tim2tox/ffi/dart_compat_group.cpp:DartNotifyGroupQuit()`

## Core functions

### Group list management

**Get the list of joined groups**:
```dart
final groups = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getJoinedGroupList();
```
**Implementation details**:
1. Get all known groups from `ffiService.knownGroups`
2. Filter out groups in `_quitGroups`
3. Get the name and avatar for each group (from `SharedPreferences`)
4. Return the `V2TimGroupInfo` list

**Key code location**:
- Dart: `tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart:getJoinedGroupList()`

### Group message

**Send Group Message**:
```dart
final message = await TencentImSDKPlugin.v2TIMManager.getMessageManager().createTextMessage(text: "Hello");
await TencentImSDKPlugin.v2TIMManager.getMessageManager().sendMessage(
  msgID: message.msgID,
  receiver: groupID,
  groupID: groupID,
);
```
**Receive group messages**:
- Received through `V2TIMAdvancedMsgListener.onRecvNewMessage` callback
- Messages are automatically persisted to the local file system

### Group member management

**Get group member list**:
```dart
final members = await TencentImSDKPlugin.v2TIMManager.getGroupManager().getGroupMemberList(
  groupID: groupID,
  filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
);
```
**Implementation details**:
- Get peer list from Tox
- Convert to `V2TimGroupMemberFullInfo` format
- Contains member nicknames, roles, online status and other information

## Data persistence

### chat_id persistence

**Why chat_id is needed**:
- `group_number` may change on each join
- `chat_id` is the unique identifier of the group and is used to reliably rejoin the group
- c-toxcore officially recommends using `chat_id` to rejoin the group

**Storage location**:
- Dart layer: `SharedPreferences`, key is `group_chat_id_<group_id>`
- C++ layer: memory mapping `g_group_id_to_chat_id`

**Storage Timing**:
1. When creating a group: `CreateGroup()` obtains `chat_id` and stores it immediately
2. When joining a group: `HandleGroupSelfJoin()` obtains `chat_id` and then stores it
3. When invited to join: `HandleGroupInvite()` obtains `chat_id` and then stores it

**Recovery time**:
1. When Client starts: `ffi_chat_service.init()` reads from `SharedPreferences` and synchronizes to the C++ layer
2. When rejoining the group: call `tox_group_join` using the stored `chat_id`

**Key code location**:
- Dart: `toxee/lib/util/prefs.dart:setGroupChatId()`
- C++: `tim2tox/ffi/tim2tox_ffi.cpp:tim2tox_ffi_set_group_chat_id()`
- C++: `tim2tox/source/V2TIMManagerImpl.cpp:HandleGroupSelfJoin()`

### Group list persistence

**Storage content**:
- `_knownGroups`: list of known group IDs
- `_quitGroups`: Exited group ID list

**Storage location**:
- `SharedPreferences`, keys are `known_groups` and `quit_groups` respectively

**Recovery time**:
- When Client starts: `ffi_chat_service.init()` read and restore

### Message history persistence

**Storage location**:
- `<appDir>/chat_history/group_<group_id>.json`

**Storage format**:
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
**Cleaning time**:
- When exiting the group: `cleanupGroupState()` deletes the corresponding history file

## Mapping relationship management

### Mapping relationship type

1. **group_id → group_number**: used to call Tox API
2. **group_number → group_id**: used to handle Tox callbacks
3. **group_id → chat_id**: used to rejoin the group
4. **chat_id → group_id**: used to find groups by `chat_id`

### Establish mapping relationship

**Normal process**:
1. When creating/joining a group, the `onGroupSelfJoin` callback is triggered
2. `HandleGroupSelfJoin()` establishes mapping relationship
3. Store `chat_id` to persistent storage

**Recovery process (after Client restart)**:
1. `InitSDK()` Query the existing groups in Tox and manually call `HandleGroupSelfJoin()`
2. `RejoinKnownGroups()` uses the stored `chat_id` to rejoin the group
3. The `onGroupSelfJoin` callback is triggered and the mapping relationship is established.
4. `GetJoinedGroupList()` If the mapping is empty, try to rebuild the mapping through `chat_id`

**Recovery Mechanism**:
- `QuitGroup()` If mapping cannot be found, try to restore via `chat_id`
- `GetJoinedGroupList()` If the mapping is empty, try to rebuild the mapping from the Dart layer

### Mapping relationship loss problem

**Possible reasons**:
1. After the Client restarts, the Tox group has not been restored from savedata.
2. The group no longer exists, but `chat_id` is still stored locally
3. Network problems cause `tox_group_join` to fail

**Solution**:
1. Wait for the Tox connection to be established before rejoining the group
2. Implement mapping recovery mechanism (implemented)
3. Regularly clean up invalid `chat_id` (to be implemented)

## FAQ

### 1. After exiting the group, the UI refresh still displays the group

**Reason**:
- Group not deleted from `_knownGroups`
- The session was not removed from the session list
- `getJoinedGroupList()` unfiltered `_quitGroups`

**Solution**:
- Ensure `cleanupGroupState()` is executed correctly
- Make sure `getJoinedGroupList()` filters for `_quitGroups`
- Ensure UI layer handles `quitGroup` event correctly

### 2. After the Client is restarted, the group mapping relationship is lost.

**Reason**:
- Tox group has not been restored from savedata
- `onGroupSelfJoin` callback is not triggered (because the group has not actually been joined yet)

**Solution**:
- Rejoin group using `chat_id` (implemented)
- Wait for Tox connection to be established before rejoining (implemented)
- Implement mapping recovery mechanism (implemented)

### 3. Failed to rejoin the group

**Reason**:
- The group no longer exists (all members have left)
- Network problems prevent DHT from discovering peers
- `chat_id` is invalid or expired

**Solution**:
- This is normal behavior of the Tox protocol
- If the group no longer exists, the `onGroupSelfJoin` callback will not trigger
- You can consider adding a timeout mechanism to regularly clean up invalid `chat_id`

### 4. Failed to send group message

**Reason**:
- Group mapping relationship is lost
- `group_number` is invalid
- Tox connection not established

**Solution**:
- Ensure that the mapping relationship is established correctly
- Check Tox connection status
- Implement message retry mechanism (to be implemented)

## Debugging Guide

### Log keywords

**Group Creation**:
- `CreateGroup: ENTRY`
- `tox_group_new`
- `Stored chat_id for group`

**Group Join**:
- `RejoinKnownGroups: Attempting to rejoin`
- `tox_group_join`
- `onGroupSelfJoin`

**Group Exit**:
- `DartQuitGroup: ENTRY`
- `tox_group_leave`
- `cleanupGroupState`

**Mapping relationship**:
- `HandleGroupSelfJoin`
- `Rebuilt mapping`
- `group not found in mappings`

### Check mapping relationship

**C++ layer**:
```cpp
// Add logs in V2TIMManagerImpl
V2TIM_LOG(kInfo, "Mapping: group_id_to_group_number_ size=%zu", group_id_to_group_number_.size());
```
**Dart layer**:
```dart
print('[FfiChatService] _knownGroups: ${_knownGroups.toList()}');
print('[FfiChatService] _quitGroups: ${_quitGroups.toList()}');
```
### Check chat_id storage

**Dart layer**:
```dart
final chatId = await Prefs.getGroupChatId(groupId);
print('[Prefs] chat_id for $groupId: $chatId');
```
**C++ layer**:
```cpp
char stored_chat_id[65];
bool has_stored = (tim2tox_ffi_get_group_chat_id_from_storage(group_id, stored_chat_id, sizeof(stored_chat_id)) == 1);
V2TIM_LOG(kInfo, "Stored chat_id for %s: %s", group_id, has_stored ? stored_chat_id : "not found");
```
### Common log modes

**Normal process**:
```
CreateGroup: ENTRY
tox_group_new: success, group_number=0
Stored chat_id for group tox_1: ...
HandleGroupSelfJoin: group_number=0, groupID=tox_1
```
**Map Recovery**:
```
QuitGroup: Group not found in mappings, attempting recovery via stored chat_id
Rebuilt mapping: groupID=tox_1 <-> group_number=0
```
**Rejoin**:
```
RejoinKnownGroups: Attempting to rejoin group tox_1 using chat_id ...
tox_group_join: success, group_number=0
onGroupSelfJoin: group_number=0
HandleGroupSelfJoin: Rebuilt mapping from stored chat_id
```
```

## Problem analysis and solutions

### Exit group process problem

#### Problem description

After exiting the group, the group can still be seen after the UI is refreshed. The following issues were found from log analysis:

1. **Calling path problem**: `ffi_chat_service.quitGroup` in Dart layer may not be called
2. **Group mapping problem**: The group cannot be found in the mapping, resulting in the inability to call `tox_group_leave`
3. **UI refresh problem**: `getJoinedGroupList` gets the group list from `ffiService.knownGroups`, but after exiting the group, `knownGroups` is not cleaned up correctly

#### Solution

**Fixed**: Complete group exit process implemented:

1. **C++ layer cleaning**:
   - Find the mapping from `group_id` to `group_number` (if not found, try to restore via `chat_id`)
   - Call `tox_group_leave` to leave the Tox group
   - Clean all C++ layer state (maps, members, session cache)
   - Notify Dart layer via `DartNotifyGroupQuit()`

2. **Dart layer cleaning**:
   - Removed from `_knownGroups`
   - Add to `_quitGroups`
   - Clear message history (memory and persistence)
   - Clear offline message queue

3. **Mapping recovery mechanism**:
   - In `QuitGroup()`, if the mapping is not found, try to rebuild the mapping from the stored `chat_id`
   - Ensure correct group exit even if mapping is lost after reboot

**Key code location**:
- C++: `tim2tox/source/V2TIMGroupManagerImpl.cpp:QuitGroup()`
- Dart: `tim2tox/dart/lib/service/ffi_chat_service.dart:cleanupGroupState()`

### Group mapping recovery problem

#### Problem description

When exiting the group, the log shows that the group is not found in the mapping, preventing `tox_group_leave` from being called.

**Root Cause**:
- `group_id_to_group_number_` mappings are stored in the memory of the C++ layer and are **not persisted**
- After the Client restarts, the mapping is lost
- Restoration of the map is **delayed** and will only be rebuilt when `GetGroupMemberList`, `InviteUserToGroup` is called, or a `HandleGroupSelfJoin` event is received

#### Solution

**Implemented**: Multi-layer mapping recovery mechanism:

1. **Recovery in QuitGroup**:
   - If the mapping is not found, try to rebuild it from the stored `chat_id`
   - Refer to the recovery logic in `GetGroupMemberList`

2. **Recovery in GetJoinedGroupList**:
   - If the mapping is empty, try to rebuild the mapping for all known groups from the Dart layer
   - Find the corresponding group in Tox through the stored `chat_id`
   - If found, reconstruct the mapping relationship

3. **Active recovery at startup**:
   - In `GetJoinedGroupList`, automatically rebuild mappings for all known groups if mappings are found to be empty
   - Based on stored `chat_id`, ensure correct mapping

**Key code location**:
- C++: `tim2tox/source/V2TIMGroupManagerImpl.cpp:QuitGroup()`
- C++: `tim2tox/source/V2TIMGroupManagerImpl.cpp:GetJoinedGroupList()`

### Group membership function issues

#### Problem Overview

Without modifying `chat-uikit-flutter`, the group member list page and the add member function have the following problems:

1. **Empty list display problem**: When the group member list is empty, the page displays blank and there is no prompt message.
2. **Data synchronization problem**:
   - The member list is not automatically updated (only listens for role updates, not member addition/deletion)
   - Data layer cache is not updated after adding members
   - Limitation of data layer `addGroupMember` (if the cache list is empty, new members will not be added)
3. **User experience issues**:
   - Missing loading status
   - Lack of success feedback
   - Missing error handling
   - Missing page title

#### Solution

These problems are mainly related to the implementation of UIKit. As a sample application, toxee can be improved in the following ways:

1. **Customized group member list page**: implements complete member list display and addition functions
2. **Data Synchronization**: Ensure that the data layer and UI are updated correctly after adding/removing members
3. **User Experience**: Add loading status, success feedback and error handling

**Note**: These issues do not affect the core group chat functionality, they are mainly UI experience issues.

## Related documents

- [toxee Architecture](../architecture/ARCHITECTURE.md) - Overall architecture and recovery mechanism
- [Implementation details](../architecture/MAINTAINER_ARCHITECTURE.md) - Detailed implementation instructions
