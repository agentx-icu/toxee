import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/ui/settings/global_settings_section.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/responsive_layout.dart';

import 'settings_account_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempRoot;
  late SettingsChannelMocks mocks;
  setUp(() async {
    ResponsiveLayout.debugIsDesktopPlatformOverride = () => true;
    tempRoot = await Directory.systemTemp.createTemp('settings_organization_');
    mocks = SettingsChannelMocks.install(tempRoot);
    SharedPreferences.setMockInitialValues({});
    await Prefs.initialize(await SharedPreferences.getInstance());
    await Prefs.setCurrentAccountToxId(kSettingsToxId);
    await Prefs.setNickname('Account Nick');
    await Prefs.addAccount(toxId: kSettingsToxId, nickname: 'Account Nick');
  });
  tearDown(() {
    ResponsiveLayout.debugIsDesktopPlatformOverride = null;
    mocks.teardown();
    tempRoot.deleteSync(recursive: true);
  });

  testWidgets('desktop shows Appearance ahead of account management and '
      'renders General once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = SettingsHarnessService();
    addTearDown(service.disposeStub);
    await tester.pumpWidget(
      settingsApp(
        SettingsPage(
          service: service,
          connectionStatusStream: service.connectionStatusStream,
          autoAcceptFriends: false,
          onAutoAcceptFriendsChanged: (_) {},
          autoAcceptGroupInvites: false,
          onAutoAcceptGroupInvitesChanged: (_) {},
        ),
      ),
    );
    await settleSettings(tester);
    final firstSection = tester.widget<GlobalSettingsSection>(
      find.byType(GlobalSettingsSection).first,
    );
    expect(firstSection.view, GlobalSettingsView.appearance);
    // Measure ordering after expanding the test viewport so the lazy list
    // also mounts the account card's lower management heading.
    await tester.binding.setSurfaceSize(const Size(1280, 4000));
    await settleSettings(tester);
    expect(
      tester.getTopLeft(find.byType(GlobalSettingsSection).first).dy,
      lessThan(tester.getTopLeft(find.text('Account Management')).dy),
    );
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    for (final element
        in find.widgetWithIcon(IconButton, Icons.copy_outlined).evaluate()) {
      final size = (element.renderObject as RenderBox).size;
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    // ListView only mounts nearby sections. Reach General by scrolling instead
    // of assuming below-fold widgets already exist in the element tree.
    final general = find.byWidgetPredicate(
      (widget) =>
          widget is GlobalSettingsSection &&
          widget.view == GlobalSettingsView.general,
    );
    await tester.scrollUntilVisible(
      general,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settleSettings(tester);
    expect(general, findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is GlobalSettingsSection &&
            widget.view == GlobalSettingsView.all,
      ),
      findsNothing,
    );
  });
}
