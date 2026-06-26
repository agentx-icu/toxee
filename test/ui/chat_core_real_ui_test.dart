// Real-UI widget tests for the chat CORE — the desktop flows the marionette
// MCP harness CANNOT drive (no key-injection for Enter-to-send, no right-click).
// A WidgetTester CAN: it injects the real Enter key into the desktop composer's
// RawKeyEvent handler, exercising the actual send path (not the l3_send_text
// debug bypass). Runs in CI via `flutter test`.
//
// Test #1 (composer send via Enter) is the highest-value gate: it covers the
// send path that is structurally unreachable by marionette on desktop.
// Tests #2/#3 (right-click menu->delete->confirm, emoji panel) depend on a
// heavier render harness and are documented as the next step.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data_notifier.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_builders.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/menu/tencent_cloud_chat_message_item_with_menu_container.dart';
import 'package:tencent_cloud_chat_common/components/component_event_handlers/tencent_cloud_chat_contact_event_handlers.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/widgets/desktop_popup/tencent_cloud_chat_desktop_popup.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact_builders.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_item.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_group_member_info.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_group_member_list.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_builders.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_item.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/desktop/tencent_cloud_chat_message_input_desktop.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_mobile.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_group_profile.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_group_profile_builders.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_group_profile_controller.dart';
import 'package:toxee/ui/group/group_member_list_wrapper.dart';
import 'package:toxee/ui/group/group_builder_override.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_group_profile_options.dart';

// Wrap a child so the UIKit fork's i18n singleton (`tL10n`) is initialized from
// a real Localizations ancestor before the child builds — the fork composer
// reads `tL10n` during build and throws if it is uninitialized.
Widget _localized({required Widget child}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
    localizationsDelegates: const [
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) {
          TencentCloudChatIntl().init(context);
          return child;
        },
      ),
    ),
  );
}

class _FakeGroupSdkPlatform extends TencentCloudChatSdkPlatform {
  V2TimGroupInfo? lastGroupInfo;

  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimCallback> setGroupInfo({
    required V2TimGroupInfo info,
  }) async {
    lastGroupInfo = info;
    return V2TimCallback(code: 0, desc: 'ok');
  }
}

MessageInputBuilderMethods _stubMethods(List<String> sentSink) {
  return MessageInputBuilderMethods(
    sendTextMessage: ({required String text, List<String>? mentionedUsers}) {
      sentSink.add(text);
    },
    sendImageMessage: ({String? imagePath, String? imageName, dynamic inputElement}) {},
    sendVideoMessage: ({String? videoPath, dynamic inputElement}) {},
    sendFileMessage: ({String? filePath, String? fileName, dynamic inputElement}) {},
    sendVoiceMessage: ({required String voicePath, required int duration}) {},
    onChooseGroupMembers: () async => <V2TimGroupMemberFullInfo>[],
    controller: Object(),
    clearRepliedMessage: () {},
    setDesktopMentionBoxPositionX: (_) {},
    setDesktopMentionBoxPositionY: (_) {},
    setActiveMentionIndex: (_) {},
    setCurrentFilteredMembersListForMention: (_) {},
    desktopInputMemberSelectionPanelScroll: AutoScrollController(),
    messageAttachmentOptionsBuilder: Object(),
    closeSticker: () {},
  );
}

MessageInputBuilderData _data({bool hasStickerPlugin = false}) {
  return MessageInputBuilderData(
    userID: 'friend1',
    attachmentOptions: const [],
    inSelectMode: false,
    enableReplyWithMention: false,
    status: TencentCloudChatMessageInputStatus.canSendMessage,
    selectedMessages: const [],
    desktopMentionBoxPositionX: 0,
    desktopMentionBoxPositionY: 0,
    isGroupAdmin: false,
    activeMentionIndex: -1,
    currentFilteredMembersListForMention: const [],
    groupMemberList: const [],
    currentConversationShowName: 'Friend One',
    hasStickerPlugin: hasStickerPlugin,
    stickerPluginInstance: null,
  );
}

