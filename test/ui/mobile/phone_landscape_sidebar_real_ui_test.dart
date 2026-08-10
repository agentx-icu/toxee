// Real-UI gate for the LANDSCAPE-PHONE navigation rail — the deliberately
// counter-intuitive tier of `ResponsiveLayout`.
//
// A phone in landscape (844x390) has shortestSide 390, so every device-class
// helper (`isMobile`) still says "phone". But the layout-capacity helpers use
// WIDTH: 844 clears `largePhoneBreakpoint` (720), so `shouldShowBottomNav` is
// FALSE and `responsiveSidebarWidth` returns 72 — the compact, icon-only rail —
// even though the device is a phone. `home_page.dart` renders exactly that:
//   SizedBox(width: ResponsiveLayout.responsiveSidebarWidth(context),
//            child: buildSidebar(...))
// which this file mirrors, then drives the REAL rail items with real taps.
//
// What is asserted (rendered widgets + real callbacks, never boolean helpers):
//   * the rail lays out at 72pt from the production width helper;
//   * `isCompactRail` is in force — the item LABELS are not rendered and the
//     label is surfaced through the compact `Tooltip` instead (the fallback
//     affordance that only exists in the compact branch);
//   * every rail item still routes its own tab index through the real `onTap`.
//
// The PORTRAIT phone (390x844) counterpart is intentionally absent: there the
// production width helper returns 0 and `home_page.dart` does not build the rail
// at all (bottom-nav tier), so rendering it would be testing a layout the app
// never produces. The portrait tier's user-visible fork is covered by
// `settings_mobile_index_real_ui_test.dart`.
//
// Mobile parity: `sidebar.dart` + `responsive_layout.dart` are shared Dart, so
// this is the same rail iOS/Android get when a phone is rotated.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/sidebar.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/responsive_layout.dart';

const String _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567';

/// The rotated phone: shortestSide 390 (mobile tier) but width 844 (>= 720, so
/// sidebar tier; also >= 800, the master-detail breakpoint).
const Size _landscapePhone = Size(844, 390);

/// Key on the rail host so its laid-out width can be measured.
const Key _railHostKey = ValueKey('landscape_rail_host');

class _SidebarHarnessService extends FfiChatService {
  _SidebarHarnessService() : super();

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  @override
  String get selfId => _toxId;

  @override
  String? getSelfToxId() => _toxId;

  @override
  Future<void> updateSelfProfile({
    required String nickname,
    required String statusMessage,
  }) async {}

  @override
  Future<void> updateAvatar(String? avatarPath) async {}

  void disposeStub() => unawaited(_connection.close());
}

