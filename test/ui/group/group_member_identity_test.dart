// MM-6 (UI half) — group member rows are identified by a Tox NGC PER-GROUP
// key, not by the member's Tox ID. The member-info surface used to label that
// key "ID", copy it as a "Tox ID" and open a user profile (→ add-friend) for
// it. Now the id is only presented / routed as a Tox identity when it resolves
// (self, or a friend whose long-term key the row carries — legacy conference
// peers); otherwise it is labelled a member key and no profile entry is shown.
//
// Shared UIKit-fork Dart (member info is a dialog on desktop, a pushed page on
// phone/tablet; both host this same body) — mobile covered.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_contact/widgets/group_member_identity.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_group_member_info.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

final _friendPk = 'A1' * 32; // 64-char long-term public key
final _friendToxId = '$_friendPk${'B2' * 6}'; // 76-char Tox ID
final _groupKey = 'C3' * 32; // a per-group NGC key: nobody's Tox ID
final _selfPk = 'D4' * 32;
final _selfToxId = '$_selfPk${'E5' * 6}';

Widget _localized(Widget child) {
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

V2TimGroupMemberFullInfo _member(String userID) => V2TimGroupMemberFullInfo(
      userID: userID,
      nickName: 'Member',
      role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER,
      joinTime: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  V2TimUserFullInfo? oldCurrentUser;

  setUp(() {
    oldCurrentUser = TencentCloudChat.instance.dataInstance.basic.currentUser;
    TencentCloudChat.instance.dataInstance.basic.updateCurrentUserInfo(
        userFullInfo: V2TimUserFullInfo(userID: _selfToxId));
    TencentCloudChat.instance.dataInstance.contact.buildFriendList(
      [V2TimFriendInfo(userID: _friendToxId)],
      'mm6_test',
    );
  });

  tearDown(() {
    TencentCloudChat.instance.dataInstance.contact
        .deleteFromFriendList([_friendToxId], 'mm6_test');
    if (oldCurrentUser != null) {
      TencentCloudChat.instance.dataInstance.basic
          .updateCurrentUserInfo(userFullInfo: oldCurrentUser!);
    }
  });

  group('resolveGroupMemberUserID', () {
    test('a per-group key resolves to nobody', () {
      expect(resolveGroupMemberUserID(_groupKey), isNull);
      expect(resolveGroupMemberUserID(''), isNull);
    });

    test('a long-term key resolves to the friend (Tox ID form)', () {
      expect(resolveGroupMemberUserID(_friendPk), _friendToxId);
      expect(resolveGroupMemberUserID(_friendPk.toLowerCase()), _friendToxId);
    });

    test('our own long-term key resolves to the logged-in id', () {
      expect(resolveGroupMemberUserID(_selfPk), _selfToxId);
    });

    test('short ids never prefix-match', () {
      expect(resolveGroupMemberUserID('A1A1'), isNull);
    });
  });

  group('member info body', () {
    late String? clipboard;

    setUp(() {
      clipboard = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('an unresolved NGC key is labelled a member key, copied as '
        'one, and offers no profile route', (tester) async {
      await tester.pumpWidget(_localized(
          TencentCloudChatGroupMemberInfoBody(memberFullInfo: _member(_groupKey))));
      await tester.pumpAndSettle();

      expect(find.text('Member key: $_groupKey'), findsOneWidget);
      expect(find.byKey(const ValueKey('group_member_info_key_hint')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('group_member_info_profile_entry')),
          findsNothing);

      await tester
          .tap(find.byKey(const ValueKey('group_member_info_copy_id_button')));
      await tester.pumpAndSettle();
      expect(clipboard, _groupKey);
      expect(find.text('Member key copied'), findsOneWidget);
      expect(find.text('Tox ID copied'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a friend in a conference resolves: Tox ID shown and copied, '
        'profile entry offered', (tester) async {
      await tester.pumpWidget(_localized(
          TencentCloudChatGroupMemberInfoBody(memberFullInfo: _member(_friendPk))));
      await tester.pumpAndSettle();

      expect(find.text('ID: $_friendToxId'), findsOneWidget);
      expect(find.byKey(const ValueKey('group_member_info_key_hint')),
          findsNothing);
      expect(find.byKey(const ValueKey('group_member_info_profile_entry')),
          findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('group_member_info_copy_id_button')));
      await tester.pumpAndSettle();
      expect(clipboard, _friendToxId);
      expect(find.text('Tox ID copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the self row keeps working (long-term key)', (tester) async {
      await tester.pumpWidget(_localized(
          TencentCloudChatGroupMemberInfoBody(memberFullInfo: _member(_selfPk))));
      await tester.pumpAndSettle();

      expect(find.text('ID: $_selfToxId'), findsOneWidget);
      expect(find.byKey(const ValueKey('group_member_info_profile_entry')),
          findsOneWidget);
    });

    // A legacy-conference peer who is not a friend is named by their
    // LONG-TERM key: "only identifies the member in this group" is wrong for
    // it. The hint follows the group kind (every caller passes it: member
    // list desktop menu + mobile sheet, group profile, sender avatar).
    for (final type in ['conference', 'av_conference', 'AVChatRoom']) {
      testWidgets('an unresolved $type peer gets the long-term-key hint',
          (tester) async {
        await tester.pumpWidget(_localized(TencentCloudChatGroupMemberInfoBody(
            memberFullInfo: _member(_groupKey), groupType: type)));
        await tester.pumpAndSettle();
        final hint = tester.widget<Text>(
            find.byKey(const ValueKey('group_member_info_key_hint')));
        expect(hint.data, tL10n.conferenceMemberKeyHint);
        expect(hint.data, isNot(tL10n.groupMemberKeyHint));
        expect(tL10n.conferenceMemberKeyHint, contains('long-term'));
      });
    }

    for (final type in [null, 'Work', 'Public']) {
      testWidgets('an unresolved NGC ($type) member keeps the per-group hint',
          (tester) async {
        await tester.pumpWidget(_localized(TencentCloudChatGroupMemberInfoBody(
            memberFullInfo: _member(_groupKey), groupType: type)));
        await tester.pumpAndSettle();
        final hint = tester.widget<Text>(
            find.byKey(const ValueKey('group_member_info_key_hint')));
        expect(hint.data, tL10n.groupMemberKeyHint);
      });
    }
  });
}
