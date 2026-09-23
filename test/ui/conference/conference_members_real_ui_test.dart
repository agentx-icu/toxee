// Conference real-UI gates for the member surfaces: member info
// (tencent_cloud_chat_group_member_info.dart), the member-list manage sheet
// (tencent_cloud_chat_group_member_list.dart) and the add-member picker
// (tencent_cloud_chat_group_add_member.dart). Conferences are
// `GroupType.AVChatRoom`.
//
// Notable conference-specific behaviour exercised here:
//   * S173: `canDeleteMember()` short-circuits to FALSE for AVChatRoom
//     (tencent_cloud_chat_group_member_list.dart:341-343) — legacy conferences
//     have no roles/moderation (S156: "no roles"), so the kick action is NOT
//     surfaced. The spec's "kick appears" premise is wrong for the conference
//     branch; this gate asserts the truthful NEGATIVE, with a Work-group control
//     proving the absence is conference-specific (not a setup gap).
//
// Two-process notes: S171-S175/S184 ultimately need a remote member / native
// invite. The single-process observables driven here are the real member-info
// render (S171/S172), the real selection InkWell (S175) and the shared keyed
// invite confirm for a conference groupInfo (S174/S184). The native
// `tox_conference_invite` branch + a peer actually joining are the
// `conference_message` two-process gate.
//
// Mobile parity: all these widgets are shared UIKit-fork Dart (no platform
// split) — this L1 coverage applies to iOS/Android too.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_group_member_info.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_group_member_list.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_group_add_member.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

Widget _localized({required Widget child}) {
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
          return child;
        },
      ),
    ),
  );
}

