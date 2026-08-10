// L1 — `lib/ui/widgets/app_snackbar.dart`. Every user-facing toast in the app
// goes through this helper (~35 call sites across login, profile, home, call
// effects, settings, plus `SendFailureNotifier`).
//
// WHY THIS FILE EXISTS
// --------------------
// `AppSnackBar` owns three decisions that nothing else pinned:
//
//   1. WHERE the theme is resolved. `SnackBar.backgroundColor` is evaluated
//      EAGERLY, at the call site. The `showOn(ScaffoldMessengerState)` entry
//      point exists for callers that have no BuildContext at all (SDK
//      callbacks holding a GlobalKey), and the only context such a caller can
//      reach — the messenger's own — is NOT below `MaterialApp`'s
//      `AnimatedTheme`. Resolving eagerly there yields `ThemeData`'s default
//      light scheme, i.e. a light-mode error toast in dark mode. The fix is to
//      resolve inside the SnackBar's content `Builder`, at the display site.
//      `resolves its colours where the toast is displayed` is the test that
//      says so, and it is deliberately built so it discriminates WITHOUT
//      depending on any claim about Flutter's internal widget ordering: it
//      puts an explicit `Theme` override between the messenger and the
//      Scaffold, so "resolved at the call site" and "resolved at the display
//      site" produce different colours under any ordering.
//
//   2. THAT `show(BuildContext)` and `showOn(ScaffoldMessengerState)` are the
//      same toast. `show` is a thin wrapper; if the two ever drift, half the
//      app gets one look and the SDK-callback path gets another. That is the
//      exact duplication this file's subject was refactored to remove.
//
//   3. WHICH variants get the transparent-shell treatment. Error/success
//      contribute a colour from the `ColorScheme` and therefore must be built
//      at the display site; info/neutral contribute nothing and let
//      `snackBarTheme` own the surface, which `SnackBar` already resolves at
//      the display site itself. That split is intentional and is pinned below,
//      because "simplifying" it in either direction is a regression: making
//      info transparent means reimplementing `snackBarTheme` by hand, making
//      error opaque brings the dark-mode bug back.
//
// WHAT THIS FILE DOES NOT COVER (and why)
// ---------------------------------------
//   * Exact geometry (margin values, shadow) — asserted only as "the same via
//     both entry points", not against pixel goldens.
//   * The `SendFailureNotifier` wiring and copy: that is
//     `test/util/send_failure_notifier_test.dart`, which drives the production
//     single-messenger tree.
//
// GLOBAL STATE: none. `AppSnackBar` is a stateless namespace; every test here
// builds its own `MaterialApp` + `GlobalKey<ScaffoldMessengerState>`, so there
// is nothing for a `tearDown` to reset. (`SendFailureNotifier`'s process-global
// dedup map is deliberately not touched from here.)
//
// Mobile parity: pure Flutter widgets, no platform branch — iOS/Android/desktop
// run exactly this code.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/widgets/app_snackbar.dart';
import 'package:toxee/util/app_theme_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bodyKey = Key('test-body');
  const scaffoldKey = Key('test-scaffold');

  ColorScheme scheme({
    Brightness brightness = Brightness.light,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
  }) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00AA00),
      brightness: brightness,
    );
    return base.copyWith(
      errorContainer: errorContainer,
      onErrorContainer: onErrorContainer,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
    );
  }

  Widget host({
    required GlobalKey<ScaffoldMessengerState> messengerKey,
    ThemeData? theme,
    ThemeData? darkTheme,
    ThemeMode? themeMode,
    ThemeData? displaySiteTheme,
  }) {
    const scaffold = Scaffold(
      key: scaffoldKey,
      body: SizedBox.shrink(key: bodyKey),
    );
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: displaySiteTheme == null
          ? scaffold
          : Theme(data: displaySiteTheme, child: scaffold),
    );
  }

  // A SnackBar carries an auto-dismiss Timer; `testWidgets` fails the test if a
  // Timer is still pending when the tree is torn down, so every test drains.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  SnackBar snackBarOf(WidgetTester tester) =>
      tester.widget<SnackBar>(find.byType(SnackBar));

  /// Everything observable about a coloured (error/success) toast. Used to
  /// compare the two entry points field by field.
  Map<String, Object?> describeColouredToast(WidgetTester tester) {
    final snackBar = snackBarOf(tester);
    final surfaceFinder = find.byKey(AppSnackBar.toastSurfaceKey);
    final surface = tester.widget<Material>(surfaceFinder);
    final icon = tester.widget<Icon>(
      find.descendant(of: surfaceFinder, matching: find.byType(Icon)),
    );
    final text = tester.widget<Text>(
      find.descendant(of: surfaceFinder, matching: find.byType(Text)),
    );
    return <String, Object?>{
      'shellBackground': snackBar.backgroundColor,
      'shellElevation': snackBar.elevation,
      'shellPadding': snackBar.padding,
      'shellClip': snackBar.clipBehavior,
      'behavior': snackBar.behavior,
      'margin': snackBar.margin,
      'duration': snackBar.duration,
      'surfaceColor': surface.color,
      'surfaceElevation': surface.elevation,
      'surfaceRadius': surface.borderRadius,
      'icon': icon.icon,
      'iconColor': icon.color,
      'text': text.data,
      'textColor': text.style?.color,
    };
  }

  /// Everything observable about a theme-owned (info/neutral) toast.
  Map<String, Object?> describePlainToast(WidgetTester tester) {
    final snackBar = snackBarOf(tester);
    final text = tester.widget<Text>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
    );
    return <String, Object?>{
      'background': snackBar.backgroundColor,
      'shape': snackBar.shape,
      'behavior': snackBar.behavior,
      'margin': snackBar.margin,
      'duration': snackBar.duration,
      'hasAction': snackBar.action != null,
      'text': text.data,
      'textStyle': text.style,
    };
  }

  group('where the theme is resolved', () {
    testWidgets(
        'resolves its colours where the toast is displayed, not where it was '
        'raised', (tester) async {
      // THE regression test for the messenger entry point, and the one that
      // does not lean on any assumption about MaterialApp's internal ordering:
      // the app theme and the display-site theme carry different error pairs,
      // and the toast is presented inside the display-site `Theme`.
      const appErrorContainer = Color(0xFFAA0001);
      const appOnErrorContainer = Color(0xFFAA0002);
      const displayErrorContainer = Color(0xFF0B0C0D);
      const displayOnErrorContainer = Color(0xFF0E0F10);

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(
          colorScheme: scheme(
            errorContainer: appErrorContainer,
            onErrorContainer: appOnErrorContainer,
          ),
        ),
        displaySiteTheme: ThemeData(
          colorScheme: scheme(
            errorContainer: displayErrorContainer,
            onErrorContainer: displayOnErrorContainer,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      AppSnackBar.showErrorOn(messengerKey.currentState!, 'boom');
      await tester.pumpAndSettle();

      final surfaceFinder = find.byKey(AppSnackBar.toastSurfaceKey);
      expect(
        find.descendant(
          of: find.byKey(scaffoldKey),
          matching: surfaceFinder,
        ),
        findsOneWidget,
        reason: 'the toast is presented by the Scaffold, below the override',
      );

      final surface = tester.widget<Material>(surfaceFinder);
      expect(
        surface.color,
        displayErrorContainer,
        reason: 'an eagerly-resolved backgroundColor would carry the theme the '
            'CALLER could see ($appErrorContainer), not the one on screen',
      );

      final text = tester.widget<Text>(find.text('boom'));
      expect(
        text.style?.color,
        displayOnErrorContainer,
        reason: 'the foreground has to come from the same resolution as the '
            'background, not from the caller-side $appOnErrorContainer',
      );

      await drain(tester);
    });

    testWidgets('a dark-mode error toast uses the app dark scheme',
        (tester) async {
      // The production symptom: the app is in dark mode, the toast is raised
      // from an SDK callback that only holds the messenger key, and the colours
      // come out of ThemeData's default LIGHT scheme.
      const lightErrorContainer = Color(0xFFFFEEEE);
      const darkErrorContainer = Color(0xFF3A0D0D);
      const darkOnErrorContainer = Color(0xFFFFD9D9);

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(
          colorScheme: scheme(errorContainer: lightErrorContainer),
        ),
        darkTheme: ThemeData(
          colorScheme: scheme(
            brightness: Brightness.dark,
            errorContainer: darkErrorContainer,
            onErrorContainer: darkOnErrorContainer,
          ),
        ),
        themeMode: ThemeMode.dark,
      ));
      await tester.pumpAndSettle();

      AppSnackBar.showErrorOn(messengerKey.currentState!, 'boom');
      await tester.pumpAndSettle();

      final surface = tester.widget<Material>(
        find.byKey(AppSnackBar.toastSurfaceKey),
      );
      expect(
        surface.color,
        darkErrorContainer,
        reason: 'the two wrong answers this pins out are the app LIGHT scheme '
            '($lightErrorContainer) and the default ThemeData scheme — both of '
            'which an eager, caller-side resolution can produce',
      );
      expect(
        tester.widget<Text>(find.text('boom')).style?.color,
        darkOnErrorContainer,
        reason: 'foreground and background must come from the SAME scheme, or '
            'the toast can end up unreadable',
      );

      await drain(tester);
    });
  });

  group('show(context) and showOn(messenger) are the same toast', () {
    testWidgets('for the error variant', (tester) async {
      const errorContainer = Color(0xFF123456);
      const onErrorContainer = Color(0xFF654321);

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(
          colorScheme: scheme(
            errorContainer: errorContainer,
            onErrorContainer: onErrorContainer,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      AppSnackBar.showError(tester.element(find.byKey(bodyKey)), 'boom');
      await tester.pumpAndSettle();
      final viaContext = describeColouredToast(tester);

      messengerKey.currentState!.clearSnackBars();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      AppSnackBar.showErrorOn(messengerKey.currentState!, 'boom');
      await tester.pumpAndSettle();
      final viaMessenger = describeColouredToast(tester);

      // Anchor the comparison to concrete values first, so the equality below
      // cannot pass by both sides being empty/null.
      expect(viaContext['surfaceColor'], errorContainer);
      expect(viaContext['textColor'], onErrorContainer);
      expect(viaContext['icon'], Icons.error_outline);
      expect(viaContext['duration'], const Duration(seconds: 4));
      expect(viaContext['text'], 'boom');

      expect(
        viaMessenger,
        viaContext,
        reason: 'show() is a thin wrapper over showOn(); any divergence means '
            'the styling has forked again',
      );

      await drain(tester);
    });

    testWidgets('for the theme-owned neutral variant', (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(colorScheme: scheme()),
      ));
      await tester.pumpAndSettle();

      AppSnackBar.show(tester.element(find.byKey(bodyKey)), 'plain');
      await tester.pumpAndSettle();
      final viaContext = describePlainToast(tester);

      messengerKey.currentState!.clearSnackBars();
      await tester.pumpAndSettle();

      AppSnackBar.showOn(messengerKey.currentState!, 'plain');
      await tester.pumpAndSettle();
      final viaMessenger = describePlainToast(tester);

      expect(viaContext['text'], 'plain');
      expect(viaContext['duration'], const Duration(seconds: 3));
      expect(viaContext['background'], isNull);
      expect(viaMessenger, viaContext);

      await drain(tester);
    });
  });

  group('variants', () {
    testWidgets('error paints errorContainer on a transparent shell',
        (tester) async {
      const errorContainer = Color(0xFF112233);
      const onErrorContainer = Color(0xFF445566);

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(
          colorScheme: scheme(
            errorContainer: errorContainer,
            onErrorContainer: onErrorContainer,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      AppSnackBar.showErrorOn(messengerKey.currentState!, 'boom');
      await tester.pumpAndSettle();

      final snackBar = snackBarOf(tester);
      expect(
        snackBar.backgroundColor,
        Colors.transparent,
        reason: 'the shell must stay transparent — an opaque one would be '
            'resolved eagerly, which is the whole bug',
      );
      expect(snackBar.elevation, 0);
      expect(
        snackBar.padding,
        EdgeInsets.zero,
        reason: 'the inner Material draws the padding itself',
      );
      expect(
        snackBar.clipBehavior,
        Clip.none,
        reason: 'the default Clip.hardEdge clips the child to the SHELL shape, '
            'and the shell is exactly the size of the inner surface — the '
            'elevation shadow would be clipped away and the toast would look '
            'flat',
      );
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect(snackBar.duration, const Duration(seconds: 4));

      final surface = tester.widget<Material>(
        find.byKey(AppSnackBar.toastSurfaceKey),
      );
      expect(surface.color, errorContainer);
      expect(
        surface.elevation,
        6,
        reason: 'the shell gave up its elevation, so the inner surface has to '
            'reproduce a floating SnackBar default of 6',
      );
      expect(surface.borderRadius, BorderRadius.circular(AppRadii.card));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
        onErrorContainer,
      );

      await drain(tester);
    });

    testWidgets('success paints tertiaryContainer and keeps the 3s default',
        (tester) async {
      const tertiaryContainer = Color(0xFF0F9D58);
      const onTertiaryContainer = Color(0xFFEFFFF4);

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(
          colorScheme: scheme(
            tertiaryContainer: tertiaryContainer,
            onTertiaryContainer: onTertiaryContainer,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      AppSnackBar.showSuccess(tester.element(find.byKey(bodyKey)), 'saved');
      await tester.pumpAndSettle();

      expect(
        tester.widget<Material>(find.byKey(AppSnackBar.toastSurfaceKey)).color,
        tertiaryContainer,
      );
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('saved')).style?.color,
        onTertiaryContainer,
      );
      expect(
        snackBarOf(tester).duration,
        const Duration(seconds: 3),
        reason: 'only errors get the extended 4s',
      );

      await drain(tester);
    });

    testWidgets('info and neutral leave the surface to snackBarTheme',
        (tester) async {
      const themedSurface = Color(0xFF303030);

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(
          colorScheme: scheme(),
          snackBarTheme: const SnackBarThemeData(
            backgroundColor: themedSurface,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      AppSnackBar.showInfo(tester.element(find.byKey(bodyKey)), 'heads up');
      await tester.pumpAndSettle();

      expect(
        find.byKey(AppSnackBar.toastSurfaceKey),
        findsNothing,
        reason: 'these variants contribute no colour, so they must NOT get the '
            'transparent shell — SnackBar resolves snackBarTheme at the '
            'display site by itself',
      );
      expect(snackBarOf(tester).backgroundColor, isNull);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(
        tester
            .widget<Material>(
              // SnackBar's own surface Material is the outermost one in its
              // subtree, so depth-first order puts it first.
              find
                  .descendant(
                    of: find.byType(SnackBar),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        themedSurface,
        reason: 'the painted surface really is the themed one',
      );

      await drain(tester);
    });

    testWidgets('the coloured surface keeps snackBarTheme typography',
        (tester) async {
      // The inner Material would otherwise install `textTheme.bodyMedium` as
      // the default text style, silently changing weight/size relative to a
      // plain SnackBar. Only the COLOUR is meant to differ.
      const contentTextStyle = TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Color(0xFF00FF00),
      );
      const onErrorContainer = Color(0xFF654321);

      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(
          colorScheme: scheme(onErrorContainer: onErrorContainer),
          snackBarTheme: const SnackBarThemeData(
            contentTextStyle: contentTextStyle,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      AppSnackBar.showErrorOn(messengerKey.currentState!, 'boom');
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderParagraph>(find.text('boom'));
      final resolved = paragraph.text.style;
      expect(resolved?.fontSize, 17);
      expect(resolved?.fontWeight, FontWeight.w700);
      expect(
        resolved?.color,
        onErrorContainer,
        reason: 'the error pair still wins over the themed content colour',
      );

      await drain(tester);
    });
  });

  group('messenger semantics', () {
    testWidgets('a second toast replaces the first instead of queueing',
        (tester) async {
      // The messenger QUEUES snackbars: without the `hideCurrentSnackBar()`
      // every show performs, the second message would wait out the first one's
      // duration and the user would keep reading stale copy.
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(colorScheme: scheme()),
      ));
      await tester.pumpAndSettle();

      AppSnackBar.showOn(messengerKey.currentState!, 'first');
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);

      AppSnackBar.showOn(messengerKey.currentState!, 'second');
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsOneWidget);

      await drain(tester);
    });

    testWidgets('show(context) inherits the same replace-not-queue behaviour',
        (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(colorScheme: scheme()),
      ));
      await tester.pumpAndSettle();

      final context = tester.element(find.byKey(bodyKey));
      AppSnackBar.showError(context, 'first');
      await tester.pumpAndSettle();
      AppSnackBar.showSuccess(context, 'second');
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsOneWidget);

      await drain(tester);
    });

    testWidgets('an error toast outlives the 3s default, then dismisses',
        (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(colorScheme: scheme()),
      ));
      await tester.pumpAndSettle();

      // Baseline: the default duration really is 3s, so the error assertion
      // below is a difference and not just "snackbars linger".
      AppSnackBar.showOn(messengerKey.currentState!, 'neutral');
      await tester.pumpAndSettle();
      expect(find.text('neutral'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('neutral'), findsNothing);

      AppSnackBar.showErrorOn(messengerKey.currentState!, 'error');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      expect(
        find.text('error'),
        findsOneWidget,
        reason: 'errors are pinned to 4s — a failure the user misses is a '
            'failure that never happened as far as they know',
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('error'), findsNothing);
    });
  });

  group('actions', () {
    testWidgets('an error action sits inside the coloured surface and fires',
        (tester) async {
      // The shell has zero padding and a transparent background, so SnackBar's
      // own action slot would render the button OFF the coloured area.
      var taps = 0;
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(colorScheme: scheme()),
      ));
      await tester.pumpAndSettle();

      AppSnackBar.showOn(
        messengerKey.currentState!,
        'mic is blocked',
        isError: true,
        actionLabel: 'Settings',
        onAction: () => taps++,
      );
      await tester.pumpAndSettle();

      expect(
        snackBarOf(tester).action,
        isNull,
        reason: 'the action moved into the content for the coloured variants',
      );
      expect(
        find.descendant(
          of: find.byKey(AppSnackBar.toastSurfaceKey),
          matching: find.byType(SnackBarAction),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(taps, 1);
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'SnackBarAction dismisses the toast it belongs to',
      );
    });

    testWidgets('a neutral action stays in the stock SnackBar action slot',
        (tester) async {
      var taps = 0;
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(host(
        messengerKey: messengerKey,
        theme: ThemeData(colorScheme: scheme()),
      ));
      await tester.pumpAndSettle();

      AppSnackBar.showOn(
        messengerKey.currentState!,
        'camera unavailable',
        actionLabel: 'Settings',
        onAction: () => taps++,
      );
      await tester.pumpAndSettle();

      expect(
        snackBarOf(tester).action,
        isNotNull,
        reason: 'the theme-owned variants keep the stock layout, including the '
            'action slot SnackBar lays out itself',
      );

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(taps, 1);

      await drain(tester);
    });
  });
}
