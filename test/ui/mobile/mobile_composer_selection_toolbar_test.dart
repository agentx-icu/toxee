// I1 (MOBILE_DEVICE_FEATURES): the mobile composer's system text-selection
// toolbar must not outlive the text it was built for.
//
// Reproduced on an API 36 emulator: long-press the composer text (the system
// Cut / Copy / Paste toolbar appears), then tap send — the message went out and
// the field was cleared, but the toolbar stayed as a lone "Paste" bubble with a
// caret handle over the empty field, and system BACK did not close it. The
// field's EditableText hides that UI only for edits it makes itself; the
// composer's programmatic replacements (send-and-clear, draft swap) now drop it.
//
// Pumps the REAL fork `TencentCloudChatMessageInputMobile`; drives a real long
// press and a real tap on the send button.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/foundation.dart';
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
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_mobile.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

// Same wrapper as test/ui/mobile/mobile_composer_real_ui_test.dart (copied, not
// imported: test files don't share private helpers). The fork composer reads
// the `tL10n` singleton during build.
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

MessageInputBuilderMethods _methods(List<String> sent) {
  return MessageInputBuilderMethods(
    sendTextMessage: ({required String text, List<String>? mentionedUsers}) {
      sent.add(text);
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
    controller: TencentCloudChatMessageControllerGenerator.getInstance(),
    desktopInputMemberSelectionPanelScroll: AutoScrollController(),
    messageAttachmentOptionsBuilder:
        ({
          Key? key,
          MessageAttachmentOptionsBuilderWidgets? widgets,
          required MessageAttachmentOptionsBuilderData data,
          required MessageAttachmentOptionsBuilderMethods methods,
        }) => const SizedBox.shrink(),
    closeSticker: () {},
  );
}

MessageInputBuilderData _data({String? specifiedMessageText}) {
  return MessageInputBuilderData(
    // No conversation id: the draft path early-returns, so nothing reaches the
    // SDK conversation manager (unavailable hermetically).
    userID: null,
    groupID: null,
    attachmentOptions: const [],
    inSelectMode: false,
    enableReplyWithMention: false,
    status: TencentCloudChatMessageInputStatus.canSendMessage,
    selectedMessages: const [],
    specifiedMessageText: specifiedMessageText,
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

// The selection handles (Material and Cupertino) live in the field's selection
// overlay as a private `_SelectionHandleOverlay` widget.
Finder _selectionHandles() => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_SelectionHandleOverlay',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  setUp(() {
    // A non-empty clipboard, so a stale toolbar over an EMPTY field still has
    // a button to show ("Paste") — exactly what the device showed.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.hasStrings':
              return <String, dynamic>{'value': true};
            case 'Clipboard.getData':
              return <String, dynamic>{'text': 'clip'};
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  void usePhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> typeAndSelect(WidgetTester tester, String text) async {
    final field = find.byType(ExtendedTextField);
    await tester.tap(field);
    await tester.pump();
    tester.testTextInput.enterText(text);
    await tester.pumpAndSettle();
    // Select the first word, which opens the selection toolbar: a long press
    // on Android, a double tap on iOS (a long press there only moves the
    // caret under the magnifier).
    final rect = tester.getRect(field);
    final word = Offset(rect.left + 12, rect.center.dy);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await tester.tapAt(word);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(word);
    } else {
      await tester.longPressAt(word);
    }
    await tester.pumpAndSettle();
    expect(
      find.text('Copy'),
      findsOneWidget,
      reason: 'precondition: the long press shows the selection toolbar',
    );
  }

  // Android (Material toolbar) and iOS (Cupertino toolbar) share this
  // composer; both variants run the real selection controls of that platform.
  const phones = TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  testWidgets('sending with the selection toolbar up dismisses it', variant: phones, (
    tester,
  ) async {
    usePhoneSurface(tester);
    final sent = <String>[];
    await tester.pumpWidget(
      _localized(
        child: TencentCloudChatMessageInputMobile(
          inputData: _data(),
          inputMethods: _methods(sent),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await typeAndSelect(tester, 'hello world');
    expect(
      _selectionHandles(),
      findsWidgets,
      reason: 'precondition: the selection shows its handles',
    );

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(sent, ['hello world']);
    expect(
      find.text('Paste'),
      findsNothing,
      reason: 'no stale toolbar over the cleared field',
    );
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Select all'), findsNothing);
    expect(_selectionHandles(), findsNothing, reason: 'no stale caret handle');
  });

  testWidgets(
    'a draft swap (didUpdateWidget) with the toolbar up dismisses it',
    variant: phones,
    (tester) async {
    usePhoneSurface(tester);
    final sent = <String>[];
    late StateSetter setOuter;
    String? specified;
    await tester.pumpWidget(
      _localized(
        child: StatefulBuilder(
          builder: (context, setState) {
            setOuter = setState;
            return TencentCloudChatMessageInputMobile(
              inputData: _data(specifiedMessageText: specified),
              inputMethods: _methods(sent),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await typeAndSelect(tester, 'draft text');

    // The host hands the composer different text (the path a "quote" /
    // specified-text change takes): the controller is rewritten from
    // didUpdateWidget, i.e. during build.
    setOuter(() => specified = 'replacement');
    await tester.pumpAndSettle();

    final controller = tester
        .widget<ExtendedTextField>(find.byType(ExtendedTextField))
        .controller!;
    expect(controller.text, 'replacement');
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Paste'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(sent, isEmpty);
  });

  testWidgets('selection-only changes keep the toolbar', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      _localized(
        child: TencentCloudChatMessageInputMobile(
          inputData: _data(),
          inputMethods: _methods(<String>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await typeAndSelect(tester, 'keep me');
    final controller = tester
        .widget<ExtendedTextField>(find.byType(ExtendedTextField))
        .controller!;
    // Widen the selection to the whole text (what Select all does): the
    // controller notifies its listeners but the text is unchanged.
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    await tester.pumpAndSettle();

    expect(
      find.text('Copy'),
      findsOneWidget,
      reason: 'a selection-only change keeps the toolbar',
    );
  });

  testWidgets(
    'typing over a selection (IME edit) still ends with no toolbar',
    variant: phones,
    (tester) async {
      // EditableText hides the toolbar itself for IME edits and hides the
      // handles for keyboard-caused selection changes; the composer's extra
      // dismissal on text change must not leave anything different behind.
      usePhoneSurface(tester);
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatMessageInputMobile(
            inputData: _data(),
            inputMethods: _methods(<String>[]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await typeAndSelect(tester, 'abc def');
      tester.testTextInput.enterText('typed');
      await tester.pumpAndSettle();

      final controller = tester
          .widget<ExtendedTextField>(find.byType(ExtendedTextField))
          .controller!;
      expect(controller.text, 'typed');
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Paste'), findsNothing);
    },
  );

  testWidgets(
    'an earlier IME edit does not mask a later code write (IME empties, code '
    'fills a draft, the user selects it and sends)',
    variant: phones,
    (tester) async {
      usePhoneSurface(tester);
      final sent = <String>[];
      late StateSetter setOuter;
      String? specified;
      await tester.pumpWidget(
        _localized(
          child: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return TencentCloudChatMessageInputMobile(
                inputData: _data(specifiedMessageText: specified),
                inputMethods: _methods(sent),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // IME: type, then delete everything (the field's own edits, down to "").
      final field = find.byType(ExtendedTextField);
      await tester.tap(field);
      await tester.pump();
      tester.testTextInput.enterText('x');
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('');
      await tester.pumpAndSettle();

      // Code fills a draft; the user selects it and sends (code clears to "").
      setOuter(() => specified = 'draft words');
      await tester.pumpAndSettle();
      final rect = tester.getRect(field);
      final word = Offset(rect.left + 12, rect.center.dy);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await tester.tapAt(word);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(word);
      } else {
        await tester.longPressAt(word);
      }
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget, reason: 'precondition');

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(sent, ['draft words']);
      expect(find.text('Paste'), findsNothing);
      expect(find.text('Copy'), findsNothing);
      expect(_selectionHandles(), findsNothing);
    },
  );
}
