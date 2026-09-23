// MM-10 — an OPEN group member page must follow joins and leaves. The page
// (GroupMemberListWrapper) fetched once and latched `_hasLoaded`; the fork list
// only reacted to role changes. The UIKit already patches its member cache on
// onMemberEnter / onMemberLeave / onMemberKicked (tencent_cloud_chat_group_sdk
// → groupProfile.addGroupMember / deleteGroupMember) and announces it as a
// `membersChange`; the wrapper now listens and refetches.
//
// The page is shared Dart for every form factor (pushed on phone, full-window
// route on desktop/tablet) — mobile covered.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/data/group_profile/tencent_cloud_chat_group_profile_data.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/group/group_member_list_refresh.dart';
import 'package:toxee/ui/group/group_member_list_wrapper.dart';

V2TimGroupMemberFullInfo _m(String id, {int role = 0, String? card}) =>
    V2TimGroupMemberFullInfo(userID: id, nickName: id, role: role, nameCard: card);

class _MembersPlatform extends TencentCloudChatSdkPlatform {
  List<V2TimGroupMemberFullInfo> members = [];
  int listCalls = 0;

  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimValueCallback<V2TimGroupMemberInfoResult>> getGroupMemberList({
    required String groupID,
    required int filter,
    required String nextSeq,
    int count = 15,
    int offset = 0,
  }) async {
    listCalls += 1;
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: V2TimGroupMemberInfoResult(
        nextSeq: '0',
        memberInfoList: List.of(members),
      ),
    );
  }

  @override
  Future<V2TimValueCallback<List<V2TimGroupMemberFullInfo>>>
      getGroupMembersInfo({
    required String groupID,
    required List<String> memberList,
  }) async {
    return V2TimValueCallback(
      code: 0,
      desc: 'ok',
      data: [
        for (final id in memberList)
          members.firstWhere((m) => m.userID == id, orElse: () => _m(id)),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  group('memberListNeedsRefresh', () {
    test('no cache → nothing to compare', () {
      expect(memberListNeedsRefresh([_m('a')], const []), isFalse);
    });
    test('same rows (any order) → no refresh', () {
      expect(memberListNeedsRefresh([_m('a'), _m('b')], [_m('b'), _m('a')]),
          isFalse);
    });
    test('join / leave / role / name card → refresh', () {
      expect(memberListNeedsRefresh([_m('a')], [_m('a'), _m('b')]), isTrue);
      expect(memberListNeedsRefresh([_m('a'), _m('b')], [_m('a')]), isTrue);
      expect(memberListNeedsRefresh([_m('a')], [_m('a', role: 300)]), isTrue);
      expect(memberListNeedsRefresh([_m('a')], [_m('a', card: 'x')]), isTrue);
    });
    test('avatar / nickname enrichment alone is not a change', () {
      final shown = _m('a')..faceUrl = '/tmp/a.png';
      expect(memberListNeedsRefresh([shown], [_m('a')]), isFalse);
    });
  });

  testWidgets('an open member page shows a peer joining and leaving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const groupID = 'tox_group_mm10_live';
    final platform = _MembersPlatform()..members = [_m('alice'), _m('bob')];
    final old = TencentCloudChatSdkPlatform.instance;
    TencentCloudChatSdkPlatform.instance = platform;
    addTearDown(() => TencentCloudChatSdkPlatform.instance = old);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: const [
        TencentCloudChatLocalizations.delegate,
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (context) {
        TencentCloudChatIntl().init(context);
        return GroupMemberListWrapper(
          groupInfo: V2TimGroupInfo(groupID: groupID, groupType: GroupType.Work),
          memberInfoList: const [],
        );
      }),
    ));
    await tester.pumpAndSettle();
    Finder row(String id) =>
        find.byKey(ValueKey('group_member_list_item:$id'));
    expect(row('alice'), findsOneWidget);
    expect(row('bob'), findsOneWidget);
    expect(row('carol'), findsNothing);

    // carol joins: the UIKit's onMemberEnter handler path.
    platform.members = [_m('alice'), _m('bob'), _m('carol')];
    await TencentCloudChat.instance.dataInstance.groupProfile
        .addGroupMember(groupID, [V2TimGroupMemberInfo(userID: 'carol')]);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(row('carol'), findsOneWidget,
        reason: 'the open page must show the member who just joined');

    // bob leaves: onMemberLeave path.
    platform.members = [_m('alice'), _m('carol')];
    TencentCloudChat.instance.dataInstance.groupProfile
        .deleteGroupMember(groupID, [V2TimGroupMemberInfo(userID: 'bob')]);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(row('bob'), findsNothing,
        reason: 'the open page must drop the member who left');
    expect(row('alice'), findsOneWidget);

    // alice is granted admin (onGrantAdministrator → updateMemberRole), then
    // revoked. The role event does not touch the member cache; the open page
    // must still show it.
    Finder adminBadge(String id) =>
        find.descendant(of: row(id), matching: find.text('Admin'));
    expect(adminBadge('alice'), findsNothing);
    TencentCloudChat.instance.dataInstance.groupProfile.updateGroupMemberRole(
        groupID,
        [V2TimGroupMemberInfo(userID: 'alice')],
        GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(adminBadge('alice'), findsWidgets,
        reason: 'an admin grant must show on the open page');
    TencentCloudChat.instance.dataInstance.groupProfile.updateGroupMemberRole(
        groupID,
        [V2TimGroupMemberInfo(userID: 'alice')],
        GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(adminBadge('alice'), findsNothing,
        reason: 'an admin revoke must show on the open page');

    // A membersChange for ANOTHER group does not refetch this page.
    final calls = platform.listCalls;
    TencentCloudChat.instance.dataInstance.groupProfile.setGroupMemberList(
        'tox_group_other', [_m('zed')]);
    TencentCloudChat.instance.dataInstance.groupProfile.updateGroupID =
        'tox_group_other';
    TencentCloudChat.instance.dataInstance.groupProfile.notifyListener(
        TencentCloudChatGroupProfileDataKeys.membersChange);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(platform.listCalls, calls);

    // Drain the UIKit's 2 s load-debounce timers before teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
