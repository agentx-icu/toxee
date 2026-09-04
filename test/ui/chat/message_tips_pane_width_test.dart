import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_list_view/message_row/tencent_cloud_chat_message_row.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/message_type_builders/tencent_cloud_chat_message_tips_common.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';

/// Regression: the desktop message ROW placed a tips item (recall notice,
/// group tips) as a bare child of a max-size Row, so the tip got UNBOUNDED
/// width, sized itself to the WINDOW and overflowed the (narrower) message
/// pane by ~94 px for a long "<tox id> Recalled a Message" (Windows real-UI
/// screenshot, 2026-09-04). Rendered through the REAL row widget so the test
/// exercises the product composition, not a re-implementation of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop tips row stays inside a pane narrower than the window',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
    TencentCloudChatScreenAdapter.hasInitialized = true;
    addTearDown(() {
      TencentCloudChatScreenAdapter.deviceScreenType = null;
      TencentCloudChatScreenAdapter.hasInitialized = false;
    });

    const paneWidth = 420.0;
    const longText =
        '4A30DE1AEFAA00927A02F3EFE50C73D5455BEEDAEF820868D829C5AC7908DC1277EB96417178'
        ' Recalled a Message';
    // fromJson: the V2TimMessage constructor asks TIMManager for the server
    // time, which loads the native SDK library (absent under flutter test).
    // (fromJson takes the native snake_case keys, so set the fields directly.)
    final tips = V2TimMessage.fromJson({})
      ..msgID = 'tips-1'
      ..elemType = 101
      ..timestamp = 1;
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
          body: Builder(
            builder: (context) {
              TencentCloudChatIntl().init(context);
              return Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: paneWidth,
                  child: TencentCloudChatMessageRow(
                    data: MessageRowBuilderData(
                      message: tips,
                      messageRowWidth: paneWidth,
                      showMessageSenderName: false,
                      inSelectMode: false,
                      isSelected: false,
                      isMergeMessage: false,
                      showMessageStatusIndicator: false,
                      showSelfAvatar: false,
                      showOthersAvatar: false,
                      showMessageTimeIndicator: false,
                      hasStickerPlugin: false,
                    ),
                    methods: MessageRowBuilderMethods(
                      onSelectCurrent: (_) {},
                      loadToSpecificMessage: ({
                        required bool highLightTargetMessage,
                        V2TimMessage? message,
                        int? timeStamp,
                        int? seq,
                      }) async =>
                          true,
                    ),
                    widgets: MessageRowBuilderWidgets(
                      messageRowAvatar: const SizedBox.shrink(),
                      messageRowMessageSenderName: const SizedBox.shrink(),
                      messageRowTips:
                          const TencentCloudChatMessageTipsCommon(text: longText),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    final tipBox = tester.getRect(find.byType(TencentCloudChatMessageTipsCommon));
    expect(tipBox.width, lessThanOrEqualTo(paneWidth));
    expect(tipBox.right, lessThanOrEqualTo(1600.0 - 0));
  });
}
