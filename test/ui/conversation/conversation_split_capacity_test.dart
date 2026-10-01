import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_conversation/desktop/tencent_cloud_chat_conversation_desktop_mode.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_builders.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:toxee/util/responsive_layout.dart';

const _messagePane = ValueKey('capacity_message_pane');

Widget _app() => MaterialApp(
  locale: const Locale('en'),
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
        return Row(
          children: [
            SizedBox(width: ResponsiveLayout.responsiveSidebarWidth(context)),
            const Expanded(child: TencentCloudChatConversationDesktopMode()),
          ],
        );
      },
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');
  setUp(() {
    ResponsiveLayout.debugIsDesktopPlatformOverride = () => true;
    TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
    TencentCloudChatScreenAdapter.hasInitialized = true;
    final data = TencentCloudChat.instance.dataInstance;
    data.conversation.conversationBuilder =
        TencentCloudChatConversationBuilders();
    data.basic.componentsMap[TencentCloudChatComponentsEnum.message] =
        ({required Map<String, dynamic> options}) =>
            const SizedBox.expand(key: _messagePane);
  });
  tearDown(() {
    ResponsiveLayout.debugIsDesktopPlatformOverride = null;
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
    final data = TencentCloudChat.instance.dataInstance;
    data.conversation.conversationBuilder = null;
    data.basic.componentsMap.remove(TencentCloudChatComponentsEnum.message);
  });

  testWidgets('split keeps a usable chat at intermediate widths and preserves '
      'the mounted state while resizing', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(1100, 1200);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 50));
    final initialState = tester.state(
      find.byType(TencentCloudChatConversationDesktopMode),
    );
    for (final width in [800.0, 834.0, 1024.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 1200);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width=$width');
      final chatWidth = tester.getSize(find.byKey(_messagePane)).width;
      expect(chatWidth, greaterThanOrEqualTo(360), reason: 'width=$width');
      final railWidth = width < 1100 ? 72 : 200;
      final listWidth = width - railWidth - chatWidth - 1;
      expect(listWidth, inInclusiveRange(280, 330));
      expect(
        tester.state(find.byType(TencentCloudChatConversationDesktopMode)),
        same(initialState),
        reason: 'resizing retains controllers and selection',
      );
    }
    tester.view.physicalSize = const Size(700, 1200);
    await tester.pump();
    // The host normally hides this split below 800. Its component still
    // degrades without an overflow if embedded in a smaller pane.
    expect(tester.takeException(), isNull);
  });
}
