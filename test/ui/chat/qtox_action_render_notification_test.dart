// Shared mobile/desktop rendering and notification contracts for qTox ACTION.
// ignore_for_file: depend_on_referenced_packages, directives_ordering

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/message_type_builders/tencent_cloud_chat_message_text.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimAdvancedMsgListener.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_user_full_info.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform_converters.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/notifications/notification_message_listener.dart';
import 'package:toxee/notifications/notification_service.dart';
import 'package:toxee/sdk_fake/uikit_data_facade.dart';

const String _actionBody = 'waves';

final class _ActionListenerPlatform extends TencentCloudChatSdkPlatform {
  V2TimAdvancedMsgListener? listener;

  @override
  bool get isCustomPlatform => true;

  @override
  Future<String> addAdvancedMsgListener({
    required V2TimAdvancedMsgListener listener,
  }) async {
    this.listener = listener;
    return 'qtox-action-listener';
  }

  @override
  Future<void> removeAdvancedMsgListener({
    V2TimAdvancedMsgListener? listener,
    String? uuid,
  }) async {
    if (identical(this.listener, listener)) this.listener = null;
  }
}

Widget _localized(Widget child) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: const <Locale>[Locale('en')],
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    TencentCloudChatLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: Builder(
      builder: (BuildContext context) {
        TencentCloudChatIntl().init(context);
        return child;
      },
    ),
  ),
);

ChatMessage _actionModel() => ChatMessage.fromJson(<String, dynamic>{
  'text': _actionBody,
  'fromUserId': 'action_peer',
  'isSelf': false,
  'timestamp': DateTime.utc(2026, 7, 29).toIso8601String(),
  'groupId': null,
  'filePath': null,
  'fileName': null,
  'mediaKind': null,
  'contentKind': 'action',
  'isPending': false,
  'isReceived': true,
  'isRead': false,
  'msgID': 'qtox-action-ui',
});

String _contentKindName(ChatMessage message) {
  final dynamic kind = (message as dynamic).contentKind;
  return kind is String ? kind : kind.toString().split('.').last;
}

V2TimMessage _actionV2Message(FfiChatService service) {
  final platform = Tim2ToxSdkPlatform(ffiService: service);
  return platform.chatMessageToV2TimMessage(_actionModel(), 'self');
}

MessageItemBuilderData _bubbleData(V2TimMessage message, double rowWidth) =>
    MessageItemBuilderData(
      message: message,
      userID: 'action_peer',
      altText: '[message]',
      enableParseMarkdown: false,
      showMessageStatusIndicator: true,
      showMessageTimeIndicator: true,
      shouldBeHighlighted: false,
      showMessageSenderName: false,
      messageRowWidth: rowWidth,
      renderOnMenuPreview: false,
      inSelectMode: false,
      inMergerMessagePreviewMode: false,
      hasStickerPlugin: false,
    );

MessageItemBuilderMethods _bubbleMethods() => MessageItemBuilderMethods(
  clearHighlightFunc: () {},
  triggerLinkTappedEvent: (_) {},
  setMessageTextWithMentions:
      ({
        required String messageText,
        required List<String> groupMembersNeedToMention,
      }) {},
  onResendMessage: () {},
);

Future<void> _pumpActionBubble(
  WidgetTester tester, {
  required Size size,
  required DeviceScreenType screenType,
  required V2TimMessage message,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  TencentCloudChatScreenAdapter.deviceScreenType = screenType;
  TencentCloudChatScreenAdapter.hasInitialized = true;
  addTearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  TencentCloudChat.instance.dataInstance.basic.updateCurrentUserInfo(
    userFullInfo: V2TimUserFullInfo(userID: 'self', nickName: 'Self'),
  );
  await tester.pumpWidget(
    _localized(
      SizedBox(
        width: size.width,
        child: TencentCloudChatMessageText(
          data: _bubbleData(message, size.width),
          methods: _bubbleMethods(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  group('qTox ACTION conversion, rendering, and notification', () {
    late Directory root;
    late FfiChatService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('qtox_action_ui_red_');
      SharedPreferences.setMockInitialValues(<String, Object>{});
      service = FfiChatService(
        historyDirectory: path.join(root.path, 'history'),
        queueFilePath: path.join(root.path, 'offline_queue.json'),
        fileRecvPath: path.join(root.path, 'file_recv'),
        avatarsPath: path.join(root.path, 'avatars'),
      );
    });

    tearDown(() async {
      await NotificationMessageListener.disposeAndReset();
      NotificationService.debugForceIsAndroid = null;
      NotificationService.instance.debugAndroidPermissionGranted = null;
      UikitDataFacade.currentConversation = null;
      await service.dispose();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('ACTION model stays action-aware and converts to V2TIM text', () {
      final model = _actionModel();
      final converted = _actionV2Message(service);

      expect(_contentKindName(model), 'action');
      expect(converted.elemType, MessageElemType.V2TIM_ELEM_TYPE_TEXT);
      expect(converted.textElem?.text, _actionBody);
      expect(converted.customElem, isNull);
    });

    for (final target
        in <({String name, Size size, DeviceScreenType screenType})>[
          (
            name: 'mobile',
            size: const Size(400, 800),
            screenType: DeviceScreenType.mobile,
          ),
          (
            name: 'desktop',
            size: const Size(1200, 800),
            screenType: DeviceScreenType.desktop,
          ),
        ])
      testWidgets('ACTION renders its body as text on ${target.name}', (
        WidgetTester tester,
      ) async {
        await _pumpActionBubble(
          tester,
          size: target.size,
          screenType: target.screenType,
          message: _actionV2Message(service),
        );

        expect(find.text(_actionBody), findsOneWidget);
        expect(find.text('[Custom]'), findsNothing);
        expect(tester.takeException(), isNull);
      });

    testWidgets('ACTION notification previews the text body, not custom data', (
      WidgetTester tester,
    ) async {
      const notificationsChannel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      Object? showArguments;
      final capturedMethods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            capturedMethods.add(call.method);
            if (call.method == 'initialize') return true;
            if (call.method == 'getNotificationAppLaunchDetails') return null;
            if (call.method == 'show') showArguments = call.arguments;
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(notificationsChannel, null);
      });

      final fakePlatform = _ActionListenerPlatform();
      final previousPlatform = TencentCloudChatSdkPlatform.instance;
      TencentCloudChatSdkPlatform.instance = fakePlatform;
      addTearDown(
        () => TencentCloudChatSdkPlatform.instance = previousPlatform,
      );

      final listener = NotificationMessageListener.forService(service);
      UikitDataFacade.currentConversation = null;
      await listener.register();
      NotificationService.debugForceIsAndroid = true;
      NotificationService.instance.debugAndroidPermissionGranted = true;
      final action = _actionV2Message(service)
        ..sender = 'action_peer'
        ..userID = 'action_peer'
        ..nickName = 'Alice'
        ..textElem = V2TimTextElem(text: _actionBody);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      addTearDown(() {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      expect(
        NotificationMessageListener.debugShouldSuppressFor(service, action),
        isFalse,
      );
      expect(fakePlatform.listener!.onRecvNewMessage, isNotNull);
      fakePlatform.listener!.onRecvNewMessage?.call(action);
      for (var attempt = 0; attempt < 20 && showArguments == null; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        showArguments,
        isNotNull,
        reason: 'notification channel methods: $capturedMethods',
      );
      final arguments = showArguments! as Map<Object?, Object?>;
      expect(arguments['title'], 'Alice');
      expect(arguments['body'], _actionBody);
      expect(arguments['body'], isNot('[Custom Message]'));
    });
  });
}
