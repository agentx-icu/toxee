/// Stable identity hints for widgets driven by automated UI tests
/// (flutter_test, integration_test) and AI agents (marionette MCP).
///
/// See `doc/research/UI_AUTOMATION_ROADMAP.en.md` for the naming convention and
/// when to add new keys. tl;dr: all-lowercase snake_case, screen prefix
/// + role suffix; only add keys for widgets that automation actually
/// needs to target reliably.
///
/// Conventions:
///   * Dart field name: camelCase (e.g. `sidebarChats`) — matches the
///     rest of the codebase.
///   * Underlying `Key` string: snake_case, `<screen>_<role>` (e.g.
///     `'sidebar_chats_tab'`) — what `find.byKey` and marionette's
///     `tap(key: ...)` actually match against.
///   * Group fields by screen with a header comment pointing at the
///     widget file that owns them, so a grep from either side finds
///     the other.
///
/// When adding a key:
///   1. Append the constant here, in the right screen section, in
///      source-order of the widget tree.
///   2. Reference it at the widget call site as `key: UiKeys.fieldName`.
///   3. Update `doc/research/UI_AUTOMATION_ROADMAP.en.md` if the new key unlocks
///      a smoke case.
library;

import 'package:flutter/foundation.dart';

/// Centralized `ValueKey` registry for widgets that automation targets.
///
/// Instantiated nowhere; use the static fields directly:
/// `Widget(key: UiKeys.sidebarChats, ...)`.
class UiKeys {
  UiKeys._();

  // Sidebar navigation (lib/ui/settings/sidebar.dart).
  static const Key sidebarChats = Key('sidebar_chats_tab');
  static const Key sidebarContacts = Key('sidebar_contacts_tab');
  static const Key sidebarApplications = Key('sidebar_applications_tab');
  static const Key sidebarSettings = Key('sidebar_settings_tab');
  static const Key sidebarUserAvatar = Key('sidebar_user_avatar');

  // Login page (lib/ui/login_page.dart).
  static const Key loginPageRestoreFromToxFile = Key(
    'login_page_restore_from_tox_file',
  );
  static const Key loginPageSettingsButton = Key('login_page_settings_button');

  /// Stable automation anchor for a specific LoginPage saved-account card.
  ///
  /// Contract: `login_page_account_card:<toxId>`.
  static Key loginPageAccountCard(String toxId) =>
      Key('login_page_account_card:$toxId');

  // Register page (lib/ui/register_page.dart).
  static const Key registerPageNicknameField = Key(
    'register_page_nickname_field',
  );
  static const Key registerPagePasswordField = Key(
    'register_page_password_field',
  );
  static const Key registerPageConfirmPasswordField = Key(
    'register_page_confirm_password_field',
  );
  static const Key registerPageRegisterButton = Key(
    'register_page_register_button',
  );

  // Add Friend dialog (lib/ui/add_friend_dialog.dart).
  static const Key addFriendIdInput = Key('add_friend_id_input');
  static const Key addFriendPasteButton = Key('add_friend_paste_button');
  static const Key addFriendMessageInput = Key('add_friend_message_input');
  static const Key addFriendSubmitButton = Key('add_friend_submit_button');
  static const Key addFriendCancelButton = Key('add_friend_cancel_button');

  // Add Group dialog (lib/ui/add_group_dialog.dart).
  static const Key addGroupJoinIdInput = Key('add_group_join_id_input');
  static const Key addGroupJoinPasteButton = Key('add_group_join_paste_button');
  static const Key addGroupJoinMessageInput = Key(
    'add_group_join_message_input',
  );
  static const Key addGroupAliasInput = Key('add_group_alias_input');
  static const Key addGroupCreateNameInput = Key('add_group_create_name_input');
  static const Key addGroupTypeSelector = Key('add_group_type_selector');
  // Per-segment hook for the create-group type selector. SegmentedButton's
  // ButtonSegment takes no key, so the "Private" label is wrapped in a
  // KeyedSubtree carrying this key — lets UI automation pick Private
  // (invite-only, reliable same-host) without depending on the localized label.
  static const Key addGroupTypePrivateSegment = Key(
    'add_group_type_private_segment',
  );
  static const Key addGroupTypePublicSegment = Key(
    'add_group_type_public_segment',
  );
  static const Key addGroupTypeConferenceSegment = Key(
    'add_group_type_conference_segment',
  );
  static const Key addGroupCreateSubmitButton = Key(
    'add_group_create_submit_button',
  );
  static const Key addGroupCopyIdButton = Key('add_group_copy_id_button');

