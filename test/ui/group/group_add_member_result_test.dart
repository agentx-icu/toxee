// GI-6 — the add-member picker must REPORT the invite result instead of
// discarding it. Tox delivers a group invite only to a friend who is online
// right now: natively an offline friend comes back as
// V2TIM_GROUP_MEMBER_RESULT_FAIL (0) (V2TIMGroupManagerImpl::InviteUserToGroup),
// and the picker used to fire-and-forget `submitAdd()` and pop immediately, so
// the invite was silently lost.
//
// The picker is shared UIKit-fork Dart (tencent_cloud_chat_group_add_member
// .dart) used on desktop, tablet and phone alike, so these gates cover mobile.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_callbacks.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_code_info.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_group_add_member.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

class _InvitePlatform extends TencentCloudChatSdkPlatform {
  _InvitePlatform(this.respond);

  final V2TimValueCallback<List<V2TimGroupMemberOperationResult>> Function(
      List<String> userList) respond;
  int calls = 0;

  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimValueCallback<List<V2TimGroupMemberOperationResult>>>
      inviteUserToGroup({
    required String groupID,
    required List<String> userList,
  }) async {
    calls += 1;
    return respond(userList);
  }
}

V2TimFriendInfo _friend(String userID, String nickName) => V2TimFriendInfo(
      userID: userID,
      userProfile: V2TimUserFullInfo(userID: userID, nickName: nickName),
    );

Widget _host(Widget picker) {
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
          return Center(
            child: ElevatedButton(
              key: const ValueKey('open_picker'),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => picker)),
              child: const Text('open'),
            ),
          );
        },
      ),
    ),
  );
}

TencentCloudChatGroupAddMember _picker(List<V2TimFriendInfo> friends) =>
    TencentCloudChatGroupAddMember(
      groupInfo: V2TimGroupInfo(
          groupID: 'tox_group_gi6', groupType: GroupType.Work),
      memberList: const <V2TimGroupMemberFullInfo>[],
      contactList: friends,
    );

