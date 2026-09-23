// Regression tests for the profile "Send a message" navigation policy
// (lib/ui/home/profile_send_message_navigation.dart).
//
// Bug fixed: opening a friend's profile from the CHAT-HEADER avatar and
// tapping "Send a message" pushed a fresh profile page instead of returning
// to the chat — endlessly. Root cause was a single UIKit handler slot
// (onNavigateToChat aliased onTapContactItem) that forced HomePage to guess
// the firing surface from a flag only the contacts-tab path set. The fork now
// has a dedicated onNavigateToChat slot and this policy handles it with a
// real Navigator-stack check instead of a side-channel flag.
//
// These tests drive the policy against a REAL Navigator whose routes carry
// the same RouteSettings (name + {'options': ...}) that
// TencentCloudChatRouter.navigateTo produces.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';
import 'package:toxee/ui/home/profile_send_message_navigation.dart';

const _userA = // 76-char full Tox id (64-char pk + nospam/checksum suffix)
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    '0123456789AB';
const _userAPk = // the 64-char public-key form of the same identity
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _groupG = 'group-g';

final _navKey = GlobalKey<NavigatorState>();

NavigatorState get _nav => _navKey.currentState!;

Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navKey,
      home: const Scaffold(body: Text('home-root')),
    ),
  );
}

