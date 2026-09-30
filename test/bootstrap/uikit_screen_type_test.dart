// L6 / L8 (MOBILE_DEVICE_FEATURES): UIKit's phone-vs-desktop BUILDER choice on
// iOS / Android follows toxee's shell, not UIKit's aspect-ratio rule.
//
// Found in a real Android split-screen pane (411x283 dp): toxee showed the
// phone shell (width < 800), but UIKit called the wider-than-tall window
// "desktop" — the Chats app bar lost its title row, "+" and search entry, and a
// pushed chat lost its back button.
//
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_platform_adapter.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_app_bar.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/bootstrap/app_runtime_bootstrap.dart';

void main() {
  tearDown(() {
    TencentCloudChatScreenAdapter.mobileScreenTypeResolver = null;
  });

  Future<DeviceScreenType> classify(WidgetTester tester, Size size) async {
    late DeviceScreenType result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (context) {
            result = TencentCloudChatScreenAdapter.resolveMobileScreenType(
              context,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return result;
  }

  group('without the toxee resolver (UIKit rule alone)', () {
    testWidgets('a short split pane is "desktop" — the mismatch', (
      tester,
    ) async {
      expect(
        await classify(tester, const Size(411, 283)),
        DeviceScreenType.desktop,
      );
    });
  });

  group('with the toxee resolver installed', () {
    setUp(() {
      TencentCloudChatScreenAdapter.mobileScreenTypeResolver =
          AppRuntimeBootstrap.uikitMobileScreenType;
    });

    final phoneShell = <String, Size>{
      'short split pane (API 36 phone, divider dragged up)': const Size(
        411,
        283,
      ),
      'half split pane': const Size(411, 452),
      'portrait phone': const Size(411, 914),
      'landscape phone under the 800 breakpoint': const Size(740, 360),
      'folded outer display (simulated)': const Size(336, 841),
      'just under the breakpoint, landscape': const Size(799, 400),
    };
    phoneShell.forEach((name, size) {
      testWidgets('$name $size -> mobile builders', (tester) async {
        expect(await classify(tester, size), DeviceScreenType.mobile);
      });
    });

    testWidgets('master-detail widths keep UIKit\'s own rule', (tester) async {
      // Landscape phone over 800 (API 36 phone rotated) and a tablet: desktop.
      expect(
        await classify(tester, const Size(914, 411)),
        DeviceScreenType.desktop,
      );
      expect(
        await classify(tester, const Size(1024, 768)),
        DeviceScreenType.desktop,
      );
      // Unfolded foldable / iPad portrait between 800 and 900: UIKit says
      // mobile, unchanged by this resolver.
      expect(
        await classify(tester, const Size(841, 1100)),
        DeviceScreenType.mobile,
      );
    });
  });

  // Renders the REAL UIKit conversation app bar as a phone would (the fork's
  // platform adapter reports mobile) and resizes the window live: the phone
  // builder carries the title row and toxee's "+" (trailingBuilder); the
  // tablet/desktop builder drops both.
  group('conversation app bar on a phone, live window resizes', () {
    const trailingKey = ValueKey('test_new_entry_button');

    setUp(() {
      TencentCloudChatPlatformAdapter.debugOverrideIsMobile(true);
      TencentCloudChatConversationAppBarName.trailingBuilder = (_) =>
          const SizedBox(key: trailingKey, width: 40, height: 40);
    });
    tearDown(() {
      TencentCloudChatPlatformAdapter.debugOverrideIsMobile(null);
      TencentCloudChatConversationAppBarName.trailingBuilder = null;
      TencentCloudChatScreenAdapter.deviceScreenType = null;
      TencentCloudChatScreenAdapter.hasInitialized = false;
    });

    Future<void> pumpAppBar(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
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
                return const TencentCloudChatConversationAppBar();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> resize(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
    }

    testWidgets('without the resolver a short split pane loses the "+"', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpAppBar(tester, const Size(411, 452));
      expect(find.byKey(trailingKey), findsOneWidget);
      await resize(tester, const Size(411, 283));
      expect(
        find.byKey(trailingKey),
        findsNothing,
        reason: 'the bug: UIKit switched to its tablet builder',
      );
    });

    testWidgets('with the resolver the phone app bar survives the resizes', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TencentCloudChatScreenAdapter.mobileScreenTypeResolver =
          AppRuntimeBootstrap.uikitMobileScreenType;
      await pumpAppBar(tester, const Size(411, 452));
      expect(find.byKey(trailingKey), findsOneWidget);
      for (final size in const [
        Size(411, 283), // divider dragged up
        Size(740, 360), // landscape phone under 800
        Size(411, 914), // back to full height
      ]) {
        await resize(tester, size);
        expect(find.byKey(trailingKey), findsOneWidget, reason: '$size');
        expect(tester.takeException(), isNull);
      }
      // Crossing into master-detail widths still hands over to UIKit's rule.
      await resize(tester, const Size(1000, 420));
      expect(find.byKey(trailingKey), findsNothing);
    });
  });
}
