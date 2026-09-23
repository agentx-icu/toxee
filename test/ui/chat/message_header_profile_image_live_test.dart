// UI-9: the chat header AVATAR must follow the live conversation the way the
// title does (`ToxeeMessageHeaderInfo`). A new group avatar picked on the group
// profile reached the conversation row, but the open chat's header kept the
// conversation captured when the chat opened — on a compact shell the pushed
// message route is never rebuilt, so it stayed stale until the chat reopened.
// Shared fork Dart: the same widget is the header on desktop, tablet and phone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/data/conversation/tencent_cloud_chat_conversation_data.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/widgets/avatar/tencent_cloud_chat_avatar.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_header/tencent_cloud_chat_message_header_profile_image.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  V2TimConversation group(String face, {String id = 'tox_1'}) =>
      V2TimConversation(
        conversationID: 'group_$id',
        type: 2,
        groupID: id,
        showName: 'G',
        faceUrl: face,
      );

  String? shownFace(WidgetTester tester) => tester
      .widget<TencentCloudChatAvatar>(find.byType(TencentCloudChatAvatar))
      .imageList
      .first;

  void fire(List<V2TimConversation> list) {
    TencentCloudChat.instance.eventBusInstance.fire(
      TencentCloudChatConversationData<dynamic>(
        TencentCloudChatConversationDataKeys.conversationList,
      )..conversationList = list,
      'TencentCloudChatConversationData',
    );
  }

  Widget host(V2TimConversation conv) => MaterialApp(
        home: Scaffold(
          body: TencentCloudChatMessageHeaderProfileImage(
            getGroupMembersInfo: () => const [],
            conversation: conv,
          ),
        ),
      );

  testWidgets('header avatar follows a conversation-list avatar change',
      (tester) async {
    await tester.pumpWidget(host(group('/nonexistent/group_tox_1_old.png')));
    await tester.pumpAndSettle();
    expect(shownFace(tester), '/nonexistent/group_tox_1_old.png');

    fire([group('/nonexistent/group_tox_1_new.png')]);
    await tester.pumpAndSettle();
    expect(shownFace(tester), '/nonexistent/group_tox_1_new.png');

    // Another conversation's change must not leak into this header.
    fire([group('/nonexistent/other.png', id: 'tox_9')]);
    await tester.pumpAndSettle();
    expect(shownFace(tester), '/nonexistent/group_tox_1_new.png');
  });

  testWidgets('a parent rebuild with a fresher conversation wins',
      (tester) async {
    await tester.pumpWidget(host(group('/nonexistent/a.png')));
    await tester.pumpAndSettle();
    fire([group('/nonexistent/event.png')]);
    await tester.pumpAndSettle();
    expect(shownFace(tester), '/nonexistent/event.png');
    await tester.pumpWidget(host(group('/nonexistent/parent.png')));
    await tester.pumpAndSettle();
    expect(shownFace(tester), '/nonexistent/parent.png');
  });
}
