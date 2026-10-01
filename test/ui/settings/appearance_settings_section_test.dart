import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/appearance_settings_section.dart';
import 'package:toxee/util/interface_style.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/theme_controller.dart';

Widget _harness({
  AppearanceSaver? save,
  double textScale = 1,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: AppearanceSettingsSection(saveAppearance: save),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  AppearanceSaver? save,
  Size size = const Size(1200, 1000),
  double scale = 1,
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _harness(save: save, textScale: scale, locale: locale),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.initialize(await SharedPreferences.getInstance());
    AppTheme.style.value = InterfaceStyle.classic;
    AppTheme.mode.value = ThemeMode.system;
  });

  testWidgets('five native thumbnails select a local chat preview only', (
    tester,
  ) async {
    await _pump(tester);
    for (final style in InterfaceStyle.values) {
      expect(find.byKey(Key('settings_style_${style.name}')), findsOneWidget);
    }
    await _tap(tester, find.byKey(const Key('settings_style_cartoon')));
    expect(AppTheme.style.value, InterfaceStyle.classic);
    expect(AppTheme.mode.value, ThemeMode.system);
    final preview = tester.widget<DecoratedBox>(
      find.byKey(const Key('settings_appearance_preview')),
    );
    expect(
      (preview.decoration as BoxDecoration).color,
      InterfaceStyle.cartoon.palette(Brightness.light).canvas,
    );
    expect(
      find.text('Preview only. Apply to save your changes.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'style thumbnails expose selection and activation to assistive tools',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(tester);
        final target = find.bySemanticsLabel('Fresh Cartoon');
        expect(target, findsOneWidget);
        expect(
          tester
              .getSemantics(target)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('brightness stays staged until Apply commits both values', (
    tester,
  ) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('settings_style_paper')));
    await _tap(tester, find.text('Dark').first);
    expect(AppTheme.mode.value, ThemeMode.system);
    expect(AppTheme.style.value, InterfaceStyle.classic);
    await _tap(tester, find.byKey(const Key('settings_appearance_apply')));
    expect(AppTheme.mode.value, ThemeMode.dark);
    expect(AppTheme.style.value, InterfaceStyle.paper);
    final apply = tester.widget<FilledButton>(
      find.byKey(const Key('settings_appearance_apply')),
    );
    expect(apply.onPressed, isNull);
  });

  testWidgets(
    'Reset stages classic and system without changing global values',
    (tester) async {
      AppTheme.style.value = InterfaceStyle.cartoon;
      AppTheme.mode.value = ThemeMode.dark;
      await _pump(tester);
      await _tap(tester, find.byKey(const Key('settings_appearance_reset')));
      expect(AppTheme.style.value, InterfaceStyle.cartoon);
      expect(AppTheme.mode.value, ThemeMode.dark);
      final preview = tester.widget<DecoratedBox>(
        find.byKey(const Key('settings_appearance_preview')),
      );
      expect(
        (preview.decoration as BoxDecoration).color,
        InterfaceStyle.classic.palette(Brightness.light).canvas,
      );
      await _tap(tester, find.byKey(const Key('settings_appearance_apply')));
      expect(AppTheme.style.value, InterfaceStyle.classic);
      expect(AppTheme.mode.value, ThemeMode.system);
    },
  );

  testWidgets(
    'failed saving preserves global values and staged choice for retry',
    (tester) async {
      var fail = true;
      final choices = <(InterfaceStyle, ThemeMode)>[];
      await _pump(
        tester,
        save: ({required style, required mode}) async {
          choices.add((style, mode));
          if (fail) throw StateError('disk write failed');
          await AppTheme.setAppearance(style: style, mode: mode);
        },
      );
      await _tap(tester, find.byKey(const Key('settings_style_night')));
      await _tap(tester, find.text('Dark').first);
      await _tap(tester, find.byKey(const Key('settings_appearance_apply')));
      expect(AppTheme.style.value, InterfaceStyle.classic);
      expect(AppTheme.mode.value, ThemeMode.system);
      expect(
        find.text(
          'Could not save appearance. Your choices are kept; please try again.',
        ),
        findsOneWidget,
      );
      fail = false;
      await _tap(tester, find.byKey(const Key('settings_appearance_apply')));
      expect(choices, [
        (InterfaceStyle.night, ThemeMode.dark),
        (InterfaceStyle.night, ThemeMode.dark),
      ]);
      expect(AppTheme.style.value, InterfaceStyle.night);
      expect(AppTheme.mode.value, ThemeMode.dark);
    },
  );

  testWidgets('in-flight saving disables repeated Apply and Reset', (
    tester,
  ) async {
    final save = Completer<void>();
    var calls = 0;
    await _pump(
      tester,
      save: ({required style, required mode}) {
        calls++;
        return save.future;
      },
    );
    await _tap(tester, find.byKey(const Key('settings_style_modern')));
    await tester.tap(find.byKey(const Key('settings_appearance_apply')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('settings_appearance_apply')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('settings_appearance_reset')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('settings_appearance_apply')));
    await tester.pump();
    expect(calls, 1);
    save.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('leaving discards pending selections', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const Key('settings_style_cartoon')));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    final preview = tester.widget<DecoratedBox>(
      find.byKey(const Key('settings_appearance_preview')),
    );
    expect(
      (preview.decoration as BoxDecoration).color,
      InterfaceStyle.classic.palette(Brightness.light).canvas,
    );
  });

  for (final locale in [
    const Locale('en'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    const Locale('ar'),
  ]) {
    testWidgets(
      'narrow large-text controls remain reachable (${locale.toLanguageTag()})',
      (tester) async {
        await _pump(
          tester,
          size: const Size(320, 640),
          scale: 2,
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.byKey(const Key('settings_style_cartoon')));
        await _tap(tester, find.byKey(const Key('settings_appearance_apply')));
        expect(AppTheme.style.value, InterfaceStyle.cartoon);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const Key('settings_appearance_reset')),
        );
        expect(
          find.byKey(const Key('settings_appearance_reset')).hitTestable(),
          findsOneWidget,
        );
      },
    );
  }
}