/// Pushes a route shaped exactly like TencentCloudChatRouter.navigateTo's
/// output: MaterialPageRoute + RouteSettings(name, {'options': ...}).
Future<void> _pushUikitRoute(
  WidgetTester tester,
  String routeName, {
  Object? options,
  String? label,
}) async {
  unawaited(
    _nav.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: Text(label ?? routeName)),
        settings: RouteSettings(name: routeName, arguments: {
          'options': options,
        }),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<({String? peerId, String? groupId})> _driveSendMessage(
  WidgetTester tester, {
  required bool isCompactLayout,
  String? userID,
  String? groupID,
  int fires = 1,
}) {
  final opened = <({String? peerId, String? groupId})>[];
  for (var i = 0; i < fires; i++) {
    final handled = handleProfileSendMessage(
      _nav,
      isCompactLayout: isCompactLayout,
      openChat: ({String? peerId, String? groupId}) =>
          opened.add((peerId: peerId, groupId: groupId)),
      userID: userID,
      groupID: groupID,
    );
    expect(handled, isTrue);
  }
  return opened;
}

void main() {
  testWidgets(
      'REGRESSION chat-header origin: send-a-message pops the profile and '
      'opens the chat instead of pushing another profile (desktop)',
      (tester) async {
    await _pumpHost(tester);
    // Desktop master-detail: chat is the home pane; header avatar pushes the
    // profile route directly (no contacts-tab flag involved).
    await _pushUikitRoute(tester, TencentCloudChatRouteNames.userProfile,
        label: 'profile-A');
    expect(find.text('profile-A'), findsOneWidget);

    final opened =
        _driveSendMessage(tester, isCompactLayout: false, userID: _userA);
    await tester.pumpAndSettle();

    // Profile popped, chat opened exactly once — no second profile push.
    expect(find.text('profile-A'), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
    expect(opened, [(peerId: _userA, groupId: null)]);
  });

  testWidgets(
      'double-fire is idempotent: the second fire must not pop the route '
      'revealed beneath the profile', (tester) async {
    await _pumpHost(tester);
    await _pushUikitRoute(tester, TencentCloudChatRouteNames.userProfile,
        label: 'profile-A');

    // flutter_skill-style double-fire: onTap invoked twice back-to-back.
    final opened = _driveSendMessage(tester,
        isCompactLayout: false, userID: _userA, fires: 2);
    await tester.pumpAndSettle();

    // Only the profile is gone; home-root survived the second fire.
    expect(find.text('home-root'), findsOneWidget);
    expect(opened, hasLength(2)); // re-bind is harmless
  });

  testWidgets(
      'compact from-chat: pop reveals the target chat, no duplicate chat '
      'route is pushed (id normalization: 76-char profile id vs 64-char pk)',
      (tester) async {
    await _pumpHost(tester);
    await _pushUikitRoute(
      tester,
      TencentCloudChatRouteNames.message,
      options: TencentCloudChatMessageOptions(userID: _userAPk, groupID: null),
      label: 'chat-A',
    );
    await _pushUikitRoute(tester, TencentCloudChatRouteNames.userProfile,
        label: 'profile-A');

    final opened =
        _driveSendMessage(tester, isCompactLayout: true, userID: _userA);
    await tester.pumpAndSettle();

    // Back in the existing chat; nothing pushed on top of it.
    expect(find.text('chat-A'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets(
      'compact from contacts tab: pop reveals home, chat is opened via '
      'openChat', (tester) async {
    await _pumpHost(tester);
    await _pushUikitRoute(tester, TencentCloudChatRouteNames.userProfile,
        label: 'profile-A');

    final opened =
        _driveSendMessage(tester, isCompactLayout: true, userID: _userA);
    await tester.pumpAndSettle();

    expect(find.text('home-root'), findsOneWidget);
    expect(opened, [(peerId: _userA, groupId: null)]);
  });

  testWidgets(
      'compact group-member profile: underlying GROUP chat does not satisfy '
      'the c2c dedupe — the 1:1 chat is opened', (tester) async {
    await _pumpHost(tester);
    await _pushUikitRoute(
      tester,
      TencentCloudChatRouteNames.message,
      options: TencentCloudChatMessageOptions(userID: null, groupID: _groupG),
      label: 'chat-G',
    );
    await _pushUikitRoute(tester, TencentCloudChatRouteNames.userProfile,
        label: 'profile-A');

    final opened =
        _driveSendMessage(tester, isCompactLayout: true, userID: _userA);
    await tester.pumpAndSettle();

    expect(opened, [(peerId: _userA, groupId: null)]);
  });

  testWidgets(
      'group profile send-message: pops the group profile; compact dedupe '
      'matches the group chat beneath', (tester) async {
    await _pumpHost(tester);
    await _pushUikitRoute(
      tester,
      TencentCloudChatRouteNames.message,
      options: TencentCloudChatMessageOptions(userID: null, groupID: _groupG),
      label: 'chat-G',
    );
    await _pushUikitRoute(tester, TencentCloudChatRouteNames.groupProfile,
        label: 'group-profile-G');

    final opened =
        _driveSendMessage(tester, isCompactLayout: true, groupID: _groupG);
    await tester.pumpAndSettle();

    expect(find.text('group-profile-G'), findsNothing);
    expect(find.text('chat-G'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('empty target is reported unhandled and pops nothing',
      (tester) async {
    await _pumpHost(tester);
    await _pushUikitRoute(tester, TencentCloudChatRouteNames.userProfile,
        label: 'profile-A');

    final handled = handleProfileSendMessage(
      _nav,
      isCompactLayout: false,
      openChat: ({String? peerId, String? groupId}) =>
          fail('openChat must not be called for an empty target'),
    );
    await tester.pumpAndSettle();

    expect(handled, isFalse);
    expect(find.text('profile-A'), findsOneWidget);
  });

  // finishLeaveGroup must close exactly the group profile it was started from.
  // It used to `maybePop()` whatever was on top — after the (network-bound)
  // quit, that could be a dialog that opened meanwhile (the group-invite
  // prompt), leaving the left group's profile on screen.
  group('finishLeaveGroup', () {
    late BuildContext profileContext;

    Future<void> pushChatAndProfile(WidgetTester tester) async {
      await _pumpHost(tester);
      await _pushUikitRoute(
        tester,
        TencentCloudChatRouteNames.message,
        options: TencentCloudChatMessageOptions(groupID: _groupG),
        label: 'chat-G',
      );
      unawaited(_nav.push(MaterialPageRoute<void>(
        settings: const RouteSettings(
            name: TencentCloudChatRouteNames.groupProfile),
        builder: (context) {
          profileContext = context;
          return const Scaffold(body: Text('profile-G'));
        },
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('profile on top: closes it and the left group chat beneath',
        (tester) async {
      await pushChatAndProfile(tester);
      await finishLeaveGroup(profileContext, groupID: _groupG, succeeded: true);
      await tester.pumpAndSettle();
      expect(find.text('profile-G'), findsNothing);
      expect(find.text('chat-G'), findsNothing);
      expect(find.text('home-root'), findsOneWidget);
    });

    testWidgets('a dialog opened meanwhile stays; the profile goes; the chat '
        'goes once the dialog closes', (tester) async {
      await pushChatAndProfile(tester);
      unawaited(showDialog<void>(
        context: _navKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('invite-dialog')),
      ));
      await tester.pumpAndSettle();

      final done = finishLeaveGroup(profileContext,
          groupID: _groupG, succeeded: true);
      await tester.pumpAndSettle();
      expect(find.text('invite-dialog'), findsOneWidget,
          reason: 'the dialog on top must not be the route that gets closed');
      expect(find.text('profile-G', skipOffstage: false), findsNothing,
          reason: 'the left group profile is removed where it stands');

      _nav.pop(); // user dismisses the dialog
      await done;
      await tester.pumpAndSettle();
      expect(find.text('chat-G', skipOffstage: false), findsNothing);
      expect(find.text('home-root'), findsOneWidget);
    });

    testWidgets('a page pushed over the profile is never popped by the leave', (tester) async {
      await pushChatAndProfile(tester);
      unawaited(_nav.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('other-page')),
      )));
      await tester.pumpAndSettle();
      final done = finishLeaveGroup(profileContext,
          groupID: _groupG, succeeded: true);
      await tester.pumpAndSettle();
      expect(find.text('other-page'), findsOneWidget);
      _nav.pop();
      await done;
      await tester.pumpAndSettle();
      expect(find.text('home-root'), findsOneWidget);
    });
  });
}
