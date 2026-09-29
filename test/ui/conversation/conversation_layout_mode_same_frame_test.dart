// L4a (doc/reference/MOBILE_DEVICE_FEATURES.md): when a rotation crosses the
// master-detail breakpoint, the home shell flips UIKit's layout mode in its
// own build. The conversation widget must follow in that same frame — a copy
// of the mode cached from the (asynchronous) change event kept the split for
// one frame at phone width and overflowed its right pane.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_conversation/desktop/tencent_cloud_chat_conversation_desktop_mode.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation.dart'
    as conv_pkg;
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_builders.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  testWidgets('the layout mode flipped in the parent build applies this frame', (
    tester,
  ) async {
    TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.mobile;
    TencentCloudChatScreenAdapter.hasInitialized = true;
    final data = TencentCloudChat.instance.dataInstance;
    data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
    data.conversation.conversationBuilder =
        TencentCloudChatConversationBuilders();
    addTearDown(() {
      TencentCloudChatScreenAdapter.deviceScreenType = null;
      TencentCloudChatScreenAdapter.hasInitialized = false;
      data.conversation.conversationBuilder = null;
      data.conversation.conversationConfig.setConfigs(
        useDesktopMode: true,
        forceDesktopLayout: false,
      );
      data.basic.usedComponents = [];
    });

    final wide = ValueNotifier(true);
    addTearDown(wide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          TencentCloudChatLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: wide,
            builder: (context, isWide, _) {
              TencentCloudChatIntl().init(context);
              // What the home shell does in its build (MasterDetailTransition).
              data.conversation.conversationConfig.setConfigs(
                useDesktopMode: isWide,
                forceDesktopLayout: isWide,
              );
              // ignore: prefer_const_constructors
              return conv_pkg.TencentCloudChatConversation();
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(TencentCloudChatConversationDesktopMode), findsOneWidget);

    // Rotate to a phone portrait width in the same frame the mode flips.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    expect(find.byType(TencentCloudChatConversationDesktopMode), findsOneWidget);

    tester.view.physicalSize = const Size(400, 900);
    wide.value = false;
    await tester.pump(); // the crossing frame, before any change event
    expect(tester.takeException(), isNull, reason: 'no overflow this frame');
    expect(
      find.byType(TencentCloudChatConversationDesktopMode),
      findsNothing,
      reason: 'the split must not survive into the compact frame',
    );

    tester.view.physicalSize = const Size(1400, 900);
    wide.value = true;
    await tester.pump();
    expect(find.byType(TencentCloudChatConversationDesktopMode), findsOneWidget);
  });
}
