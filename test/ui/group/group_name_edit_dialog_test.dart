// Hermetic pin for `GroupNameEditDialog` (lib/ui/group/group_name_edit_dialog.dart).
//
// The dialog must OWN its TextEditingController and dispose it at unmount, so
// no rebuild during the dialog's dismiss transition can ever observe a disposed
// controller. The pre-fix `_changeGroupName` disposed it from
// `showDialog(...).whenComplete(addPostFrameCallback(controller.dispose))` —
// one frame after `didPop`, while the TextField stays mounted for the ~150 ms
// transition — and the soft keyboard animating out (a `MediaQuery.viewInsets`
// change the dialog builder depends on) rebuilt the field against the disposed
// controller (`_AnimatedState.didUpdateWidget` → `Listenable.merge(...)
// .addListener`). That FlutterError orphaned the field's subtree with its
// InheritedElement registrations intact, and removing the dialog's overlay
// entry then tripped `'_dependents.isEmpty'` inside the Navigator's Overlay,
// which replaced the ENTIRE route stack with an ErrorWidget (iPad
// conference_rename_leave, 2026-09-05).
//
// `_confirmAndRebuildMidDismiss` reproduces exactly that timeline. The pin
// test runs it against the real dialog and demands zero errors + a surviving
// host route; the LAST test runs the same timeline against an in-test copy of
// the old pattern and demands the stage-1 error — the control that proves the
// timeline is sensitive (if a Flutter upgrade ever stops reproducing the
// hazard, the control fails and says the pin no longer proves anything).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/ui/group/group_name_edit_dialog.dart';
import 'package:toxee/util/app_l10n.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/ui/widgets/safe_dialog_pop.dart';

const _hostKey = Key('rename_dialog_host');
const _openKey = Key('rename_dialog_open');

/// A localized app (the UIKit fork's `tL10n` singleton needs a real
/// Localizations ancestor) whose home route hosts one button that runs [open]
/// with the host's BuildContext — a real `showDialog` on the app Navigator,
/// like `_ToxeeGroupProfileContentState._changeGroupName`.
Widget _app({required void Function(BuildContext context) open}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
    localizationsDelegates: const [
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      key: _hostKey,
      body: Builder(
        builder: (context) {
          TencentCloudChatIntl().init(context);
          return TextButton(
            key: _openKey,
            onPressed: () => open(context),
            child: const Text('open'),
          );
        },
      ),
    ),
  );
}

/// Open the REAL dialog, recording every confirmed name.
void _openFixed(
  BuildContext context,
  List<String> confirmed, {
  String groupType = GroupType.Work,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => GroupNameEditDialog(
      initialName: 'old name',
      groupType: groupType,
      onConfirm: confirmed.add,
    ),
  );
}

/// The PRE-FIX pattern, kept verbatim in shape: controller created by the
/// caller, dialog builder depends on `MediaQuery.viewInsetsOf`, controller
/// disposed one frame after the route pops. Control only — never ship this.
void _openLegacy(BuildContext context) {
  final controller = TextEditingController(text: 'old name');
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: UiKeys.groupProfileEditNameDialog,
      content: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
        ),
        child: TextField(
          key: UiKeys.groupProfileEditNameField,
          controller: controller,
          autofocus: true,
        ),
      ),
      actions: [
        TextButton(
          key: UiKeys.groupProfileEditNameConfirmButton,
          onPressed: () => popDialogIfCurrent(dialogContext),
          child: const Text('ok'),
        ),
      ],
    ),
  ).whenComplete(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  });
}

Future<void> _pumpOpen(
  WidgetTester tester, {
  required void Function(BuildContext context) open,
}) async {
  await tester.pumpWidget(_app(open: open));
  await tester.tap(find.byKey(_openKey));
  await tester.pumpAndSettle();
  expect(find.byKey(UiKeys.groupProfileEditNameDialog), findsOneWidget);
}