  // New-entry popup menu (lib/ui/home/home_widgets.dart).
  static const Key newEntryMenuButton = Key('new_entry_menu_button');
  static const Key newEntryAddContactItem = Key('new_entry_add_contact_item');
  static const Key newEntryCreateGroupItem = Key('new_entry_create_group_item');
  static const Key newEntryJoinIrcItem = Key('new_entry_join_irc_item');

  // Applications page (lib/ui/applications/applications_page.dart).
  static const Key applicationsIrcCard = Key('applications_irc_card');
  static const Key applicationsIrcInstallButton = Key(
    'applications_irc_install_button',
  );
  static const Key applicationsIrcUninstallButton = Key(
    'applications_irc_uninstall_button',
  );
  static const Key applicationsIrcAddChannelButton = Key(
    'applications_irc_add_channel_button',
  );
  static const Key applicationsIrcServerField = Key(
    'applications_irc_server_field',
  );
  static const Key applicationsIrcPortField = Key(
    'applications_irc_port_field',
  );
  static const Key applicationsIrcSaveConfigButton = Key(
    'applications_irc_save_config_button',
  );
  static Key applicationsIrcChannelTile(String channel) =>
      Key('applications_irc_channel_tile:$channel');
  static Key applicationsIrcRemoveChannelButton(String channel) =>
      Key('applications_irc_remove_channel_button:$channel');

  // Profile page edit form (lib/ui/profile/profile_header.dart,
  // lib/ui/profile/profile_edit_fields.dart).
  static const Key profileEditToggle = Key('profile_edit_toggle');
  static const Key profileNicknameField = Key('profile_nickname_field');
  static const Key profileStatusField = Key('profile_status_field');
  static const Key profileSaveButton = Key('profile_save_button');
  static const Key profileToxIdCopyButton = Key('profile_tox_id_copy_button');
  static const Key profileQrCopyButton = Key('profile_qr_copy_button');
  static const Key profileToxIdSelectableText = Key(
    'profile_tox_id_selectable_text',
  );

  // Settings export flow (lib/ui/settings/settings_page*.dart).
  static const Key settingsExportAccountButton = Key(
    'settings_export_account_button',
  );
  static const Key settingsCopyToxIdButton = Key('settings_copy_tox_id_button');
  static const Key settingsSetPasswordButton = Key(
    'settings_set_password_button',
  );
  static const Key settingsLogoutButton = Key('settings_logout_button');
  static const Key settingsLogoutConfirmButton = Key(
    'settings_logout_confirm_button',
  );
  static const Key settingsAutoLoginSwitch = Key('settings_auto_login_switch');
  static const Key settingsNotificationSoundSwitch = Key(
    'settings_notification_sound_switch',
  );
  static const Key settingsDownloadLimitField = Key(
    'settings_download_limit_field',
  );
  static const Key settingsDownloadLimitSaveButton = Key(
    'settings_download_limit_save_button',
  );
  static const Key settingsBootstrapModeManual = Key(
    'settings_bootstrap_mode_manual',
  );
  static const Key settingsBootstrapModeAuto = Key(
    'settings_bootstrap_mode_auto',
  );
  static const Key settingsBootstrapModeLan = Key(
    'settings_bootstrap_mode_lan',
  );
  static const Key settingsExportProfileToxOption = Key(
    'settings_export_profile_tox_option',
  );
  static const Key settingsExportFullBackupOption = Key(
    'settings_export_full_backup_option',
  );
  static const Key settingsAccountSwitchConfirmButton = Key(
    'settings_account_switch_confirm_button',
  );
  static const Key settingsAccountSwitchCancelButton = Key(
    'settings_account_switch_cancel_button',
  );

