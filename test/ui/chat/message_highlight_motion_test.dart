import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/tencent_cloud_chat_message_item.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

class _HighlightProbe extends TencentCloudChatMessageItemBase {
  const _HighlightProbe({
    super.key,
    required super.data,
    required super.methods,
  });
  @override
  State<_HighlightProbe> createState() => _HighlightProbeState();
}

class _HighlightProbeState
    extends TencentCloudChatMessageState<_HighlightProbe> {
  @override
  void consoleLog(String logs) {}
  @override
  Widget defaultBuilder(BuildContext context) =>
      Text('highlight=$showHighlightStatus active=$isAnimating');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');
  late int cleared;
  late MessageItemBuilderData data;
  late MessageItemBuilderMethods methods;
  setUp(() {
    cleared = 0;
    data = MessageItemBuilderData(
      message: V2TimMessage(
        elemType: 1,
        msgID: 'highlight-message',
        isSelf: true,
      ),
      altText: 'message',
      enableParseMarkdown: false,
      showMessageStatusIndicator: false,
      showMessageTimeIndicator: false,
      shouldBeHighlighted: true,
      showMessageSenderName: false,
      messageRowWidth: 400,
      renderOnMenuPreview: false,
      inSelectMode: false,
      inMergerMessagePreviewMode: false,
      hasStickerPlugin: false,
    );
    methods = MessageItemBuilderMethods(
      clearHighlightFunc: () => cleared++,
      triggerLinkTappedEvent: (_) {},
      setMessageTextWithMentions:
          ({
            required String messageText,
            required List<String> groupMembersNeedToMention,
          }) {},
    );
  });
  Widget harness(bool reduced) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates:
        TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        TencentCloudChatIntl().init(context);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: _HighlightProbe(
            key: const ValueKey('highlight-probe'),
            data: data,
            methods: methods,
          ),
        );
      },
    ),
  );
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets(
    'reduced motion keeps one static cue instead of periodic flashes',
    (tester) async {
      await tester.pumpWidget(harness(true));
      expect(find.text('highlight=true active=true'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('highlight=true active=true'), findsOneWidget);
      }
      expect(cleared, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('highlight=false active=false'), findsOneWidget);
      await dispose(tester);
    },
  );

  testWidgets(
    'changing preference during a live highlight cancels periodic flashing',
    (tester) async {
      await tester.pumpWidget(harness(false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('highlight=false active=true'), findsOneWidget);
      await tester.pumpWidget(harness(true));
      expect(find.text('highlight=true active=true'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('highlight=true active=true'), findsOneWidget);
      expect(cleared, 1);
      await dispose(tester);
    },
  );

  testWidgets(
    'returning to motion preserves the original completion deadline',
    (tester) async {
      await tester.pumpWidget(harness(true));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpWidget(harness(false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('highlight=false active=true'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('highlight=true active=true'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('highlight=false active=false'), findsOneWidget);
      expect(cleared, 1);
      await dispose(tester);
    },
  );

  testWidgets(
    'normal motion preserves existing highlight and request completion',
    (tester) async {
      await tester.pumpWidget(harness(false));
      expect(find.text('highlight=true active=true'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('highlight=false active=true'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('highlight=true active=true'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('highlight=false active=false'), findsOneWidget);
      expect(cleared, 1);
      await dispose(tester);
    },
  );

  testWidgets(
    'disposing the highlighted row cancels deferred provider callbacks',
    (tester) async {
      await tester.pumpWidget(harness(false));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      expect(
        cleared,
        0,
        reason: 'a disposed conversation must not mutate a later owner',
      );
    },
  );
}
