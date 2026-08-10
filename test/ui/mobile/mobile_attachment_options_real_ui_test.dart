// Real-CONTROL counterpart to `mobile_attachment_and_stt_policy_test.dart`.
//
// That file asserts the toxee mobile attachment policy as pure data (it renders
// nothing — zero `testWidgets`). This file takes the SAME production builder,
// `buildToxeeMobileAttachmentOptions` (lib/ui/home/mobile_attachment_policy.dart,
// wired into UIKit at home_page_bootstrap.dart via
// `additionalAttachmentOptionsForMobile`), hands it to the REAL phone composer
// `TencentCloudChatMessageInputMobile`, and drives it with real taps:
//
//   1. tap the real attachment "+" -> the production overlay mounts the real
//      `TencentCloudChatMessageAttachmentOptionsWidget`;
//   2. the rendered option set is EXACTLY the toxee pair, in order, with the
//      production icons (`Icons.attach_file`, `Icons.camera_alt_outlined`) —
//      i.e. what the finger actually sees, read back off the rendered widgets;
//   3. tapping an option runs its production picker seam (`item.onTap` ->
//      `onFile` / `onCamera`) exactly once and dismisses the overlay (the
//      fork's `onActionFinish`).
//
// The option `onTap` IS the seam the production wiring passes `_sendMedia` /
// `_showCameraMediaOptions` into, so capturing it here is faithful and no
// native file/camera picker channel is touched.
//
// Mobile parity: `mobile_attachment_policy.dart` and the fork composer are
// shared Dart, so this covers iOS and Android identically.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
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
import 'package:toxee/ui/home/mobile_attachment_policy.dart';

// The fork composer reads the `tL10n` singleton during build, so it needs a
// real Localizations ancestor initialized first. Copied (not imported) from the
// sibling composer gate per the harness rule: never import another test file's
// private helpers.
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

/// Inert composer methods, except `messageAttachmentOptionsBuilder`, which
/// returns the REAL production attachment-options widget (the same one the
/// default UIKit builder returns).
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
        }) => TencentCloudChatMessageAttachmentOptionsWidget(
          key: key,
          data: data,
          methods: methods,
        ),
    closeSticker: () {},
  );
}

MessageInputBuilderData _data(
  List<TencentCloudChatMessageGeneralOptionItem> attachmentOptions,
) {
  return MessageInputBuilderData(
    // Null conversation ids keep `_updateDraft` short-circuited so no SDK
    // conversation manager is required; the attachment overlay is independent
    // of the conversation id.
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

/// Labels production passes in from l10n (`appL10n.file` / `tL10n.camera`).
const String _fileLabel = 'File';
const String _cameraLabel = 'Camera';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  late List<String> invoked;
  late List<TencentCloudChatMessageGeneralOptionItem> productionOptions;

  setUp(() {
    invoked = <String>[];
    // The REAL production option list — same call shape as
    // home_page_bootstrap.dart's `additionalAttachmentOptionsForMobile`.
    productionOptions = buildToxeeMobileAttachmentOptions(
      fileLabel: _fileLabel,
      cameraLabel: _cameraLabel,
      onFile: () async => invoked.add('file'),
      onCamera: () async => invoked.add('camera'),
    );
  });

  void usePhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpComposer(WidgetTester tester) async {
    await tester.pumpWidget(
      _localized(
        child: TencentCloudChatMessageInputMobile(
          inputData: _data(productionOptions),
          inputMethods: _methods(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAttachmentOverlay(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mobile attachment "+" renders exactly the toxee File + Camera options '
    'with their production icons',
    (WidgetTester tester) async {
      usePhoneSurface(tester);
      await pumpComposer(tester);

      // Closed state: the overlay is not mounted.
      expect(
        find.byType(TencentCloudChatMessageAttachmentOptionsWidget),
        findsNothing,
      );
      expect(find.text(_fileLabel), findsNothing);
      expect(find.text(_cameraLabel), findsNothing);

      await openAttachmentOverlay(tester);

      final overlay = find.byType(
        TencentCloudChatMessageAttachmentOptionsWidget,
      );
      expect(
        overlay,
        findsOneWidget,
        reason: 'the "+" must mount the production options overlay',
      );

      // Read the RENDERED option set back off the widget tree: the toxee policy
      // replaces the stock Album/Photo/Video entries with File + Camera, so
      // exactly these two labels, in this order, must reach the user.
      final renderedLabels = tester
          .widgetList<Text>(
            find.descendant(of: overlay, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .toList();
      expect(
        renderedLabels,
        <String>[_fileLabel, _cameraLabel],
        reason: 'the rendered option labels must be the toxee pair, in order',
      );

      expect(
        find.descendant(of: overlay, matching: find.byIcon(Icons.attach_file)),
        findsOneWidget,
        reason: 'File option must render the production attach_file icon',
      );
      expect(
        find.descendant(
          of: overlay,
          matching: find.byIcon(Icons.camera_alt_outlined),
        ),
        findsOneWidget,
        reason: 'Camera option must render the production camera icon',
      );
      expect(
        invoked,
        isEmpty,
        reason: 'opening the sheet must not invoke any picker seam',
      );
    },
  );

  testWidgets(
    'tapping File runs the production file seam once and dismisses the overlay',
    (WidgetTester tester) async {
      usePhoneSurface(tester);
      await pumpComposer(tester);
      await openAttachmentOverlay(tester);

      await tester.tap(find.text(_fileLabel));
      await tester.pumpAndSettle();

      expect(
        invoked,
        <String>['file'],
        reason:
            'tapping File must invoke exactly the onFile seam production wires '
            'to `_sendMedia(type: file)` — and nothing else',
      );
      expect(
        find.byType(TencentCloudChatMessageAttachmentOptionsWidget),
        findsNothing,
        reason: 'picking an option must close the overlay (onActionFinish)',
      );
    },
  );

  testWidgets(
    'tapping Camera runs the production camera seam once, independently of File',
    (WidgetTester tester) async {
      usePhoneSurface(tester);
      await pumpComposer(tester);
      await openAttachmentOverlay(tester);

      await tester.tap(find.text(_cameraLabel));
      await tester.pumpAndSettle();

      expect(
        invoked,
        <String>['camera'],
        reason:
            'tapping Camera must invoke only the onCamera seam production '
            'wires to the camera media chooser',
      );
      expect(
        find.byType(TencentCloudChatMessageAttachmentOptionsWidget),
        findsNothing,
      );

      // Re-open and pick the other option: the overlay is reusable and the two
      // seams stay distinct across invocations.
      await openAttachmentOverlay(tester);
      await tester.tap(find.text(_fileLabel));
      await tester.pumpAndSettle();

      expect(invoked, <String>['camera', 'file']);
    },
  );
}
