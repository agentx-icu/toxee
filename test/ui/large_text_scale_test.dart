// L11 (doc/reference/MOBILE_DEVICE_FEATURES.md): with the largest system
// font, labels must stay whole words and every text must follow the scale.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_leading.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_user_profile_body.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/ui/widgets/search_utils.dart';
import 'package:toxee/util/bootstrap_nodes.dart';

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: TencentCloudChatLocalizations.localizationsDelegates,
  supportedLocales: TencentCloudChatLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  setUp(() {
    TencentCloudChat.instance.dataInstance.contact.buildUserStatusList([
      V2TimUserStatus(userID: 'peer', statusType: 1, onlineDevices: const []),
    ], 'test');
  });

  // flutter_test renders with Ahem (every glyph 1 em wide), so "message" at
  // 16 px is 112 px here — the widths below are chosen for that font.
  Future<List<double>> actionRows(
    WidgetTester tester,
    double scale, {
    required double width,
  }) async {
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        TencentCloudChatUserProfileChatButton(
          userFullInfo: V2TimUserFullInfo(userID: 'peer'),
          isNavigatedFromChat: true,
        ),
        scale: scale,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return [
      for (final key in [
        'friend_profile_send_message_tile',
        'friend_profile_voice_call_tile',
      ])
        tester.getTopLeft(find.byKey(ValueKey(key))).dy,
    ];
  }

  testWidgets('profile actions sit side by side at the default size', (
    tester,
  ) async {
    final rows = await actionRows(tester, 1, width: 800);
    expect(rows[0], rows[1]);
  });

  testWidgets('profile actions stack rather than split a word at 2x', (
    tester,
  ) async {
    final rows = await actionRows(tester, 2, width: 800);
    expect(rows[1], greaterThan(rows[0]), reason: 'one action per row');
  });

  testWidgets('search highlights follow the system text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SearchUtils.buildHighlightedText(
          'hello world',
          'wor',
          const TextStyle(fontSize: 14),
        ),
        scale: 2,
      ),
    );
    final text = tester.widget<RichText>(find.byType(RichText).first);
    expect(text.textScaler, const TextScaler.linear(2));
  });

  Future<double> leadingWidth(
    WidgetTester tester, {
    required double scale,
    required double screen,
  }) async {
    tester.view.physicalSize = Size(screen, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late double width;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            TencentCloudChatIntl().init(context);
            width = TencentCloudChatContactLeading.width(context);
            return const SizedBox();
          },
        ),
        scale: scale,
      ),
    );
    return width;
  }

  testWidgets('the contact back leading fits its label, not more', (
    tester,
  ) async {
    // Ahem: "Back" at 14 px = 56 px; with icon and padding just over 100.
    expect(
      await leadingWidth(tester, scale: 1, screen: 400),
      closeTo(10 + 24 + 8 + 56 + 4, 0.5),
    );
    // At 2x: 112 px of label.
    final large = await leadingWidth(tester, scale: 2, screen: 800);
    expect(large, closeTo(10 + 24 + 8 + 112 + 4, 0.5));
    // A narrow phone keeps 60% for the title; the label ellipsizes.
    expect(await leadingWidth(tester, scale: 2, screen: 320), 128);
  });

  test('a node address breaks before its port, never inside it', () {
    expect(displayBootstrapEndpoint('1.2.3.4', 33445), '1.2.3.4:​33445');
    expect(displayBootstrapEndpoint('::1', 33445), '[::1]:​33445');
    expect(formatBootstrapEndpoint('1.2.3.4', 33445), '1.2.3.4:33445');
  });
}
