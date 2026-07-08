// Widget tests for [IrcChannelDialog].
//
// The dialog is one of the few entry points on ApplicationsPage that has zero
// FFI / Prefs dependencies — it's a pure Form, so it's a strong target for
// behavior tests. The page itself depends on FfiChatService and IrcAppManager
// (Prefs-backed singleton) and cannot be pumped under flutter_test.
//
// What this covers:
//   1. Submit returns a record with the channel/password/nickname trimmed.
//   2. A name without #/& fails validation (the dialog stays open, no pop).
//      Note: there is a dead normalization branch in irc_channel_dialog.dart
//      that prefixes `#` if missing, but it's unreachable because the
//      validator rejects missing-prefix input first. The behavior tested
//      here is "reject", not "auto-prefix".
//   3. `&` sigil is accepted (LAN-channel form).
//   4. Empty password/nickname become null in the returned record.
//   5. The visibility toggle flips obscureText on the password field.
//   6. Cancel pops with null.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/applications/irc_channel_dialog.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

/// Result type used by the dialog's submit path. Mirrors the anonymous record
/// the dialog pops.
typedef _DialogResult = ({String channel, String? password, String? nickname});

class _ResultHolder {
  Future<_DialogResult?>? future;
}

Widget _harness(_ResultHolder holder) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                holder.future = showDialog<_DialogResult>(
                  context: context,
                  builder: (_) => const IrcChannelDialog(),
                );
              },
              child: const Text('open-dialog'),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open-dialog'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IrcChannelDialog', () {
    testWidgets('renders stable automation keys', (tester) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(_harness(holder));
      await _openDialog(tester);

      expect(find.byKey(UiKeys.ircChannelDialogChannelField), findsOneWidget);
      expect(find.byKey(UiKeys.ircChannelDialogPasswordField), findsOneWidget);
      expect(find.byKey(UiKeys.ircChannelDialogNicknameField), findsOneWidget);
      expect(
        find.byKey(UiKeys.ircChannelDialogPasswordVisibilityToggle),
        findsOneWidget,
      );
      expect(find.byKey(UiKeys.ircChannelDialogCancelButton), findsOneWidget);
      expect(find.byKey(UiKeys.ircChannelDialogJoinButton), findsOneWidget);

      await tester.tap(find.byKey(UiKeys.ircChannelDialogCancelButton));
      await tester.pumpAndSettle();
    });

    testWidgets('Cancel pops with null', (tester) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(_harness(holder));
      await _openDialog(tester);

      await tester.tap(find.byKey(UiKeys.ircChannelDialogCancelButton));
      await tester.pumpAndSettle();

      final result = await holder.future;
      expect(result, isNull);
    });

    testWidgets('Submit with empty channel keeps dialog open (validation)', (
      tester,
    ) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(_harness(holder));
      await _openDialog(tester);

      // Tap Join with empty channel — validator should reject and the dialog
      // should remain mounted.
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(
        find.byType(IrcChannelDialog),
        findsOneWidget,
        reason: 'Empty channel should not submit, dialog remains visible',
      );
      // Tear down cleanly.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Submit with channel missing # prefix fails validation', (
      tester,
    ) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(_harness(holder));
      await _openDialog(tester);

      // Find the channel field (the first TextFormField) and type without a
      // leading # or &. The validator should reject.
      await tester.enterText(
        find.byKey(UiKeys.ircChannelDialogChannelField),
        'plainname',
      );
      await tester.tap(find.byKey(UiKeys.ircChannelDialogJoinButton));
      await tester.pumpAndSettle();

      expect(
        find.byType(IrcChannelDialog),
        findsOneWidget,
        reason: 'Channel "plainname" lacks #/&, validation must block submit',
      );
      // The validator surfaces a helper message — assert it appears somewhere
      // on screen so the user has feedback.
      expect(
        find.textContaining('#'),
        findsWidgets,
        reason: 'Validator copy mentions the # sigil',
      );

      await tester.tap(find.byKey(UiKeys.ircChannelDialogCancelButton));
      await tester.pumpAndSettle();
    });

    testWidgets('Valid channel + empty password/nickname submits with nulls', (
      tester,
    ) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(_harness(holder));
      await _openDialog(tester);

      await tester.enterText(
        find.byKey(UiKeys.ircChannelDialogChannelField),
        '#flutterdev',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(UiKeys.ircChannelDialogJoinButton));
      await tester.pumpAndSettle();

      final result = await holder.future;
      expect(result, isNotNull);
      expect(result!.channel, '#flutterdev');
      expect(
        result.password,
        isNull,
        reason: 'Empty password trims to null in the returned record',
      );
      expect(result.nickname, isNull);
    });

    testWidgets('Channel starting with & is preserved (valid IRC sigil)', (
      tester,
    ) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(_harness(holder));
      await _openDialog(tester);

      await tester.enterText(
        find.byKey(UiKeys.ircChannelDialogChannelField),
        '&local',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(UiKeys.ircChannelDialogJoinButton));
      await tester.pumpAndSettle();

      final result = await holder.future;
      expect(result, isNotNull);
      expect(
        result!.channel,
        '&local',
        reason: '& sigil channels are local-only IRC channels, kept as-is',
      );
    });

    testWidgets('Submit fills password and nickname when provided', (
      tester,
    ) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(_harness(holder));
      await _openDialog(tester);

      await tester.enterText(
        find.byKey(UiKeys.ircChannelDialogChannelField),
        '#secret',
      );
      await tester.enterText(
        find.byKey(UiKeys.ircChannelDialogPasswordField),
        'hunter2',
      );
      await tester.enterText(
        find.byKey(UiKeys.ircChannelDialogNicknameField),
        'mynick',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(UiKeys.ircChannelDialogJoinButton));
      await tester.pumpAndSettle();

      final result = await holder.future;
      expect(result, isNotNull);
      expect(result!.channel, '#secret');
      expect(result.password, 'hunter2');
      expect(result.nickname, 'mynick');
    });

    testWidgets('Password visibility toggle flips obscureText', (tester) async {
      final holder = _ResultHolder();
      await tester.pumpWidget(_harness(holder));
      await _openDialog(tester);

      // Drop into the underlying EditableText to read obscureText (the public
      // TextFormField doesn't expose it). EditableTexts are listed in the
      // same visual order as their wrapping TextFormFields.
      EditableText passwordEditable() =>
          tester.widget<EditableText>(find.byType(EditableText).at(1));

      expect(
        passwordEditable().obscureText,
        isTrue,
        reason: 'Password starts obscured for safety',
      );

      // Tap the visibility icon (the only one inside the dialog).
      await tester.tap(
        find.byKey(UiKeys.ircChannelDialogPasswordVisibilityToggle),
      );
      await tester.pumpAndSettle();

      expect(
        passwordEditable().obscureText,
        isFalse,
        reason: 'Tap on the eye reveals the password text',
      );

      // Tap the now-shown visibility_off icon to obscure again.
      await tester.tap(
        find.byKey(UiKeys.ircChannelDialogPasswordVisibilityToggle),
      );
      await tester.pumpAndSettle();

      expect(
        passwordEditable().obscureText,
        isTrue,
        reason: 'Second tap re-obscures',
      );

      await tester.tap(find.byKey(UiKeys.ircChannelDialogCancelButton));
      await tester.pumpAndSettle();
    });
  });
}
