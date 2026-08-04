[简体中文](./UIKIT_PRIVATE_API.zh-CN.md)

# UIKit private-API surface

toxee depends on a number of undocumented members of the vendored
Tencent Cloud Chat UIKit (`third_party/chat-uikit-flutter/`). Every
write — and every co-located read — goes through
`lib/sdk_fake/uikit_data_facade.dart::UikitDataFacade`, so this file
plus the facade are the audit checklist for every chat-uikit-flutter
rebase.

If any member listed below changes signature, disappears, or changes
semantics, fix the facade first and re-run the migrations described in
the audit. Call sites should never need to be updated for a UIKit
upgrade unless behavior intentionally changes.

See also: `CLAUDE.md` > "Hybrid architecture" for why toxee writes
into `TencentCloudChat.instance.dataInstance.*` at all.

## Submodules touched

`TencentCloudChat.instance.dataInstance` exposes six submodules. toxee
touches five today (search is only cleared in `clearAll`; no direct
writes).

### `contact` — `tencent_cloud_chat_common/lib/data/contact/tencent_cloud_chat_contact_data.dart`

| UIKit member | Facade wrapper | Notes |
|---|---|---|
| `buildFriendList(List<V2TimFriendInfo>, String)` | `buildFriendList` | merges by `userID`, fires `contactList` listener |
| `deleteFromFriendList(List<String>, String)` | `deleteFromFriendList` | removes by userID, fires listener |
| `buildGroupList(List<V2TimGroupInfo>, String)` | `buildGroupList` | clears then re-adds; total replace |
| `addGroupInfoToJoinedGroupList(V2TimGroupInfo)` | `addGroupInfoToJoinedGroupList` | upsert by `groupID` |
| `deleteGroupInfoFromJoinedGroupList(String)` | `deleteGroupInfoFromJoinedGroupList` | remove by `groupID` |
| `getGroupInfo(String) → V2TimGroupInfo` | `getGroupInfo` | returns empty `V2TimGroupInfo(groupID: '', ...)` if not found |
| `buildApplicationList(List<V2TimFriendApplication>, String)` | `buildApplicationList` | |
| `setApplicationUnreadCount(List<V2TimFriendApplication>?)` | `setApplicationUnreadCount` | |
| `buildUserStatusList(List<V2TimUserStatus>, String)` | `buildUserStatusList` | |
| `contactEventHandlers` (setter) | `contactEventHandlers=` | accepts `TencentCloudChatContactEventHandlers` |
| `contactList` (getter) | `contactList` | |
| `groupList` (getter) | `groupList` | |
| `applicationUnreadCount` (getter) | `applicationUnreadCount` | |

### `conversation` — `.../data/conversation/tencent_cloud_chat_conversation_data.dart`

| UIKit member | Facade wrapper | Notes |
|---|---|---|
| `buildConversationList(List<V2TimConversation>, String)` | `buildConversationList` | upsert by `conversationID` |
| `removeConversation(List<String>)` | `removeConversation` | by `conversationID` |
| `setTotalUnreadCount(int)` | `setTotalUnreadCount` | |
| `currentConversation` (getter/setter) | `currentConversation` | |
| `currentTargetMessage` (setter) | `currentTargetMessage=` | |
| `conversationConfig.setConfigs(forceDesktopLayout: ...)` | `setConversationConfig` | nested config API |
| `notifyListener(TencentCloudChatConversationDataKeys.currentConversation)` | `notifyCurrentConversation` | forces message component rebuild after plugin registration |
| `conversationList` (getter) | `conversationList` | |
| `totalUnreadCount` (getter) | `totalUnreadCount` | |

### `messageData` — `.../data/message/tencent_cloud_chat_message_data.dart`

| UIKit member | Facade wrapper | Notes |
|---|---|---|
| `onReceiveNewMessage(V2TimMessage)` | `onReceiveNewMessage` | required for conversation list to pick up new last-message |
| `messageNeedUpdate` (setter) | `setMessageNeedUpdate` | triggers per-message UI refresh |
| `notifyListener(TencentCloudChatMessageDataKeys.messageNeedUpdate, {userID, groupID})` | `notifyMessageNeedUpdate` | override has extra named params |
| `clearMessageList({String? userID, String? groupID})` | `clearMessageList` | clears in-memory list for one conv |
| `getMessageList({required String key}) → List<V2TimMessage>` | `getMessageList` | key is userID or groupID |