/// Tap confirm, then — 50 ms into the dialog's 150 ms dismiss transition, i.e.
/// one frame AFTER the legacy post-frame dispose — animate the view insets
/// (the soft keyboard leaving), which re-runs the dialog builder's
/// `MediaQuery.viewInsetsOf` dependency and rebuilds the still-mounted
/// TextField. Every reported error is drained after each pump (a second
/// pending exception would otherwise collapse into the framework's "multiple
/// exceptions" placeholder) and returned in order; the transition is then
/// pumped to completion so the overlay entry removal (stage 2) also runs.
Future<List<Object>> _confirmAndRebuildMidDismiss(WidgetTester tester) async {
  final errors = <Object>[];
  void drain() {
    final e = tester.takeException();
    if (e != null) errors.add(e);
  }

  await tester.tap(find.byKey(UiKeys.groupProfileEditNameConfirmButton));
  await tester.pump(); // pop; legacy: whenComplete → post-frame dispose
  drain();
  await tester.pump(const Duration(milliseconds: 50)); // mid-transition
  drain();
  tester.view.viewInsets = const FakeViewPadding(bottom: 320);
  await tester.pump(); // MediaQuery change → dialog + TextField rebuild
  drain();
  tester.view.viewInsets = FakeViewPadding.zero;
  await tester.pump();
  drain();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    drain();
  }
  return errors;
}

