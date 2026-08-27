import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data_notifier.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/desktop/tencent_cloud_chat_message_input_desktop.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

/// Pins the desktop composer's @-mention insertion against the two ways the
/// macOS real-UI case `group_at_member_send` lost its label inside a long
/// bundle (2026-08-23/24): a composer selection of -1 / 0 when the mention
/// panel row is tapped (`lastIndexOf('@', -2)` threw RangeError in the gesture
/// callback), and a second selection of the SAME member being ignored because
/// `membersNeedToMention` was compared by value instead of consumed as an
/// event.
Widget _localized({required Widget child}) {
  return MaterialApp(
    localizationsDelegates: const [
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

MessageInputBuilderMethods _methods() {
  return MessageInputBuilderMethods(
    sendTextMessage: ({required String text, List<String>? mentionedUsers}) {},
    sendImageMessage:
        ({String? imagePath, String? imageName, dynamic inputElement}) {},
    sendVideoMessage: ({String? videoPath, dynamic inputElement}) {},
    sendFileMessage:
        ({String? filePath, String? fileName, dynamic inputElement}) {},
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

MessageInputBuilderData _data({
  List<V2TimGroupMemberFullInfo>? membersNeedToMention,
}) {
  return MessageInputBuilderData(
    groupID: 'tox_1',
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
    membersNeedToMention: membersNeedToMention,
    currentConversationShowName: 'Group One',
    hasStickerPlugin: false,
    stickerPluginInstance: null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  final bob = V2TimGroupMemberFullInfo(userID: 'bob', nickName: 'Bob');

  Future<TextEditingController> pump(
    WidgetTester tester,
    TencentCloudChatMessageSeparateDataProvider provider, {
    List<V2TimGroupMemberFullInfo>? mention,
  }) async {
    await tester.pumpWidget(
      _localized(
        child: TencentCloudChatMessageDataProviderInherited(
          dataProvider: provider,
          child: TencentCloudChatMessageInputDesktop(
            inputData: _data(membersNeedToMention: mention),
            inputMethods: _methods(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<ExtendedTextField>(
      find.byType(ExtendedTextField).first,
    );
    return field.controller!;
  }

  testWidgets('a panel selection with an invalid selection still inserts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = TencentCloudChatMessageSeparateDataProvider();
    final controller = await pump(tester, provider);

    // Type "@" through the field so the composer enters at-search mode, then
    // invalidate the selection the way a programmatic text set / focus move
    // does before the panel row is tapped.
    await tester.tap(find.byType(ExtendedTextField).first);
    await tester.pump();
    tester.testTextInput.enterText('@');
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: -1);

    await pump(tester, provider, mention: [bob]);
    expect(tester.takeException(), isNull);
    expect(controller.text, '@Bob ');
  });

  testWidgets('selecting the same member twice inserts twice', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = TencentCloudChatMessageSeparateDataProvider();
    final controller = await pump(tester, provider);

    await pump(tester, provider, mention: [bob]);
    expect(controller.text, contains('@Bob '));
    // A second selection hands the composer a NEW list with equal contents —
    // it is an event and must be consumed again.
    await pump(tester, provider, mention: [bob]);
    expect(tester.takeException(), isNull);
    expect('@Bob '.allMatches(controller.text).length, 2);
  });
}
