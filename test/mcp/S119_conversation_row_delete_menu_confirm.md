# S119 — Conversation row: Delete via context-menu item + confirm dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=any friends=1 history=present(c2c with F)`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L1 WidgetTester — `chat_core_real_ui_test.dart:368` proves the conversation menu opens on right-click; the delete item + keyed confirm dialog (`confirm_dialog_primary_button` exists in the fork; toxee's own confirm key is `delete_conversation_confirm_button`) is the L1-promotable surface. The actual disk-delete needs the data layer (`integration_test`).
**Status**: covered at the widget layer (L1) — the delete-confirm dialog surface (keyed confirm button, conversation label in body, confirm dismisses dialog) is gated by `test/ui/conversation/conversation_row_menu_c2c_real_ui_test.dart` (tests "S119 C2C delete-confirm dialog mounts with keyed confirm button" and "S119 C2C delete-confirm dialog confirm button dismisses the dialog"). HONEST: the C2C row persists after delete (friend-driven list) — only history is cleared. "Row GONE" is not assertable at L1 for C2C.
**Covered-by**: `test/ui/conversation/conversation_row_menu_c2c_real_ui_test.dart`

> Real menu-item + confirm-dialog surface for the delete action. The non-gateable-removal reality is stated plainly: deleting a C2C conversation for a still-friend only wipes its history; the row reappears because the sidebar is friend-driven. The discriminator from S112 (delete the FRIEND) is that friendship stays intact here.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — active account `echo_seeded_test` (auto-login on), 1 friend F (echo peer, Offline), seeded C2C conversation `c2c_3116CBE0…7244` with ≥1 message in each direction (so `messages[]` is non-empty pre-delete, making the clear-history assertion non-vacuous). Restore wipes existing state; cache miss auto-regenerates.
- **Optionally pin first** (`l3_set_pinned true`) so A4's unpin-on-delete is observable; the default seed is unpinned.
- `Prefs.local_friends_<toxA_prefix16>` contains `<toxF>` (friendship — the discriminator from S112). `friend_nickname_<toxF>` set to a unique label.
- Account A logged in, plaintext, sidebar Online (poll ≤60s); context-menu handler registered (no `[HomePage] Failed to register conversation context-menu handlers`, home_page.dart:376).
- F's row present as `UiKeys.conversationListTile("c2c_3116CBE0…7244")` (`conversation_list_item:c2c_3116CBE0…7244`, fork tencent_cloud_chat_conversation_list.dart:118).

## Executable Driver

No data-half runner gate — per `doc/architecture/MCP_UI_TEST_PLAYBOOK.md` §5c, S119 row, S20/S119 delete is "not distinctly gateable": the observable equals `clear_history`, and the conversation never leaves the friend-driven list. The clear-history half is exercised by existing history gates; the menu + confirm-dialog SURFACE is proven at L1 by `chat_core_real_ui_test.dart:252` (message-menu delete → `confirm_dialog_primary_button`) and `:368` (conversation menu opens). The marionette flow below IS the conversation-row test at L3.

## UI Driver
1. `marionette.tap(UiKeys.sidebarChats)` (`sidebar_chats_tab`); baseline `official.get_runtime_errors({})`. Confirm `l3_dump_state` for the peer: `messages[]` non-empty, and (if pinned in precondition) `isPinned: true`; capture `conversationIds[]` (contains `c2c_3116CBE0…7244`).
2. Open the row's menu on `UiKeys.conversationListTile("c2c_3116CBE0…7244")`:
   - **DESKTOP**: right-click → `onSecondaryTapConversationItem` → `_showConversationContextMenu` (home_page.dart:328-336, :1582).
   - **MOBILE/marionette**: `marionette.long_press(...)` (`ext.flutter.marionette.longPress`) → `onLongPressConversationItem` → same handler (home_page.dart:337-345).
3. Tap `UiKeys.conversationContextMenuDeleteItem` (`conversation_context_menu_delete_item`, home_page.dart:159, value `'delete'`). This opens the confirm dialog via `buildDeleteConversationDialog` (home_page.dart:1638, title `deleteConversationTitle`).
4. Snapshot → confirm the dialog is present (title `deleteConversationTitle`; primary action keyed). Tap `UiKeys.deleteConversationConfirmButton` (`delete_conversation_confirm_button`, home_page.dart:188) → pops `true` → `deleteConversation(convId)` (home_page.dart:1648-1650 → `FakeConversationManager.deleteConversation`, fake_managers.dart:410).
5. Poll `l3_dump_state` ≤2s and re-read the peer's `messages[]`, `isPinned`, and `conversationIds[]`.

