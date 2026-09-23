// Tapping a message sender's avatar in a group (fork message_row).
//
// In a Tox NGC group `message.sender` is the sender's PER-GROUP key, not a Tox
// ID. The avatar tap opened a user profile for that key — a stranger with a
// fake "Tox ID" and add-friend actions that can never work. Now the sender is
// resolved like a member-list row (resolveGroupMemberUserID, moved to the
// common package): self / friends open their real profile, anyone else opens
// the group member-info page (with the member's cached row when loaded).
//
// Mobile parity: the desktop row and the mobile row both render
// TencentCloudChatMessageRowMessageSenderAvatar, whose tap is exercised here;
// the desktop row's outer wrapper calls the same openMessageSender. On a
// desktop host the member-info page opens as a dialog, elsewhere as a pushed
// route — both come from the registered route builder used below.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_group_member_info_options.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_user_profile_options.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_route_names.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_router.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_list_view/message_row/tencent_cloud_chat_message_row_message_sender_avatar.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

final _friendPk = 'A1' * 32; // long-term key (a conference peer's id)
final _friendToxId = '$_friendPk${'B2' * 6}';
final _groupKey = 'C3' * 32; // an NGC per-group key: nobody's Tox ID
final _selfToxId = '${'D4' * 32}${'E5' * 6}';
const _ngc = 'tox_group_1';
const _conf = 'tox_conf_1';

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: const [
        TencentCloudChatLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(builder: (context) {
          TencentCloudChatIntl().init(context);
          return Center(child: child);
        }),
      ),
    );

Widget _avatar(V2TimMessage message, {String? groupID}) =>
    TencentCloudChatMessageRowMessageSenderAvatar(
      data: MessageRowMessageSenderAvatarBuilderData(
        message: message,
        groupID: groupID,
        messageSenderAvatarURL: '',
      ),
      methods: MessageRowMessageSenderAvatarBuilderMethods(),
      showOthersAvatar: true,
      showSelfAvatar: false,
    );

V2TimMessage _incoming(String sender, {String? groupID}) => V2TimMessage(
      elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
      sender: sender,
      groupID: groupID,
      isSelf: false,
      nickName: 'Stranger',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  final router = TencentCloudChatRouter();
  WidgetBuilder? oldProfile;
  WidgetBuilder? oldMemberInfo;
  V2TimUserFullInfo? oldCurrentUser;

  setUp(() {
    oldProfile = router.routes[TencentCloudChatRouteNames.userProfile];
    oldMemberInfo = router.routes[TencentCloudChatRouteNames.groupMemberInfo];
    router.registerRouter(
      routeName: TencentCloudChatRouteNames.userProfile,
      builder: (context) {
        final o = router.getArgumentFromMap<TencentCloudChatUserProfileOptions>(
            context, 'options')!;
        return Text('profile:${o.userID}');
      },
    );
    router.registerRouter(
      routeName: TencentCloudChatRouteNames.groupMemberInfo,
      builder: (context) {
        final o = router
            .getArgumentFromMap<TencentCloudChatGroupMemberInfoOptions>(
                context, 'options')!;
        final m = o.memberFullInfo;
        return Text('member:${m.userID}:${o.groupType}:${m.role}:'
            '${m.nickName}');
      },
    );

    oldCurrentUser = TencentCloudChat.instance.dataInstance.basic.currentUser;
    TencentCloudChat.instance.dataInstance.basic.updateCurrentUserInfo(
        userFullInfo: V2TimUserFullInfo(userID: _selfToxId));
    TencentCloudChat.instance.dataInstance.contact.buildFriendList(
      [V2TimFriendInfo(userID: _friendToxId)],
      'sender_avatar_test',
    );
    TencentCloudChat.instance.dataInstance.contact.buildGroupList([
      V2TimGroupInfo(groupID: _ngc, groupType: GroupType.Work),
      V2TimGroupInfo(groupID: _conf, groupType: 'conference'),
    ], 'sender_avatar_test');
  });

  tearDown(() {
    void restore(String name, WidgetBuilder? old) {
      if (old == null) {
        router.routes.remove(name);
      } else {
        router.registerRouter(routeName: name, builder: old);
      }
    }

    restore(TencentCloudChatRouteNames.userProfile, oldProfile);
    restore(TencentCloudChatRouteNames.groupMemberInfo, oldMemberInfo);
    TencentCloudChat.instance.dataInstance.contact
        .deleteFromFriendList([_friendToxId], 'sender_avatar_test');
    TencentCloudChat.instance.dataInstance.contact
        .buildGroupList([], 'sender_avatar_test');
    TencentCloudChat.instance.dataInstance.groupProfile.groupMemberListCache
        .set(_ngc, []);
    if (oldCurrentUser != null) {
      TencentCloudChat.instance.dataInstance.basic
          .updateCurrentUserInfo(userFullInfo: oldCurrentUser!);
    }
  });

  Future<void> tapAvatar(WidgetTester tester, Widget avatar) async {
    await tester.pumpWidget(_app(avatar));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TencentCloudChatMessageRowMessageSenderAvatar));
    await tester.pumpAndSettle();
  }

  testWidgets('an NGC per-group key opens member info, never a user profile',
      (tester) async {
    await tapAvatar(tester, _avatar(_incoming(_groupKey, groupID: _ngc)));
    expect(find.textContaining('profile:'), findsNothing);
    expect(find.text('member:$_groupKey:${GroupType.Work}:null:Stranger'),
        findsOneWidget);
  });

  testWidgets('the cached member row (role) is shown when loaded',
      (tester) async {
    TencentCloudChat.instance.dataInstance.groupProfile.groupMemberListCache
        .set(_ngc, [
      V2TimGroupMemberFullInfo(
        userID: _groupKey,
        nickName: 'Moderator',
        role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN,
      ),
    ]);
    // The conversation-level groupID is enough when the message has none.
    await tapAvatar(tester, _avatar(_incoming(_groupKey), groupID: _ngc));
    expect(
        find.text('member:$_groupKey:${GroupType.Work}:'
            '${GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN}:Moderator'),
        findsOneWidget);
  });

  testWidgets('a friend in a conference opens their real profile',
      (tester) async {
    await tapAvatar(tester, _avatar(_incoming(_friendPk, groupID: _conf)));
    expect(find.text('profile:$_friendToxId'), findsOneWidget);
    expect(find.textContaining('member:'), findsNothing);
  });

  testWidgets('an unknown conference peer opens member info as a conference '
      'member', (tester) async {
    await tapAvatar(tester, _avatar(_incoming(_groupKey, groupID: _conf)));
    expect(find.text('member:$_groupKey:conference:null:Stranger'),
        findsOneWidget);
  });

  testWidgets('one-to-one chats keep opening the peer profile', (tester) async {
    await tapAvatar(tester, _avatar(_incoming(_friendToxId)));
    expect(find.text('profile:$_friendToxId'), findsOneWidget);
  });
}
