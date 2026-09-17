import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/error_message_converter.dart';
import 'package:tencent_cloud_chat_common/utils/face_manager.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_code_info.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/group_profile_widgets/tencent_cloud_chat_group_profile_body.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_group_profile.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/group/group_builder_override.dart';

void _useEnglish() {
  TencentCloudChatIntl().setLocale(const Locale('en'));
}

void _useSimplifiedChinese() {
  TencentCloudChatIntl().setLocale(
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  );
}

V2TimGroupInfo _groupInfo() {
  return V2TimGroupInfo(
    groupID: 'group-123',
    groupName: 'Weekend Hikers',
    groupType: GroupType.Work,
  );
}

Future<void> _pumpMaterial(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      localizationsDelegates:
          TencentCloudChatLocalizations.localizationsDelegates,
      supportedLocales: TencentCloudChatLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() {
    _useEnglish();
    TencentCloudChatGroupProfileManager.builder.setBuilders();
  });

  test(
    'UIKit utility strings resolve from the current locale after switching',
    () {
      _useEnglish();

      expect(
        ErrorMessageConverter.getErrorMessage(10008, ''),
        'Invalid request',
      );
      expect(FaceManager.emojiMap['[TUIEmoji_Smile]'], '[Smile]');
      expect(TencentCloudChatCodeInfo.groupJoined.text, 'Group Joined');

      _useSimplifiedChinese();

      expect(ErrorMessageConverter.getErrorMessage(10008, ''), '请求非法');
      expect(FaceManager.emojiMap['[TUIEmoji_Smile]'], '[微笑]');
      expect(TencentCloudChatCodeInfo.groupJoined.text, '加入群组');
      expect(
        TencentCloudChatCodeInfo.retrievingGroupMembers.text,
        '正在获取群成员，请稍候。',
      );
    },
  );

  testWidgets('UIKit message bubble time follows the UIKit locale', (
    tester,
  ) async {
    // Regression: formatTimestampToTime used a locale-less DateFormat.jm(), so
    // every non-English UI rendered English "9:28 AM" bubble times while the
    // conversation list next to it read "09:28".
    final ts = DateTime(2026, 9, 17, 9, 28).millisecondsSinceEpoch ~/ 1000;
    late BuildContext ctx;
    _useSimplifiedChinese();
    await _pumpMaterial(
      tester,
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    );

    expect(TencentCloudChatIntl.formatTimestampToTime(ts, ctx), '09:28');
    expect(TencentCloudChatIntl.formatTimestampToTime(ts), '09:28');

    _useEnglish();
    expect(
      TencentCloudChatIntl.formatTimestampToTime(ts, ctx),
      matches(RegExp(r'^9:28\sAM$')),
    );
  });

  testWidgets(
    'UIKit member date-times use the UIKit locale, not the log format',
    (tester) async {
      // Regression: group member info/list rendered join and last-message times
      // with getFormattedTimeString ('yyyy-MM-dd hh:mm:ss a', always English
      // AM/PM) and a hard-coded Chinese '无' for "none" in every language.
      final dt = DateTime(2026, 9, 17, 21, 5);
      late BuildContext ctx;
      _useSimplifiedChinese();
      await _pumpMaterial(
        tester,
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      );
      final zh = TencentCloudChatIntl.formatDateTime(dt, ctx);
      expect(zh, contains('21:05'));
      expect(zh, isNot(contains('PM')));
      expect(tL10n.none, isNot('None'));

      _useEnglish();
      expect(TencentCloudChatIntl.formatDateTime(dt, ctx), contains('PM'));
      expect(tL10n.none, 'None');
    },
  );

  test('app status labels are translated in every shipped locale', () {
    // Regression: statusOnline/statusOffline existed only in the en/ar ARBs, so
    // the zh sidebar and profile read "Online" (gen-l10n falls back to English).
    const cases = [
      (Locale('zh'), '在线', '离线'),
      (Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'), '在线', '离线'),
      (Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), '在線', '離線'),
      (Locale('ja'), 'オンライン', 'オフライン'),
      (Locale('ko'), '온라인', '오프라인'),
    ];
    for (final (locale, online, offline) in cases) {
      final l10n = lookupAppLocalizations(locale);
      expect(l10n.statusOnline, online, reason: '$locale');
      expect(l10n.statusOffline, offline, reason: '$locale');
    }
  });

  testWidgets('UIKit group profile content localizes the group ID label', (
    tester,
  ) async {
    _useSimplifiedChinese();

    await _pumpMaterial(
      tester,
      TencentCloudChatGroupProfileContent(groupInfo: _groupInfo()),
    );

    expect(find.textContaining('群组ID: group-123'), findsOneWidget);
    expect(find.textContaining('Group ID:'), findsNothing);
  });

  testWidgets('toxee group profile override localizes the group ID label', (
    tester,
  ) async {
    _useSimplifiedChinese();
    final handle = GroupProfileBuilderOverrideHandle.capture();
    handle.installOverrides();
    addTearDown(handle.restore);

    final widget = TencentCloudChatGroupProfileManager.builder
        .getGroupProfileContentBuilder(groupInfo: _groupInfo());
    await _pumpMaterial(tester, widget);

    expect(find.textContaining('群组ID: group-123'), findsOneWidget);
    expect(find.textContaining('Group ID:'), findsNothing);
  });
}
