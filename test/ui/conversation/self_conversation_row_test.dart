// The self conversation ("note to self") row and chat header: it offers no
// Delete or Hide anywhere — toxee's context menu (right-click / long-press),
// the UIKit row's swipe "More", its More sheet, its desktop fallback menu —
// while a friend's row keeps them; and its header shows "Saved on this device
// only" with no call actions. Mobile and desktop layouts both.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_builders.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_item.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/home/message_header_actions.dart';
import 'package:toxee/ui/home/toxee_message_header_info.dart';
import 'package:toxee/ui/home_page.dart' show buildConversationContextMenuItems;
import 'package:toxee/ui/testing/ui_keys.dart';

const _selfKey =
    'ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB';
const _selfToxId = '${_selfKey}0000000012EF';
const _friendKey =
    'CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCD';

/// The header only asks the service whether a conversation is the self one.
class _SelfOnlyService implements FfiChatService {
  @override
  bool isSelfPeer(String peerId) =>
      peerId.replaceFirst('c2c_', '').toUpperCase() == _selfKey;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        TencentCloudChatLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    );

V2TimConversation _c2c(String key, String name, {int unread = 0}) =>
    V2TimConversation(
      conversationID: 'c2c_$key',
      type: 1,
      userID: key,
      showName: name,
      unreadCount: unread,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  void signInAs(String userID) {
    final basic = TencentCloudChat.instance.dataInstance.basic;
    basic.updateCurrentUserInfo(
      userFullInfo: V2TimUserFullInfo(userID: userID),
    );
  }

  void useScreen(DeviceScreenType type) {
    TencentCloudChatScreenAdapter.deviceScreenType = type;
    TencentCloudChatScreenAdapter.hasInitialized = true;
    final data = TencentCloudChat.instance.dataInstance;
    data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
    data.conversation.conversationBuilder =
        TencentCloudChatConversationBuilders();
    data.conversation.conversationEventHandlers = null; // UIKit's own menus
    addTearDown(() {
      TencentCloudChatScreenAdapter.deviceScreenType = null;
      TencentCloudChatScreenAdapter.hasInitialized = false;
      data.conversation.conversationBuilder = null;
      data.basic.usedComponents = [];
    });
  }

  // The row's long-press deadline is 650 ms (it lets a slow swipe win the
  // arena), longer than tester.longPress holds; hold past it explicitly.
  Future<void> hold(WidgetTester tester, Finder finder) async {
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// The UIKit's signed-in user is global state; check the test still owns it
  /// so a failure says whether the row logic or the precondition broke.
  void expectSignedInAs(String userID) => expect(
        TencentCloudChat.instance.dataInstance.basic.currentUser?.userID,
        userID,
        reason: 'precondition: the UIKit current user is the test identity',
      );

  Future<void> pumpRow(WidgetTester tester, V2TimConversation conversation) =>
      tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              TencentCloudChatIntl().init(context);
              return TencentCloudChatConversationItem(
                conversation: conversation,
                isOnline: false,
              );
            },
          ),
        ),
      );

  testWidgets('toxee context menu: no Delete for the self conversation',
      (tester) async {
    late AppLocalizations l10n;
    late ColorScheme scheme;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      l10n = AppLocalizations.of(context)!;
      scheme = Theme.of(context).colorScheme;
      return const SizedBox.shrink();
    })));
    List<PopupMenuEntry<String>> items({required bool isSelf}) =>
        buildConversationContextMenuItems(
          l10n: l10n,
          scheme: scheme,
          isPinned: false,
          hasUnread: true,
          isSelf: isSelf,
        );
    final selfKeys = items(isSelf: true).map((e) => e.key).toSet();
    expect(selfKeys, isNot(contains(UiKeys.conversationContextMenuDeleteItem)));
    expect(items(isSelf: true).whereType<PopupMenuDivider>(), isEmpty);
    expect(selfKeys, contains(UiKeys.conversationContextMenuPinItem));
    expect(
      items(isSelf: false).map((e) => e.key),
      contains(UiKeys.conversationContextMenuDeleteItem),
    );
  });

  testWidgets('mobile row: swipe and long-press offer no Hide/Delete for self',
      (tester) async {
    useScreen(DeviceScreenType.mobile);
    signInAs(_selfToxId); // a Tox address: compared on its public key

    await pumpRow(tester, _c2c(_selfKey, 'Ann'));
    expectSignedInAs(_selfToxId);
    final selfCell = tester.widget<SwipeActionCell>(find.byType(SwipeActionCell));
    expect(selfCell.trailingActions, hasLength(1), reason: 'pin only');
    await hold(tester, find.text('Ann'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Hide'), findsNothing);

    await pumpRow(tester, _c2c(_friendKey, 'Bob'));
    await tester.pumpAndSettle();
    final friendCell =
        tester.widget<SwipeActionCell>(find.byType(SwipeActionCell));
    expect(friendCell.trailingActions, hasLength(2), reason: 'pin + More');
    await hold(tester, find.text('Bob'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('an unread self row keeps More, reduced to Mark as read',
      (tester) async {
    useScreen(DeviceScreenType.mobile);
    signInAs(_selfKey);
    await pumpRow(tester, _c2c(_selfKey, 'Ann', unread: 2));
    expectSignedInAs(_selfKey);
    final cell = tester.widget<SwipeActionCell>(find.byType(SwipeActionCell));
    expect(cell.trailingActions, hasLength(2), reason: 'pin + More');
    await hold(tester, find.text('Ann'));
    expect(find.text('Mark as Read'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Hide'), findsNothing);
  });

  testWidgets('desktop fallback menu offers no Hide/Delete for self',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    useScreen(DeviceScreenType.desktop);
    signInAs(_selfKey);

    await pumpRow(tester, _c2c(_selfKey, 'Ann'));
    expectSignedInAs(_selfKey);
    await tester.tap(find.text('Ann'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Hide'), findsNothing);
    expect(find.text('Pin'), findsOneWidget);
  });

  testWidgets('chat header: local-only subtitle, no call actions', (
    tester,
  ) async {
    signInAs(_selfKey);
    final service = _SelfOnlyService();
    MessageHeaderBuilderWidgets widgets() => MessageHeaderBuilderWidgets(
          messageHeaderProfileImage: const SizedBox(),
          messageHeaderInfo: const SizedBox(),
          messageHeaderActions: const Text('call actions'),
          messageHeaderMessagesSelectMode: const SizedBox(),
        );
    MessageHeaderBuilderData data(String key) => MessageHeaderBuilderData(
          userID: key,
          conversation: _c2c(key, 'x'),
          inSelectMode: false,
          selectAmount: 0,
          showUserOnlineStatus: true,
        );

    await tester.pumpWidget(_app(Builder(builder: (context) {
      return Column(children: [
        ToxeeMessageHeaderInfo(
          userID: _selfKey,
          conversation: _c2c(_selfKey, 'Ann'),
          showUserOnlineStatus: true,
          getUserOnlineStatus: ({required String userID}) => true,
          getGroupMembersInfo: () => const [],
        ),
        buildToxeeMessageHeaderActions(context,
            widgets: widgets(),
            data: data(_selfKey),
            service: service,
            isMounted: () => true),
        buildToxeeMessageHeaderActions(context,
            widgets: widgets(),
            data: data(_friendKey),
            service: service,
            isMounted: () => true),
      ]);
    })));
    await tester.pump();
    expect(find.text('Saved on this device only'), findsOneWidget);
    expect(find.text('Online'), findsNothing);
    expect(find.text('call actions'), findsOneWidget,
        reason: 'the friend keeps its actions; the self header has none');
  });
}