V2TimGroupInfo _conference({String groupID = 'tox_conf_42', int? role}) {
  return V2TimGroupInfo(
    groupID: groupID,
    groupName: 'Members Conference',
    groupType: GroupType.AVChatRoom,
    role: role,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  // S171 — open member info: the member-info body renders for a conference
  // member, showing the member's display name.
  testWidgets(
    'S171 conference member info body renders the member name',
    (tester) async {
      final member = V2TimGroupMemberFullInfo(
        userID: 'bob_conf_171',
        nickName: 'Bob Conference',
        role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
        joinTime: 0,
      );
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupMemberInfoBody(memberFullInfo: member),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bob Conference'), findsOneWidget,
          reason: 'the member info body must show the member display name');
      // Non-vacuous: the identifier surface is present too (member info opened,
      // not an empty panel).
      expect(find.textContaining('bob_conf_171'), findsWidgets);
    },
  );

  // S172 — copy a member ID: the member-info surface shows the exact
  // `ID: <userID>` identifier — the value the copy action reads.
  testWidgets(
    'S172 conference member info shows the copyable member identifier text',
    (tester) async {
      final member = V2TimGroupMemberFullInfo(
        userID: 'bob_conf_172',
        nickName: 'Bob ID',
        role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
        joinTime: 0,
      );
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupMemberInfoBody(memberFullInfo: member),
        ),
      );
      await tester.pumpAndSettle();

      // bob is not a known friend, so the id is presented as what it is — a
      // group member key, not a Tox ID (MM-6; the resolved-friend branch is in
      // test/ui/group/group_member_identity_test.dart).
      expect(find.text('Member key: bob_conf_172'), findsOneWidget,
          reason:
              'the member info view must display the member identifier that the '
              'copy action copies');
    },
  );

  // S173 — kick-action surface: for a CONFERENCE (AVChatRoom) the manage sheet
  // does NOT offer a kick action (canDeleteMember() == false for AVChatRoom).
  // A Work-group control with the SAME roles proves the absence is
  // conference-specific.
  testWidgets(
    'S173 conference (AVChatRoom) member manage sheet hides the kick action; '
    'a Work-group control surfaces it',
    (tester) async {
      // currentUser must differ from the member (onManageMember returns early on
      // isSelf()).
      final oldCurrentUser =
          TencentCloudChat.instance.dataInstance.basic.currentUser;
      TencentCloudChat.instance.dataInstance.basic
          .updateCurrentUserInfo(userFullInfo: V2TimUserFullInfo(userID: 'alice'));
      addTearDown(() {
        if (oldCurrentUser != null) {
          TencentCloudChat.instance.dataInstance.basic
              .updateCurrentUserInfo(userFullInfo: oldCurrentUser);
        }
      });

      final member = V2TimGroupMemberFullInfo(
        userID: 'bob_conf_173',
        nickName: 'Bob Member',
        role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
        joinTime: 0,
      );
      const kickKey = ValueKey('group_member_action_kick_button');

      // CONFERENCE: AVChatRoom, owner-as-me, member target → no kick.
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupMemberListItem(
            groupInfo: _conference(
              groupID: 'tox_conf_173',
              role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
            ),
            memberFullInfo: member,
            myRole: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
            onDeleteGroupMember: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Tap the member name (the row's GestureDetector uses deferToChild, so the
      // geometric center can miss) to open the manage sheet.
      await tester.tap(find.text('Bob Member'));
      await tester.pumpAndSettle();

      // The manage sheet opened (Info action present) but offers no kick.
      expect(find.text('Info'), findsOneWidget,
          reason: 'the conference member manage sheet should still open');
      expect(find.byKey(kickKey), findsNothing,
          reason:
              'a conference (AVChatRoom) has no roles/moderation, so the kick '
              'action must NOT be surfaced');

      // Dismiss the sheet before the control pump.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // CONTROL: a Work group with the SAME owner/member roles DOES surface the
      // kick — proving the conference absence above is the AVChatRoom gate, not
      // a setup gap.
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupMemberListItem(
            groupInfo: V2TimGroupInfo(
              groupID: 'tox_group_173',
              groupName: 'Work Group',
              groupType: GroupType.Work,
              role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
            ),
            memberFullInfo: member,
            myRole: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER,
            onDeleteGroupMember: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob Member'));
      await tester.pumpAndSettle();

      expect(find.byKey(kickKey), findsOneWidget,
          reason:
              'a Work group with the same roles must surface the kick action '
              '(control for the conference negative)');
    },
  );

  // S174 — add-member entry opens the picker: the real picker renders the
  // selectable friend rows + the keyed invite confirm.
  testWidgets(
    'S174 conference add-member picker renders the selectable friend list and '
    'the confirm affordance',
    (tester) async {
      final friends = <V2TimFriendInfo>[
        V2TimFriendInfo(
          userID: 'amy_174',
          userProfile: V2TimUserFullInfo(userID: 'amy_174', nickName: 'Amy'),
        ),
        V2TimFriendInfo(
          userID: 'ben_174',
          userProfile: V2TimUserFullInfo(userID: 'ben_174', nickName: 'Ben'),
        ),
      ];
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupAddMember(
            groupInfo: _conference(groupID: 'tox_conf_174'),
            memberList: const <V2TimGroupMemberFullInfo>[],
            contactList: friends,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('add_member_contact_item:amy_174')),
        findsOneWidget,
        reason: 'the picker must render the selectable friend rows',
      );
      expect(
        find.byKey(const ValueKey('add_member_contact_item:ben_174')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group_member_invite_confirm_button')),
        findsOneWidget,
        reason: 'the picker must render the keyed invite confirm affordance',
      );
    },
  );

  // S175 — add-member picker selects a friend: tapping a friend row registers
  // the selection through the real picker list's onSelectedMemberItemChange.
  testWidgets(
    'S175 conference add-member picker registers a friend selection on tap',
    (tester) async {
      List<V2TimFriendInfo>? lastSelection;
      final friends = <V2TimFriendInfo>[
        V2TimFriendInfo(
          userID: 'cara_175',
          userProfile: V2TimUserFullInfo(userID: 'cara_175', nickName: 'Cara'),
        ),
      ];
      await tester.pumpWidget(
        _localized(
          child: TencentCloudChatGroupProfileAddMemberList(
            contactList: friends,
            memberList: const <V2TimGroupMemberFullInfo>[],
            onSelectedMemberItemChange: (selected) {
              lastSelection = (selected as List).cast<V2TimFriendInfo>();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('add_member_contact_item:cara_175'));
      expect(row, findsOneWidget);
      expect(lastSelection, isNull);

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(lastSelection, isNotNull,
          reason: 'tapping a friend row must fire the selection callback');
      expect(lastSelection!.map((f) => f.userID), contains('cara_175'),
          reason: 'the tapped friend must be in the registered selection');
    },
  );

  // S184 — invite uses the conference branch: the add-member picker is the
  // SHARED keyed invite UI for a conference groupInfo (AVChatRoom + tox_conf_*).
  // Drive the real flow — select a friend, tap confirm — and assert the real
  // submitAdd handler runs (contactPresenter.inviteUserToGroup for the conference
  // groupID) and pops the picker. The native `tox_conference_invite` branch
  // selection is the two-process leg (the conference_message pair gate).
  testWidgets(
    'S184 conference invite confirm runs the real add-member handler and pops '
    'the picker',
    (tester) async {
      final conf = _conference(groupID: 'tox_conf_184');
      final friends = <V2TimFriendInfo>[
        V2TimFriendInfo(
          userID: 'dora_184',
          userProfile: V2TimUserFullInfo(userID: 'dora_184', nickName: 'Dora'),
        ),
      ];

      await tester.pumpWidget(
        _localized(
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Builder(
                builder: (base) => Center(
                  child: ElevatedButton(
                    key: const ValueKey('open_conf_picker'),
                    onPressed: () => Navigator.of(base).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TencentCloudChatGroupAddMember(
                          groupInfo: conf,
                          memberList: const <V2TimGroupMemberFullInfo>[],
                          contactList: friends,
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open_conf_picker')));
      await tester.pumpAndSettle();

      final confirm =
          find.byKey(const ValueKey('group_member_invite_confirm_button'));
      expect(confirm, findsOneWidget,
          reason: 'the conference reuses the shared keyed invite confirm');

      // Select the friend, then confirm.
      await tester.tap(
          find.byKey(const ValueKey('add_member_contact_item:dora_184')));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      // Real side-effect: the keyed confirm invoked the production submitAdd
      // (inviteUserToGroup for the conference groupID) and popped the picker —
      // proving the confirm is wired to the real handler, not re-read input.
      expect(confirm, findsNothing,
          reason: 'confirming must run submitAdd and pop the conference picker');
      expect(find.byKey(const ValueKey('open_conf_picker')), findsOneWidget,
          reason: 'the flow returns to the base surface after the invite confirm');
    },
  );
}