## Assertions
- A1 (non-vacuous baseline): Step 1 — the peer's `messages[]` is non-empty; if pinned in precondition, `conversations[].isPinned == true`; `conversationIds[]` contains `c2c_3116CBE0…7244`.
- A2 (confirm dialog appears, keyed — the SURFACE gate): after Step 3 the snapshot contains the `delete_conversation_confirm_button` keyed button (and the dialog title `deleteConversationTitle`). This is the headline surface assertion.
- A3 (confirm → clear-history): after Step 4 the peer's `messages[]` is EMPTY — `clearC2CHistory(normalizedId)` ran (fake_managers.dart:443). This equals S20/clear_history; it is NOT a distinct "removed" observable.
- A4 (confirm → unpin): if pinned in precondition, the peer's `conversations[].isPinned == false` and `pinnedConversations` no longer contains `3116CBE0974181B6` (`_pinned.remove` + `Prefs.setPinned`, fake_managers.dart:450-451).
- A5 (**row PERSISTS — the non-gateable-removal reality**): after Step 4, `l3_dump_state.conversationIds[]` STILL contains `c2c_3116CBE0…7244` — the friend-driven list re-emits the entry (`refreshConversations`, fake_managers.dart:457; `doc/architecture/MCP_UI_TEST_PLAYBOOK.md` §5c, S119 row). There is no "conversation removed" observable; do NOT assert the row disappears.
- A6 (friendship intact — discriminator vs S112): `Prefs.local_friends_<toxA_prefix16>` still contains `<toxF>`; `[FfiChatService] deleteFriend` MUST NOT appear (that would be S112-style friend removal).
- Log markers in order: `[FakeConversationManager] deleteConversation: START - conversationID=c2c_3116CBE0…7244` → `[FakeConversationManager] deleteConversation: DONE` (fake_managers.dart:411/459). `[HomePage] deleteConversation failed for <convId>` (home_page.dart:1653) MUST NOT appear.
- A7: `official.get_runtime_errors({})` matches the Step-1 baseline.

## Notes
- L3-pin + non-gateable-removal reason: the conversation list is friend-driven (`fake_managers.dart` emits every friend regardless of history; `doc/architecture/MCP_UI_TEST_PLAYBOOK.md` §5c, S119 row), so C2C delete only clears history + unpins — the row reappears. No distinct data gate is possible; assert the confirm SURFACE + clear-history + unpin + row-persists instead.
- Keys verified: `conversationContextMenuDeleteItem` @ home_page.dart:159, `deleteConversationConfirmButton` @ home_page.dart:188 (defined ui_keys.dart:182-189). Menu built by `buildConversationContextMenuItems` (home_page.dart:117); dialog by `buildDeleteConversationDialog` (home_page.dart:173) shown at home_page.dart:1636. The fork's own confirm key is `confirm_dialog_primary_button` (REAL_UI_GATES, used by the message-delete L1 gate); toxee's conversation-delete dialog uses its own `delete_conversation_confirm_button`.
- Sibling distinction: S20 (older) covers the same toxee menu+confirm flow and historically asserted row-absence; the authoritative coverage map (line 292) supersedes that — the C2C row persists. S112 = delete the FRIEND (`deleteFriend`, removes from contacts); S119 = delete the conversation only (history cleared, friend intact). A6 is the discriminator.
- The `deleteConversationBody` copy lies ("Message history stays on disk") while the implementation deletes it — do NOT assert on the dialog body text (tracked separately; see S20 notes).
- Desktop right-click vs mobile long-press: both route to the SAME `_showConversationContextMenu` (home_page.dart:334/343), and `deleteConversation` is shared Dart (`fake_managers.dart`) — so this covers mobile via the shared handler + manager. The desktop popup is a Flutter `showMenu` route; the L1 WidgetTester promotion relies on the global tearDown resetting the fork's static desktop popup state (REAL_UI_GATES #4).
