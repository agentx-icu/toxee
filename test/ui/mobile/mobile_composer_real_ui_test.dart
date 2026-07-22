// Real-UI widget tests for the MOBILE composer (fork
// `TencentCloudChatMessageInputMobile`) — the phone-shaped send + attachment
// surface the desktop composer gate does NOT cover. Mobile parity is hard
// policy and the suite is desktop-leaning; this file gates the two mobile-only
// composer affordances directly on the production widget:
//
//   1. Type text -> the real animated send button appears -> tapping it drives
//      the production `sendTextMessage` seam (NOT a debug bypass). Proves the
//      send button is gated on non-empty text (typing alone with an empty field
//      shows the press-to-record mic, not the send arrow).
//   2. Tap the real attachment "+" -> the production attachment-options overlay
//      mounts the REAL `TencentCloudChatMessageAttachmentOptionsWidget` with the
//      photo/file options -> tapping an option invokes its production picker
//      seam (`onTap`). The native picker is never opened: the option `onTap`
//      IS the seam the mobile input consumes, so capturing it proves the wiring
//      without binding image_picker / file_picker to a real platform channel.
//
// Pumps the REAL fork widget under a mobile-sized surface; drives REAL taps /
// text entry; captures the production callbacks. No production logic is
// re-implemented here.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_controller.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_attachment_options.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_mobile.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

// Wrap a child so the UIKit fork's i18n singleton (`tL10n`) is initialized from
// a real Localizations ancestor before the child builds — the fork composer
// reads `tL10n` during build and throws if it is uninitialized. (Copied from
// test/ui/chat_core_real_ui_test.dart per the harness rule: do not import
// another test file's private helpers.)
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

// Records the production callbacks the mobile composer drives. Only the fields
// this file asserts on are captured; the rest are inert stubs.
class _RecordingMethods {
  final List<String> sentText = [];

  MessageInputBuilderMethods build() {
    return MessageInputBuilderMethods(
      sendTextMessage: ({required String text, List<String>? mentionedUsers}) {
        sentText.add(text);
      },
      sendImageMessage:
          ({String? imagePath, String? imageName, dynamic inputElement}) {},
      sendVideoMessage: ({String? videoPath, dynamic inputElement}) {},
      sendFileMessage:
          ({String? filePath, String? fileName, dynamic inputElement}) {},
      sendVoiceMessage: ({required String voicePath, required int duration}) {},
      onChooseGroupMembers: () async => <V2TimGroupMemberFullInfo>[],
      clearRepliedMessage: () {},
      setDesktopMentionBoxPositionX: (_) {},
      setDesktopMentionBoxPositionY: (_) {},
      setActiveMentionIndex: (_) {},
      setCurrentFilteredMembersListForMention: (_) {},
      // A REAL message controller: the mobile composer casts
      // `inputMethods.controller as TencentCloudChatMessageController` on field
      // tap (scrollToBottom) and on text change (setDraft). Both go through the
      // event bus; with userID/groupID null below, setDraft early-returns so no
      // SDK conversation manager is hit.
      controller: TencentCloudChatMessageControllerGenerator.getInstance(),
      desktopInputMemberSelectionPanelScroll: AutoScrollController(),
      // The REAL production attachment-options widget; this is the same widget
      // the default UIKit builder returns (tencent_cloud_chat_message_builders
      // getAttachmentOptionsBuilder). It renders whatever options it is given
      // and invokes their `onTap` on tap — exactly the seam the mobile input
      // consumes.
      messageAttachmentOptionsBuilder:
          ({
            Key? key,
            MessageAttachmentOptionsBuilderWidgets? widgets,
            required MessageAttachmentOptionsBuilderData data,
            required MessageAttachmentOptionsBuilderMethods methods,
          }) => TencentCloudChatMessageAttachmentOptionsWidget(
            key: key,
            data: data,
            methods: methods,
          ),
      closeSticker: () {},
    );
  }
}

