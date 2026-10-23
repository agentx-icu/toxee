import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data_notifier.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/desktop/tencent_cloud_chat_message_input_desktop.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final entry in [
    (LogicalKeyboardKey.controlLeft, TargetPlatform.windows, 'windows'),
    (LogicalKeyboardKey.controlRight, TargetPlatform.windows, 'windows'),
    (LogicalKeyboardKey.metaLeft, TargetPlatform.macOS, 'macos'),
    (LogicalKeyboardKey.metaRight, TargetPlatform.macOS, 'macos'),
  ]) {
    testWidgets(
      '${entry.$1.keyLabel} V reads resources on down once and preserves default text paste',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var imageReads = 0;
        var fileReads = 0;
        var textReads = 0;
        messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (
          call,
        ) async {
          if (call.method == 'image') {
            imageReads++;
            return null;
          }
          if (call.method == 'files') {
            fileReads++;
            return <String>[];
          }
          throw StateError(
            'Unexpected resource clipboard operation ${call.method}',
          );
        });
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.getData') {
            textReads++;
            return {'text': 'pasted text'};
          }
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(
            const MethodChannel('pasteboard'),
            null,
          );
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        });
        final scroll = AutoScrollController();
        final provider = TencentCloudChatMessageSeparateDataProvider();
        final methods = MessageInputBuilderMethods(
          sendTextMessage:
              ({required String text, List<String>? mentionedUsers}) {},
          sendImageMessage:
              ({String? imagePath, String? imageName, dynamic inputElement}) {},
          sendVideoMessage: ({String? videoPath, dynamic inputElement}) {},
          sendFileMessage:
              ({String? filePath, String? fileName, dynamic inputElement}) {},
          sendVoiceMessage:
              ({required String voicePath, required int duration}) {},
          onChooseGroupMembers: () async => <V2TimGroupMemberFullInfo>[],
          controller: Object(),
          clearRepliedMessage: () {},
          setDesktopMentionBoxPositionX: (_) {},
          setDesktopMentionBoxPositionY: (_) {},
          setActiveMentionIndex: (_) {},
          setCurrentFilteredMembersListForMention: (_) {},
          desktopInputMemberSelectionPanelScroll: scroll,
          messageAttachmentOptionsBuilder: Object(),
          closeSticker: () {},
        );
        final data = MessageInputBuilderData(
          userID: 'paste-fixture',
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
          currentConversationShowName: 'Fixture',
          hasStickerPlugin: false,
          stickerPluginInstance: null,
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates:
                TencentCloudChatLocalizations.localizationsDelegates,
            supportedLocales: TencentCloudChatLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  TencentCloudChatIntl().init(context);
                  return TencentCloudChatMessageDataProviderInherited(
                    dataProvider: provider,
                    child: TencentCloudChatMessageInputDesktop(
                      inputData: data,
                      inputMethods: methods,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.byType(ExtendedTextField).first;
        await tester.tap(field);
        await tester.pump();
        tester.testTextInput.enterText('before ');
        await tester.pump();
        textReads = imageReads = fileReads = 0;
        await tester.sendKeyDownEvent(entry.$1, platform: entry.$3);
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.keyV,
          platform: entry.$3,
        );
        await tester.pumpAndSettle();
        expect(imageReads, 1);
        expect(fileReads, 1);
        expect(
          textReads,
          1,
          reason:
              'the existing framework PasteTextIntent remains the only text insertion',
        );
        expect(
          tester.widget<ExtendedTextField>(field).controller!.text,
          'before pasted text',
        );
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.keyV,
          platform: entry.$3,
        );
        await tester.pumpAndSettle();
        expect(
          imageReads,
          1,
          reason: 'key-up must not start another resource read',
        );
        expect(fileReads, 1);
        expect(textReads, 1);
        await tester.sendKeyUpEvent(entry.$1, platform: entry.$3);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        scroll.dispose();
        provider.dispose();
      },
      variant: TargetPlatformVariant.only(entry.$2),
    );
  }
}
