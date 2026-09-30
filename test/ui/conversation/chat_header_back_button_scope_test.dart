// L3 / L5 (doc/reference/MOBILE_DEVICE_FEATURES.md): the chat header's back
// button is a navigation affordance — it must appear exactly when the chat is on
// a route of its own. It used to follow the fork's screen classifier instead, so
// an iPad in portrait (834 pt, classified "mobile") showed it on the chat that
// the split layout EMBEDS next to the list; tapping it popped the home route and
// left the app blank. A narrow window classified "desktop" (a Stage Manager
// window wider than tall) pushed the chat as a route with no back button at all.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/widgets/tencent_cloud_chat_embedded_message_pane.dart';
import 'package:tencent_cloud_chat_conversation/desktop/tencent_cloud_chat_conversation_desktop_mode.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_builders.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_header/tencent_cloud_chat_message_header.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

const _backKey = ValueKey('chat_header_back_button');

Widget _app(Widget child) => MaterialApp(
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

Widget _header() => TencentCloudChatMessageHeader(
  widgets: MessageHeaderBuilderWidgets(
    messageHeaderProfileImage: const SizedBox(width: 34, height: 34),
    messageHeaderInfo: const Text('Bob'),
    messageHeaderActions: const SizedBox.shrink(),
    messageHeaderMessagesSelectMode: const SizedBox.shrink(),
  ),
  data: MessageHeaderBuilderData(
    userID: 'bob',
    inSelectMode: false,
    selectAmount: 0,
    showUserOnlineStatus: false,
  ),
  methods: MessageHeaderBuilderMethods(
    onClearSelect: () {},
    onCancelSelect: () {},
    getUserOnlineStatus: ({required String userID}) => false,
    getGroupMembersInfo: () => const [],
    controller: Object(),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  void classifyAs(DeviceScreenType type) {
    TencentCloudChatScreenAdapter.deviceScreenType = type;
    TencentCloudChatScreenAdapter.hasInitialized = true;
  }

  tearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  for (final type in DeviceScreenType.values) {
    testWidgets('pushed chat offers back ($type)', (tester) async {
      classifyAs(type);
      await tester.pumpWidget(_app(_header()));
      expect(find.byKey(_backKey), findsOneWidget);
    });

    testWidgets('embedded chat offers no back ($type)', (tester) async {
      classifyAs(type);
      await tester.pumpWidget(
        _app(TencentCloudChatEmbeddedMessagePane(child: _header())),
      );
      expect(find.byKey(_backKey), findsNothing);
    });
  }

  testWidgets('the split layout embeds its message widget', (tester) async {
    // iPad portrait: toxee forces the split while the classifier says mobile.
    classifyAs(DeviceScreenType.mobile);
    final data = TencentCloudChat.instance.dataInstance;
    data.conversation.conversationBuilder =
        TencentCloudChatConversationBuilders();
    bool? embedded;
    data.basic.componentsMap[TencentCloudChatComponentsEnum.message] =
        ({required Map<String, dynamic> options}) => Builder(
          builder: (context) {
            embedded = TencentCloudChatEmbeddedMessagePane.isIn(context);
            return const SizedBox.expand();
          },
        );
    addTearDown(() {
      data.basic.componentsMap.remove(TencentCloudChatComponentsEnum.message);
      data.conversation.conversationBuilder = null;
    });
    tester.view.physicalSize = const Size(834, 1194);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(const TencentCloudChatConversationDesktopMode()),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(embedded, isTrue);
  });

  testWidgets(
    'closing a moot chat (friend deleted / group quit) never pops the host',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      bool? popped;
      Widget page(String name, {required bool embedded}) {
        final body = Builder(
          builder: (context) => TextButton(
            onPressed: () => popped =
                TencentCloudChatEmbeddedMessagePane.closeChatRoute(context),
            child: Text(name),
          ),
        );
        return Scaffold(
          body: embedded
              ? TencentCloudChatEmbeddedMessagePane(child: body)
              : body,
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: page('home-with-embedded-chat', embedded: true),
        ),
      );
      final conversationData = TencentCloudChat.instance.dataInstance.conversation;
      conversationData.currentConversation = V2TimConversation(
        conversationID: 'group_g1',
        groupID: 'g1',
      );
      addTearDown(() => conversationData.currentConversation = null);
      await tester.tap(find.text('home-with-embedded-chat'));
      await tester.pumpAndSettle();
      expect(popped, isFalse);
      expect(find.text('home-with-embedded-chat'), findsOneWidget);
      expect(
        conversationData.currentConversation,
        isNull,
        reason: 'the split pane stops showing the departed conversation',
      );

      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => page('pushed-chat', embedded: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('pushed-chat'));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(find.text('pushed-chat'), findsNothing);
      expect(find.text('home-with-embedded-chat'), findsOneWidget);
    },
  );
}
