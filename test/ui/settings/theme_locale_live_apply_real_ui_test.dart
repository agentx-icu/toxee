// Real-UI L1 WidgetTester coverage for theme + locale LIVE-APPLY (S38 + S57).
//
// The sibling settings_sections_global_real_ui_test.dart already gates the
// SETTER side of the Appearance / Language rows (each control drives
// AppTheme.mode / AppLocale.locale AND persists to Prefs). This file does NOT
// duplicate that. It gates the LIVE-APPLY consequence the setters exist for:
// a real MaterialApp shell wired to the PRODUCTION controllers (AppTheme.mode,
// AppLocale.locale via ValueListenableBuilder, exactly as lib/main.dart wires
// the root app) actually REBUILDS its descendants when a real tap on the real
// GlobalSettingsSection flips the theme / locale:
//
//   * S57: tapping the real "Dark" segment -> applyThemeModeEverywhere ->
//     AppTheme.mode flips -> Theme.of(descendant).brightness becomes dark AND
//     a fork chat subtree (TencentCloudChatThemeWidget) rebuilds across the
//     change without throwing, its UIKit colorTheme flipping too (the UIKit
//     brightness event the applier fires).
//   * S38: tapping a real language option -> applyLocaleEverywhere ->
//     AppLocale.locale flips -> a visible AppLocalizations string in a
//     descendant changes (en "Appearance" -> zh "外观"); the Arabic option
//     additionally flips the ambient Directionality to RTL.
//
// No production logic is re-implemented: the shell wiring mirrors main.dart,
// and every flip is driven by a real tap on the real settings control, which
// calls the real appliers in lib/util/appearance_sync.dart.
//
// Mobile parity: AppTheme / AppLocale / appearance_sync.dart / the
// GlobalSettingsSection rows are all shared Dart, and MaterialApp theme/locale
// propagation is platform-agnostic, so this behavior is identical on
// iOS/Android. Nothing here is desktop-only.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/global_settings_section.dart';
import 'package:toxee/util/locale_controller.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/theme_controller.dart';
import 'package:toxee/util/appearance_sync.dart';

// Probe descendant keys: a tree node that reads Theme.of + AppLocalizations so
// we can assert the live values AFTER a flip (kept far below the section so the
// rebuild genuinely propagates down).
const Key _kProbe = ValueKey('theme_locale_probe');
const Key _kForkColor = ValueKey('fork_color_probe');

// Captured-from-the-fork colorTheme background, so S57 can assert the fork
// subtree's UIKit theme actually flipped across the rebuild.
Color? _lastForkBackground;

Future<void> _initPrefs() async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

