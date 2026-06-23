import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/error_message_converter.dart';
import 'package:tencent_cloud_chat_common/utils/face_manager.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_code_info.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/group_profile_widgets/tencent_cloud_chat_group_profile_body.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_group_profile.dart';
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
