import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_item.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

/// Pins the conversation-row crash the iPhone real-UI pair exposed after a
/// voice call ended (2026-08-24): a hang-up call record whose signaling JSON
/// has no `call_end` (a zero-duration call used to omit it) made
/// `CallingMessage.getContent()` throw inside the row's last-message summary,
/// and the row rendered as an ErrorWidget.
Widget _localized({required Widget child}) {
  return MaterialApp(
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

V2TimMessage _hangupRecord({int? callEnd}) {
  final signaling = <String, dynamic>{
    'businessID': 'av_call',
    'call_type': 1,
    'data': {'cmd': 'hangup', 'inviter': 'b_self'},
    if (callEnd != null) 'call_end': callEnd,
  };
  return V2TimMessage(
      elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM,
      msgID: 'call_record_zero',
      timestamp: 1700000000,
      isSelf: true,
    )
    ..id = 'call_record_zero'
    ..sender = 'b_self'
    ..userID = 'a_peer'
    ..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC
    ..customElem = V2TimCustomElem(
      data: jsonEncode({
        'data': jsonEncode(signaling),
        'actionType': 1,
        'timeout': 30,
        'inviter': 'b_self',
        'inviteeList': ['a_peer'],
        'inviteID': 'call_test_zero',
        'groupID': '',
      }),
      desc: '',
      extension: '',
    );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  Future<void> pumpRow(WidgetTester tester, V2TimMessage last) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.mobile;
    TencentCloudChatScreenAdapter.hasInitialized = true;
    addTearDown(() {
      TencentCloudChatScreenAdapter.deviceScreenType = null;
      TencentCloudChatScreenAdapter.hasInitialized = false;
    });
    final conversation = V2TimConversation(
      conversationID: 'c2c_a_peer',
      type: 1,
      userID: 'a_peer',
      showName: 'A Peer',
    )..lastMessage = last;
    await tester.pumpWidget(
      _localized(
        child: SizedBox(
          width: 320,
          child: Row(
            children: [
              TencentCloudChatConversationItemContent(
                conversation: conversation,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a hang-up record WITHOUT call_end renders, as 00:00', (
    tester,
  ) async {
    await pumpRow(tester, _hangupRecord());
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.textContaining('00:00'), findsOneWidget);
  });

  testWidgets('a hang-up record with a duration renders it', (tester) async {
    await pumpRow(tester, _hangupRecord(callEnd: 75));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('01:15'), findsOneWidget);
  });
}
