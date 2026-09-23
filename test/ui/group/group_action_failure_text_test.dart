// Item 14 — a failed group-member action (kick, set/dismiss admin, whole-call
// invite) shows a REAL reason derived from the Tim2Tox code instead of the
// generic "Failed" (kick used `contactAddFailed`). Shared fork Dart: the
// member row's desktop menu and mobile sheet both route through it.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/widgets/group_action_failure_text.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';

void main() {
  // (`tL10n` is a process singleton initialized once, so one locale per file.)
  for (final locale in ['en']) {
    testWidgets('codes map to localized reasons ($locale)', (tester) async {
      late TencentCloudChatLocalizations l10n;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale),
        supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
        localizationsDelegates: const [
          TencentCloudChatLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(builder: (context) {
          TencentCloudChatIntl().init(context);
          l10n = TencentCloudChatLocalizations.of(context)!;
          return const SizedBox();
        }),
      ));
      await tester.pumpAndSettle();

      expect(groupActionFailureText(10007, 'x'), l10n.groupActionNoPermission);
      expect(groupActionFailureText(7013, 'x'), l10n.groupActionNotSupported);
      expect(groupActionFailureText(6013, 'x'), l10n.groupActionNotConnected);
      expect(groupActionFailureText(6017, l10n.kickMemberFailed),
          l10n.kickMemberFailed);
      expect(l10n.kickMemberFailed, isNot(l10n.contactAddFailed));
      expect(tL10n.groupActionNoPermission,
          "You don't have permission to do that in this group.");
    });
  }
}
