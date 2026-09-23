// Group announcement editing (fork tencent_cloud_chat_group_notification.dart).
//
// Tim2Tox reports every NGC group as GroupType.Work, and the stock UIKit rule
// let ANYONE edit a Work group's notification. An NGC announcement is the Tox
// topic, which toxcore refuses to a plain member under the topic lock (on by
// default) — and the refusal was dropped silently. Now:
//   * the Edit action follows the host's live topic permission
//     (groupAnnouncementEditableResolver, wired by toxee to the Tox instance)
//     and otherwise the real self role; conferences (local-only note) stay
//     editable;
//   * a failed edit is reported through onUserNotificationEvent with the
//     localized reason (10007 → "no permission").
//
// Mobile parity: the announcement page is shared fork Dart; both its
// desktopBuilder (dialog body, desktop-size screen) and defaultBuilder (pushed
// page, phone-size screen) are pumped below.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_callbacks.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/group_announcement_permission.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/group_profile_widgets/tencent_cloud_chat_group_notification.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_platform_interface.dart';

class _AnnouncementPlatform extends TencentCloudChatSdkPlatform {
  _AnnouncementPlatform(this.code);

  final int code;
  V2TimGroupInfo? lastInfo;

  @override
  bool get isCustomPlatform => true;

  @override
  Future<V2TimCallback> setGroupInfo({required V2TimGroupInfo info}) async {
    lastInfo = info;
    return V2TimCallback(code: code, desc: code == 0 ? 'ok' : 'refused');
  }
}

V2TimGroupInfo _group({
  String type = GroupType.Work,
  int? role,
  String id = 'tox_group_7',
}) =>
    V2TimGroupInfo(
      groupID: id,
      groupType: type,
      role: role,
      notification: 'Old announcement',
    );

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
          return child;
        }),
      ),
    );

/// Desktop-size screens get the page's desktopBuilder, phone-size ones its
/// defaultBuilder (TencentCloudChatScreenAdapter decides by the diagonal).
const _shells = <String, Size>{
  'desktop': Size(1600, 1000),
  'mobile': Size(390, 844),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  tearDown(() => groupAnnouncementEditableResolver = null);

  group('canEditGroupAnnouncement', () {
    const member = GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER;
    const admin = GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_ADMIN;
    const owner = GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER;

    test('NGC (Work/Public) without a live answer: founder + moderators only',
        () {
      for (final type in [GroupType.Work, GroupType.Public]) {
        expect(canEditGroupAnnouncement(_group(type: type, role: member)),
            isFalse);
        expect(canEditGroupAnnouncement(_group(type: type, role: null)),
            isFalse, reason: 'unknown role never throws, never edits');
        expect(
            canEditGroupAnnouncement(_group(type: type, role: admin)), isTrue);
        expect(
            canEditGroupAnnouncement(_group(type: type, role: owner)), isTrue);
      }
    });

    test('the live topic permission wins over the role', () {
      groupAnnouncementEditableResolver = (id) => id == 'tox_group_7';
      expect(canEditGroupAnnouncement(_group(role: member)), isTrue,
          reason: 'topic lock off: a plain member may set the topic');
      groupAnnouncementEditableResolver = (_) => false;
      expect(canEditGroupAnnouncement(_group(role: owner)), isFalse,
          reason: 'e.g. an owner row that is stale');
      groupAnnouncementEditableResolver = (_) => null;
      expect(canEditGroupAnnouncement(_group(role: member)), isFalse);
      expect(canEditGroupAnnouncement(_group(role: admin)), isTrue);
    });

    test('a conference announcement is a local note: always editable', () {
      groupAnnouncementEditableResolver = (_) => false;
      for (final type in ['conference', 'av_conference', GroupType.AVChatRoom]) {
        expect(canEditGroupAnnouncement(_group(type: type, role: member)),
            isTrue, reason: type);
      }
    });
  });

  group('announcement page', () {
    late TencentCloudChatSdkPlatform oldPlatform;
    late List<({TencentCloudChatComponentsEnum c, int code, String text})>
        notices;
    late TencentCloudChatCallbacks sink;

    setUp(() {
      oldPlatform = TencentCloudChatSdkPlatform.instance;
      notices = [];
      sink = TencentCloudChatCallbacks(
        onTencentCloudChatUIKitUserNotificationEvent: (component, event) =>
            notices.add((c: component, code: event.eventCode, text: event.text)),
      );
      TencentCloudChat.instance.callbacks.addCallback(sink);
    });

    tearDown(() {
      TencentCloudChat.instance.callbacks.removeCallback(sink);
      TencentCloudChatSdkPlatform.instance = oldPlatform;
    });

    Future<void> pumpPage(WidgetTester tester, Size size, V2TimGroupInfo info) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          _app(TencentCloudChatGroupNotification(groupInfo: info)));
      await tester.pumpAndSettle();
    }

    for (final shell in _shells.entries) {
      testWidgets('${shell.key}: a plain NGC member is offered no Edit',
          (tester) async {
        await pumpPage(tester, shell.value,
            _group(role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER));
        expect(find.text('Old announcement'), findsOneWidget);
        expect(find.text(tL10n.edit), findsNothing);
      });

      testWidgets('${shell.key}: the owner edits; a refusal is reported',
          (tester) async {
        final platform = _AnnouncementPlatform(10007);
        TencentCloudChatSdkPlatform.instance = platform;
        await pumpPage(tester, shell.value,
            _group(role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_OWNER));

        await tester.tap(find.text(tL10n.edit));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(CupertinoTextField), 'New rules');
        await tester.tap(find.text(tL10n.confirm));
        await tester.pumpAndSettle();

        expect(platform.lastInfo?.notification, 'New rules');
        expect(find.text('Old announcement'), findsOneWidget,
            reason: 'a refused edit must not show as applied');
        expect(notices, hasLength(1));
        expect(notices.single.code, 10007);
        expect(notices.single.text, tL10n.groupActionNoPermission);
      });

      testWidgets('${shell.key}: a successful edit shows and reports nothing',
          (tester) async {
        TencentCloudChatSdkPlatform.instance = _AnnouncementPlatform(0);
        groupAnnouncementEditableResolver = (_) => true;
        await pumpPage(tester, shell.value,
            _group(role: GroupMemberRoleType.V2TIM_GROUP_MEMBER_ROLE_MEMBER));

        await tester.tap(find.text(tL10n.edit));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(CupertinoTextField), 'New rules');
        await tester.tap(find.text(tL10n.confirm));
        await tester.pumpAndSettle();

        expect(find.text('New rules'), findsOneWidget);
        expect(notices, isEmpty);
      });
    }
  });
}