Widget _app(Widget child) {
  return MaterialApp(
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
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempRoot;

  setUp(() async {
    // Without this the host OS makes `_isDesktopPlatform()` true, `isDesktop`
    // returns true for any viewport and the rail would resolve to the 200pt
    // labelled desktop rail instead of the 72pt phone-landscape one.
    ResponsiveLayout.debugIsDesktopPlatformOverride = () => false;

    tempRoot = await Directory.systemTemp.createTemp(
      'phone_landscape_sidebar_',
    );
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      platformChannel,
      (MethodCall call) async => null,
    );
    messenger.setMockMethodCallHandler(pathProviderChannel, (
      MethodCall call,
    ) async {
      switch (call.method) {
        case 'getApplicationSupportDirectory':
        case 'getApplicationDocumentsDirectory':
          return tempRoot.path;
        case 'getApplicationCacheDirectory':
          return p.join(tempRoot.path, 'cache');
        case 'getTemporaryDirectory':
          return p.join(tempRoot.path, 'temp');
        case 'getDownloadsDirectory':
          return p.join(tempRoot.path, 'Downloads');
        default:
          return null;
      }
    });

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(_toxId);
    await Prefs.setNickname('Rail Nick');
    await Prefs.setStatusMessage('Rail Status');
    // Keep the chats-tab unread badge out of the picture and leave the shared
    // conversation data layer as we found it (process-global singleton).
    TencentCloudChat.instance.dataInstance.conversation.setTotalUnreadCount(0);
  });

  tearDown(() {
    // Process-global: must be cleared or later suites silently switch tiers.
    ResponsiveLayout.debugIsDesktopPlatformOverride = null;
    TencentCloudChat.instance.dataInstance.conversation.setTotalUnreadCount(0);
    messenger.setMockMethodCallHandler(platformChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  void useLandscapePhone(WidgetTester tester) {
    tester.view.physicalSize = _landscapePhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Mirrors `home_page.dart`'s rail host: the width comes from the production
  /// helper, not from a hard-coded test constant.
  Widget railHost(FfiChatService service, void Function(int) onTap) {
    return Builder(
      builder: (context) => Row(
        children: [
          SizedBox(
            key: _railHostKey,
            width: ResponsiveLayout.responsiveSidebarWidth(context),
            child: buildSidebar(
              context: context,
              selectedIndex: 0,
              onTap: onTap,
              service: service,
              connectionStatusStream: service.connectionStatusStream,
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }

  testWidgets(
    'landscape phone: the rail is the 72pt icon-only compact rail — labels are '
    'replaced by tooltips',
    (WidgetTester tester) async {
      final service = _SidebarHarnessService();
      addTearDown(service.disposeStub);
      useLandscapePhone(tester);

      await tester.pumpWidget(_app(railHost(service, (_) {})));
      await _settle(tester);

      // The production width helper resolves to the compact rail on a rotated
      // phone (width 844 >= 720 -> no bottom nav; not desktop -> 72, not 200).
      expect(
        tester.getSize(find.byKey(_railHostKey)).width,
        72.0,
        reason:
            'a landscape phone must lay the rail out at the compact 72pt width',
      );

      // Compact branch: every item renders its icon only...
      for (final icon in const <IconData>[
        Icons.chat_bubble_outline,
        Icons.contacts,
        Icons.apps,
        Icons.settings,
      ]) {
        expect(
          find.byIcon(icon),
          findsOneWidget,
          reason: 'compact rail must still render the $icon entry',
        );
      }

      // ...and the text labels are NOT rendered (there is no room for them at
      // 72pt — rendering them was the historical RenderFlex overflow).
      for (final label in const <String>[
        'Chats',
        'Contacts',
        'Applications',
        'Settings',
      ]) {
        expect(
          find.text(label),
          findsNothing,
          reason: 'compact rail must hide the "$label" label',
        );
        // The compact branch is the ONLY branch that wraps the icon in a
        // Tooltip, so this is a positive proof that `isCompactRail` won — not
        // just an absence check.
        expect(
          find.byTooltip(label),
          findsOneWidget,
          reason: 'compact rail must surface "$label" as a tooltip instead',
        );
      }
    },
  );

  testWidgets(
    'landscape phone: each compact rail item taps through to its own tab index',
    (WidgetTester tester) async {
      final service = _SidebarHarnessService();
      addTearDown(service.disposeStub);
      useLandscapePhone(tester);

      final tapped = <int>[];
      await tester.pumpWidget(_app(railHost(service, tapped.add)));
      await _settle(tester);

      expect(tapped, isEmpty, reason: 'rendering must not select a tab');

      // REAL taps on the production rail items, in a non-sequential order so a
      // "returns the item position" bug cannot pass by accident.
      await tester.tap(find.byKey(UiKeys.sidebarSettings));
      await tester.pump();
      await tester.tap(find.byKey(UiKeys.sidebarChats));
      await tester.pump();
      await tester.tap(find.byKey(UiKeys.sidebarApplications));
      await tester.pump();
      await tester.tap(find.byKey(UiKeys.sidebarContacts));
      await tester.pump();

      expect(
        tapped,
        <int>[3, 0, 2, 1],
        reason:
            'the compact rail must still route each entry to its own tab index',
      );
    },
  );
}
