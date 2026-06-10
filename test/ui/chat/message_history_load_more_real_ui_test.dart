// P2 — history load-more + current fork multi-select status.
//
// The page under test is the real TencentCloudChatMessage surface. A recording
// SDK platform serves paged history and captures cursors. The first test proves
// the production list/provider requests older history with lastMsgID and renders
// the second page. The second test records the current fork truth: the text
// bubble menu does not expose multiSelect, so batch delete is not enabled.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_builders.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimUIKitListener.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

class _HistoryRequest {
  const _HistoryRequest({required this.lastMsgID, required this.count});
  final String? lastMsgID;
  final int count;
}

class _PagingSdkPlatform extends TencentCloudChatSdkPlatform {
  final List<_HistoryRequest> requests = [];

  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimValueCallback<V2TimMessageListResult>> getHistoryMessageListV2({
    int getType = HistoryMessageGetType.V2TIM_GET_LOCAL_OLDER_MSG,
    String? userID,
    String? groupID,
    int lastMsgSeq = -1,
    required int count,
    String? lastMsgID,
    List<int>? messageTypeList,
    List<int>? messageSeqList,
    int? timeBegin,
    int? timePeriod,
  }) async {
    requests.add(_HistoryRequest(lastMsgID: lastMsgID, count: count));
    if (lastMsgID == null) {
      return V2TimValueCallback(
        code: 0,
        desc: 'ok',
        data: V2TimMessageListResult(
          isFinished: false,
          messageList: [
            _message('page1_new', 'newest page one', secondsAgo: 10),
            _message('page1_old', 'oldest page one', secondsAgo: 20),
          ],
        ),
      );
    }
    if (lastMsgID == 'page1_old') {
      return V2TimValueCallback(
        code: 0,
        desc: 'ok',
        data: V2TimMessageListResult(
          isFinished: true,
          messageList: [
            _message('page2_old', 'older page two', secondsAgo: 30),
          ],
        ),
      );
    }
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimMessageListResult(isFinished: true, messageList: const []),
    );
  }

  @override
  Future<V2TimValueCallback<V2TimConversation>> getConversation({
    required String conversationID,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimConversation(
        conversationID: conversationID,
        type: 1,
        userID: 'friend1',
        showName: 'Friend One',
      ),
    );
  }

  @override
  Future<V2TimCallback> cleanConversationUnreadMessageCount({
    required String conversationID,
    required int cleanTimestamp,
    required int cleanSequence,
  }) async => V2TimCallback(code: 0, desc: 'ok');

  @override
  Future<V2TimCallback> markC2CMessageAsRead({required String userID}) async =>
      V2TimCallback(code: 0, desc: 'ok');

  @override
  Future<V2TimCallback> sendMessageReadReceipts({
    List<String>? messageIDList,
  }) async => V2TimCallback(code: 0, desc: 'ok');

  @override
  Future<V2TimValueCallback<List<V2TimUserFullInfo>>> getUsersInfo({
    required List<String> userIDList,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: userIDList
          .map((id) => V2TimUserFullInfo(userID: id, nickName: id))
          .toList(),
    );
  }

  @override
  Future<V2TimValueCallback<List<V2TimFriendInfoResult>>> getFriendsInfo({
    required List<String> userIDList,
  }) async => V2TimValueCallback(code: 0, desc: 'ok', data: const []);

  @override
  Future<V2TimValueCallback<List<V2TimUserStatus>>> getUserStatus({
    required List<String> userIDList,
  }) async => V2TimValueCallback(code: 0, desc: 'ok', data: const []);

  @override
  Future<V2TimCallback> subscribeUserStatus({
    required List<String> userIDList,
  }) async => V2TimCallback(code: 0, desc: 'ok');

  @override
  Future<V2TimCallback> unsubscribeUserStatus({
    required List<String> userIDList,
  }) async => V2TimCallback(code: 0, desc: 'ok');

  @override
  String addUIKitListener({required V2TimUIKitListener listener}) =>
      'history_load_more_listener';

  @override
  void removeUIKitListener({String? uuid}) {}
}

V2TimMessage _message(String id, String text, {required int secondsAgo}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return V2TimMessage(
    msgID: id,
    elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
    textElem: V2TimTextElem(text: text),
    isSelf: false,
    timestamp: now - secondsAgo,
    sender: 'friend1',
    nickName: 'Friend One',
  )..status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
}

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

Future<_PagingSdkPlatform> _pumpChat(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
  TencentCloudChatScreenAdapter.hasInitialized = true;
  addTearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  final data = TencentCloudChat.instance.dataInstance;
  data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
  data.basic.updateCurrentUserInfo(
    userFullInfo: V2TimUserFullInfo(userID: 'self_user', nickName: 'Me'),
  );
  data.messageData.messageListMap = {};
  data.conversation.conversationList = [
    V2TimConversation(
      conversationID: 'c2c_friend1',
      type: 1,
      userID: 'friend1',
      showName: 'Friend One',
    ),
  ];
  addTearDown(() {
    data.basic.usedComponents = [];
    data.messageData.messageListMap = {};
    data.conversation.conversationList = [];
  });

  final platform = _PagingSdkPlatform();
  final oldPlatform = TencentCloudChatSdkPlatform.instance;
  TencentCloudChatSdkPlatform.instance = platform;
  addTearDown(() => TencentCloudChatSdkPlatform.instance = oldPlatform);

  await tester.pumpWidget(
    _localized(
      child: TencentCloudChatMessage(
        options: TencentCloudChatMessageOptions(userID: 'friend1'),
        config: TencentCloudChatMessageConfig(),
        builders: TencentCloudChatMessageBuilders(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pumpAndSettle();
  return platform;
}

Finder _rowItem(String msgID) =>
    find.byKey(ValueKey('message_list_item:$msgID'), skipOffstage: false);

Finder _textBubbleCore(String msgID) =>
    find.byKey(Key(msgID), skipOffstage: false).last;

Future<void> _rightClick(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Finder _menuItem(String action) =>
    find.byKey(ValueKey('message_menu_item:$action'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  testWidgets('history list auto-loads older page with lastMsgID cursor', (
    tester,
  ) async {
    final platform = await _pumpChat(tester);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(_rowItem('page1_new'), findsOneWidget);
    expect(_rowItem('page1_old'), findsOneWidget);
    expect(_rowItem('page2_old'), findsOneWidget);
    expect(platform.requests.map((r) => r.lastMsgID), contains(null));
    expect(
      platform.requests.map((r) => r.lastMsgID),
      contains('page1_old'),
      reason: 'older-history request must use the oldest visible msgID cursor',
    );
  });

  testWidgets('current fork does not expose multiSelect for text bubbles', (
    tester,
  ) async {
    await _pumpChat(tester);

    await _rightClick(tester, _textBubbleCore('page1_new'));

    expect(_menuItem('copy'), findsOneWidget);
    expect(_menuItem('delete'), findsOneWidget);
    expect(
      _menuItem('multiSelect'),
      findsNothing,
      reason: 'batch delete is not enabled because the fork strips multiSelect',
    );
  });
}
