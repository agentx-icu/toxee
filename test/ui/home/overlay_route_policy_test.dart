// UI-7: on the master-detail (wide) shell, opening a chat — notably from a
// notification tap — while a UIKit page (group profile / member list / member
// info) covers the window used to only rebind the hidden right pane: the tap
// looked dead. `openChatOnWideShell` binds the pane AND pops the covering
// full-window routes, keeping fullscreen-dialog surfaces (the AV conference
// session page) and stopping at the home shell (an AppPageRoute).
//
// Mobile parity: compact layouts never reach this helper — `_openChat` pushes
// the chat route there, which lands on top of any overlay and is visible.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';
import 'package:toxee/ui/home/overlay_route_policy.dart';
import 'package:toxee/ui/home/profile_send_message_navigation.dart';
import 'package:toxee/ui/widgets/app_page_route.dart';

void main() {
  final navKey = GlobalKey<NavigatorState>();

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Text('login'),
    ));
    // The home shell is an AppPageRoute on top of the login route, exactly as
    // LoginPage/StartupGate push HomePage.
    navKey.currentState!.push(AppPageRoute(page: const Text('shell')));
    await tester.pumpAndSettle();
  }

  void pushUikitPage(String name, {bool fullscreenDialog = false}) {
    navKey.currentState!.push(MaterialPageRoute<void>(
      fullscreenDialog: fullscreenDialog,
      settings: RouteSettings(name: name),
      builder: (_) => Scaffold(body: Text(name)),
    ));
  }

  testWidgets(
      'wide open pops the UIKit pages covering the shell and binds the pane',
      (tester) async {
    await pumpShell(tester);
    pushUikitPage('groupProfile');
    pushUikitPage('groupMemberList');
    await tester.pumpAndSettle();
    expect(find.text('groupMemberList'), findsOneWidget);

    var selected = 0;
    openChatOnWideShell(
      navigator: navKey.currentState,
      select: () => selected++,
    );
    expect(selected, 1, reason: 'the pane is bound synchronously');
    await tester.pumpAndSettle();

    expect(find.text('groupMemberList'), findsNothing);
    expect(find.text('groupProfile'), findsNothing);
    expect(find.text('shell'), findsOneWidget,
        reason: 'the pop must stop at the home shell, never dispose it');
  });

  testWidgets('a fullscreen-dialog surface (conference page) is kept',
      (tester) async {
    await pumpShell(tester);
    pushUikitPage('groupProfile');
    pushUikitPage('conference', fullscreenDialog: true);
    await tester.pumpAndSettle();

    openChatOnWideShell(navigator: navKey.currentState, select: () {});
    await tester.pumpAndSettle();

    expect(find.text('conference'), findsOneWidget,
        reason: 'an active conference session must not be torn down by an '
            'unrelated open');
  });

  testWidgets('L3 predicate (keepFullscreenDialogs: false) pops every page',
      (tester) async {
    await pumpShell(tester);
    pushUikitPage('groupProfile');
    pushUikitPage('selfProfile', fullscreenDialog: true);
    await tester.pumpAndSettle();

    // Not awaited before pumping: the pop waits for a frame the test pumps.
    final pop = popShellOverlayRoutes(
      navKey.currentState,
      keepFullscreenDialogs: false,
    );
    await tester.pumpAndSettle();
    await pop;

    expect(find.text('selfProfile'), findsNothing);
    expect(find.text('groupProfile'), findsNothing);
    expect(find.text('shell'), findsOneWidget);
  });

  testWidgets('nothing on top of the shell: open is a plain pane bind',
      (tester) async {
    await pumpShell(tester);
    var selected = 0;
    openChatOnWideShell(
      navigator: navKey.currentState,
      select: () => selected++,
    );
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('shell'), findsOneWidget);
  });

  // Compact (phone) shell: `_openChat` for the chat that is already the newest
  // pushed chat route does not push a duplicate — it used to return with a
  // group profile / member list still covering that chat. It now pops down to
  // the chat route and stops there.
  testWidgets('compact repeat open reveals the already-pushed chat route',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(navigatorKey: navKey, home: const Text('login')));
    navKey.currentState!.push(AppPageRoute(page: const Text('shell')));
    navKey.currentState!.push(MaterialPageRoute<void>(
      settings: RouteSettings(
        name: TencentCloudChatRouteNames.message,
        arguments: {
          'options': TencentCloudChatMessageOptions(groupID: 'tox_group_1'),
        },
      ),
      builder: (_) => const Scaffold(body: Text('chat tox_group_1')),
    ));
    pushUikitPage('groupProfile');
    pushUikitPage('groupMemberList');
    await tester.pumpAndSettle();

    final pop = popShellOverlayRoutes(
      navKey.currentState,
      stopAt: (r) => routeIsMessageFor(r, groupID: 'tox_group_1'),
    );
    await tester.pumpAndSettle();
    await pop;

    expect(find.text('chat tox_group_1'), findsOneWidget);
    expect(find.text('groupProfile'), findsNothing);
    expect(find.text('groupMemberList'), findsNothing);
  });
}