void main() {
  testWidgets(
    'rebuild during the dismiss transition never sees a disposed controller '
    'and the route stack survives',
    (tester) async {
      addTearDown(tester.view.resetViewInsets);
      final confirmed = <String>[];
      await _pumpOpen(tester, open: (c) => _openFixed(c, confirmed));
      await tester.enterText(
        find.byKey(UiKeys.groupProfileEditNameField),
        '  Renamed  ',
      );
      final errors = await _confirmAndRebuildMidDismiss(tester);
      expect(errors, isEmpty, reason: 'no FlutterError may be reported');
      expect(confirmed, ['Renamed']);
      expect(find.byKey(UiKeys.groupProfileEditNameDialog), findsNothing);
      // The Navigator's Overlay was NOT replaced by an ErrorWidget: the host
      // route is still on screen and the dialog can be opened again.
      expect(find.byKey(_hostKey), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      await tester.tap(find.byKey(_openKey));
      await tester.pumpAndSettle();
      expect(find.byKey(UiKeys.groupProfileEditNameDialog), findsOneWidget);
    },
  );

  testWidgets('confirm delivers the trimmed name; empty and cancel do not', (
    tester,
  ) async {
    final confirmed = <String>[];
    await _pumpOpen(tester, open: (c) => _openFixed(c, confirmed));
    expect(find.text('old name'), findsOneWidget);
    await tester.enterText(
      find.byKey(UiKeys.groupProfileEditNameField),
      '\t New Name \n',
    );
    await tester.tap(find.byKey(UiKeys.groupProfileEditNameConfirmButton));
    await tester.pumpAndSettle();
    expect(confirmed, ['New Name']);
    expect(find.byKey(UiKeys.groupProfileEditNameDialog), findsNothing);

    await tester.tap(find.byKey(_openKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(UiKeys.groupProfileEditNameField), '   ');
    await tester.tap(find.byKey(UiKeys.groupProfileEditNameConfirmButton));
    await tester.pumpAndSettle();
    expect(confirmed, ['New Name'], reason: 'whitespace-only is rejected');
    expect(find.byKey(UiKeys.groupProfileEditNameDialog), findsNothing);

    await tester.tap(find.byKey(_openKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(UiKeys.groupProfileEditNameField),
      'Discarded',
    );
    await tester.tap(find.widgetWithText(TextButton, tL10n.cancel));
    await tester.pumpAndSettle();
    expect(confirmed, ['New Name'], reason: 'cancel confirms nothing');
    expect(find.byKey(UiKeys.groupProfileEditNameDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Same UTF-8 byte limits as creating the group (group_name_limits.dart):
  // 48 for an NGC group, 128 for a conference title. 17 CJK characters are
  // 51 bytes. Shared Dart: the rename dialog is the same on every shell.
  testWidgets('an over-long name is refused in the field, per group kind', (
    tester,
  ) async {
    final confirmed = <String>[];
    final ngcMax = '\u7fa4' * 16; // 48 bytes: fits an NGC name exactly
    final tooLong = '\u7fa4' * 17; // 51 bytes
    await _pumpOpen(tester, open: (c) => _openFixed(c, confirmed));
    await tester.enterText(find.byKey(UiKeys.groupProfileEditNameField), tooLong);
    await tester.tap(find.byKey(UiKeys.groupProfileEditNameConfirmButton));
    await tester.pumpAndSettle();
    expect(confirmed, isEmpty);
    expect(find.byKey(UiKeys.groupProfileEditNameDialog), findsOneWidget,
        reason: 'the dialog stays open to fix the name');
    expect(find.text(currentAppL10n().groupNameTooLong), findsOneWidget);

    // Editing clears the error; a name at the limit goes through.
    await tester.enterText(find.byKey(UiKeys.groupProfileEditNameField), ngcMax);
    await tester.pump();
    expect(find.text(currentAppL10n().groupNameTooLong), findsNothing);
    await tester.tap(find.byKey(UiKeys.groupProfileEditNameConfirmButton));
    await tester.pumpAndSettle();
    expect(confirmed, [ngcMax]);

    // A conference title may be longer (TOX_MAX_NAME_LENGTH = 128 bytes).
    for (final type in ['conference', GroupType.AVChatRoom]) {
      await _pumpOpen(tester,
          open: (c) => _openFixed(c, confirmed, groupType: type));
      await tester.enterText(
          find.byKey(UiKeys.groupProfileEditNameField), tooLong);
      await tester.tap(find.byKey(UiKeys.groupProfileEditNameConfirmButton));
      await tester.pumpAndSettle();
      expect(confirmed.last, tooLong, reason: type);
      expect(find.byKey(UiKeys.groupProfileEditNameDialog), findsNothing);
    }
    final confTooLong = '\u7fa4' * 43; // 129 bytes
    await _pumpOpen(tester,
        open: (c) => _openFixed(c, confirmed, groupType: 'conference'));
    await tester.enterText(
        find.byKey(UiKeys.groupProfileEditNameField), confTooLong);
    await tester.tap(find.byKey(UiKeys.groupProfileEditNameConfirmButton));
    await tester.pumpAndSettle();
    expect(confirmed.last, isNot(confTooLong));
    expect(find.text(currentAppL10n().groupNameTooLong), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // CONTROL — must stay LAST: it deliberately leaves an orphaned subtree
  // behind, which the explicit teardown below unmounts before the file ends.
  testWidgets(
    'control: the pre-fix caller-owned controller reproduces the disposed-'
    'controller rebuild on the same timeline',
    (tester) async {
      addTearDown(tester.view.resetViewInsets);
      await _pumpOpen(tester, open: _openLegacy);
      final errors = await _confirmAndRebuildMidDismiss(tester);
      expect(
        errors.map((e) => e.toString()),
        anyElement(contains('used after being disposed')),
        reason: 'the timeline must exercise the stage-1 hazard',
      );
      // Stage 2, exactly as on the iPad: the orphaned field subtree trips
      // `_dependents.isEmpty` when the dialog's overlay entry is removed, and
      // the Navigator's Overlay swaps its whole route stack for an ErrorWidget
      // — the host route is gone.
      expect(
        errors.map((e) => e.toString()),
        anyElement(contains("'_dependents.isEmpty': is not true")),
      );
      expect(find.byKey(_hostKey), findsNothing);
      expect(find.byType(ErrorWidget), findsOneWidget);
      // Unmount whatever the crash left behind, draining its errors, so the
      // binding ends the file clean.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.takeException();
    },
  );
}
