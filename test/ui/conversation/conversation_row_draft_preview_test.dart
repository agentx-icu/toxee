// Regression guard for the conversation-row draft preview.
//
// A draft with a newline (the composer keeps multi-line text) used to be
// rendered as a bare `Text` inside the preview `Row` — no flex slot, no
// maxLines, no ellipsis — so the Text laid itself out at its widest line's
// intrinsic width and the row overflowed ("RIGHT OVERFLOWED BY 67 PIXELS").
// The preview is now a single ellipsized line in an `Expanded` slot, and the
// (empty) last-message slot yields its width to it. The same Row is used by
// the desktop and the mobile builder, so one test covers both.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_item.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

const _kRowWidth = 320.0;

Widget _host(V2TimConversation conversation) {
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
          // The content widget returns an `Expanded`, so it must live in a
          // Row of a known width — the same shape the real list row uses.
          return Center(
            child: SizedBox(
              width: _kRowWidth,
              child: Row(
                children: [
                  TencentCloudChatConversationItemContent(
                    conversation: conversation,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // `V2TimMessage(...)` stamps a server time through the native bindings, so
  // the SDK must resolve libtim2tox_ffi (same as bootstrap_nodes_page_test).
  setUpAll(() => setNativeLibraryName('tim2tox_ffi'));

  testWidgets(
    'a multi-line draft renders as one ellipsized line and never overflows',
    (tester) async {
      const draft =
          'RUIB6ML1-1782361445806405\nRUIB6ML2-1782361445806405 and more text';
      final conversation = V2TimConversation(
        conversationID: 'c2c_echo_live_test',
        type: 1,
        userID: 'echo_live_test',
        showName: 'echo_live_test',
        draftText: draft,
      );

      await tester.pumpWidget(_host(conversation));
      await tester.pump();

      // No RenderFlex overflow (it is reported as a framework exception).
      expect(tester.takeException(), isNull);

      final preview = find.textContaining('[Draft]');
      expect(preview, findsOneWidget);
      final text = tester.widget<Text>(preview);
      expect(text.textSpan!.toPlainText(), isNot(contains('\n')));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      // The preview is bounded by the row, not by its own intrinsic width.
      expect(tester.getRect(preview).width, lessThanOrEqualTo(_kRowWidth));
    },
  );

  testWidgets(
    'group @-tips share the same single ellipsized slot and never overflow',
    (tester) async {
      final conversation = V2TimConversation(
        conversationID: 'group_hikers',
        type: 2,
        groupID: 'hikers',
        showName: 'Weekend Hikers',
        groupAtInfoList: [
          V2TimGroupAtInfo(seq: '1', atType: 2),
          V2TimGroupAtInfo(seq: '2', atType: 1),
        ],
        lastMessage: V2TimMessage(
          msgID: 'm1',
          elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
          textElem: V2TimTextElem(
            text: 'a rather long last message that must be clipped',
          ),
        ),
      );

      await tester.pumpWidget(_host(conversation));
      await tester.pump();
      expect(tester.takeException(), isNull);

      final preview = find.textContaining('@');
      expect(preview, findsOneWidget);
      final text = tester.widget<Text>(preview);
      final plain = text.textSpan!.toPlainText();
      expect(plain, contains('['));
      expect(plain, contains('a rather long last message'));
      expect(text.maxLines, 1);
      expect(tester.getRect(preview).width, lessThanOrEqualTo(_kRowWidth));
    },
  );

  testWidgets('a draft preview takes the full preview width', (tester) async {
    final conversation = V2TimConversation(
      conversationID: 'c2c_peer',
      type: 1,
      userID: 'peer',
      showName: 'peer',
      draftText: 'x',
    );

    await tester.pumpWidget(_host(conversation));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final preview = find.textContaining('[Draft]');
    final previewRect = tester.getRect(preview);
    final contentRect = tester.getRect(
      find.byType(TencentCloudChatConversationItemContent),
    );
    // The empty last-message slot yields, so the draft's slot spans the
    // content width (a loose or split slot would stop well short of it).
    expect(previewRect.right, moreOrLessEquals(contentRect.right, epsilon: 1));
  });
}
