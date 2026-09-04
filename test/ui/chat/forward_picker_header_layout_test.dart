// Regression guard for the forward picker header layout.
//
// The header is a three-slot Row: Cancel (start) / title (center) / Send
// (end). The middle slot used to be `Flexible`, which only takes the title's
// intrinsic width; Flutter's flex layout does not hand the unused share back
// to the siblings, so the trailing slot started right after the title and
// "Send" sat roughly (1/3 of the width − title width) short of the right edge
// on the desktop dialog, with the title left of center. The middle slot is now
// `Expanded`; this test pins the geometry: the Send button ends at the same
// inset from the right edge as Cancel starts from the left, and the title is
// centered on the sheet. The header is shared by the desktop dialog and the
// mobile bottom sheet, so one test covers both.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/forward/tencent_cloud_chat_message_forward.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hostWidth = 900.0;
  const hostHeight = 600.0;

  Future<void> pumpPicker(WidgetTester tester) async {
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
              return Center(
                child: SizedBox(
                  width: hostWidth,
                  height: hostHeight,
                  child: TencentCloudChatMessageForward(
                    data: MessageForwardBuilderData(
                      type: TencentCloudChatForwardType.individually,
                      // A few rows so the mobile sheet (chosen when the test
                      // host is not detected as desktop) sizes itself from
                      // real content instead of the bare header estimate.
                      conversationList: [
                        for (var i = 0; i < 3; i++)
                          V2TimConversation(
                            conversationID: 'c2c_peer$i',
                            type: 1,
                            userID: 'peer$i',
                            showName: 'Peer $i',
                          ),
                      ],
                      contactList: const [],
                      groupList: const [],
                    ),
                    methods: MessageForwardBuilderMethods(
                      onSelectConversations: (_) {},
                      onCancel: () {},
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'Send is flush with the trailing edge and the title is centered',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpPicker(tester);

      final host = tester.getRect(find.byType(TencentCloudChatMessageForward));
      final cancel = tester.getRect(
        find.byKey(const ValueKey('forward_picker_cancel_button')),
      );
      final send = tester.getRect(
        find.byKey(const ValueKey('forward_picker_send_button')),
      );

      final leadingInset = cancel.left - host.left;
      final trailingInset = host.right - send.right;
      // Symmetric insets: the Send button must end as close to the right
      // edge as Cancel starts from the left (both are the Row padding).
      expect(
        trailingInset,
        moreOrLessEquals(leadingInset, epsilon: 1.0),
        reason:
            'Send must sit at the trailing edge; a loose middle slot leaves '
            'it ~(width/3 − title width) short of it',
      );

      // The title is the header text between the two buttons.
      final title = tester.getRect(find.text('Forward Individually'));
      expect(
        title.center.dx,
        moreOrLessEquals(host.center.dx, epsilon: 1.0),
        reason: 'the title must be centered on the sheet',
      );
    },
  );
}
