// P2 — history load-more + current fork multi-select status.
//
// The page under test is the real TencentCloudChatMessage surface. A recording
// SDK platform serves paged history and captures cursors. The first test proves
// the production list/provider requests older history with lastMsgID and renders
// the second page. The second test records the current fork truth: the text
// bubble menu does not expose multiSelect, so batch delete is not enabled.

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_builders.dart';
import 'package:tencent_cloud_chat_sdk/enum/V2TimUIKitListener.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

class _HistoryRequest {
  const _HistoryRequest({
    required this.getType,
    required this.lastMsgID,
    required this.count,
  });

  final int getType;
  final String? lastMsgID;
  final int count;

  @override
  bool operator ==(Object other) {
    return other is _HistoryRequest &&
        other.getType == getType &&
        other.lastMsgID == lastMsgID &&
        other.count == count;
  }

  @override
  int get hashCode => Object.hash(getType, lastMsgID, count);
}

class _HistoryPage {
  const _HistoryPage({
    required this.request,
    required this.messageIDs,
    required this.isFinished,
  });

  final _HistoryRequest request;
  final List<String> messageIDs;
  final bool isFinished;

  @override
  bool operator ==(Object other) {
    return other is _HistoryPage &&
        other.request == request &&
        const ListEquality<String>().equals(other.messageIDs, messageIDs) &&
        other.isFinished == isFinished;
  }

  @override
  int get hashCode => Object.hash(
    request,
    const ListEquality<String>().hash(messageIDs),
    isFinished,
  );
}

class _PagingSdkPlatform extends TencentCloudChatSdkPlatform {
  final List<_HistoryRequest> requests = [];
  final List<_HistoryPage> pages = [];
  final Map<String, V2TimUIKitListener> _listenersById = {};
  final List<String> addedListenerIds = [];
  final List<String> removedListenerIds = [];

  int _listenerSequence = 0;

  List<String> get activeListenerIds =>
      List<String>.unmodifiable(_listenersById.keys);

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
    final request = _HistoryRequest(
      getType: getType,
      lastMsgID: lastMsgID,
      count: count,
    );
    requests.add(request);
    if (lastMsgID == null) {
      final messageList = [
        _message('page1_new', 'newest page one', secondsAgo: 10),
        _message('page1_old', 'oldest page one', secondsAgo: 20),
      ];
      pages.add(
        _HistoryPage(
          request: request,
          messageIDs: messageList
              .map((message) => message.msgID ?? '')
              .toList(growable: false),
          isFinished: false,
        ),
      );
      return V2TimValueCallback(
        code: 0,
        desc: 'ok',
        data: V2TimMessageListResult(
          isFinished: false,
          messageList: messageList,
        ),
      );
    }
    if (lastMsgID == 'page1_old') {
      final messageList = [
        _message('page2_old', 'older page two', secondsAgo: 30),
      ];
      pages.add(
        _HistoryPage(
          request: request,
          messageIDs: messageList
              .map((message) => message.msgID ?? '')
              .toList(growable: false),
          isFinished: true,
        ),
      );
      return V2TimValueCallback(
        code: 0,
        desc: 'ok',
        data: V2TimMessageListResult(
          isFinished: true,
          messageList: messageList,
        ),
      );
    }
    pages.add(
      _HistoryPage(request: request, messageIDs: const [], isFinished: true),
    );
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
      _addUIKitListener(listener);

  @override
  void removeUIKitListener({String? uuid}) {
    if (uuid == null) {
      return;
    }
    if (_listenersById.remove(uuid) != null) {
      removedListenerIds.add(uuid);
    }
  }

  String _addUIKitListener(V2TimUIKitListener listener) {
    final listenerId = 'history_load_more_listener_${_listenerSequence++}';
    _listenersById[listenerId] = listener;
    addedListenerIds.add(listenerId);
    return listenerId;
  }
}

class _RecordingMessageReactionPlugin extends TencentCloudChatPlugin {
  int getMessageReactionsCalls = 0;

  @override
  Future<Map<String, dynamic>> init(String? data) async => <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> unInit(String? data) async =>
      <String, dynamic>{};

  @override
  TencentCloudChatPlugin getInstance() => this;

  @override
  Future<Map<String, dynamic>> callMethod({
    required String methodName,
    String? data,
  }) async {
    if (methodName == 'getMessageReactions') {
      getMessageReactionsCalls++;
    }
    return <String, dynamic>{};
  }

  @override
  Future<Widget?> getWidget({
    required String methodName,
    Map<String, String>? data,
    Map<String, TencentCloudChatPluginTapFn>? fns,
  }) async => null;

  @override
  Map<String, dynamic> callMethodSync({
    required String methodName,
    String? data,
  }) => <String, dynamic>{};