### `groupProfile` — `.../data/group_profile/tencent_cloud_chat_group_profile_data.dart`

| UIKit member | Facade wrapper | Notes |
|---|---|---|
| `loadGroupMemberList({groupID, loadGroupAdminAndOwnerOnly, nextSeq})` | `loadGroupMemberList` | hits SDK, fires `membersChange` |
| `getGroupMemberList(String?)` | `getGroupMemberList` | reads cached members only |
| `updateGroupID` (field) | `updateGroupID` get/set | bare field, not property |
| `updateGroupInfo` (field) | `updateGroupInfo` get/set | bare field, not property — defaults to empty `V2TimGroupInfo(groupID: '', groupType: '')` |

### `basic` — `.../data/basic/tencent_cloud_chat_basic_data.dart`

| UIKit member | Facade wrapper | Notes |
|---|---|---|
| `useCallKit` (setter) | `setUseCallKit` | toggles TUICallKit |
| `updateLoginStatus({required bool status}) → bool` | `updateLoginStatus` | also fires `hasLoggedIn` listener |
| `updateInitializedStatus({required bool status}) → bool` | `updateInitializedStatus` | also fires `hasInitialized` listener |
| `updateCurrentUserInfo({required V2TimUserFullInfo userFullInfo})` | `updateCurrentUserInfo` | fires `selfInfo` listener |
| `addUsedComponent(({componentEnum, widgetBuilder}))` | `addUsedComponent` | populates `usedComponents` + `componentsMap`; record-typed param is unusual |
| `notifyListener(TencentCloudChatBasicDataKeys.addUsedComponent)` | `notifyAddUsedComponent` | toxee fires this manually after batched `addUsedComponent` calls |
| `addPlugin(TencentCloudChatPluginItem)` | `addPlugin` | |
| `getPlugin(String) → TencentCloudChatPluginItem?` | `getPlugin` | |
| `hasPlugins(String)` (return type inferred as `dynamic`) | `hasPlugin` | facade casts to `bool` |
| `plugins` (field, `List<TencentCloudChatPluginItem>`) | `plugins` getter | bare field |
| `usedComponents` (getter) | `usedComponents` | used by search to detect message-component presence |
| `currentUser` (getter, `V2TimUserFullInfo?`) | `currentUser` | source of truth for `selfId` in message mapping |

### `search` — `.../data/search/tencent_cloud_chat_search_data.dart`

No direct writes from toxee today. The submodule's `clear()` is called
from `clearAll(...)` for the per-account reset.

## Cross-submodule helpers

`UikitDataFacade.clearAll(reason: String)` is the only multi-step
operation. It mirrors the per-account reset previously inlined at
`FakeUIKit.dispose()`:

1. `data.contact.clear()`
2. `data.conversation.clear()`
3. `data.messageData.clear()`
4. `data.groupProfile.clear()`
5. `data.basic.clear()`
6. `data.search.clear()`
7. `data.contact.buildGroupList([], reason)` (notify — `clear()` does not)
8. `data.conversation.buildConversationList([], reason)` (notify — `clear()` does not)

If `clear()` ever starts notifying, the trailing `buildXxxList([], ...)`
calls become dead weight; remove them.

## Why this exists

`TencentCloudChat.instance.dataInstance.*` is private UIKit state with
no API contract. toxee treats it as a write target because UIKit's
public components (conversation list, contact list, message list)
*read* this state to render. A clean Tox→Tim2Tox→UIKit pipeline still
needs to push state into the UIKit data layer, but routing every write
through one facade gives us:

- **One audit point on rebase**: grep `lib/sdk_fake/uikit_data_facade.dart`
  for `UIKit internal:` and walk each line against the upstream file.
- **One file's worth of breakage when UIKit changes**: call sites stay
  pure; only the facade needs to be patched.
- **One place to document quirks** like `hasPlugins` returning
  `dynamic`, `notifyListener` having extra `userID/groupID` named
  params only on `messageData`, or `updateGroupID/updateGroupInfo`
  being bare fields rather than setters.
