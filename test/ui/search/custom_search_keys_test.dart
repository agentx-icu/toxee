import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/chat_sdk/components/tencent_cloud_chat_search_sdk.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/search/custom_search.dart';
import 'package:toxee/ui/search/search_chat_history_window.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/ui/widgets/search_utils.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

Future<void> _pumpSettled(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness(child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

V2TimMessage _textMessage({required String msgId, required String text}) {
  return V2TimMessage.fromJson(<String, dynamic>{
    'message_conv_type': 1,
    'message_conv_id': 'friend_123',
    'message_sender': '',
    'message_client_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'message_server_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'message_msg_id': msgId,
    'message_elem_array': <Map<String, dynamic>>[
      V2TimTextElem(text: text).toJson(),
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('search anchors', () {
    testWidgets('CustomSearch exposes a stable search field key', (
      tester,
    ) async {
      await _pumpSettled(tester, const CustomSearch());

      expect(find.byKey(UiKeys.messageSearchField), findsOneWidget);
    });

    testWidgets(
      'SearchChatHistoryWindow exposes stable result and message row keys',
      (tester) async {
        final result = TencentCloudChatSearchResultItemData(
          conversationID: 'c2c_friend_123',
          showName: 'Friend 123',
          messageList: <V2TimMessage>[
            _textMessage(msgId: 'msg-1', text: 'pizza keyword'),
          ],
        );

        await _pumpSettled(
          tester,
          SearchChatHistoryWindow(
            initialKeyword: 'pizza',
            messageSearchResults: <TencentCloudChatSearchResultItemData>[
              result,
            ],
            initialSelectedResult: result,
            onNavigateToMessage:
                ({
                  String? userID,
                  String? groupID,
                  V2TimMessage? targetMessage,
                }) {},
          ),
        );

        expect(find.byKey(UiKeys.messageSearchField), findsOneWidget);
        expect(
          find.byKey(UiKeys.searchResultMessage('c2c_friend_123')),
          findsOneWidget,
        );
        expect(
          find.byKey(UiKeys.searchHistoryMessage('msg-1')),
          findsOneWidget,
        );
      },
    );
  });

  // S93 — in-conversation message search: the MATCHING + per-message HIGHLIGHT
  // (the half the anchor tests above don't cover — they render pre-built
  // results, this proves the keyword filter + highlight logic).
  group('S93 message search matching + highlight', () {
    testWidgets(
      'SearchChatHistoryWindow renders only messages matching the keyword',
      (tester) async {
        // One matching ("pizza"), one not ("hello world"). The window filters
        // each result.messageList through _messageMatchesKeyword on the initial
        // keyword, so only the match should render.
        final result = TencentCloudChatSearchResultItemData(
          conversationID: 'c2c_friend_123',
          showName: 'Friend 123',
          messageList: <V2TimMessage>[
            _textMessage(msgId: 'match-1', text: 'pizza tonight?'),
            _textMessage(msgId: 'nomatch-1', text: 'hello world'),
          ],
        );

        await _pumpSettled(
          tester,
          SearchChatHistoryWindow(
            initialKeyword: 'pizza',
            messageSearchResults: <TencentCloudChatSearchResultItemData>[
              result,
            ],
            initialSelectedResult: result,
            onNavigateToMessage:
                ({
                  String? userID,
                  String? groupID,
                  V2TimMessage? targetMessage,
                }) {},
          ),
        );

        expect(find.byKey(UiKeys.searchHistoryMessage('match-1')), findsOneWidget,
            reason: 'the "pizza" message must survive the keyword filter');
        expect(find.byKey(UiKeys.searchHistoryMessage('nomatch-1')), findsNothing,
            reason: 'the non-matching "hello world" message must be filtered out');
      },
    );

    test('buildHighlightedText highlights the matched keyword span only', () {
      const base = TextStyle(fontSize: 14);
      final widget =
          SearchUtils.buildHighlightedText('order a pizza tonight', 'pizza', base);
      // Text.rich (not RichText: that ignores the system text scale, L11).
      expect(widget, isA<Text>().having((t) => t.textSpan, 'textSpan', isNotNull),
          reason: 'a non-empty keyword match must produce spans, not a plain Text');
      final spans = ((widget as Text).textSpan! as TextSpan)
          .children!
          .cast<TextSpan>();

      final keywordSpan = spans.firstWhere((s) => s.text == 'pizza');
      expect(keywordSpan.style?.fontWeight, FontWeight.w600,
          reason: 'the matched keyword must be emphasized');
      expect(keywordSpan.style?.backgroundColor, isNotNull,
          reason: 'the matched keyword must carry the highlight background');

      // EVERY surrounding non-keyword span must stay plain: no highlight
      // background AND the base weight (not the w600 the keyword span gets) —
      // otherwise a regression that bolds/looks-up the wrong range would pass.
      final plainSpans = spans.where((s) => s.text != 'pizza').toList();
      expect(plainSpans, isNotEmpty);
      for (final s in plainSpans) {
        expect(s.style?.backgroundColor, isNull,
            reason: 'non-matching text must not carry the highlight background');
        expect(s.style?.fontWeight, isNot(FontWeight.w600),
            reason: 'non-matching text must keep the base weight, not bold');
      }
    });

    test('buildHighlightedText is case-insensitive; empty keyword → plain Text',
        () {
      const base = TextStyle();
      final ci = SearchUtils.buildHighlightedText('Pizza party', 'PIZZA', base);
      final spans = ((ci as Text).textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(
          spans.any(
              (s) => s.text == 'Pizza' && s.style?.fontWeight == FontWeight.w600),
          isTrue,
          reason: 'case-insensitive match must still highlight the original case');

      expect(
          SearchUtils.buildHighlightedText('hello', '', base),
          isA<Text>().having((t) => t.textSpan, 'textSpan', isNull),
          reason: 'an empty keyword must fall back to a plain Text (no highlight)');
    });
  });
}
