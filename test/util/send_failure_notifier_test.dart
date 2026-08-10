// L1 — `lib/util/send_failure_notifier.dart`. This is the only place a send
// failure becomes words the user reads, so every branch here is directly
// user-visible copy.
//
// WHY THIS FILE EXISTS
// --------------------
// `SendFailureNotifier.handleSdkFailure` is wired to
// `onTencentCloudChatSDKFailedCallback` in `lib/ui/home_page_bootstrap.dart`.
// It owns four decisions, none of which were pinned by anything:
//
//   1. WHICH failures surface at all — only `apiName == 'sendMessage'`.
//   2. THAT a toast reaches the screen at all in the real widget tree.
//   3. WHAT the user is told — `_humanize` pattern-matches the Tim2Tox `desc`
//      (the platform path always returns code -1 and puts the real reason in
//      `desc`) and maps it onto one of five messages, falling back to the
//      localized `sendFailed` template.
//   4. HOW OFTEN — identical `(apiName, code)` pairs are suppressed inside a
//      3s window so a burst of failed sends doesn't carpet the screen.
//
// Regressions here are silent: reordering the `_humanize` checks, or widening
// one pattern, swaps a precise message ("Message too long (max 1372 bytes)")
// for a useless one, and nothing crashes.
//
// WIDGET-TREE SHAPE — THIS IS LOAD-BEARING, DON'T "SIMPLIFY" IT
// -------------------------------------------------------------
// `host()` below mirrors PRODUCTION exactly: the global
// `scaffoldMessengerKey` is handed to `MaterialApp(scaffoldMessengerKey:)`
// (`lib/main.dart` -> `TencentCloudChatMaterialApp` -> `MaterialApp`), so the
// keyed messenger is the ROOT messenger with no ancestor messenger anywhere,
// and the only `Scaffold` is one of its descendants.
//
// An earlier revision of this file used a NESTED host — the key on an inner
// `ScaffoldMessenger` under `MaterialApp`'s own — and that shape MASKED a real
// bug. The notifier used to resolve `scaffoldMessengerKey.currentState.context`
// and hand it to `AppSnackBar`, which calls `ScaffoldMessenger.of(context)`.
// `of` searches ANCESTORS for `_ScaffoldMessengerScope`, but a
// `ScaffoldMessenger` publishes that scope to its DESCENDANTS — so a
// messenger's own context can never resolve itself. Under the nested host the
// lookup silently landed on `MaterialApp`'s messenger and a toast appeared;
// in production there is no ancestor messenger, so the lookup failed and the
// user saw nothing. Every test below now runs against the production shape:
// they are ALL red against the pre-fix implementation, and
// `renders a toast in the production single-messenger tree` is the one that
// says so out loud.
//
// The nested shape survives in exactly one test —
// `targets the keyed messenger, not an ancestor one` — where it is the
// discriminator rather than a convenience: it proves the toast is presented by
// the messenger we hold the key to and not by whatever messenger happens to sit
// above it.
//
// WHERE THE STYLING LIVES NOW
// ---------------------------
// The notifier no longer builds its own SnackBar: it calls
// `AppSnackBar.showErrorOnBuilder(messengerState, ...)`
// (`lib/ui/widgets/app_snackbar.dart`), which owns the transparent-shell +
// inner-`Material` structure, the `hideCurrentSnackBar()` that precedes every
// show, and the 4s error duration. `SendFailureNotifier.toastSurfaceKey`
// re-exports `AppSnackBar.toastSurfaceKey`, so the finders below keep working
// and keep meaning "the coloured surface of the toast". The tests here stay
// scoped to what this MODULE decides (which failures, what copy, how often, and
// that a toast reaches the production tree at all); the styling contract itself
// is pinned by `test/ui/widgets/app_snackbar_test.dart`.
//
// WHAT THIS FILE DOES NOT COVER (and why)
// ---------------------------------------
//   * Expiry of the 3s dedup window. `_lastShown` is compared against
//     `DateTime.now()` (wall clock), which `tester.pump(Duration)` does not
//     advance, so "the same code shows again after 3s" cannot be driven
//     deterministically without a clock seam in production code. Only the
//     inside-the-window suppression, the per-key scoping, and the explicit
//     `resetForTests` escape hatch are asserted.
//   * Exact geometry (margin/padding/elevation) of the toast — only the
//     theme-derived colours are pinned, because those are what a themeless
//     context silently gets wrong.
//   * The real `onSDKFailed` registration in `home_page_bootstrap.dart`.
//
// Mobile parity: pure Flutter widgets + a static map; no platform branch, so
// iOS/Android/desktop run exactly this code.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/util/send_failure_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeScaffoldKey = Key('test-home-scaffold');

  // Production shape: the key goes to MaterialApp's own ScaffoldMessenger,
  // which is the only messenger in the tree.
  Widget host({ThemeData? theme}) => MaterialApp(
        locale: const Locale('en'),
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        scaffoldMessengerKey: SendFailureNotifier.scaffoldMessengerKey,
        home: const Scaffold(
          key: homeScaffoldKey,
          body: SizedBox.shrink(),
        ),
      );

  setUp(SendFailureNotifier.resetForTests);

  tearDown(() {
    // `_lastShown` is a process-global static: an entry left behind would
    // suppress an unrelated later test's toast.
    SendFailureNotifier.resetForTests();
  });

  // A SnackBar carries an auto-dismiss Timer; `testWidgets` fails the test if a
  // Timer is still pending when the tree is torn down, so every test drains.
  Future<void> drainSnackBars(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  group('reaching the screen at all', () {
    testWidgets('renders a toast in the production single-messenger tree',
        (tester) async {
      // THE regression test. Against the pre-fix implementation (messenger's
      // own context -> `ScaffoldMessenger.of`) this throws
      // `debugCheckHasScaffoldMessenger` right here, because this tree — like
      // production — has no ancestor messenger to fall back onto.
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', -1, 'boom');
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(homeScaffoldKey),
          matching: find.byKey(SendFailureNotifier.toastSurfaceKey),
        ),
        findsOneWidget,
        reason:
            'the toast must be presented by the Scaffold that lives under the '
            'keyed messenger — that is the screen the user is looking at',
      );
      expect(find.text('Send failed: boom'), findsOneWidget);

      await drainSnackBars(tester);
    });

    testWidgets('targets the keyed messenger, not an ancestor one',
        (tester) async {
      // Nested on purpose: outer Scaffold registers with MaterialApp's
      // messenger, inner Scaffold registers with the keyed one. Presenting via
      // the ancestor messenger (the old `ScaffoldMessenger.of` behaviour) puts
      // the SnackBar in the OUTER Scaffold's snackbar slot, which is a sibling
      // of `body` and therefore NOT under the inner Scaffold.
      const outerScaffoldKey = Key('outer-scaffold');
      const innerScaffoldKey = Key('inner-scaffold');

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            key: outerScaffoldKey,
            body: ScaffoldMessenger(
              key: SendFailureNotifier.scaffoldMessengerKey,
              child: const Scaffold(
                key: innerScaffoldKey,
                body: SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', -1, 'boom');
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(innerScaffoldKey),
          matching: find.byType(SnackBar),
        ),
        findsOneWidget,
        reason:
            'the notifier must drive the messenger its key points at; showing '
            'on an ancestor messenger is how the toast got lost in production',
      );

      await drainSnackBars(tester);
    });

    testWidgets('takes its colours from the app theme', (tester) async {
      // The toast body is built at the DISPLAY site (inside the Scaffold), so
      // it sees the app's theme. Resolving colours from the messenger's own
      // context instead yields Flutter's fallback ThemeData — a light-mode
      // scheme that has nothing to do with these values — so this test also
      // guards against "fix the messenger, keep the themeless context".
      const errorContainer = Color(0xFF123456);
      const onErrorContainer = Color(0xFF654321);
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF00AA00))
          .copyWith(
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
      );

      await tester.pumpWidget(host(theme: ThemeData(colorScheme: scheme)));
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', -1, 'boom');
      await tester.pumpAndSettle();

      final surface = tester.widget<Material>(
        find.byKey(SendFailureNotifier.toastSurfaceKey),
      );
      expect(surface.color, errorContainer);

      final text = tester.widget<Text>(find.text('Send failed: boom'));
      expect(
        text.style?.color,
        onErrorContainer,
        reason:
            'foreground and background must come from the same ColorScheme, or '
            'the toast can end up unreadable (e.g. light-on-light in dark mode)',
      );

      await drainSnackBars(tester);
    });
  });

  group('which failures surface', () {
    testWidgets('a non-sendMessage api failure raises no toast',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('login', 6013, 'service unavailable');
      await tester.pumpAndSettle();

      expect(
        find.byType(SnackBar),
        findsNothing,
        reason:
            'only sendMessage failures are user-facing here; other api errors '
            'are already logged by the SDK trigger',
      );

      await drainSnackBars(tester);
    });

    testWidgets('a sendMessage failure raises exactly one toast',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', -1, 'boom');
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Send failed: boom'), findsOneWidget);

      await drainSnackBars(tester);
    });
  });

  group('_humanize — desc pattern to user-facing copy', () {
    testWidgets('an over-length payload names the Tox byte limit',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure(
        'sendMessage',
        -1,
        'msg_body_size exceeds limit',
      );
      await tester.pumpAndSettle();

      // The literal 1372 is asserted on purpose: it is `toxMaxTextBytes`, which
      // mirrors MAX_MESSAGE_LENGTH in c-toxcore. If the constant drifts away
      // from the C layer the user is told the wrong number.
      expect(find.text('Message too long (max 1372 bytes)'), findsOneWidget);

      await drainSnackBars(tester);
    });

    testWidgets('an offline-friend desc promises a retry', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure(
        'sendMessage',
        -1,
        'friend is offline',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Friend offline — will retry when they reconnect'),
        findsOneWidget,
        reason:
            'Tier 1B queues these silently; if one still reaches the user it '
            'must not read like a permanent failure',
      );

      await drainSnackBars(tester);
    });

    testWidgets('a group file desc states the unsupported feature',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure(
        'sendMessage',
        -1,
        'group file transfer refused',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('File transfer in group chats is not supported'),
        findsOneWidget,
        reason:
            'the group+file check must win over the generic file check, which '
            'would otherwise echo a meaningless raw desc',
      );

      await drainSnackBars(tester);
    });

    testWidgets('a file error echoes the underlying reason', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure(
        'sendMessage',
        -1,
        'file not found: /tmp/x.png',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('File send failed: file not found: /tmp/x.png'),
        findsOneWidget,
      );

      await drainSnackBars(tester);
    });

    testWidgets('an unrecognised desc falls back to the localized template',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', -1, 'weird failure');
      await tester.pumpAndSettle();

      expect(find.text('Send failed: weird failure'), findsOneWidget);

      await drainSnackBars(tester);
    });

    testWidgets('an empty desc with a real code shows the code', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', 6017, '   ');
      await tester.pumpAndSettle();

      expect(
        find.text('Send failed: error 6017'),
        findsOneWidget,
        reason: 'the toast must never render as a dangling "Send failed: "',
      );

      await drainSnackBars(tester);
    });

    testWidgets('an empty desc with code 0 shows "unknown error"',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', 0, '');
      await tester.pumpAndSettle();

      expect(find.text('Send failed: unknown error'), findsOneWidget);

      await drainSnackBars(tester);
    });

    testWidgets('a runaway desc is trimmed to 120 chars with an ellipsis',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // 'z' matches none of the patterns, so this lands on the generic branch
      // and exercises `_trim` alone.
      SendFailureNotifier.handleSdkFailure('sendMessage', -1, 'z' * 200);
      await tester.pumpAndSettle();

      expect(
        find.text('Send failed: ${'z' * 120}…'),
        findsOneWidget,
        reason: 'an unbounded desc would push the toast off-screen on mobile',
      );

      await drainSnackBars(tester);
    });
  });

  group('dedup window', () {
    testWidgets('a repeat of the same (apiName, code) is suppressed',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', 7000, 'first failure');
      await tester.pumpAndSettle();
      expect(find.text('Send failed: first failure'), findsOneWidget);

      // Same code, different desc: if the dedup key were the desc (or absent),
      // this second message would appear.
      SendFailureNotifier.handleSdkFailure(
        'sendMessage',
        7000,
        'second failure',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Send failed: second failure'),
        findsNothing,
        reason: 'a burst of identical failures must collapse to one toast',
      );
      expect(
        find.text('Send failed: first failure'),
        findsOneWidget,
        reason: 'the suppressed repeat must not disturb the toast on screen',
      );

      await drainSnackBars(tester);
    });

    testWidgets('a DIFFERENT code is not suppressed', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', 7000, 'first failure');
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', 7001, 'other failure');
      await tester.pumpAndSettle();

      expect(
        find.text('Send failed: other failure'),
        findsOneWidget,
        reason:
            'the window is per (apiName, code); distinct error types must each '
            'reach the user',
      );

      await drainSnackBars(tester);
    });

    testWidgets('a distinct failure replaces the toast instead of queueing',
        (tester) async {
      // The messenger queues SnackBars: without the `hideCurrentSnackBar()`
      // that precedes every show, the second failure would wait out the first
      // one's 4s duration and the user would read a stale error.
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', 7000, 'first failure');
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', 7001, 'other failure');
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Send failed: first failure'), findsNothing);
      expect(find.text('Send failed: other failure'), findsOneWidget);

      await drainSnackBars(tester);
    });

    testWidgets('resetForTests clears the window', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      SendFailureNotifier.handleSdkFailure('sendMessage', 7000, 'first failure');
      await tester.pumpAndSettle();

      SendFailureNotifier.resetForTests();
      SendFailureNotifier.handleSdkFailure(
        'sendMessage',
        7000,
        'after the reset',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Send failed: after the reset'),
        findsOneWidget,
        reason:
            'resetForTests is also the account-switch cleanup hook: a stale '
            'entry must not swallow the first failure of the next session',
      );

      await drainSnackBars(tester);
    });

    testWidgets(
        'a failure raised with no messenger mounted does not consume the '
        'dedup slot', (tester) async {
      // Detach the global key deterministically before probing the
      // "currentState == null" branch.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(SendFailureNotifier.scaffoldMessengerKey.currentState, isNull);

      // Dropped: nothing to show it on. Crucially it must NOT be recorded in
      // `_lastShown`, or the first failure after the UI comes up would be
      // silently swallowed.
      SendFailureNotifier.handleSdkFailure('sendMessage', 7002, 'early failure');

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      SendFailureNotifier.handleSdkFailure('sendMessage', 7002, 'late failure');
      await tester.pumpAndSettle();

      expect(find.text('Send failed: late failure'), findsOneWidget);

      await drainSnackBars(tester);
    });
  });
}
