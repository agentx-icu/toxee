// Actual UIKit bubbles/composer and production appearance controls, with optional
// PNG capture. No account, transport or real SDK calls are made.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:extended_text_field/extended_text_field.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/desktop/tencent_cloud_chat_message_input_desktop.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/message_type_builders/tencent_cloud_chat_message_text.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data_notifier.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:toxee/ui/app_theme_data.dart';
import 'package:toxee/ui/settings/appearance_settings_section.dart';
import 'package:toxee/util/appearance_sync.dart';
import 'package:toxee/util/interface_style.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/theme_controller.dart';

MessageItemBuilderData bubbleData(bool sent) => MessageItemBuilderData(
  message: V2TimMessage(
    msgID: sent ? 'sent' : 'received',
    elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    isSelf: sent,
    sender: sent ? 'self' : 'friend',
    // A LOCAL wall-clock 3 PM: the metadata lookup below keys on the "PM"
    // marker, and a fixed epoch renders as AM on a UTC runner (CI) but PM
    // at UTC+8 (the dev Mac).
    timestamp: DateTime(2026, 10, 1, 15).millisecondsSinceEpoch ~/ 1000,
    textElem: V2TimTextElem(
      text: sent
          ? 'Sounds good. See you tomorrow!'
          : 'Shall we meet tomorrow afternoon?',
    ),
  ),
  userID: 'friend',
  altText: '[message]',
  enableParseMarkdown: false,
  showMessageStatusIndicator: true,
  showMessageTimeIndicator: true,
  shouldBeHighlighted: false,
  showMessageSenderName: false,
  messageRowWidth: 680,
  renderOnMenuPreview: false,
  inSelectMode: false,
  inMergerMessagePreviewMode: false,
  hasStickerPlugin: false,
);
final bubbleMethods = MessageItemBuilderMethods(
  clearHighlightFunc: () {},
  triggerLinkTappedEvent: (_) {},
  onResendMessage: () {},
  setMessageTextWithMentions:
      ({
        required String messageText,
        required List<String> groupMembersNeedToMention,
      }) {},
);
MessageInputBuilderData inputData() => MessageInputBuilderData(
  userID: 'friend',
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
  currentConversationShowName: 'Alex',
  hasStickerPlugin: false,
  stickerPluginInstance: null,
);
MessageInputBuilderMethods inputMethods() => MessageInputBuilderMethods(
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

ThemeData captureTheme(ThemeData base) {
  const dir = String.fromEnvironment('TOXEE_STYLE_CAPTURE_DIR');
  if (dir.isEmpty) return base;
  ButtonStyle withFont(ButtonStyle style) => style.copyWith(
    textStyle: WidgetStateProperty.all(
      const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: withFont(base.filledButtonTheme.style!),
    ),
    textButtonTheme: TextButtonThemeData(
      style: withFont(base.textButtonTheme.style!),
    ),
  );
}

Widget shell(
  GlobalKey capture,
  TencentCloudChatMessageSeparateDataProvider provider,
) => AnimatedBuilder(
  animation: AppTheme.changes,
  builder: (context, _) => MaterialApp(
    theme: captureTheme(buildLightTheme()),
    darkTheme: captureTheme(buildDarkTheme()),
    themeMode: AppTheme.mode.value,
    locale: const Locale('en'),
    themeAnimationDuration: Duration.zero,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) {
          TencentCloudChatIntl().init(context);
          return RepaintBoundary(
            key: capture,
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const ListTile(
                            leading: CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text('Alex'),
                            subtitle: Text('Online'),
                          ),
                          const Divider(),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TencentCloudChatMessageText(
                              data: bubbleData(false),
                              methods: bubbleMethods,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TencentCloudChatMessageText(
                              data: bubbleData(true),
                              methods: bubbleMethods,
                            ),
                          ),
                          const Spacer(),
                          TencentCloudChatMessageDataProviderInherited(
                            dataProvider: provider,
                            child: TencentCloudChatMessageInputDesktop(
                              key: const Key('real_composer'),
                              inputData: inputData(),
                              inputMethods: inputMethods(),
                              debugDraftPersistenceOnly: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 420,
                    child: SingleChildScrollView(
                      child: AppearanceSettingsSection(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('all styles render real chat widgets and retain the composer', (
    tester,
  ) async {
    setNativeLibraryName('tim2tox_ffi');
    const captureDir = String.fromEnvironment('TOXEE_STYLE_CAPTURE_DIR');
    if (captureDir.isNotEmpty) {
      await tester.runAsync(() async {
        final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
        final icons = File(
          '/Users/bin.gao/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (await icons.exists()) {
          await ui.loadFontFromList(
            await icons.readAsBytes(),
            fontFamily: 'MaterialIcons',
          );
        }
        if (await font.exists()) {
          await ui.loadFontFromList(
            await font.readAsBytes(),
            fontFamily: 'Roboto',
          );
        }
      });
    }
    SharedPreferences.setMockInitialValues({});
    await Prefs.initialize(await SharedPreferences.getInstance());
    await AppTheme.initFromPrefs();
    tester.view.physicalSize = const Size(1200, 1160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
    TencentCloudChatScreenAdapter.hasInitialized = true;
    addTearDown(() {
      TencentCloudChatScreenAdapter.deviceScreenType = null;
      TencentCloudChatScreenAdapter.hasInitialized = false;
    });
    TencentCloudChat.instance.dataInstance.basic.updateCurrentUserInfo(
      userFullInfo: V2TimUserFullInfo(userID: 'self'),
    );
    AppTheme.changes.addListener(syncUIKitAppearance);
    addTearDown(() => AppTheme.changes.removeListener(syncUIKitAppearance));
    syncUIKitAppearance();
    final capture = GlobalKey();
    final provider = TencentCloudChatMessageSeparateDataProvider();
    await tester.pumpWidget(shell(capture, provider));
    await tester.pumpAndSettle();
    final composerState = tester.state(find.byKey(const Key('real_composer')));
    final controller = tester
        .widget<ExtendedTextField>(find.byType(ExtendedTextField))
        .controller!;
    controller.text = 'A draft stays here';
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 7);
    for (final style in InterfaceStyle.values) {
      for (final brightness in Brightness.values) {
        await tester.runAsync(
          () => AppTheme.setAppearance(
            style: style,
            mode: brightness == Brightness.light
                ? ThemeMode.light
                : ThemeMode.dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$style $brightness');
        expect(
          tester.state(find.byKey(const Key('real_composer'))),
          same(composerState),
        );
        expect(controller.text, 'A draft stays here');
        expect(
          controller.selection,
          const TextSelection(baseOffset: 2, extentOffset: 7),
        );
        final metadata = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(TencentCloudChatMessageText),
                matching: find.byType(Text),
              ),
            )
            .where((t) => t.data?.contains('PM') ?? false)
            .toList();
        expect(metadata, hasLength(2));
        for (final label in metadata) {
          expect(
            label.style!.color!.a,
            1,
            reason: 'required timestamps must retain the palette contrast',
          );
          expect(label.style!.fontSize, greaterThanOrEqualTo(12));
        }
        final p = style.palette(brightness);
        final boxes = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(TencentCloudChatMessageText),
                matching: find.byType(Container),
              ),
            )
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .where((d) => d.color == p.sent || d.color == p.received)
            .toList();
        expect(boxes, hasLength(2));
        for (final box in boxes) {
          final sent = box.color == p.sent;
          expect(
            box.borderRadius,
            TencentCloudChat.instance.dataInstance.theme.themeModel.visualStyle
                .bubbleBorderRadius(sent),
          );
          if (style == InterfaceStyle.cartoon) {
            expect((box.border as Border).top.width, 2);
          }
        }
        const directory = String.fromEnvironment('TOXEE_STYLE_CAPTURE_DIR');
        if (directory.isNotEmpty) {
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final frame = await boundary.toImage(pixelRatio: 1);
            final bytes = await frame.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(directory).create(recursive: true);
            await File(
              '$directory/${style.name}-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            frame.dispose();
          });
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