  @override
  Widget? getWidgetSync({
    required String methodName,
    Map<String, String>? data,
    Map<String, TencentCloudChatPluginTapFn>? fns,
  }) => null;
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

Future<_PagingSdkPlatform> _pumpChat(
  WidgetTester tester, {
  DeviceScreenType screenType = DeviceScreenType.desktop,
  _RecordingMessageReactionPlugin? messageReactionPlugin,
}) async {
  final physicalSize = screenType == DeviceScreenType.desktop
      ? const Size(1200, 720)
      : const Size(400, 800);
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  TencentCloudChatScreenAdapter.deviceScreenType = screenType;
  TencentCloudChatScreenAdapter.hasInitialized = true;
  addTearDown(() {
    TencentCloudChatScreenAdapter.deviceScreenType = null;
    TencentCloudChatScreenAdapter.hasInitialized = false;
  });

  final data = TencentCloudChat.instance.dataInstance;
  final previousCurrentUser = data.basic.currentUser;
  final previousHasLoggedIn = data.basic.hasLoggedIn;
  final previousPlugins = List<TencentCloudChatPluginItem>.of(
    data.basic.plugins,
  );
  final previousUsedComponents = List<TencentCloudChatComponentsEnum>.of(
    data.basic.usedComponents,
  );
  final previousConversationList = List<V2TimConversation>.of(
    data.conversation.conversationList,
  );
  final previousMessageListMap = Map<String, List<V2TimMessage>>.from(
    data.messageData.messageListMap,
  );
  final oldPlatform = TencentCloudChatSdkPlatform.instance;

  if (messageReactionPlugin != null) {
    data.basic.plugins = [
      ...previousPlugins.where((plugin) => plugin.name != 'messageReaction'),
      TencentCloudChatPluginItem(
        name: 'messageReaction',
        pluginInstance: messageReactionPlugin,
      ),
    ];
  }
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

  final platform = _PagingSdkPlatform();
  TencentCloudChatSdkPlatform.instance = platform;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      platform.addedListenerIds,
      isNotEmpty,
      reason: 'the message page must register at least one UIKit listener',
    );
    expect(
      platform.activeListenerIds,
      isEmpty,
      reason: 'the message page must remove every UIKit listener on dispose',
    );
    expect(
      platform.removedListenerIds,
      unorderedEquals(platform.addedListenerIds),
      reason:
          'add/remove UIKit listener ids must match exactly after widget disposal',
    );

    if (previousCurrentUser != null) {
      data.basic.updateCurrentUserInfo(userFullInfo: previousCurrentUser);
    } else {
      data.basic.clear();
      if (data.basic.hasLoggedIn != previousHasLoggedIn) {
        data.basic.updateLoginStatus(status: previousHasLoggedIn);
      }
    }

    data.basic.plugins = previousPlugins;
    data.basic.usedComponents = previousUsedComponents;
    data.messageData.messageListMap = previousMessageListMap;
    data.conversation.conversationList = previousConversationList;
    TencentCloudChatSdkPlatform.instance = oldPlatform;
  });

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

Future<T> _captureTccfLogs<T>(
  List<String> capturedLogs,
  Future<T> Function() body,
) {
  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (line.startsWith('TCCF:')) {
          capturedLogs.add(line);
        }
        parent.print(zone, line);
      },
    ),
  );
}

List<String> _logsForComponent(List<String> logs, String component) {
  final componentField = RegExp(
    ':${RegExp.escape(component)}:(?:none|debug|info|error|all):\\{ ',
  );
  return logs.where(componentField.hasMatch).toList(growable: false);
}

void _expectNoProhibitedTokens(
  List<String> logs,
  List<String> prohibitedTokens,
  String component,
) {
  for (final log in logs) {
    for (final prohibited in prohibitedTokens) {
      expect(
        log,
        isNot(contains(prohibited)),
        reason: '$component: $prohibited',
      );
    }
  }
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

Future<void> _longPress(WidgetTester tester, Finder target) async {
  await tester.longPress(target);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

Finder _messageRows() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('message_list_item:') &&
      !key.value.startsWith('message_list_item:time-divider-');
}, skipOffstage: false);

