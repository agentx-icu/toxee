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
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_mobile.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

/// The follow-up recorded by PR #81: `mobile_mention_deletion_clears_token`
/// could only pin the TEXT contract, because `_mentionedUsers` pruning is
/// invisible on the toxee wire — a Tox group message carries no
/// `groupAtUserList`, so "the token is gone from the text" was the only
/// observable the real-UI case had. The pruning itself is what matters: if a
/// deleted mention stayed in `_mentionedUsers`, the send would still address
/// a member the user removed.
///
/// This pins it where it IS observable — the `mentionedUsers` argument the
/// composer hands `sendTextMessage` — on BOTH composers, because the two
/// implementations carry their own copy of the same logic
/// (`..._input_mobile.dart` and `..._input_desktop.dart`).
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

MessageInputBuilderMethods _methods({
  required void Function(String text, List<String>? mentionedUsers) onSend,
}) {
  return MessageInputBuilderMethods(
    sendTextMessage: ({required String text, List<String>? mentionedUsers}) =>
        onSend(text, mentionedUsers),
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
  final carol = V2TimGroupMemberFullInfo(userID: 'carol', nickName: 'Carol');

  /// Deletes one character from inside the FIRST mention token, the way a real
  /// backspace does.
  ///
  /// It goes through `tester.enterText` — the platform text-input path — and
  /// NOT through the controller, because the two composers listen differently:
  /// mobile registers a controller listener (a programmatic write reaches it),
  /// desktop passes `onChanged:` to the field (a programmatic write does NOT).
  /// Driving the controller directly would silently skip the desktop handler
  /// and make this test claim a pass it never earned.
  Future<void> backspaceInsideToken(
    WidgetTester tester,
    TextEditingController controller,
    String token,
  ) async {
    final start = controller.text.indexOf(token);
    expect(start, isNonNegative, reason: 'token "$token" is not in the text');
    final cut = start + token.length - 1;
    final field = tester.widget<ExtendedTextField>(
      find.byType(ExtendedTextField).first,
    );
    // Reproduce what the framework does for a real keystroke: update the
    // editing value, THEN notify the field's onChanged. `tester.enterText` is
    // not usable here — it needs an `EditableText` state and this composer is
    // built on `ExtendedEditableText`, which is the same reason the fork's own
    // harness seams exist. Mobile listens on the controller (so the write
    // above is enough); desktop only gets `onChanged:`, and driving the
    // controller alone would silently skip its handler.
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(cut, cut + 1, ''),
      selection: TextSelection.collapsed(offset: cut),
    );
    await tester.pump();
    field.onChanged?.call(controller.text);
    await tester.pumpAndSettle();
  }

  group('mobile composer', () {
    testWidgets('deleting a mention token drops that user from the send', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? sentText;
      List<String>? sentMentions;
      final provider = TencentCloudChatMessageSeparateDataProvider();

      Future<TextEditingController> pump({
        List<V2TimGroupMemberFullInfo>? mention,
      }) async {
        await tester.pumpWidget(
          _localized(
            child: TencentCloudChatMessageDataProviderInherited(
              dataProvider: provider,
              child: TencentCloudChatMessageInputMobile(
                inputData: _data(membersNeedToMention: mention),
                inputMethods: _methods(
                  onSend: (text, mentions) {
                    sentText = text;
                    sentMentions = mentions;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester
            .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
            .controller!;
      }

      final controller = await pump();
      await pump(mention: [bob]);
      await pump(mention: [carol]);
      expect(controller.text, contains('@Bob '));
      expect(controller.text, contains('@Carol '));

      await backspaceInsideToken(tester, controller, '@Bob');

      // The composer removes the whole token, not just the typed character —
      // asserting `isNot(contains('@Bob'))` alone would pass on the mere
      // one-character deletion ('@Bo'), which is the bug this pins.
      expect(controller.text.replaceAll(' ', ''), '@Carol');

      expect(debugRealUiMobileComposerSend, isNotNull,
          reason: 'the mounted composer registers its send seam in debug');
      debugRealUiMobileComposerSend!();
      await tester.pumpAndSettle();

      expect(sentText, isNotNull);
      expect(sentMentions, isNotNull);
      expect(sentMentions, ['carol'],
          reason: 'the deleted mention must not be addressed any more — the '
              'part the toxee wire cannot show, since a Tox group message '
              'carries no groupAtUserList');
    });
  });

  group('desktop composer', () {
    testWidgets('deleting a mention token drops that user from the send', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? sentText;
      List<String>? sentMentions;
      final provider = TencentCloudChatMessageSeparateDataProvider();

      Future<TextEditingController> pump({
        List<V2TimGroupMemberFullInfo>? mention,
      }) async {
        await tester.pumpWidget(
          _localized(
            child: TencentCloudChatMessageDataProviderInherited(
              dataProvider: provider,
              child: TencentCloudChatMessageInputDesktop(
                inputData: _data(membersNeedToMention: mention),
                inputMethods: _methods(
                  onSend: (text, mentions) {
                    sentText = text;
                    sentMentions = mentions;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester
            .widget<ExtendedTextField>(find.byType(ExtendedTextField).first)
            .controller!;
      }

      final controller = await pump();
      await pump(mention: [bob]);
      await pump(mention: [carol]);
      expect(controller.text, contains('@Bob '));
      expect(controller.text, contains('@Carol '));

      await backspaceInsideToken(tester, controller, '@Bob');

      expect(controller.text.replaceAll(' ', ''), '@Carol');

      expect(debugRealUiDesktopComposerSend, isNotNull,
          reason: 'the mounted composer registers its send seam in debug');
      debugRealUiDesktopComposerSend!();
      await tester.pumpAndSettle();

      expect(sentText, isNotNull);
      expect(sentMentions, ['carol'],
          reason: 'desktop carries its own copy of the prune logic and must '
              'behave identically');
    });
  });
}
