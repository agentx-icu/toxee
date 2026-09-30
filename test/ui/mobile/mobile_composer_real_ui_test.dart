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
import 'dart:async';

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
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_layout/tencent_cloud_chat_message_layout.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data_notifier.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_builders.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
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

  /// When set, each text send stays in flight until this completes.
  Completer<void>? inFlight;

  /// Texts whose send reports failure (after [inFlight], if set).
  final Set<String> failing = {};

  MessageInputBuilderMethods build() {
    return MessageInputBuilderMethods(
      sendTextMessage: ({required String text, List<String>? mentionedUsers}) {
        sentText.add(text);
        final gate = inFlight?.future;
        if (!failing.contains(text)) return gate;
        return gate == null ? Future<bool>.value(false) : gate.then((_) => false);
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
  V2TimMessage? repliedMessage,
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
    repliedMessage: repliedMessage,
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

/// Press Enter (optionally with [modifier]) the way a hardware keyboard does:
/// when the framework leaves the press unhandled, the platform text input then
/// inserts `\n` at the caret of the multiline field (iOS UIKit `insertText:`,
/// Android `InputConnectionAdaptor.handleKeyEvent`). [platformText] is the
/// field text as the PLATFORM has it by then — it can be ahead of the
/// controller when characters typed just before Enter are still in flight.
Future<void> _pressEnter(
  WidgetTester tester,
  TextEditingController controller, {
  LogicalKeyboardKey? modifier,
  String? platformText,
}) async {
  if (modifier != null) await tester.sendKeyDownEvent(modifier);
  bool handled;
  try {
    handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
  } finally {
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
  if (platformText != null) {
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: platformText,
        selection: TextSelection.collapsed(offset: platformText.length),
      ),
    );
    await tester.pump();
  }
  if (!handled) {
    final value = controller.value;
    final caret = value.selection.isValid
        ? value.selection.baseOffset
        : value.text.length;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: value.text.replaceRange(caret, caret, '\n'),
        selection: TextSelection.collapsed(offset: caret + 1),
      ),
    );
    await tester.pump();
  }
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
    'mobile composer inside the REAL message layout keeps its fixed content '
    'with the keyboard up (landscape phone, reply bar + multi-line text)',
    (tester) async {
      // Layout-overflow audit M-M1 / codex round 2: the layout bounds the
      // input so the list keeps a strip, but a keyboard-shrunk body (~114 px
      // on a landscape phone) must go to the composer's fixed content — the
      // old unconditional 96-px reservation left it 18 px. Mounted through
      // the real TencentCloudChatMessageLayout (the host that applies the
      // cap); the other cases in this file mount the input directly.
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 216);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.mobile;
      TencentCloudChatScreenAdapter.hasInitialized = true;
      addTearDown(() {
        TencentCloudChatScreenAdapter.deviceScreenType = null;
        TencentCloudChatScreenAdapter.hasInitialized = false;
      });

      final methods = _RecordingMethods();
      // fromJson: the V2TimMessage constructor asks TIMManager for the server
      // time, which needs the native SDK library (absent under flutter test).
      final replied = V2TimMessage.fromJson({})
        ..msgID = 'reply-1'
        ..elemType = 1
        ..timestamp = 1
        ..sender = 'peer'
        ..nickName = 'Peer';
      const listKey = ValueKey('layout-test-list');
      // Production always has the message data provider above the composer;
      // the reply bar reads it in didChangeDependencies and renders through
      // its stock builders (without them the bar would be an empty Container
      // and add no height, weakening the gate).
      final provider = TencentCloudChatMessageSeparateDataProvider()
        ..messageBuilders = TencentCloudChatMessageBuilders();

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageDataProviderInherited(
            dataProvider: provider,
            child: TencentCloudChatMessageLayout(
              data: MessageLayoutBuilderData(
                currentConversationShowName: 'Friend One',
                desktopMentionBoxPositionX: 0,
                desktopMentionBoxPositionY: 0,
                activeMentionIndex: -1,
                currentFilteredMembersListForMention: const [],
                desktopStickerBoxPositionX: 0,
                desktopStickerBoxPositionY: 0,
                hasStickerPlugin: false,
              ),
              methods: MessageLayoutBuilderMethods(
                sendTextMessage:
                    ({required String text, List<String>? mentionedUsers}) {},
                sendImageMessage:
                    ({
                      String? imagePath,
                      String? imageName,
                      dynamic inputElement,
                    }) {},
                sendVideoMessage:
                    ({String? videoPath, dynamic inputElement}) {},
                sendFileMessage:
                    ({
                      String? filePath,
                      String? fileName,
                      dynamic inputElement,
                    }) {},
                sendVoiceMessage:
                    ({required String voicePath, required int duration}) {},
                desktopInputMemberSelectionPanelScroll: AutoScrollController(),
                onSelectMember: (_) {},
                closeSticker: () {},
              ),
              widgets: MessageLayoutBuilderWidgets(
                header: AppBar(title: const Text('Friend One')),
                messageListView: const ColoredBox(
                  key: listKey,
                  color: Colors.white,
                  child: SizedBox.expand(),
                ),
                messageInput: TencentCloudChatMessageInputMobile(
                  inputData: _data(repliedMessage: replied),
                  inputMethods: methods.build(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'the composer must fit the keyboard-shrunk body',
      );

      await _focusComposerAndEnterText(
        tester,
        'line one\nline two\nline three',
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'a multi-line draft under a reply bar must still fit',
      );

      final field = tester.getRect(find.byType(ExtendedTextField));
      final list = tester.getRect(find.byKey(listKey));
      expect(field.height, greaterThan(0));
      expect(
        list.bottom,
        lessThanOrEqualTo(field.top + 0.01),
        reason: 'the list yields; it never paints over the composer',
      );
      // Reply bar + three lines exceed the ~118-px body: the composer scrolls
      // anchored at the text field, which must stay fully above the keyboard.
      expect(
        field.bottom,
        lessThanOrEqualTo(390 - 216 + 0.01),
        reason: 'the text field stays visible above the keyboard',
      );
    },
  );

  group('desktop-builder chat on a landscape phone with the keyboard up', () {
    // A phone in landscape classifies as a desktop screen, so the fork
    // layout's DESKTOP builder hosts the chat: as the master-detail right pane
    // (inside the home shell's Scaffold, which consumes the keyboard inset)
    // and as a pushed route on a 720-800 dp phone (nothing consumes it). On
    // an API 36 emulator (914x411 dp, 262-dp keyboard) the right pane was
    // ~125 dp — less than header + composer — and overflowed by ~19 px. The
    // test host is a desktop OS, where the fork classifies by diagonal
    // (>= 11" = desktop), hence 1000x420 here.
    Future<void> pumpChat(
      WidgetTester tester, {
      required double keyboard,
      double? paneHeight,
      bool asRoute = false,
      bool reply = false,
    }) async {
      tester.view.physicalSize = const Size(1000, 420);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
      TencentCloudChatScreenAdapter.hasInitialized = true;
      addTearDown(() {
        TencentCloudChatScreenAdapter.deviceScreenType = null;
        TencentCloudChatScreenAdapter.hasInitialized = false;
      });
      final methods = _RecordingMethods();
      final provider = TencentCloudChatMessageSeparateDataProvider()
        ..messageBuilders = TencentCloudChatMessageBuilders();
      final replied = V2TimMessage.fromJson({})
        ..msgID = 'reply-1'
        ..elemType = 1
        ..timestamp = 1
        ..sender = 'peer'
        ..nickName = 'Peer';
      final layout = TencentCloudChatMessageDataProviderInherited(
        dataProvider: provider,
        child: TencentCloudChatMessageLayout(
          data: MessageLayoutBuilderData(
            currentConversationShowName: 'Friend One',
            desktopMentionBoxPositionX: 0,
            desktopMentionBoxPositionY: 0,
            activeMentionIndex: -1,
            currentFilteredMembersListForMention: const [],
            desktopStickerBoxPositionX: 0,
            desktopStickerBoxPositionY: 0,
            hasStickerPlugin: false,
          ),
          methods: MessageLayoutBuilderMethods(
            sendTextMessage:
                ({required String text, List<String>? mentionedUsers}) {},
            sendImageMessage:
                ({
                  String? imagePath,
                  String? imageName,
                  dynamic inputElement,
                }) {},
            sendVideoMessage: ({String? videoPath, dynamic inputElement}) {},
            sendFileMessage:
                ({String? filePath, String? fileName, dynamic inputElement}) {},
            sendVoiceMessage:
                ({required String voicePath, required int duration}) {},
            desktopInputMemberSelectionPanelScroll: AutoScrollController(),
            onSelectMember: (_) {},
            closeSticker: () {},
          ),
          widgets: MessageLayoutBuilderWidgets(
            header: AppBar(title: const Text('Friend One')),
            messageListView: const ColoredBox(
              key: ValueKey('pane-list'),
              color: Colors.white,
              child: SizedBox.expand(),
            ),
            messageInput: TencentCloudChatMessageInputMobile(
              inputData: _data(repliedMessage: reply ? replied : null),
              inputMethods: methods.build(),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        asRoute
            // A pushed chat route: the layout is the page, no outer Scaffold.
            ? MaterialApp(
                locale: const Locale('en'),
                supportedLocales: const [Locale('en')],
                localizationsDelegates: const [
                  TencentCloudChatLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: Builder(
                  builder: (context) {
                    TencentCloudChatIntl().init(context);
                    return layout;
                  },
                ),
              )
            : _localized(
                // The home shell: a Scaffold whose body hosts the right pane.
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topRight,
                    child: SizedBox(
                      width: 670,
                      height: paneHeight,
                      child: layout,
                    ),
                  ),
                ),
              ),
      );
      await tester.pumpAndSettle();
    }

    void expectFieldAboveKeyboard(WidgetTester tester, double keyboard) {
      final field = tester.getRect(find.byType(ExtendedTextField));
      expect(field.height, greaterThan(0));
      expect(
        field.bottom,
        lessThanOrEqualTo(420 - keyboard + 0.01),
        reason: 'the text field stays above the keyboard',
      );
    }

    testWidgets('right pane: the header yields, the composer fits', (
      tester,
    ) async {
      await pumpChat(tester, keyboard: 262);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the keyboard-shrunk pane must not overflow',
      );
      expect(
        find.text('Friend One'),
        findsNothing,
        reason: 'no room for the header while the keyboard is up',
      );
      expectFieldAboveKeyboard(tester, 262);
    });

    testWidgets('right pane: the header comes back when the keyboard closes', (
      tester,
    ) async {
      await pumpChat(tester, keyboard: 262);
      expect(find.text('Friend One'), findsNothing);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Friend One'), findsOneWidget);
    });

    testWidgets('the focused composer keeps focus as the keyboard opens', (
      tester,
    ) async {
      // Opening the keyboard switches the layout (header dropped, composer
      // bounded). If that changed the composer's ancestors, its element would
      // be rebuilt and lose focus — closing the keyboard it just opened
      // (seen on an API 36 emulator).
      await pumpChat(tester, keyboard: 0);
      await tester.tap(find.byType(ExtendedTextField));
      await tester.pumpAndSettle();
      bool fieldFocused() {
        final focused = FocusManager.instance.primaryFocus?.context;
        return focused != null &&
            find
                .descendant(
                  of: find.byType(ExtendedTextField),
                  matching: find.byWidget(focused.widget),
                )
                .evaluate()
                .isNotEmpty;
      }

      expect(fieldFocused(), isTrue, reason: 'tapping focuses the composer');
      tester.view.viewInsets = const FakeViewPadding(bottom: 262);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Friend One'), findsNothing);
      expect(
        fieldFocused(),
        isTrue,
        reason: 'the keyboard opening must not rebuild the composer',
      );
    });

    testWidgets('pushed route: the unconsumed inset is counted, no overflow', (
      tester,
    ) async {
      await pumpChat(tester, keyboard: 262, asRoute: true);
      expect(tester.takeException(), isNull);
      expect(find.text('Friend One'), findsNothing);
      expectFieldAboveKeyboard(tester, 262);
    });

    testWidgets(
      'just above the threshold: header kept, a reply bar and multi-line '
      'draft still fit',
      (tester) async {
        // 420 - 200 = 220 dp for header + body: not compact (56 + 140), so
        // the header stays and only the composer bound keeps things in.
        await pumpChat(tester, keyboard: 200, reply: true);
        expect(find.text('Friend One'), findsOneWidget);
        await _focusComposerAndEnterText(
          tester,
          'line one\nline two\nline three',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expectFieldAboveKeyboard(tester, 200);
      },
    );

    testWidgets('a short pane without a soft keyboard keeps its header', (
      tester,
    ) async {
      // Desktops have no soft keyboard: a short window is not a reason to
      // drop the header. (Overflow at this artificial height is not what
      // this case checks.)
      await pumpChat(tester, keyboard: 0, paneHeight: 149);
      tester.takeException();
      expect(find.text('Friend One'), findsOneWidget);
    });
  });

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
      await _pressEnter(tester, controller);

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
        tester.testTextInput.updateEditingValue(controller.value);
        await tester.pump();
        await _pressEnter(tester, controller, modifier: modifier);
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
      final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(handled, isFalse, reason: 'the IME owns this Enter');
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
      await _pressEnter(tester, controller);
      expect(methods.sentText, isEmpty, reason: 'empty Enter must not send');
      expect(controller.text, isEmpty, reason: 'nor leave a stray newline');

      final overLimit = 'x' * 1373;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: overLimit,
          selection: TextSelection.collapsed(offset: overLimit.length),
        ),
      );
      await tester.pump();
      await _pressEnter(tester, controller);

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

  testWidgets(
    'mobile composer: hardware Enter sends the text typed just before it '
    '(characters still in flight at key time)',
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

      // iPad simulator, 2026-09-29: "qwerty" + Enter without a pause sent
      // "qwe" — the framework saw Enter before UIKit had delivered "rty".
      final controller = await _focusComposerAndEnterText(tester, 'qwe');
      await _pressEnter(tester, controller, platformText: 'qwerty');

      expect(methods.sentText, ['qwerty']);
      expect(controller.text, isEmpty);

      // A letter typed right after Enter: the platform still held "qwerty\n"
      // when it inserted it (iPad simulator: "abc" Enter "h" left "abc\nh").
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'qwerty\nh',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      await tester.pump();
      expect(controller.text, 'h');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0)),
      );
      await tester.pump();

      // Shift+Enter the same way keeps the newline after the late characters.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      await _pressEnter(
        tester,
        controller,
        modifier: LogicalKeyboardKey.shiftLeft,
        platformText: 'abc',
      );
      expect(controller.text, 'abc\n');
      expect(methods.sentText, ['qwerty'], reason: 'Shift+Enter never sends');
    },
  );

  testWidgets(
    'mobile composer: a second hardware Enter while the first message is still '
    'being sent is queued, not dropped',
    (tester) async {
      useMobileSurface(tester);
      final methods = _RecordingMethods()..inFlight = Completer<void>();

      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputMobile(
            inputData: _data(),
            inputMethods: methods.build(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = await _focusComposerAndEnterText(tester, 'a');
      await _pressEnter(tester, controller);
      expect(methods.sentText, ['a']);

      // "b" + Enter before the first send finished; the platform still echoes
      // the first message ("a\nb", then "a\nb\n").
      await _pressEnter(tester, controller, platformText: 'a\nb');
      expect(methods.sentText, ['a'], reason: 'b waits for a');

      final first = methods.inFlight!;
      methods.inFlight = null;
      first.complete();
      await tester.pumpAndSettle();
      expect(methods.sentText, ['a', 'b']);
    },
  );

  group('mobile composer: hardware Enter in the middle of the draft, and failed sends', () {
    Future<(_RecordingMethods, TextEditingController)> pumpComposer(
      WidgetTester tester, {
      bool holdSends = true,
      Set<String> failing = const {},
    }) async {
      useMobileSurface(tester);
      final methods = _RecordingMethods();
      if (holdSends) methods.inFlight = Completer<void>();
      methods.failing.addAll(failing);
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
      return (methods, controller);
    }

    void platformUpdate(WidgetTester tester, String text, [int? caret]) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret ?? text.length),
        ),
      );
    }

    Future<void> finishSends(
      WidgetTester tester,
      _RecordingMethods methods,
    ) async {
      final held = methods.inFlight!;
      methods.inFlight = null;
      held.complete();
      await tester.pumpAndSettle();
    }

    testWidgets('a key typed right after a mid-draft Enter does not bring the '
        'sent message back', (tester) async {
      final (methods, controller) = await pumpComposer(tester);
      platformUpdate(tester, 'abcd', 2); // caret after "b"
      await tester.pump();
      await _pressEnter(tester, controller); // platform: "ab\ncd", caret 3
      expect(methods.sentText, ['abcd']);
      expect(controller.text, 'abcd', reason: 'kept until the send completes');

      // The platform still held "ab\ncd" when it inserted the next key.
      platformUpdate(tester, 'ab\nhcd', 4);
      await tester.pump();
      expect(controller.text, 'h');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));

      await finishSends(tester, methods);
      expect(controller.text, 'h');
      expect(methods.sentText, ['abcd']);
    });

    testWidgets('a failed send the user typed past is put back in front of '
        'the new text', (tester) async {
      final (methods, controller) =
          await pumpComposer(tester, failing: {'abc'});
      platformUpdate(tester, 'abc');
      await tester.pump();
      await _pressEnter(tester, controller);
      platformUpdate(tester, 'abc\nh'); // typed "h" within the echo
      await tester.pump();
      expect(controller.text, 'h');

      await finishSends(tester, methods);
      expect(controller.text, 'abc\nh', reason: 'the failed text is not lost');
      expect(controller.selection, const TextSelection.collapsed(offset: 5),
          reason: 'the caret stays after what the user typed');

      // Typing continues on the restored text (no rebase off it).
      platformUpdate(tester, 'abc\nhi');
      await tester.pump();
      expect(controller.text, 'abc\nhi');
      expect(methods.sentText, ['abc']);
    });

    testWidgets('a failed send still in the field stays there once', (
      tester,
    ) async {
      final (methods, controller) =
          await pumpComposer(tester, holdSends: false, failing: {'abc'});
      platformUpdate(tester, 'abc');
      await tester.pump();
      await _pressEnter(tester, controller);
      await tester.pumpAndSettle();
      expect(methods.sentText, ['abc']);
      expect(controller.text, 'abc');
    });

    testWidgets('a failed send the user edited after the echo ended is not '
        'inserted again', (tester) async {
      final (methods, controller) =
          await pumpComposer(tester, failing: {'hi'});
      platformUpdate(tester, 'hi');
      await tester.pump();
      await _pressEnter(tester, controller);
      // The platform caught up ("hi"), then the user kept typing in it.
      platformUpdate(tester, 'high');
      await tester.pump();
      expect(controller.text, 'high');

      await finishSends(tester, methods);
      expect(controller.text, 'high');
    });

    testWidgets('first send fails while the second is queued: the second is '
        'sent and cleared, the first comes back once', (tester) async {
      final (methods, controller) = await pumpComposer(tester, failing: {'a'});
      platformUpdate(tester, 'a');
      await tester.pump();
      await _pressEnter(tester, controller);
      await _pressEnter(tester, controller, platformText: 'a\nb');
      expect(methods.sentText, ['a']);

      await finishSends(tester, methods);
      expect(methods.sentText, ['a', 'b']);
      expect(controller.text, 'a', reason: 'b went out; only a is put back');
    });

    testWidgets('failed first + sent second: a stale platform echo after the '
        'restore keeps the first and does not bring the second back', (
      tester,
    ) async {
      final (methods, controller) = await pumpComposer(tester, failing: {'a'});
      platformUpdate(tester, 'a');
      await tester.pump();
      await _pressEnter(tester, controller);
      // "b" and Enter arrive while the platform still echoes "a\n".
      platformUpdate(tester, 'a\nb');
      await tester.pump();
      expect(controller.text, 'b');
      final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      expect(handled, isFalse);
      platformUpdate(tester, 'a\nb\n');
      await tester.pump();
      expect(methods.sentText, ['a']);

      await finishSends(tester, methods);
      expect(methods.sentText, ['a', 'b']);
      expect(controller.text, 'a');

      // The platform had not processed the restore yet when "x" was typed.
      platformUpdate(tester, 'a\nb\nx');
      await tester.pump();
      expect(controller.text, 'a\nx');
    });

    testWidgets('a mid-draft Enter after a quick caret move then a key does '
        'not bring the sent message back', (tester) async {
      final (methods, controller) = await pumpComposer(tester);
      platformUpdate(tester, 'abcd', 2);
      await tester.pump();
      await _pressEnter(tester, controller); // platform: "ab\ncd", caret 3
      platformUpdate(tester, 'ab\nchd', 5); // right arrow, then "h"
      await tester.pump();
      expect(controller.text, 'h');
      await finishSends(tester, methods);
      expect(controller.text, 'h');
      expect(methods.sentText, ['abcd']);
    });
  });
}
