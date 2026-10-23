import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_item.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

V2TimConversation _conversation(String id) {
  return V2TimConversation(
    conversationID: id,
    type: 1,
    userID: id.replaceFirst('c2c_', ''),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'conversation avatar exposes the online-dot key on the actual status container',
    (tester) async {
      final conversation = _conversation('c2c_alice');

      await tester.pumpWidget(
        _wrap(
          TencentCloudChatConversationItemAvatar(
            conversation: conversation,
            isOnline: true,
          ),
        ),
      );
      await tester.pump();

      final dotFinder = find.byKey(
        UiKeys.conversationItemOnlineDot(conversation.conversationID),
      );
      expect(dotFinder, findsOneWidget);

      final dot = tester.widget<Container>(dotFinder);
      final decoration = dot.decoration as BoxDecoration;
      expect(
        decoration.color,
        TencentCloudChat
            .instance
            .dataInstance
            .theme
            .colorTheme
            .conversationItemUserStatusBgColor,
      );
      expect(
        find.byKey(
          Key(
            'conversation_item_online_dot:${conversation.conversationID}:online',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'conversation avatar keeps the online-dot key when offline and clears the fill',
    (tester) async {
      final conversation = _conversation('c2c_bob');

      await tester.pumpWidget(
        _wrap(
          TencentCloudChatConversationItemAvatar(
            conversation: conversation,
            isOnline: false,
          ),
        ),
      );
      await tester.pump();

      final dotFinder = find.byKey(
        UiKeys.conversationItemOnlineDot(conversation.conversationID),
      );
      expect(dotFinder, findsOneWidget);

      final dot = tester.widget<Container>(dotFinder);
      final decoration = dot.decoration as BoxDecoration;
      expect(decoration.color, Colors.transparent);
      expect(
        find.byKey(
          Key(
            'conversation_item_online_dot:${conversation.conversationID}:offline',
          ),
        ),
        findsOneWidget,
      );
    },
  );
}
