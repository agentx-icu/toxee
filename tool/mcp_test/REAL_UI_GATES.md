# Real-UI chat-core coverage — status

Covers the REAL chat UI (compose/send, context menu, panels), not the `l3_*`
debug bypass. After finding marionette structurally can't drive the desktop chat
core, the strategy is: stable automation keys on the fork + `flutter_test`
WidgetTester gates (which CAN inject Enter + right-click and run in CI).

## What landed (codex-reviewed, analyze-clean, NOT committed)

Stable `ValueKey`s on the UIKit fork chat core:
- Message row: `message_list_item:<msgID|id|timestamp_sender>`
- Context-menu item, MOBILE **and** DESKTOP: `message_menu_item:<action>`
  (built-ins only; custom `additionalMessageMenuOptions` left unkeyed to avoid
  duplicate sibling keys). Desktop items keyed via an optional `valueKey`
  threaded through the common-pkg `TencentCloudChatColumnMenu`.
- Delete-confirm primary button: `confirm_dialog_primary_button` (desktop + mobile).
- Conversation tile: `conversation_list_item:<conversationID>`
- Contact item: `contact_list_item:<userID>`
- Emoji panel (mobile): `emoji_panel_button`; sticker (desktop): `sticker_panel_button`
- Toxee group/conference profile overrides:
  `group_profile_send_message_button`,
  `group_profile_edit_name_button`,
  `group_profile_edit_name_dialog`,
  `group_profile_edit_name_field`,
  `group_profile_edit_name_confirm_button`,
  `group_profile_id_text`,
  `group_profile_clear_history_button`,
  `group_profile_leave_button`

**Fourteen PASSING WidgetTester gates** (`test/ui/chat_core_real_ui_test.dart`, `flutter test`, codex-reviewed):
1. **composer typing + Enter → real send** (`_handleKeyEvent` → `sendTextMessage`)
   — the desktop send path marionette can't inject. Hardened: asserts no-send-before-Enter.
2. **desktop right-click → context menu → delete → confirm dialog** — drives the
   REAL menu surface (vs the `l3_invoke_action` debug hook): secondary-mouse
   gesture opens the menu, `message_menu_item:delete` → `confirm_dialog_primary_button`.
3. **mobile emoji button → sticker panel toggle** — `emoji_panel_button` tap flips
   the glyph (`emoji_emotions` → `keyboard_alt_outlined`).
4. **conversation list item** (two tests): tap SELECTS (REAL — the default desktop
   tap sets `currentConversation`), and right-click opens the REAL
   pin/markRead/hide/delete menu (REAL — `find.text('Delete'/'Pin')`). A global
   `tearDown` resets the fork's static desktop popup (`isShow`/`entry`) after every
   test, so the menu is no longer suppressed by the message-menu gate.
5. **contact list item — right-click opens the REAL "Open chat" / "Copy Tox ID"
   menu** (real `showMenu`). The tap asserts the navigate hook fires
   (`onNavigateToChat`); the real open-chat side effect uses the native
   conversation SDK (`getConversation`), order-flaky in widget tests, so it's
   asserted at the hook. Contact item now carries `contact_list_item:<userID>`.
6. **group/conference profile Send Message tile** — toxee's override chat button
   is driven by `group_profile_send_message_button`, and the test asserts the
   real `onNavigateToChat(groupID)` hook fires with the active group/conference id.
7. **group/conference profile clear-history row → confirm dialog** — the keyed
   `group_profile_clear_history_button` opens the real confirm dialog with
   cancel/confirm actions.
8. **group/conference profile leave row label + confirm dialog** — owner/non-Work
   renders `Disband Group`, member renders `Leave`, and tapping the keyed
   `group_profile_leave_button` opens the role-appropriate confirm dialog.
9. **group/conference profile content Group ID surface** — toxee's content
   override renders a stable `group_profile_id_text` `SelectableText` with the
   expected `Group ID:` payload.
10. **group/conference profile edit-name confirm path** — tapping the keyed
   `group_profile_edit_name_button` opens the rename dialog, entering text into
   `group_profile_edit_name_field` and confirming via
   `group_profile_edit_name_confirm_button` updates the displayed title after a
   successful `setGroupInfo` platform call.
11. **group profile members entry surface** — with a minimal current-user
   fixture, the toxee wrapper renders a stable `group_profile_members_entry`
   anchor over the upstream member-entry surface. This deliberately covers the
   keyed entry surface only, not the full member-list route.

3 of the 4 list-item operations assert a REAL side effect (conversation tap +
conversation right-click + contact right-click); only the contact tap is a
hook-dispatch (its real side effect goes through the flaky native SDK).

The group/conference profile gates above are **builder-level real UI surfaces**:
they drive toxee's installed group-profile override widgets directly, not the
full `TencentCloudChatGroupProfile` route mount. This is intentional: the full
route pulls in additional upstream group/profile state (current user, member
lists, SDK-backed fetches) that is orthogonal to the toxee-owned UI surfaces we
want to pin down here.

