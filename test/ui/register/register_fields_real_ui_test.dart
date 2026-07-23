// Real-UI L1 gate for the RegisterPage NICKNAME + STATUS fields.
//
// Scope (all HERMETIC — no native lib): drives REAL typing into the mounted
// `RegisterPage` fields and asserts the REAL observable side-effects:
//   * the character counter updates as the user types,
//   * an over-length value (CJK, > the field's width budget) surfaces the
//     reactive `errorText` AND disables the register button via its
//     `onPressed` guard,
//   * a within-limit value re-enables the button.
//
// These exercise the production `_RegisterPageState.build` widget tree
// directly (the same `TextFormField` decorations + the FilledButton
// `onPressed` guard that ships). No `FfiChatService` is constructed, so the
// tim2tox FFI dylib is never opened — every test here runs everywhere.
//
// `calculateTextLength` (lib/util/account_service.dart) weights CJK as 1.0 and
// ASCII as 0.5; the nickname guard trips at > 12 width units, the status guard
// at > 24. 13 CJK chars = 13.0 > 12 (and 25 CJK = 25.0 > 24) — the only way to
// exceed the guards while staying under the fields' maxLength (24 / 48 chars).
//
// Mobile parity: register_page.dart is shared Dart with no platform branches,
// so these gates cover iOS / Android / desktop identically.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/register_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: child,
  );
}

// A RegisterPage whose every session hook is inert. `registerAccount` records
// invocations and throws so that, even if a tap slips past validation, no
// native/boot/navigation work is attempted (keeps these tests hermetic).
RegisterPage _page(List<String> registerCalls) {
  return RegisterPage(
    registerAccount:
        ({required nickname, required statusMessage, required password}) async {
          registerCalls.add(nickname);
          throw Exception('stub: registration not exercised in fields test');
        },
    bootSession: (_) async {},
    teardownSession:
        ({
          required FfiChatService service,
          bool reEncryptProfile = true,
        }) async {},
    showFirstRunBackupWizard:
        ({required context, required toxId, required nickname}) async {},
    navigateToHome: (context, service) async {},
  );
}

Finder _fieldErrorText(String message) => find.descendant(
  of: find.byType(TextFormField),
  matching: find.text(message),
);