// Sets up the singleton state + renders ONE desktop conversation item, returns
// its tile key. Split tap/right-click into separate tests: the item rebuilds on
// a currentConversation change (selection highlight), which would dismiss a
// right-click menu opened in the same render. Resets the singletons in tearDown.
Future<ValueKey<String>> _pumpConversationItem(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // deviceScreenType is a cached static set once on first init; a prior
  // small-screen test (the mobile emoji gate) can leave it as mobile, which
  // makes the item's `isDesktopScreen` false and suppresses the desktop
  // right-click menu. Force it desktop for these item gates.
  TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
  TencentCloudChatScreenAdapter.hasInitialized = true;
  addTearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  final data = TencentCloudChat.instance.dataInstance;
  final conv = data.conversation;
  data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
  // Desktop combined-navigator: a tap sets currentConversation (vs the mobile
  // Navigator path, which needs a registered route).
  conv.conversationConfig.setConfigs(forceDesktopLayout: true);
  // Item renders avatar/content via conversationBuilder; null => build throws.
  conv.conversationBuilder = TencentCloudChatConversationBuilders();
  // No app hook → the DEFAULT tap (sets currentConversation) and the default
  // desktop right-click menu run.
  conv.conversationEventHandlers = null;
  conv.currentConversation = null;
  addTearDown(() {
    conv.conversationBuilder = null;
    conv.conversationEventHandlers = null;
    conv.currentConversation = null;
    conv.conversationConfig.setConfigs(forceDesktopLayout: false);
    data.basic.usedComponents = [];
  });

  const tileKey = ValueKey('conversation_list_item:c2c_alice');
  await tester.pumpWidget(
    _localized(
      child: KeyedSubtree(
        key: tileKey,
        child: TencentCloudChatConversationItem(
          conversation: V2TimConversation(
              conversationID: 'c2c_alice',
              type: 1,
              userID: 'alice',
              showName: 'Alice'),
          isOnline: false,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(tileKey), findsOneWidget);
  return tileKey;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Point the SDK at the tim2tox FFI lib name (matches production). Required
  // before constructing any V2TimMessage (the menu gate), else the SDK model
  // tries to load the stock libdart_native_imsdk.dylib and throws. Harmless for
  // the composer gate (which constructs no message). NOTE: this is process-
  // global state — fine here because every gate in this file wants the tim2tox
  // lib (the production name); a suite that needs the default lib must not rely
  // on call order.
  setNativeLibraryName('tim2tox_ffi');

  // The fork's desktop popup tracks open state in a STATIC isShow/entry; a test
  // that opens one (the message delete-confirm dialog, the conversation
  // right-click menu) must not leak it, or the next popup bails out
  // (showPopupWindow returns early when isShow is already true). Reset after
  // every test so popup gates are order-independent.
  tearDown(() {
    TencentCloudChatDesktopPopup.entry?.remove();
    TencentCloudChatDesktopPopup.entry = null;
    TencentCloudChatDesktopPopup.isShow = false;
  });

  testWidgets(
    'desktop composer: typing + Enter invokes the real send path',
    (tester) async {
      // Desktop layout so the desktop composer (Enter-to-send) renders.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sent = <String>[];
      final provider = TencentCloudChatMessageSeparateDataProvider();

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageDataProviderInherited(
            dataProvider: provider,
            child: TencentCloudChatMessageInputDesktop(
              inputData: _data(),
              inputMethods: _stubMethods(sent),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The fork composer uses ExtendedTextField (extended_text_field), whose
      // editable is ExtendedEditableText, NOT the stock EditableText.
      final field = find.byType(ExtendedTextField);
      expect(field, findsWidgets, reason: 'composer text field should render');

      // ExtendedTextField exposes no stock EditableText, so tester.enterText
      // (which looks up EditableTextState) fails. Focus via tap, then deliver
      // text through the raw text-input connection the editable established.
      await tester.tap(field.first);
      await tester.pump();
      tester.testTextInput.enterText('hello-real-ui');
      await tester.pump();
      // Typing alone must NOT send — proves the assertion below is driven by
      // Enter through the real handler, not by text entry (non-vacuous).
      expect(sent, isEmpty, reason: 'typing should not trigger send');
      // The real desktop send path: Enter (no shift) -> RawKeyEvent handler ->
      // sendTextMessage. This is exactly what marionette cannot inject.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(sent, contains('hello-real-ui'),
          reason: 'Enter should drive the composer send callback');
    },
  );

  // TODO(real-ui): right-click -> desktop context menu -> delete ->
  // confirm_dialog_primary_button. Needs the full message-list render harness
  // (message rows + the desktop menu overlay). Keys are in place
  // (message_menu_item:delete, confirm_dialog_primary_button); the blocker is
  // the heavier render setup, not the gesture (tester.tap(buttons:
  // kSecondaryButton) works). See tool/mcp_test/REAL_UI_GATES.md.
  // SCOPE: this exercises the FORK's message context-menu surface (the real
  // right-click -> menu -> delete -> confirm dialog that the l3_invoke_action
  // debug hook bypasses). It does NOT exercise toxee's row /
  // messageItemBuilder integration (home_page_bootstrap) — that wrapping is a
  // separate concern and would need a full message-list harness.
  testWidgets(
    'fork context-menu surface: right-click -> delete -> keyed confirm dialog',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = TencentCloudChatMessageSeparateDataProvider();
      // The container delegates rendering to messageBuilders.getMessageItemMenuBuilder;
      // without it, defaultBuilder falls back to an empty Container.
      provider.messageBuilders = TencentCloudChatMessageBuilders();
      final msg = V2TimMessage(
        msgID: 'm1',
        isSelf: true,
        elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
        timestamp: 1700000000,
      );

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageDataProviderInherited(
            dataProvider: provider,
            child: TencentCloudChatMessageItemWithMenuContainer(
              getMessageItemWidget: ({required bool renderOnMenuPreview, Key? key}) =>
                  Container(
                key: const ValueKey('test_bubble'),
                width: 120,
                height: 40,
                color: Colors.blue,
                child: const Text('hi'),
              ),
              useMessageReaction: false,
              message: msg,
              isMergeMessage: false,
              isTextTranslatePluginEnabled: false,
              isSoundToTextPluginEnabled: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bubble = find.byKey(const ValueKey('test_bubble'));
      expect(bubble, findsOneWidget);
      const deleteItem = ValueKey('message_menu_item:delete');
      // Menu is closed before the click: the keyed item is absent (no
      // always-mounted/offstage copy), so its appearance proves the right-click
      // opened the menu.
      expect(find.byKey(deleteItem), findsNothing);

      // Right-click (secondary mouse) opens the desktop context menu — the
      // gesture marionette cannot perform.
      final gesture = await tester.startGesture(
        tester.getCenter(bubble),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      // Exactly one REAL keyed menu item now exists (no offstage duplicate).
      expect(find.byKey(deleteItem), findsOneWidget);

      // Delete is not immediate: tapping it opens a confirm dialog whose primary
      // button is keyed. (Tapping confirm performs the backend delete, covered by
      // persistence-layer tests, not this UI-surface gate.)
      await tester.tap(find.byKey(deleteItem));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('confirm_dialog_primary_button')),
          findsOneWidget);
    },
  );

  // TODO(real-ui): tap emoji_panel_button -> assert panel opens.
  // SCOPE: proves the keyed emoji button's STATE toggle (the _showStickerPanel
  // flip, observable via the glyph swap). With stickerPluginInstance:null the
  // panel body stays an empty Container, so this does NOT prove sticker-panel
  // rendering — that needs a real plugin instance.
  testWidgets(
    'mobile emoji button toggles panel state (glyph flips emoji<->keyboard)',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputMobile(
            inputData: _data(hasStickerPlugin: true),
            inputMethods: _stubMethods(<String>[]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emojiBtn = find.byKey(const ValueKey('emoji_panel_button'));
      expect(emojiBtn, findsOneWidget);
      // Initial state: emoji glyph shown, keyboard-toggle glyph absent.
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_alt_outlined), findsNothing);

      await tester.tap(emojiBtn);
      await tester.pumpAndSettle();

      // Toggled: the glyph flips to the keyboard-toggle icon (panel-open state),
      // and the emoji glyph is gone — proving the keyed button drives the toggle.
      expect(find.byIcon(Icons.keyboard_alt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.emoji_emotions_outlined), findsNothing);
    },
  );

  // Conversation LIST-ITEM REAL side effects (item-level; keyed subtree mirrors
  // conversation_list.dart:118; default behavior, no app hook; pure-Dart). The
  // global tearDown resets the fork's static desktop popup so this right-click
  // menu renders regardless of the earlier message-menu gate.
  testWidgets('conversation list item: right-click opens the real context menu',
      (tester) async {
    final tileKey = await _pumpConversationItem(tester);
    expect(find.text('Delete'), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(tileKey)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    // The real pin / markAsRead / hide / delete menu renders.
    expect(find.text('Delete'), findsOneWidget,
        reason: 'right-click should open the conversation context menu');
    expect(find.text('Pin'), findsOneWidget);
  });

  testWidgets('conversation list item: tap selects it (sets currentConversation)',
      (tester) async {
    final tileKey = await _pumpConversationItem(tester);
    final conv = TencentCloudChat.instance.dataInstance.conversation;
    // SELECT: the default desktop tap flips currentConversation to this item.
    expect(conv.currentConversation?.conversationID, isNot('c2c_alice'));
    await tester.tap(find.byKey(tileKey));
    await tester.pumpAndSettle();
    expect(conv.currentConversation?.conversationID, 'c2c_alice',
        reason: 'tap should select the conversation (currentConversation set)');
  });

  // SCOPE: contact LIST-ITEM (item-level, not the AZ-list). The tap is asserted at
  // the navigate HOOK (onNavigateToChat): the real "open chat" side effect goes
  // through the native conversation SDK (getConversation), which is order-flaky in
  // widget tests, so we don't assert it here. Right-click asserts the REAL
  // "Open chat" / "Copy Tox ID" showMenu (a pure-Dart, reliable side effect).
  testWidgets(
    'contact list item: tap fires the navigate hook + right-click opens the real menu',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final contact = TencentCloudChat.instance.dataInstance.contact;
      // Item renders avatar/content via contactBuilder; null => build throws.
      contact.contactBuilder = TencentCloudChatContactBuilders();
      String? tappedUser;
      contact.contactEventHandlers = TencentCloudChatContactEventHandlers(
        uiEventHandlers: TencentCloudChatContactUIEventHandlers(
          // Return true ("handled") so the default native navigation does not run.
          onTapContactItem: ({userID, groupID}) async {
            tappedUser = userID;
            return true;
          },
        ),
      );
      addTearDown(() => contact.contactEventHandlers = null);
      addTearDown(() => contact.contactBuilder = null);

      final friend = V2TimFriendInfo(userID: 'bob');
      const tileKey = ValueKey('contact_list_item:bob');
      await tester.pumpWidget(
        _localized(child: TencentCloudChatContactItem(friend: friend)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(tileKey), findsOneWidget);

      // Tap → the contact navigate hook fires.
      expect(tappedUser, isNull);
      await tester.tap(find.byKey(tileKey));
      await tester.pumpAndSettle();
      expect(tappedUser, 'bob', reason: 'tap should fire the contact navigate hook');

      // Right-click (desktop secondary mouse) → the item's REAL context menu.
      expect(find.text('Open chat'), findsNothing);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(tileKey)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Open chat'), findsOneWidget,
          reason: 'right-click should show the contact context menu');
      expect(find.text('Copy Tox ID'), findsOneWidget);
    },
  );

  testWidgets(
    'group profile Send Message tile navigates back into chat via onNavigateToChat',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final contact = TencentCloudChat.instance.dataInstance.contact;
      String? tappedGroupId;
      contact.contactEventHandlers = TencentCloudChatContactEventHandlers(
        uiEventHandlers: TencentCloudChatContactUIEventHandlers(
          onTapContactItem: ({userID, groupID}) async {
            tappedGroupId = groupID;
            return true;
          },
        ),
      );
      addTearDown(() => contact.contactEventHandlers = null);

      final builders = TencentCloudChatGroupProfileManager.builder;
      final widgetUnderTest = builders.getGroupProfileChatButtonBuilder(
        groupInfo: V2TimGroupInfo(
          groupID: 'tox_conf_42',
          groupName: 'Conference 42',
          groupType: 'AVChatRoom',
        ),
      );

      await tester.pumpWidget(
        _localized(
          child: widgetUnderTest,
        ),
      );
      await tester.pumpAndSettle();

      expect(tappedGroupId, isNull);
      expect(find.byKey(UiKeys.groupProfileSendMessageButton), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.groupProfileSendMessageButton));
      await tester.pumpAndSettle();

      expect(
        tappedGroupId,
        'tox_conf_42',
        reason:
            'the toxee group-profile Send Message tile should route back to chat with the active groupID',
      );
    },
  );

  testWidgets(
    'group profile clear-history row opens the keyed confirm dialog',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      final widgetUnderTest = builders.getGroupProfileDeleteButtonBuilder(
        groupInfo: V2TimGroupInfo(
          groupID: 'tox_group_42',
          groupName: 'Group 42',
          groupType: GroupType.Work,
          role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
        ),
        groupMemberList: const <V2TimGroupMemberFullInfo>[],
      );

      await tester.pumpWidget(_localized(child: widgetUnderTest));
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupProfileClearHistoryButton), findsOneWidget);
      expect(
        find.text('Are you sure you want to clear the chat history?'),
        findsNothing,
      );

      await tester.tap(find.byKey(UiKeys.groupProfileClearHistoryButton));
      await tester.pumpAndSettle();

      expect(
        find.text('Are you sure you want to clear the chat history?'),
        findsOneWidget,
        reason: 'tapping the clear-history row should open the confirm dialog',
      );
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  testWidgets(
    'group profile leave row shows Disband Group for a non-Work owner',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      final widgetUnderTest = builders.getGroupProfileDeleteButtonBuilder(
        groupInfo: V2TimGroupInfo(
          groupID: 'tox_conf_42',
          groupName: 'Conference 42',
          groupType: GroupType.AVChatRoom,
          role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
        ),
        groupMemberList: const <V2TimGroupMemberFullInfo>[],
      );

      await tester.pumpWidget(_localized(child: widgetUnderTest));
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupProfileLeaveButton), findsOneWidget);
      expect(find.text('Disband Group'), findsOneWidget);
      expect(find.text('Leave'), findsNothing);

      await tester.tap(find.byKey(UiKeys.groupProfileLeaveButton));
      await tester.pumpAndSettle();

      expect(find.text('Disband the group?'), findsOneWidget);
    },
  );

  testWidgets(
    'group profile leave row shows Leave for a member',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      final widgetUnderTest = builders.getGroupProfileDeleteButtonBuilder(
        groupInfo: V2TimGroupInfo(
          groupID: 'tox_group_99',
          groupName: 'Group 99',
          groupType: GroupType.Work,
          role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
        ),
        groupMemberList: const <V2TimGroupMemberFullInfo>[],
      );

      await tester.pumpWidget(_localized(child: widgetUnderTest));
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupProfileLeaveButton), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('Disband Group'), findsNothing);

      await tester.tap(find.byKey(UiKeys.groupProfileLeaveButton));
      await tester.pumpAndSettle();

      expect(find.text('Leave the group?'), findsOneWidget);
    },
  );

  testWidgets(
    'group profile content shows a stable Group ID text surface',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      final widgetUnderTest = builders.getGroupProfileContentBuilder(
        groupInfo: V2TimGroupInfo(
          groupID: 'tox_group_1234',
          groupName: 'Group 1234',
          groupType: GroupType.Work,
        ),
      );

      await tester.pumpWidget(_localized(child: widgetUnderTest));
      await tester.pumpAndSettle();

      expect(find.text('Group 1234'), findsOneWidget);
      expect(find.byKey(UiKeys.groupProfileIdText), findsOneWidget);
      expect(find.textContaining('Group ID:'), findsOneWidget);
      expect(find.textContaining('tox_group_1234'), findsOneWidget);
    },
  );

  testWidgets(
    'group profile content edit button opens the rename dialog',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      final widgetUnderTest = builders.getGroupProfileContentBuilder(
        groupInfo: V2TimGroupInfo(
          groupID: 'tox_group_5678',
          groupName: 'Rename Me',
          groupType: GroupType.Work,
        ),
      );

      await tester.pumpWidget(_localized(child: widgetUnderTest));
      await tester.pumpAndSettle();

      expect(find.text('set Group Name'), findsNothing);

      expect(find.byKey(UiKeys.groupProfileEditNameButton), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.groupProfileEditNameButton));
      await tester.pumpAndSettle();

      expect(
        find.byKey(UiKeys.groupProfileEditNameDialog),
        findsOneWidget,
        reason: 'tapping the group-profile edit button should open the rename dialog',
      );
      expect(find.byKey(UiKeys.groupProfileEditNameField), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    },
  );

  testWidgets(
    'group profile content rename confirm updates the title and calls setGroupInfo',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final oldPlatform = TencentCloudChatSdkPlatform.instance;
      final fakePlatform = _FakeGroupSdkPlatform();
      TencentCloudChatSdkPlatform.instance = fakePlatform;
      addTearDown(() => TencentCloudChatSdkPlatform.instance = oldPlatform);

      final builders = TencentCloudChatGroupProfileManager.builder;
      final widgetUnderTest = builders.getGroupProfileContentBuilder(
        groupInfo: V2TimGroupInfo(
          groupID: 'tox_group_rename',
          groupName: 'Before Rename',
          groupType: GroupType.Work,
        ),
      );

      await tester.pumpWidget(_localized(child: widgetUnderTest));
      await tester.pumpAndSettle();

      expect(find.text('Before Rename'), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.groupProfileEditNameButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(UiKeys.groupProfileEditNameField),
        'After Rename',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(UiKeys.groupProfileEditNameConfirmButton));
      await tester.pumpAndSettle();

      expect(find.text('After Rename'), findsOneWidget);
      // S153: the displayed group title refreshed — the OLD name is gone, not
      // just the new one present (the widget-layer half of "rename refreshes
      // the row"; the conversation-list-row half is two-process).
      expect(find.text('Before Rename'), findsNothing);
      expect(fakePlatform.lastGroupInfo, isNotNull);
      expect(fakePlatform.lastGroupInfo!.groupID, 'tox_group_rename');
      expect(fakePlatform.lastGroupInfo!.groupName, 'After Rename');
    },
  );

  testWidgets(
    'group profile members entry renders through the toxee keyed wrapper when currentUser is set',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final oldCurrentUser =
          TencentCloudChat.instance.dataInstance.basic.currentUser;
      TencentCloudChat.instance.dataInstance.basic
          .updateCurrentUserInfo(userFullInfo: V2TimUserFullInfo(userID: 'alice'));
      addTearDown(() {
        if (oldCurrentUser != null) {
          TencentCloudChat.instance.dataInstance.basic
              .updateCurrentUserInfo(userFullInfo: oldCurrentUser);
        }
      });

      final builders = TencentCloudChatGroupProfileManager.builder;
      final widgetUnderTest = builders.getGroupProfileMemberBuilder(
        groupInfo: V2TimGroupInfo(
          groupID: 'tox_group_members',
          groupName: 'Members Group',
          groupType: GroupType.Work,
        ),
        groupMember: <V2TimGroupMemberFullInfo>[
          V2TimGroupMemberFullInfo(userID: 'alice', nickName: 'Alice'),
        ],
        contactList: const <V2TimFriendInfo>[],
      );

      await tester.pumpWidget(_localized(child: widgetUnderTest));
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupProfileMembersEntry), findsOneWidget);
      expect(find.textContaining('Group Members'), findsOneWidget);
    },
  );

  // S141 — member-info surface renders a member's name + identifier. The
  // pushed member-info ROUTE is not flutter_skill-reachable from the
  // two-process harness (same limitation as the whole group-profile route), so
  // this asserts the real member-info BODY widget directly at the widget layer.
  testWidgets(
    'S141 group member info body renders the member name and id',
    (tester) async {
      final member = V2TimGroupMemberFullInfo(
        userID: 'bob',
        nickName: 'Bob',
        role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
        joinTime: 0,
      );
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupMemberInfoBody(memberFullInfo: member),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.textContaining('bob'), findsWidgets);
    },
  );

  // S143 — an OWNER tapping a non-self member row surfaces the keyed kick
  // action (in the manage-member Cupertino sheet). The kick key is on the
  // PLAIN-tap sheet (the desktop secondary-click opens a different, unkeyed
  // menu — codex), and the row's GestureDetector uses deferToChild so a
  // byType/center tap can miss; tap the member NAME instead (mirrors the
  // working control in test/ui/conference/conference_members_real_ui_test.dart).
  // The kick FUNCTION is additionally covered data-half by S37.
  testWidgets(
    'S143 owner tapping a non-self member row surfaces the keyed kick action',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // isSelf() reads currentUser; set it to someone OTHER than the row member.
      final oldCurrentUser =
          TencentCloudChat.instance.dataInstance.basic.currentUser;
      TencentCloudChat.instance.dataInstance.basic.updateCurrentUserInfo(
          userFullInfo: V2TimUserFullInfo(userID: 'owner_self'));
      addTearDown(() {
        if (oldCurrentUser != null) {
          TencentCloudChat.instance.dataInstance.basic
              .updateCurrentUserInfo(userFullInfo: oldCurrentUser);
        }
      });

      final member = V2TimGroupMemberFullInfo(
        userID: 'bob',
        nickName: 'Bob Member',
        role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
      );
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupMemberListItem(
            groupInfo: V2TimGroupInfo(
              groupID: 'tox_group_s143',
              groupName: 'S143 Group',
              groupType: GroupType.Work,
              role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
            ),
            memberFullInfo: member,
            myRole: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
            onDeleteGroupMember: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.groupMemberActionKickButton), findsNothing);

      // Tap the member NAME (deferToChild → a center/byType tap can miss).
      await tester.tap(find.text('Bob Member'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(UiKeys.groupMemberActionKickButton),
        findsOneWidget,
        reason: 'owner viewing a non-self member must see the kick action',
      );
    },
  );

  // S139 — the toxee group-profile avatar override renders a tappable
  // local-pick surface (camera badge + GestureDetector). We do NOT fire the
  // real FilePicker (needs the plugin + per-account paths). Mirrors the working
  // conference analog test/ui/conference/conference_profile_real_ui_test.dart.
  testWidgets(
    'S139 group profile avatar override renders a tappable picker surface',
    (tester) async {
      final handle = GroupProfileBuilderOverrideHandle.capture();
      handle.installOverrides();
      addTearDown(handle.restore);

      final builders = TencentCloudChatGroupProfileManager.builder;
      await tester.pumpWidget(
        _localized(
          child: builders.getGroupProfileAvatarBuilder(
            groupInfo: V2TimGroupInfo(
              groupID: 'tox_group_s139',
              groupName: 'S139 Group',
              groupType: GroupType.Work,
            ),
            groupMember: const <V2TimGroupMemberFullInfo>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The local-pick camera badge signals the avatar is tappable (the toxee
      // override, not the upstream preset grid).
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget,
          reason: 'the group avatar must show the local-pick camera badge');
      expect(find.byType(GestureDetector), findsWidgets,
          reason: 'the avatar must be wrapped in a tap target');
    },
  );

  // S142 — the group member-info body exposes a keyed Copy-ID button that puts
  // the member's Tox id on the clipboard (toxee added it to the fork; the only
  // prior copy path was the member-LIST desktop right-click, leaving mobile
  // users no way to copy a member id).
  testWidgets(
    'S142 group member info copy-id button copies the member id to the clipboard',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? clipboardText;
      messenger.setMockMethodCallHandler(SystemChannels.platform,
          (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final member = V2TimGroupMemberFullInfo(
        userID: 'bob',
        nickName: 'Bob',
        role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
        joinTime: 0,
      );
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupMemberInfoBody(memberFullInfo: member),
        ),
      );
      await tester.pumpAndSettle();

      final copyBtn = find.byKey(UiKeys.groupMemberInfoCopyIdButton);
      expect(copyBtn, findsOneWidget);

      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(clipboardText, 'bob',
          reason: 'copy button should put the member userID on the clipboard');
    },
  );

}