  // Dynamic conversation/contact/group rows.
  //
  // Conversation and contact rows already carry stable runtime keys in the
  // current UIKit integration; expose the exact strings here so scenario docs
  // and tests stop hardcoding them ad hoc. Group rows are attached at the
  // toxee override boundary.
  static Key conversationListTile(String conversationId) =>
      Key('conversation_list_item:$conversationId');
  static Key contactListTile(String userId) => Key('contact_list_item:$userId');
  static Key groupListTile(String groupId) => Key('group_list_tile:$groupId');

  // Search surfaces (lib/ui/search/*.dart).
  static const Key messageSearchField = Key('message_search_field');
  static Key searchResultMessage(String conversationId) =>
      Key('search_result_message_$conversationId');
  // Conversation/group result ROWS in the global search (custom_search.dart) —
  // distinct from message-result tiles. Keyed so UI automation taps the row that
  // opens the conversation (tapping by name collides with the query text in the
  // search field).
  static Key searchResultGroup(String groupId) =>
      Key('search_result_group:$groupId');
  static Key searchResultConversation(String conversationId) =>
      Key('search_result_conversation:$conversationId');
  // Contact (friend) result ROWS in the global search (custom_search.dart).
  // Keyed for the same reason as the group/conversation rows: the highlighted
  // title renders as a RichText (not a plain Text) and tapping by name collides
  // with the query text in the search field.
  static Key searchResultContact(String userId) =>
      Key('search_result_contact:$userId');
  static Key searchHistoryMessage(String messageId) =>
      Key('search_history_message_$messageId');

  // Group profile actions (lib/ui/group/group_builder_override.dart).
  static const Key groupProfileMembersEntry = Key(
    'group_profile_members_entry',
  );
  static const Key groupProfileEditNameButton = Key(
    'group_profile_edit_name_button',
  );
  static const Key groupProfileIdText = Key('group_profile_id_text');
  static const Key groupProfileEditNameDialog = Key(
    'group_profile_edit_name_dialog',
  );
  static const Key groupProfileEditNameField = Key(
    'group_profile_edit_name_field',
  );
  static const Key groupProfileEditNameConfirmButton = Key(
    'group_profile_edit_name_confirm_button',
  );
  static const Key groupProfileClearHistoryButton = Key(
    'group_profile_clear_history_button',
  );
  static const Key groupProfileLeaveButton = Key('group_profile_leave_button');

  // Conversation context menu (lib/ui/home_page.dart).
  static const Key conversationContextMenuPinItem = Key(
    'conversation_context_menu_pin_item',
  );
  static const Key conversationContextMenuUnpinItem = Key(
    'conversation_context_menu_unpin_item',
  );
  static const Key conversationContextMenuDeleteItem = Key(
    'conversation_context_menu_delete_item',
  );
  static const Key conversationContextMenuMarkReadItem = Key(
    'conversation_context_menu_mark_read_item',
  );
  static const Key deleteConversationConfirmButton = Key(
    'delete_conversation_confirm_button',
  );

  // Friend profile actions (tencent_cloud_chat_user_profile_body.dart).
  static const Key userProfileEditRemarkButton = Key(
    'user_profile_edit_remark_button',
  );
  static const Key userProfileFriendNameText = Key(
    'user_profile_friend_name_text',
  );
  static const Key userProfileModifyRemarkDialog = Key(
    'user_profile_modify_remark_dialog',
  );
  static const Key userProfileModifyRemarkTextField = Key(
    'user_profile_modify_remark_text_field',
  );
  static const Key userProfileModifyRemarkConfirmButton = Key(
    'user_profile_modify_remark_confirm_button',
  );
  static const Key userProfileConversationMuteSwitch = Key(
    'user_profile_conversation_mute_switch',
  );
  static const Key userProfileClearHistoryButton = Key(
    'user_profile_clear_history_button',
  );
  static const Key userProfileClearHistoryConfirmButton = Key(
    'user_profile_clear_history_confirm_button',
  );
  static const Key userProfileDeleteFriendButton = Key(
    'user_profile_delete_friend_button',
  );
  // Contact application list (tencent_cloud_chat_contact_application*.dart).
  static Key contactApplicationItem(String userId) =>
      Key('contact_application_item:$userId');
  static Key contactApplicationAcceptButton(String userId) =>
      Key('contact_application_accept_button:$userId');
  static Key contactApplicationDeclineButton(String userId) =>
      Key('contact_application_decline_button:$userId');
  static Key contactApplicationAddWording(String userId) =>
      Key('contact_application_addwording:$userId');
  static const Key contactNewContactsTab = Key('contact_new_contacts_tab');
  static const Key contactGroupNotificationsTab = Key(
    'contact_group_notifications_tab',
  );
  static const Key contactBlockedUsersTab = Key('contact_blocked_users_tab');
  static const Key contactApplicationsListEmpty = Key(
    'contact_applications_list_empty',
  );
  static Key contactApplicationDetailAcceptButton(String userId) =>
      Key('contact_application_detail_accept_button:$userId');
  static Key contactApplicationDetailDeclineButton(String userId) =>
      Key('contact_application_detail_decline_button:$userId');

