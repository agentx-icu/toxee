// I5 (doc/reference/MOBILE_DEVICE_FEATURES.md): every control a screen
// reader reaches has a name, and a switch is read with its title.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/widgets/operation_bar/tencent_cloud_chat_operation_bar.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/profile/profile_avatar.dart';
import 'package:toxee/ui/settings/_hoverable_settings_row.dart';
import 'package:toxee/ui/widgets/error_banner.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    TencentCloudChatLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('a settings switch row is one node read with its title', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        HoverableSettingsRow(
          child: Row(
            children: [
              const Expanded(child: Text('Auto Login')),
              Switch(value: true, onChanged: (_) {}),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(Switch)),
      matchesSemantics(
        label: 'Auto Login',
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('an operation-bar switch is read with its label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        TencentCloudChatOperationBar<bool>(
          label: 'Pin',
          value: false,
          operationBarType: OperationBarType.switchControl,
          onChange: (_) {},
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(Switch)),
      isSemantics(label: 'Pin', hasToggledState: true),
    );
    handle.dispose();
  });

  testWidgets('the editable own avatar is one named button', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _app(
        ProfileAvatar(
          size: 80,
          primaryColor: Colors.blue,
          onPrimary: Colors.white,
          displayInitial: 'B',
          avatarPath: null,
          avatarFileExists: false,
          avatarVersion: 0,
          isEditable: true,
          onTap: () => taps++,
        ),
      ),
    );
    final button = find.bySemanticsLabel('Change profile photo');
    expect(button, findsOneWidget);
    expect(
      tester.getSemantics(button),
      isSemantics(isButton: true, hasTapAction: true),
    );
    tester.semantics.tap(find.semantics.byLabel('Change profile photo'));
    expect(taps, 1);
    handle.dispose();
  });

  // The conversation row (fork TencentCloudChatConversationItem) merges its
  // SwipeActionCell — whose RawGestureDetector always exposes a no-op tap —
  // with the row's InkWell. The merged node must run the row's tap.
  testWidgets('a merged row runs its own tap, not the swipe no-op', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var opened = 0, swipeNoop = 0;
    await tester.pumpWidget(
      _app(
        MergeSemantics(
          child: RawGestureDetector(
            gestures: {
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (r) => r.onTap = () => swipeNoop++,
                  ),
            },
            child: InkWell(
              onTap: () => opened++,
              child: const Text('Alice'),
            ),
          ),
        ),
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Alice'));
    expect(opened, 1);
    expect(swipeNoop, 0);
    handle.dispose();
  });

  testWidgets('the error banner close button is named', (tester) async {
    await tester.pumpWidget(
      _app(ErrorBanner(message: 'Failed', onDismiss: () {})),
    );
    expect(find.byTooltip('Close'), findsOneWidget);
  });
}
