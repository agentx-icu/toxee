import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/data/conversation/tencent_cloud_chat_conversation_data.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/home/toxee_message_header_info.dart';

/// Pins the compact-shell gap found by the iOS real-UI matrix (2026-08-24,
/// `conference_rename_leave` on iPhone and iPad): the pushed message route is
/// never rebuilt with a fresh conversation, so the header must follow UIKit's
/// conversation-list events itself (the row already showed the new name).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  V2TimConversation group(String name) => V2TimConversation(
    conversationID: 'group_tox_1',
    type: 2,
    groupID: 'tox_1',
    showName: name,
  );

  testWidgets('header title follows a conversation-list rename', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ToxeeMessageHeaderInfo(
          getUserOnlineStatus: ({required String userID}) => false,
          getGroupMembersInfo: () => const [],
          groupID: 'tox_1',
          conversation: group('RUI-OLD'),
          showUserOnlineStatus: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RUI-OLD'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat_header_title_text')),
      findsOneWidget,
    );

    final event = TencentCloudChatConversationData<dynamic>(
      TencentCloudChatConversationDataKeys.conversationList,
    )..conversationList = [group('RUI-NEW')];
    TencentCloudChat.instance.eventBusInstance.fire(
      event,
      'TencentCloudChatConversationData',
    );
    await tester.pumpAndSettle();
    expect(find.text('RUI-NEW'), findsOneWidget);
    expect(find.text('RUI-OLD'), findsNothing);

    // An event for some OTHER conversation must not touch this header.
    final other =
        TencentCloudChatConversationData<dynamic>(
            TencentCloudChatConversationDataKeys.conversationList,
          )
          ..conversationList = [
            V2TimConversation(
              conversationID: 'group_tox_9',
              type: 2,
              groupID: 'tox_9',
              showName: 'ELSEWHERE',
            ),
          ];
    TencentCloudChat.instance.eventBusInstance.fire(
      other,
      'TencentCloudChatConversationData',
    );
    await tester.pumpAndSettle();
    expect(find.text('RUI-NEW'), findsOneWidget);
  });

  testWidgets('a parent rebuild with a fresher same-id conversation wins', (
    tester,
  ) async {
    Widget header(String name) => host(
      ToxeeMessageHeaderInfo(
        getUserOnlineStatus: ({required String userID}) => false,
        getGroupMembersInfo: () => const [],
        groupID: 'tox_1',
        conversation: group(name),
        showUserOnlineStatus: false,
      ),
    );
    await tester.pumpWidget(header('RUI-OLD'));
    await tester.pumpAndSettle();
    TencentCloudChat.instance.eventBusInstance.fire(
      TencentCloudChatConversationData<dynamic>(
        TencentCloudChatConversationDataKeys.conversationList,
      )..conversationList = [group('RUI-EVENT')],
      'TencentCloudChatConversationData',
    );
    await tester.pumpAndSettle();
    expect(find.text('RUI-EVENT'), findsOneWidget);
    // The parent now rebuilds with an even newer name for the SAME id.
    await tester.pumpWidget(header('RUI-PARENT'));
    await tester.pumpAndSettle();
    expect(find.text('RUI-PARENT'), findsOneWidget);
    expect(find.text('RUI-EVENT'), findsNothing);
  });
}
