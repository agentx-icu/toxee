import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_application_list.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_tab.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _buildTabHarness() {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          TencentCloudChatContactTab(
            item: TTabItem(
              id: 'new_contacts',
              name: 'New Contacts',
              icon: Icons.person_add_alt_1_outlined,
            ),
          ),
          TencentCloudChatContactTab(
            item: TTabItem(
              id: 'group_notification',
              name: 'Group Notifications',
              icon: Icons.notification_add_outlined,
            ),
          ),
          TencentCloudChatContactTab(
            item: TTabItem(
              id: 'blocked_users',
              name: 'Blocked Users',
              icon: Icons.block_outlined,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildEmptyApplicationListHarness() {
  return const MaterialApp(
    locale: Locale('en'),
    localizationsDelegates:
        TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(
      body: TencentCloudChatContactApplicationList(applicationList: []),
    ),
  );
}

void main() {
  testWidgets('new contacts tab exposes a stable anchor key', (tester) async {
    await tester.pumpWidget(_buildTabHarness());
    await tester.pump();

    expect(find.byKey(UiKeys.contactNewContactsTab), findsOneWidget);
    expect(find.text('New Contacts'), findsOneWidget);
    expect(find.byKey(UiKeys.contactGroupNotificationsTab), findsOneWidget);
    expect(find.byKey(UiKeys.contactBlockedUsersTab), findsOneWidget);
  });

  testWidgets('empty friend applications state exposes a stable anchor key', (
    tester,
  ) async {
    await tester.pumpWidget(_buildEmptyApplicationListHarness());
    await tester.pump();

    final emptyStateFinder = find.byKey(UiKeys.contactApplicationsListEmpty);
    expect(emptyStateFinder, findsOneWidget);
    expect(
      find.descendant(
        of: emptyStateFinder,
        matching: find.text('No new application'),
      ),
      findsOneWidget,
    );
  });
}