  // Presence affordances.
  static Key conversationItemOnlineDot(String conversationId) =>
      Key('conversation_item_online_dot:$conversationId');

  // Call controls.
  static const Key chatCallVoiceButton = Key('chat_call_voice_button');
  static const Key chatCallVideoButton = Key('chat_call_video_button');
  static const Key callAcceptButton = Key('call_accept_button');
  static const Key callDeclineButton = Key('call_decline_button');
  static const Key callHangupButton = Key('call_hangup_button');
  static const Key callMicMuteButton = Key('call_mic_mute_button');
  static const Key callCameraToggleButton = Key('call_camera_toggle_button');

  // Manual bootstrap form.
  static const Key manualNodeInputButton = Key('manual_node_input_button');
  static const Key manualNodeHostField = Key('manual_node_host_field');
  static const Key manualNodePortField = Key('manual_node_port_field');
  static const Key manualNodePubkeyField = Key('manual_node_pubkey_field');
  static const Key manualNodeTestButton = Key('manual_node_test_button');

  // Group invite / moderation.
  static const Key groupAddMemberButton = Key('group_add_member_button');
  static const Key groupMemberInviteConfirmButton = Key(
    'group_member_invite_confirm_button',
  );
  static const Key groupMemberActionKickButton = Key(
    'group_member_action_kick_button',
  );
  static const Key groupMemberInfoCopyIdButton = Key(
    'group_member_info_copy_id_button',
  );
  static Key groupInviteAcceptButton(String groupId) =>
      Key('group_invite_accept_button:$groupId');

  // Chat composer + friend-profile "Send Message" wiring
  // (lib/ui/home_page_bootstrap.dart). The underlying widgets live inside
  // the Tencent UIKit fork (`third_party/chat-uikit-flutter/`); we attach
  // these keys at the toxee override boundary by wrapping the upstream
  // widgets with `KeyedSubtree(key: ..., child: ...)`. That keeps the keys
  // discoverable from `find.byKey` / marionette's `tap(key: ...)` without
  // patching third_party.
  //
  // Caveat for [chatSendButton]: UIKit's desktop input has no tappable
  // "Send" affordance — sending is keyboard-driven (Enter on the focused
  // input). On desktop the driver should submit by entering text into
  // [chatInputTextField] and dispatching `\n`, NOT by tapping this key.
  // On mobile/tablet, the key wraps the input row that contains the send
  // icon. See the wrapper at home_page_bootstrap.dart's
  // `messageInputBuilder` override.
  static const Key chatInputTextField = Key('chat_input_text_field');
  static const Key chatSendButton = Key('chat_send_button');

  // Friend profile "Send Message" tile (Contacts tab → friend → profile).
  // Wrapped at the `userProfileChatButtonBuilder` override in
  // lib/ui/home_page_bootstrap.dart; the underlying widget is UIKit's
  // `TencentCloudChatUserProfileChatButton` which renders a row of
  // [Send Message, Voice Call, Video Call] tiles — this key targets the
  // whole tile group at the toxee boundary.
  static const Key friendProfileSendMessageButton = Key(
    'friend_profile_send_message_button',
  );

  // Group/conference profile Send Message tile. Attached at toxee's custom
  // group-profile chat-button override so automation can target the single
  // send-message affordance without depending on localized text.
  static const Key groupProfileSendMessageButton = Key(
    'group_profile_send_message_button',
  );
}