FilledButton _registerButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(UiKeys.registerPageRegisterButton));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // HapticFeedback / SystemChrome flow through the JSON platform channel; the
  // page itself doesn't fire haptics on these paths, but mounting MaterialApp
  // can issue SystemChrome calls — swallow them so nothing throws.
  late TestDefaultBinaryMessenger messenger;
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  late String nicknameTooLong;
  late String statusMessageTooLong;

  setUpAll(() {
    final l10n = lookupAppLocalizations(const Locale('en'));
    nicknameTooLong = l10n.nicknameTooLong;
    statusMessageTooLong = l10n.statusMessageTooLong;
  });

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      platformChannel,
      (MethodCall call) async => null,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
  });

  testWidgets(
    'mobile autofill and Next/Done flow covers the registration form',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(_page(<String>[])));
      await tester.pumpAndSettle();

      expect(find.byType(AutofillGroup), findsOneWidget);
      EditableText editableFor(Key key) => tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(EditableText),
        ),
      );
      final nickname = editableFor(UiKeys.registerPageNicknameField);
      final status = editableFor(const Key('register_status_field'));
      final password = editableFor(UiKeys.registerPagePasswordField);
      final confirm = editableFor(UiKeys.registerPageConfirmPasswordField);

      expect(nickname.textInputAction, TextInputAction.next);
      expect(status.textInputAction, TextInputAction.next);
      expect(password.textInputAction, TextInputAction.next);
      expect(confirm.textInputAction, TextInputAction.done);
      expect(password.autofillHints, contains(AutofillHints.newPassword));
      expect(confirm.autofillHints, contains(AutofillHints.newPassword));
    },
  );

  testWidgets(
    'nickname: typing updates the character counter (real text input)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(_page(<String>[])));
      await tester.pumpAndSettle();

      // Empty → counter shows 0/24.
      expect(
        find.text('0/24'),
        findsWidgets,
        reason: 'The nickname field exposes a 0/24 counter before any input.',
      );

      await tester.enterText(
        find.byKey(UiKeys.registerPageNicknameField),
        'Alice',
      );
      await tester.pump();

      // "Alice" = 5 chars → counter advances to 5/24. This proves real keystrokes
      // flowed into the controller and the maxLength counter re-rendered.
      expect(
        find.text('5/24'),
        findsOneWidget,
        reason: 'Typing 5 chars must move the nickname counter to 5/24.',
      );
    },
  );

  testWidgets(
    'nickname: over-length CJK surfaces the field error AND disables the button',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final calls = <String>[];
      await tester.pumpWidget(_wrap(_page(calls)));
      await tester.pumpAndSettle();

      // Button starts disabled (empty nickname is not over-length, but the page
      // only disables on over-length; empty is caught by the validator on submit).
      // 13 CJK chars = 13.0 width > 12 → trips the reactive errorText + guard.
      await tester.enterText(
        find.byKey(UiKeys.registerPageNicknameField),
        '中' * 13,
      );
      await tester.pump();

      expect(
        _fieldErrorText(nicknameTooLong),
        findsOneWidget,
        reason: 'An over-length nickname must render its reactive errorText.',
      );

      expect(
        _registerButton(tester).onPressed,
        isNull,
        reason: 'An over-length nickname must disable the register button.',
      );

      // Tapping the disabled button is a no-op — registration must not run.
      await tester.tap(
        find.byKey(UiKeys.registerPageRegisterButton),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(
        calls,
        isEmpty,
        reason: 'A disabled register button must never reach registerAccount.',
      );
    },
  );

  testWidgets('nickname: within-limit value enables the register button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(_page(<String>[])));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(UiKeys.registerPageNicknameField),
      'Alice',
    );
    await tester.pump();

    expect(
      _fieldErrorText(nicknameTooLong),
      findsNothing,
      reason: 'A within-limit nickname must clear the over-length error.',
    );
    expect(
      _registerButton(tester).onPressed,
      isNotNull,
      reason: 'A within-limit nickname must leave the register button enabled.',
    );
  });

  testWidgets(
    'status: typing updates the character counter (real text input)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap(_page(<String>[])));
      await tester.pumpAndSettle();

      expect(
        find.text('0/48'),
        findsWidgets,
        reason: 'The status field exposes a 0/48 counter before any input.',
      );

      await tester.enterText(
        find.byKey(const Key('register_status_field')),
        'Hi',
      );
      await tester.pump();

      expect(
        find.text('2/48'),
        findsOneWidget,
        reason: 'Typing 2 chars must move the status counter to 2/48.',
      );
    },
  );

  testWidgets(
    'status: over-length CJK surfaces the field error AND disables the button',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final calls = <String>[];
      await tester.pumpWidget(_wrap(_page(calls)));
      await tester.pumpAndSettle();

      // A valid nickname keeps the nickname guard satisfied so we isolate the
      // status guard as the only reason the button could disable.
      await tester.enterText(
        find.byKey(UiKeys.registerPageNicknameField),
        'Alice',
      );
      // 25 CJK = 25.0 width > 24 → trips the status reactive errorText + guard.
      await tester.enterText(
        find.byKey(const Key('register_status_field')),
        '中' * 25,
      );
      await tester.pump();

      expect(
        _fieldErrorText(statusMessageTooLong),
        findsOneWidget,
        reason:
            'An over-length status message must render its reactive errorText.',
      );
      expect(
        _registerButton(tester).onPressed,
        isNull,
        reason:
            'An over-length status message must disable the register button.',
      );

      await tester.tap(
        find.byKey(UiKeys.registerPageRegisterButton),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(
        calls,
        isEmpty,
        reason: 'A disabled register button must never reach registerAccount.',
      );
    },
  );

  testWidgets('status: clearing the over-length value re-enables the button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(_page(<String>[])));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(UiKeys.registerPageNicknameField),
      'Alice',
    );
    await tester.enterText(
      find.byKey(const Key('register_status_field')),
      '中' * 25,
    );
    await tester.pump();
    expect(
      _registerButton(tester).onPressed,
      isNull,
      reason: 'Sanity: button is disabled while the status is over-length.',
    );

    // Shorten the status back under the budget → button re-enables.
    await tester.enterText(
      find.byKey(const Key('register_status_field')),
      'Hello',
    );
    await tester.pump();

    expect(
      _fieldErrorText(statusMessageTooLong),
      findsNothing,
      reason: 'A within-limit status must clear the over-length error.',
    );
    expect(
      _registerButton(tester).onPressed,
      isNotNull,
      reason:
          'A within-limit status (with valid nickname) must re-enable the button.',
    );
  });
}