Future<void> _selectAndConfirm(WidgetTester tester, List<String> ids) async {
  await tester.tap(find.byKey(const ValueKey('open_picker')));
  await tester.pumpAndSettle();
  for (final id in ids) {
    await tester.tap(find.byKey(ValueKey('add_member_contact_item:$id')));
    await tester.pumpAndSettle();
  }
  await tester.runAsync(() async {
    await tester
        .tap(find.byKey(const ValueKey('group_member_invite_confirm_button')));
    await tester.pump();
    // Drain the invite's async chain instead of sleeping a fixed 20ms.
    await pumpEventQueue();
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  late List<TencentCloudChatUserNotificationEvent> events;
  late TencentCloudChatCallbacks sink;
  late TencentCloudChatSdkPlatform oldPlatform;

  setUp(() {
    events = [];
    sink = TencentCloudChatCallbacks(
      onTencentCloudChatUIKitUserNotificationEvent:
          (TencentCloudChatComponentsEnum c, TencentCloudChatUserNotificationEvent e) =>
              events.add(e),
    );
    TencentCloudChat.instance.callbacks.addCallback(sink);
    oldPlatform = TencentCloudChatSdkPlatform.instance;
  });

  tearDown(() {
    TencentCloudChat.instance.callbacks.removeCallback(sink);
    TencentCloudChatSdkPlatform.instance = oldPlatform;
    TencentCloudChat.instance.dataInstance.contact.buildUserStatusList(
      [
        V2TimUserStatus(userID: 'olga_gi6', statusType: 1),
        V2TimUserStatus(userID: 'omar_gi6', statusType: 1),
      ],
      'test_reset',
    );
  });

  testWidgets('an offline friend (native FAIL) is reported by name; the '
      'successful one is not; the picker closes after the result', (
    tester,
  ) async {
    final platform = _InvitePlatform((users) => V2TimValueCallback(
          code: 0,
          desc: 'ok',
          data: [
            V2TimGroupMemberOperationResult(memberID: 'omar_gi6', result: 1),
            V2TimGroupMemberOperationResult(memberID: 'olga_gi6', result: 0),
          ],
        ));
    TencentCloudChatSdkPlatform.instance = platform;

    await tester.pumpWidget(_host(_picker([
      _friend('olga_gi6', 'Olga'),
      _friend('omar_gi6', 'Omar'),
    ])));
    await tester.pumpAndSettle();
    await _selectAndConfirm(tester, ['olga_gi6', 'omar_gi6']);

    expect(platform.calls, 1);
    expect(events, hasLength(1));
    expect(events.single.eventCode, isNot(0));
    expect(events.single.text, contains('Olga'));
    expect(events.single.text, isNot(contains('Omar')));
    expect(events.single.text, contains("Couldn't invite"));
    expect(events.single.text, isNot(contains('online')),
        reason: 'offline friends are queued natively (PENDING), so a FAIL '
            'must not be explained as "online only"');
    // Popped only after the awaited result.
    expect(find.byKey(const ValueKey('group_member_invite_confirm_button')),
        findsNothing);
  });

  // A whole-call failure is not a per-friend verdict: it must say what went
  // wrong, not blame the friends (and never claim "online friends only" —
  // offline friends' invites are queued natively as PENDING).
  for (final c in <(int, String)>[
    (6017, "Couldn't send the invitations"),
    (10007, "You don't have permission"),
    (6013, 'Not connected to the Tox network'),
  ]) {
    testWidgets('a failed call (code ${c.$1}) reports a reason', (tester) async {
      TencentCloudChatSdkPlatform.instance = _InvitePlatform(
        (users) => V2TimValueCallback(code: c.$1, desc: 'native'),
      );
      await tester.pumpWidget(_host(_picker([
        _friend('olga_gi6', 'Olga'),
        _friend('omar_gi6', 'Omar'),
      ])));
      await tester.pumpAndSettle();
      await _selectAndConfirm(tester, ['olga_gi6', 'omar_gi6']);

      expect(events, hasLength(1));
      expect(events.single.eventCode, c.$1);
      expect(events.single.text, contains(c.$2));
      expect(events.single.text, isNot(contains('online')));
    });
  }

  testWidgets('an exception from the invite is reported, the page still '
      'closes, nothing is unhandled', (tester) async {
    TencentCloudChatSdkPlatform.instance =
        _InvitePlatform((users) => throw StateError('ffi exploded'));
    await tester.pumpWidget(_host(_picker([_friend('olga_gi6', 'Olga')])));
    await tester.pumpAndSettle();
    await _selectAndConfirm(tester, ['olga_gi6']);

    expect(events, hasLength(1));
    expect(events.single.text, contains("Couldn't send the invitations"));
    expect(find.byKey(const ValueKey('group_member_invite_confirm_button')),
        findsNothing);
  });

  testWidgets('an all-success invite is silent; PENDING is informational', (
    tester,
  ) async {
    TencentCloudChatSdkPlatform.instance = _InvitePlatform(
      (users) => V2TimValueCallback(code: 0, desc: 'ok', data: [
        V2TimGroupMemberOperationResult(memberID: 'olga_gi6', result: 1),
        V2TimGroupMemberOperationResult(memberID: 'omar_gi6', result: 3),
      ]),
    );
    await tester.pumpWidget(_host(_picker([
      _friend('olga_gi6', 'Olga'),
      _friend('omar_gi6', 'Omar'),
    ])));
    await tester.pumpAndSettle();
    await _selectAndConfirm(tester, ['olga_gi6', 'omar_gi6']);

    expect(events, hasLength(1));
    expect(events.single.eventCode, 0);
  });

  testWidgets('a double-fired confirm invites exactly once', (tester) async {
    final platform = _InvitePlatform((users) => V2TimValueCallback(
          code: 0,
          desc: 'ok',
          data: [
            for (final u in users)
              V2TimGroupMemberOperationResult(memberID: u, result: 1),
          ],
        ));
    TencentCloudChatSdkPlatform.instance = platform;
    await tester.pumpWidget(_host(_picker([_friend('olga_gi6', 'Olga')])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add_member_contact_item:olga_gi6')));
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(find.descendant(
      of: find.byKey(const ValueKey('group_member_invite_confirm_button')),
      matching: find.byType(TextButton),
    ));
    await tester.runAsync(() async {
      button.onPressed!();
      button.onPressed!();
      // Drain both taps' async chains instead of sleeping a fixed 20ms — the
      // assertion below is that the second one was deduped, so it has to run
      // after the second call has had every chance to reach the platform.
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();
    expect(platform.calls, 1);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('friends known to be offline are flagged in the picker', (
    tester,
  ) async {
    TencentCloudChat.instance.dataInstance.contact.buildUserStatusList(
      [
        V2TimUserStatus(userID: 'olga_gi6', statusType: 0),
        V2TimUserStatus(userID: 'omar_gi6', statusType: 1),
      ],
      'test',
    );
    await tester.pumpWidget(_host(_picker([
      _friend('olga_gi6', 'Olga'),
      _friend('omar_gi6', 'Omar'),
    ])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_picker')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add_member_contact_offline:olga_gi6')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('add_member_contact_offline:omar_gi6')),
        findsNothing);
  });
}