MessageInputBuilderData _data({
  List<TencentCloudChatMessageGeneralOptionItem> attachmentOptions = const [],
}) {
  return MessageInputBuilderData(
    // userID/groupID intentionally null: the composer's _updateDraft early
    // returns when there is no conversation id, so tapping/typing does not call
    // through to the SDK conversation-draft manager (unavailable hermetically).
    // The send path (sendTextMessage) and the attachment overlay are
    // independent of the conversation id.
    userID: null,
    groupID: null,
    attachmentOptions: attachmentOptions,
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
    hasStickerPlugin: false,
    stickerPluginInstance: null,
  );
}

Future<TextEditingController> _focusComposerAndEnterText(
  WidgetTester tester,
  String text,
) async {
  final field = find.byType(ExtendedTextField);
  expect(field, findsOneWidget);
  await tester.tap(field);
  await tester.pump();
  tester.testTextInput.enterText(text);
  await tester.pump();
  return tester.widget<ExtendedTextField>(field).controller!;
}

Future<void> _pressModifiedEnter(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
) async {
  await tester.sendKeyDownEvent(modifier);
  try {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  } finally {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Match production: the fork SDK model loads the tim2tox FFI lib by name.
  // Harmless here (this file constructs no V2TimMessage) but keeps process
  // state consistent with the rest of the real-UI suite.
  setNativeLibraryName('tim2tox_ffi');

  // Mobile-sized surface so the mobile composer lays out like a phone. Reset
  // in tearDown so other suites are unaffected.
  void useMobileSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'mobile composer: empty field shows mic, typing reveals send button, tap drives sendTextMessage',
    (tester) async {
      useMobileSurface(tester);
      final methods = _RecordingMethods();

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputMobile(
            inputData: _data(),
            inputMethods: methods.build(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Empty field: the trailing affordance is the press-to-record mic, NOT
      // the send arrow (the send button is gated on non-empty text).
      expect(
        find.byIcon(Icons.mic),
        findsOneWidget,
        reason: 'empty composer should show the record affordance',
      );
      expect(
        find.byIcon(Icons.arrow_upward_rounded),
        findsNothing,
        reason: 'send button must not render for an empty field',
      );

      // Type into the REAL composer field. The fork uses ExtendedTextField
      // whose editable is ExtendedEditableText (not stock EditableText), so
      // tester.enterText cannot find an EditableTextState — focus via tap then
      // deliver text through the established text-input connection (same
      // approach as the desktop composer gate).
      final field = find.byType(ExtendedTextField);
      expect(field, findsOneWidget);
      await tester.tap(field);
      await tester.pump();
      tester.testTextInput.enterText('mobile-hello');
      await tester.pumpAndSettle();

      // The send button is now revealed by the real _onTextChanged ->
      // _showSendButton animation, and the mic is hidden.
      final sendBtn = find.byIcon(Icons.arrow_upward_rounded);
      expect(
        sendBtn,
        findsOneWidget,
        reason: 'non-empty text should reveal the send button',
      );
      expect(find.byIcon(Icons.mic), findsNothing);

      // Typing alone must NOT have sent — proves the assertion below is driven
      // by the real tap, not by text entry.
      expect(methods.sentText, isEmpty, reason: 'typing should not send');

      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(
        methods.sentText,
        contains('mobile-hello'),
        reason: 'tapping the send button drives the production send path',
      );
    },
  );

  testWidgets(
    'mobile composer: attachment "+" opens the real options overlay; tapping an option drives its picker seam',
    (tester) async {
      useMobileSurface(tester);

      String? pickedLabel;
      // Real attachment options as the mobile composer consumes them: each
      // item's `onTap` is the production picker entry point. We record which
      // fired instead of launching a native picker — the option `onTap` IS the
      // seam, so this is faithful and no real image_picker / file_picker
      // channel is touched.
      final options = <TencentCloudChatMessageGeneralOptionItem>[
        TencentCloudChatMessageGeneralOptionItem(
          icon: Icons.image,
          label: 'Photo',
          onTap: ({Offset? offset}) => pickedLabel = 'Photo',
        ),
        TencentCloudChatMessageGeneralOptionItem(
          icon: Icons.insert_drive_file,
          label: 'File',
          onTap: ({Offset? offset}) => pickedLabel = 'File',
        ),
      ];

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputMobile(
            inputData: _data(attachmentOptions: options),
            inputMethods: _RecordingMethods().build(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The options overlay is not shown until the "+" is tapped.
      expect(find.text('Photo'), findsNothing);
      expect(find.text('File'), findsNothing);

      // Tap the REAL attachment button — its onTapDown drives the production
      // toggleAttachmentOptionsOverlay, inserting the overlay.
      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await tester.pumpAndSettle();

      // The REAL TencentCloudChatMessageAttachmentOptionsWidget renders the
      // photo + file options.
      expect(
        find.byType(TencentCloudChatMessageAttachmentOptionsWidget),
        findsOneWidget,
      );
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(pickedLabel, isNull, reason: 'opening the menu must not pick');

      // Tap the photo option -> the production picker seam (item.onTap) fires.
      await tester.tap(find.text('Photo'));
      await tester.pumpAndSettle();

      expect(
        pickedLabel,
        'Photo',
        reason:
            'tapping an attachment option drives its production picker seam',
      );
    },
  );

  testWidgets(
    'mobile composer: hardware Enter sends through the production text path',
    (tester) async {
      useMobileSurface(tester);
      final methods = _RecordingMethods();

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputMobile(
            inputData: _data(),
            inputMethods: methods.build(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = await _focusComposerAndEnterText(
        tester,
        'hardware-enter',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(methods.sentText, ['hardware-enter']);
      expect(
        controller.text,
        isEmpty,
        reason: 'keyboard send must clear the composer like the send button',
      );
    },
  );

  testWidgets(
    'mobile composer: modifier plus Enter inserts a newline without sending',
    (tester) async {
      useMobileSurface(tester);
      final methods = _RecordingMethods();

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputMobile(
            inputData: _data(),
            inputMethods: methods.build(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = await _focusComposerAndEnterText(tester, 'line');
      for (final modifier in <LogicalKeyboardKey>[
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        controller.value = const TextEditingValue(
          text: 'line',
          selection: TextSelection.collapsed(offset: 4),
        );
        await _pressModifiedEnter(tester, modifier);
        expect(
          controller.text,
          'line\n',
          reason: '$modifier + Enter must insert exactly one newline',
        );
        expect(
          methods.sentText,
          isEmpty,
          reason: '$modifier + Enter must never send',
        );
      }
    },
  );

  testWidgets(
    'mobile composer: Enter is ignored while an IME composition is active',
    (tester) async {
      useMobileSurface(tester);
      final methods = _RecordingMethods();

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputMobile(
            inputData: _data(),
            inputMethods: methods.build(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = await _focusComposerAndEnterText(tester, 'ni');
      controller.value = const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(methods.sentText, isEmpty);
      expect(
        controller.text,
        'ni',
        reason: 'composer must leave the active IME composition untouched',
      );
      expect(controller.value.composing, const TextRange(start: 0, end: 2));
    },
  );

  testWidgets(
    'mobile composer: hardware Enter respects empty and byte-limit send gates',
    (tester) async {
      useMobileSurface(tester);
      final methods = _RecordingMethods();

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputMobile(
            inputData: _data(),
            inputMethods: methods.build(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = await _focusComposerAndEnterText(tester, '');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(methods.sentText, isEmpty, reason: 'empty Enter must not send');

      final overLimit = 'x' * 1373;
      controller.value = TextEditingValue(
        text: overLimit,
        selection: TextSelection.collapsed(offset: overLimit.length),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(
        methods.sentText,
        isEmpty,
        reason: 'hardware Enter must not bypass the Tox byte limit',
      );
      expect(
        controller.text,
        overLimit,
        reason: 'rejected keyboard send must preserve the draft',
      );
    },
  );
}