List<String> _renderedRowOrder(WidgetTester tester, List<String> messageIDs) {
  final rows =
      messageIDs
          .map(
            (messageID) =>
                MapEntry(messageID, tester.getRect(_rowItem(messageID)).top),
          )
          .toList(growable: false)
        ..sort((left, right) => left.value.compareTo(right.value));
  return rows.map((row) => row.key).toList(growable: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  testWidgets('history list auto-loads older page with exact trace', (
    tester,
  ) async {
    final platform = await _pumpChat(tester);

    expect(
      platform.requests,
      equals(<_HistoryRequest>[
        const _HistoryRequest(
          getType: HistoryMessageGetType.V2TIM_GET_CLOUD_OLDER_MSG,
          lastMsgID: null,
          count: 20,
        ),
        const _HistoryRequest(
          getType: HistoryMessageGetType.V2TIM_GET_CLOUD_OLDER_MSG,
          lastMsgID: 'page1_old',
          count: 20,
        ),
      ]),
    );
    expect(
      platform.pages,
      equals(<_HistoryPage>[
        const _HistoryPage(
          request: _HistoryRequest(
            getType: HistoryMessageGetType.V2TIM_GET_CLOUD_OLDER_MSG,
            lastMsgID: null,
            count: 20,
          ),
          messageIDs: <String>['page1_new', 'page1_old'],
          isFinished: false,
        ),
        const _HistoryPage(
          request: _HistoryRequest(
            getType: HistoryMessageGetType.V2TIM_GET_CLOUD_OLDER_MSG,
            lastMsgID: 'page1_old',
            count: 20,
          ),
          messageIDs: <String>['page2_old'],
          isFinished: true,
        ),
      ]),
    );

    expect(
      _messageRows(),
      findsNWidgets(3),
      reason: 'the real list should render exactly the three requested rows',
    );
    expect(
      _renderedRowOrder(tester, const <String>[
        'page1_new',
        'page1_old',
        'page2_old',
      ]),
      equals(const <String>['page2_old', 'page1_old', 'page1_new']),
      reason: 'the visible row order must match the reversed list layout',
    );
  });

  testWidgets('history diagnostics exclude identifiers and message payloads', (
    tester,
  ) async {
    final capturedLogs = <String>[];
    final reactionPlugin = _RecordingMessageReactionPlugin();

    await _captureTccfLogs(capturedLogs, () async {
      await _pumpChat(tester, messageReactionPlugin: reactionPlugin);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    });

    final sdkLogs = _logsForComponent(capturedLogs, 'GetHistoryMessageList');
    final messageDataLogs = _logsForComponent(
      capturedLogs,
      'GetHistoryMessageListMessageData',
    );
    final reactionLogs = _logsForComponent(capturedLogs, 'getMessageReactions');
    const historyProhibitedTokens = <String>[
      'conv:',
      'lastMsgID',
      'lastMsgSeq',
      'period:',
      'begin:',
      'Result:[',
      'friend1',
      'page1_new',
      'page1_old',
      'page2_old',
      'newest page one',
      'oldest page one',
      'older page two',
      'msgID',
      'textElem',
      'sender',
      'timestamp',
      'elem_type',
      'message_client_time',
      'message_msg_id',
    ];

    expect(sdkLogs, isNotEmpty);
    for (final log in sdkLogs) {
      expect(
        log,
        matches(
          RegExp(
            r'\{ getHistoryMessageListResult -- needCount:\d+ - ResultLength:\d+ - success:(?:true|false) - isFinished:(?:true|false|null) \}$',
          ),
        ),
      );
    }
    _expectNoProhibitedTokens(
      sdkLogs,
      historyProhibitedTokens,
      'GetHistoryMessageList',
    );

    expect(messageDataLogs, isNotEmpty);
    for (final log in messageDataLogs) {
      expect(
        log,
        matches(
          RegExp(
            r'\{ updateMessageList -- needCount:\d+ - ResultLength:\d+ - isFinished:(?:true|false) \}$',
          ),
        ),
      );
    }
    _expectNoProhibitedTokens(
      messageDataLogs,
      historyProhibitedTokens,
      'GetHistoryMessageListMessageData',
    );

    expect(reactionPlugin.getMessageReactionsCalls, greaterThan(0));
    expect(reactionLogs, isNotEmpty);
    for (final log in reactionLogs) {
      expect(
        log,
        matches(
          RegExp(
            r'\{ getMessageReactions -- messageCount:\d+ - includesWebInstances:(?:true|false) \}$',
          ),
        ),
      );
    }
    _expectNoProhibitedTokens(reactionLogs, <String>[
      ...historyProhibitedTokens,
      'webMessageInstanceList',
      'webMessageInstance',
      'messageFromWeb',
      'web_instance_',
    ], 'getMessageReactions');
  });

  testWidgets('desktop right-click keeps multiSelect hidden for text bubbles', (
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

  testWidgets('mobile long-press keeps multiSelect hidden for text bubbles', (
    tester,
  ) async {
    await _pumpChat(tester, screenType: DeviceScreenType.mobile);

    await _longPress(tester, _textBubbleCore('page1_new'));

    expect(_menuItem('copy'), findsOneWidget);
    expect(_menuItem('delete'), findsOneWidget);
    expect(
      _menuItem('multiSelect'),
      findsNothing,
      reason: 'batch delete is not enabled because the fork strips multiSelect',
    );
  });
}