## Coverage Registration

The retired sweep campaign's durable registration rows are kept here so source
tests do not depend on a mutable run log:

| ID | Scenario | Class | Spec |
| --- | --- | --- | --- |
| 19 | `profile_avatar_picker_opens` | 1i | S79 |
| 20 | `profile_avatar_select_default_applies` | 1i | S79 |
| 26 | `login_restore_entry_opens` | 1i | S9/S71 |

The profile batch has 8/8 runnable cases with 0 skips. The login batch has 9/9
runnable cases with 0 skips. These are registration/status facts, not a live
campaign log; new execution results belong in build artifacts.

Runner: a `long_press` action (`ext.flutter.marionette.longPress`, confirmed) for
mobile/marionette parity.

## WidgetTester harness recipe (reusable — the layers needed to render fork chat widgets)

1. `MaterialApp` with `TencentCloudChatLocalizations.delegate` + the
   `GlobalMaterialLocalizations`/`Widgets`/`Cupertino` delegates, and call
   `TencentCloudChatIntl().init(context)` in a `Builder` BEFORE the widget — the
   fork reads `tL10n` at build and throws if uninitialized.
2. `setNativeLibraryName('tim2tox_ffi')`
   (`package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart`)
   in `main()` BEFORE constructing any `V2TimMessage` — else the SDK model tries
   to load the stock `libdart_native_imsdk.dylib` and throws.
3. The composer is an `ExtendedTextField` (editable = `ExtendedEditableText`, NOT
   stock `EditableText`): `tester.enterText` FAILS; use `tester.tap(field)` +
   `tester.testTextInput.enterText('...')` + `tester.sendKeyEvent(enter)`.
4. The message-menu **container** delegates to
   `messageBuilders.getMessageItemMenuBuilder`; set
   `provider.messageBuilders = TencentCloudChatMessageBuilders()` or it renders an
   empty `Container`. Right-click = `tester.startGesture(center,
   kind: PointerDeviceKind.mouse, buttons: kSecondaryButton)`.
5. Desktop vs mobile is driven by `tester.view.physicalSize` (large = desktop
   Enter-to-send + right-click menu; small = mobile). The emoji button is mobile;
   render `TencentCloudChatMessageInputMobile` with `hasStickerPlugin: true`.
6. LIST ITEMS (conversation / contact): the item builds its avatar/content via a
   component builder — set `…dataInstance.conversation.conversationBuilder =
   TencentCloudChatConversationBuilders()` (and `…contact.contactBuilder =
   TencentCloudChatContactBuilders()`) or a null lands in the row's children and
   the build throws. Observe operations via the SETTABLE event handlers, not the
   navigation: conversation tap/right-click → `onTapConversationItem` /
   `onSecondaryTapConversationItem`; contact tap → `onNavigateToChat`. The contact
   right-click opens a Material `showMenu` with hardcoded "Open chat" (find by
   text). Reset the handlers in `addTearDown` (global singleton state).
7. GROUP/CONFERENCE PROFILE OVERRIDES: call
   `GroupProfileBuilderOverrideHandle.capture().installOverrides()` first, then
   test the installed widgets through
   `TencentCloudChatGroupProfileManager.builder.getGroupProfile…Builder(...)`
   instead of pumping the entire upstream profile route. That keeps the gate
   focused on toxee-owned UI surfaces and avoids unrelated upstream state
   requirements (current user bootstrap, member fetches, SDK-backed profile
   hydration).
8. RENAME-CONFIRM PATH: swap `TencentCloudChatSdkPlatform.instance` for a tiny
   fake platform with `isCustomPlatform == true` and a successful
   `setGroupInfo(...)` implementation. That keeps the gate hermetic while still
   exercising the real confirm/save UI path and toxee's post-success local
   title update.

## Why WidgetTester, not marionette (desktop blockers)

marionette gestures = tap/doubleTap/longPress/enterText/swipe/pinchZoom/scrollTo/
pressBackButton (`marionette_flutter 0.5.0`). On toxee's desktop target it CANNOT
open the context menu (RIGHT-CLICK, `message_item_with_menu.dart:681`) or send
(Enter via `RawKeyEvent`, `...input_desktop.dart:534`). WidgetTester has both, and
runs in CI.

## Remaining / future

- Gate 2 stops at "confirm dialog appears" — tapping confirm performs the backend
  `deleteMessagesForMe`, which needs the data layer; assert the actual deletion in
  an `integration_test` (real app + native lib), or via the existing persistence
  tests. The UI surface (menu + confirm prompt) is what these gates cover.
- Group/conference member-entry and member-list flows remain outside this doc's
  stable gate set. They currently pull in upstream profile/member state that is
  better handled either by a dedicated SDK-aware harness or by the existing
  two-process data-half gates (for example S36/S37/S81/S124).
- [P3, minor] `TencentCloudChatDesktopPopup.showColumnMenu()` drops `valueKey`;
  the message context menu uses the direct column-menu path (keyed), so current
  gates are unaffected.