// A real app shell that mirrors how lib/main.dart drives the root MaterialApp
// from AppTheme.mode + AppLocale.locale. The descendant probe + an optional
// fork chat subtree live under the same MaterialApp so a theme/locale flip has
// to rebuild through them.
Widget _shell({bool includeForkSubtree = false}) {
  return ValueListenableBuilder<ThemeMode>(
    valueListenable: AppTheme.mode,
    builder: (context, mode, _) {
      return ValueListenableBuilder<Locale>(
        valueListenable: AppLocale.locale,
        builder: (context, locale, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            themeMode: mode,
            theme: ThemeData(brightness: Brightness.light),
            darkTheme: ThemeData(brightness: Brightness.dark),
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              TencentCloudChatLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  // Init the UIKit intl singleton from a real Localizations
                  // ancestor (the fork subtree reads tL10n during build).
                  TencentCloudChatIntl().init(context);
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The REAL settings section drives the real appliers.
                        const GlobalSettingsSection(
                          colorTheme: null,
                          toxId: null,
                        ),
                        // Descendant probe: reads the LIVE theme brightness +
                        // a LIVE AppLocalizations string.
                        Builder(
                          key: _kProbe,
                          builder: (context) {
                            final brightness = Theme.of(context).brightness;
                            final appL10n = AppLocalizations.of(context)!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('probe-brightness:${brightness.name}'),
                                // The toxee AppLocalizations delegate string —
                                // the load-bearing one for S38 (flips en->zh).
                                Text('probe-appearance:${appL10n.appearance}'),
                              ],
                            );
                          },
                        ),
                        if (includeForkSubtree)
                          // A real fork "chat-ish" widget so the theme rebuild
                          // crosses fork code without throwing; it also exposes
                          // the UIKit colorTheme so we can assert it flipped.
                          TencentCloudChatThemeWidget(
                            key: _kForkColor,
                            build: (context, colorTheme, textStyle) {
                              _lastForkBackground = colorTheme.backgroundColor;
                              return Container(
                                width: 40,
                                height: 40,
                                color: colorTheme.backgroundColor,
                                child: Text(
                                  'fork',
                                  style: TextStyle(
                                    color: colorTheme.primaryTextColor,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  bool includeForkSubtree = false,
}) async {
  AppTheme.changes.addListener(syncUIKitAppearance);
  addTearDown(() => AppTheme.changes.removeListener(syncUIKitAppearance));
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_shell(includeForkSubtree: includeForkSubtree));
  // initState of the section awaits Prefs reads; flush microtask + setState.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

String _probeText(WidgetTester tester, String prefix) {
  final texts = tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(_kProbe), matching: find.byType(Text)),
      )
      .map((t) => t.data ?? '')
      .where((s) => s.startsWith(prefix));
  return texts.isEmpty ? '' : texts.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Material controls can emit HapticFeedback on SystemChannels.platform;
  // swallow it so a stray haptic never throws under the binding.
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  setUpAll(() {
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
  });
  tearDownAll(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  setUp(() async {
    await _initPrefs();
    // Process-global notifiers: reset before/after each case.
    AppTheme.mode.value = ThemeMode.light;
    AppLocale.locale.value = const Locale('en');
    _lastForkBackground = null;
  });
  tearDown(() {
    AppTheme.mode.value = ThemeMode.system;
    AppLocale.locale.value = const Locale('en');
  });

  // -------------------------------------------------------------------------
  // S57 — theme live-apply: tap real Dark segment -> descendant Theme flips +
  // fork subtree rebuilds across the change without throwing.
  // -------------------------------------------------------------------------
  testWidgets(
    'S57 tapping the real Dark segment flips the descendant theme and rebuilds a fork chat subtree',
    (tester) async {
      await _pumpShell(tester, includeForkSubtree: true);

      // Baseline: light everywhere (non-vacuous).
      expect(_probeText(tester, 'probe-brightness:'), 'probe-brightness:light');
      expect(
        find.byKey(_kForkColor),
        findsOneWidget,
        reason: 'the fork chat subtree should mount in light mode',
      );
      final lightForkBackground = _lastForkBackground;
      expect(lightForkBackground, isNotNull);

      // Tap the REAL "Dark" segment of the production SegmentedButton.
      final darkSegment = find.widgetWithText(
        SegmentedButton<ThemeMode>,
        'Dark',
      );
      expect(darkSegment, findsOneWidget);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(AppTheme.mode.value, ThemeMode.light);
      await tester.ensureVisible(
        find.byKey(const Key('settings_appearance_apply')),
      );
      await tester.tap(find.byKey(const Key('settings_appearance_apply')));
      // Apply saves the preference, then the production listener updates UIKit.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // S57 core: a descendant of the SAME app shell now renders dark — the
      // AppTheme.mode notifier drove the MaterialApp.themeMode rebuild.
      expect(AppTheme.mode.value, ThemeMode.dark);
      expect(
        _probeText(tester, 'probe-brightness:'),
        'probe-brightness:dark',
        reason: 'the descendant Theme.of(context).brightness must flip to dark',
      );

      // S57 cross-fork: the fork chat subtree survived the rebuild (still
      // present, no exception) AND its UIKit colorTheme flipped too.
      expect(
        tester.takeException(),
        isNull,
        reason:
            'the theme rebuild must cross the fork subtree without throwing',
      );
      expect(find.byKey(_kForkColor), findsOneWidget);
      expect(_lastForkBackground, isNotNull);
      expect(
        _lastForkBackground,
        isNot(lightForkBackground),
        reason:
            'the fork UIKit colorTheme background should flip when brightness changes',
      );
    },
  );

  // -------------------------------------------------------------------------
  // S38 — locale live-apply: tap a real language option -> a visible
  // AppLocalizations string in a descendant changes (en -> zh).
  // -------------------------------------------------------------------------
  testWidgets(
    'S38 selecting 简体中文 live-flips a descendant AppLocalizations string en->zh',
    (tester) async {
      await _pumpShell(tester);

      // Baseline: English string rendered in the probe (non-vacuous).
      expect(
        _probeText(tester, 'probe-appearance:'),
        'probe-appearance:Appearance',
      );

      // Expand the real collapsed language row (shows the current selection
      // "English"), then tap the 简体中文 option.
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      final zhOption = find.text('简体中文');
      expect(
        zhOption,
        findsOneWidget,
        reason: 'the expanded language list must show the 简体中文 option',
      );
      await tester.tap(zhOption);
      await tester.pumpAndSettle();

      // S38 core: AppLocale flipped AND the descendant AppLocalizations string
      // re-resolved to Simplified Chinese.
      expect(AppLocale.locale.value.languageCode, 'zh');
      expect(AppLocale.locale.value.scriptCode, 'Hans');
      expect(
        _probeText(tester, 'probe-appearance:'),
        'probe-appearance:外观',
        reason:
            'the descendant AppLocalizations.appearance must flip from "Appearance" to "外观"',
      );
    },
  );

  // -------------------------------------------------------------------------
  // S38 (RTL) — Arabic flips the ambient Directionality to RTL.
  // -------------------------------------------------------------------------
  testWidgets('S38 selecting العربية flips the ambient Directionality to RTL', (
    tester,
  ) async {
    await _pumpShell(tester);

    // Baseline LTR.
    final ltrDir = Directionality.of(tester.element(find.byKey(_kProbe)));
    expect(ltrDir, TextDirection.ltr);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    final arOption = find.text('العربية');
    expect(arOption, findsOneWidget);
    await tester.tap(arOption);
    await tester.pumpAndSettle();

    expect(AppLocale.locale.value.languageCode, 'ar');
    // The Arabic locale resolves the GlobalWidgetsLocalizations RTL
    // direction; the nearest Directionality ancestor of the descendant now
    // reports RTL (the load-bearing S38 Arabic case).
    final rtlDir = Directionality.of(tester.element(find.byKey(_kProbe)));
    expect(
      rtlDir,
      TextDirection.rtl,
      reason:
          'an Arabic locale must propagate RTL Directionality to descendants',
    );
  });
}
