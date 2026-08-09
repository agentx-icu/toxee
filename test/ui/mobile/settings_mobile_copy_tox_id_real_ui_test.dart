// Real-UI gate + root-cause characterization for "copy my Tox ID" on the PHONE
// settings surface (`SettingsPage._buildMobileAccountInfoCard`, reached through
// the drill-down index -> "Account info" section page).
//
// THE BUG THIS FILE EXISTS FOR
// ---------------------------
// The mobile card used to render the ID as:
//
//     GestureDetector(onLongPress: copyToxId, child: ... SelectableText(toxId))
//
// and that ancestor `onLongPress` NEVER RAN for a touch pointer, i.e. never on
// a phone. Evidence, read out of the pinned Flutter 3.41 SDK:
//
//   1. `SelectableText.build` always hands its `EditableText` to
//      `TextSelectionGestureDetectorBuilder.buildGestureDetector`
//      (packages/flutter/lib/src/material/selectable_text.dart:810).
//   2. `buildGestureDetector` passes `onSingleLongTapStart` as a NON-NULL
//      tear-off unconditionally
//      (packages/flutter/lib/src/widgets/text_selection.dart:3385), so
//      `TextSelectionGestureDetector.build` ALWAYS installs a
//      `LongPressGestureRecognizer` with
//      `supportedDevices: {PointerDeviceKind.touch}`
//      (packages/flutter/lib/src/widgets/text_selection.dart:3668-3686). This
//      registration is NOT forked on `TargetPlatform`, and it also happens when
//      `enableInteractiveSelection` is false — in that case only the *handler*
//      early-returns (`TextSelectionGestureDetectorBuilder.onSingleLongTapStart`,
//      text_selection.dart:2720-2723) while the recognizer stays in the arena.
//   3. `RenderEditable.hitTestSelf` returns true
//      (packages/flutter/lib/src/rendering/editable.dart:1984), so the ancestor
//      `GestureDetector` IS on the hit-test path and DOES join the same arena —
//      it simply loses it. Hit-test entries are dispatched deepest-first, so
//      SelectableText's recognizer schedules its `kLongPressTimeout` deadline
//      timer first; two equal-duration timers fire in scheduling order, the
//      inner one calls `resolve(GestureDisposition.accepted)` first, and the
//      arena rejects every other member.
//
// So: touch long-press on a `SelectableText` is owned by the `SelectableText`,
// full stop. With a MOUSE pointer the inner recognizer is not even allowed
// (`supportedDevices` is touch-only), which is why the equivalent desktop
// surface never showed the symptom — but the desktop surface does not use this
// pattern at all: `settings_page_build.dart:130` gives desktop a real copy
// `IconButton` under the SAME automation key.
//
// THE FIX BEING GATED
// -------------------
// Copy is now wired through `SelectableText.onTap` — the hook the widget
// documents for exactly this (selectable_text.dart:131) — dispatched from the
// widget's OWN winning recognizer, so it cannot be starved. Long press keeps
// its native select-word behaviour (which is all it ever actually did), the
// text stays selectable, and `tap(key: settings_copy_tox_id_button)` — what the
// MCP drivers and test/mcp/S31, S100 send — now means "copy" on mobile exactly
// as it already did on the desktop IconButton.
//
// WHAT IS RED BEFORE / GREEN AFTER
// --------------------------------
//   * `mobile Account info: tapping the real keyed Tox ID copies ...` is THE
//     gate: before the fix the keyed `SelectableText` had no `onTap`, so the
//     clipboard mock stayed empty and this test failed.
//   * The `gesture arena` group is a CHARACTERIZATION of the Flutter behaviour
//     above; it is green both before and after the app fix by design. Its job
//     is to fail loudly if a future Flutter bump ever changes the verdict (at
//     which point the comment in settings_page.dart must be revisited), and to
//     make it impossible to "fix" this by re-adding an ancestor long-press.
//
// Mobile parity: `_buildMobileAccountInfoCard` is shared Dart with no per-OS
// fork; the arena verdict is asserted across android/iOS/linux/macOS below, so
// this covers both mobile targets. The desktop Account card is untouched by the
// fix and stays covered by
// test/ui/settings/settings_account_copy_autologin_real_ui_test.dart.
//
// Harness: reuses test/ui/settings/settings_account_test_support.dart (stub
// `FfiChatService`, full l10n delegate set, `flutter/platform` clipboard
// capture, bounded `settleSettings`). `pumpAndSettle` is NOT used — the
// settings tree has perpetual-ish animated descendants.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/responsive_layout.dart';

import '../settings/settings_account_test_support.dart';

/// iPhone-class portrait phone: shortestSide 390 keeps `ResponsiveLayout` in the
/// mobile tier, so `SettingsPage` renders the drill-down index.
const Size _portraitPhone = Size(390, 844);

/// Leading icon of the "Account info" drill-down tile
/// (`settings_page.dart` `_buildMobileSettingsIndex`). Matched by icon rather
/// than by localized label so the gate survives a copy change.
const IconData _accountInfoTileIcon = Icons.badge_outlined;

void _usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = _portraitPhone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpSettings(WidgetTester tester, FfiChatService service) async {
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
}

/// Drives the REAL drill-down: tap the production "Account info" `ListTile`, so
/// the pushed section page renders the real `_buildMobileAccountInfoCard`.
Future<void> _openAccountInfoSection(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(ListTile, _accountInfoTileIcon));
  await settleSettings(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late SettingsChannelMocks mocks;

  setUp(() async {
    // `ResponsiveLayout.isMobile` ultimately reads `dart:io` `Platform.*`, which
    // `debugDefaultTargetPlatformOverride` does NOT affect. Without this seam
    // the phone branch is unreachable on the desktop test host no matter how
    // small the viewport. Process-global -> cleared in tearDown.
    ResponsiveLayout.debugIsDesktopPlatformOverride = () => false;

    tempRoot = await Directory.systemTemp.createTemp('settings_copy_tox_id_');
    mocks = SettingsChannelMocks.install(tempRoot);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(kSettingsToxId);
    await Prefs.setNickname('Phone Nick');
    await Prefs.setStatusMessage('Phone Status');
    await Prefs.addAccount(toxId: kSettingsToxId, nickname: 'Phone Nick');
  });

  tearDown(() {
    ResponsiveLayout.debugIsDesktopPlatformOverride = null;
    mocks.teardown();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('phone Account info card — copy Tox ID', () {
    testWidgets(
      'tapping the real keyed Tox ID control copies the FULL id and shows the '
      '"copied" SnackBar',
      (WidgetTester tester) async {
        final service = SettingsHarnessService();
        addTearDown(service.disposeStub);
        _usePhoneSurface(tester);

        await _pumpSettings(tester, service);
        await _openAccountInfoSection(tester);

        final idFinder = find.byKey(UiKeys.settingsCopyToxIdButton);
        expect(
          idFinder,
          findsOneWidget,
          reason: 'the pushed section page must carry the account-info card',
        );
        expect(
          mocks.clipboardLog,
          isEmpty,
          reason: 'nothing may reach the clipboard before the interaction',
        );

        await tester.ensureVisible(idFinder);
        await tester.pump();

        // REAL tap on the REAL production control. Before the fix this control
        // had no `onTap` at all (copy hung off an ancestor
        // GestureDetector.onLongPress that the gesture arena always starved),
        // so the clipboard stayed empty and this expect failed.
        await tester.tap(idFinder);
        await settleSettings(tester);

        expect(
          mocks.clipboardLog,
          contains(kSettingsToxId),
          reason:
              'activating settings_copy_tox_id_button on phone must '
              'Clipboard.setData the resolved 76-hex account Tox ID, exactly '
              'like the desktop IconButton under the same key',
        );
        expect(
          find.text('ID copied to clipboard'),
          findsOneWidget,
          reason: 'the copy handler must surface its idCopiedToClipboard '
              'SnackBar',
        );
      },
    );

    testWidgets(
      'the copy control stays a SELECTABLE text of the full id (the fix must '
      'not downgrade it to a plain Text)',
      (WidgetTester tester) async {
        final service = SettingsHarnessService();
        addTearDown(service.disposeStub);
        _usePhoneSurface(tester);

        await _pumpSettings(tester, service);
        await _openAccountInfoSection(tester);

        // Deliberate trade-off lock. The tempting "fix" for the dead ancestor
        // long-press was to swap SelectableText for Text + GestureDetector.
        // That would silently remove partial-selection / system-context-menu
        // copy on mobile AND break the type assumption in
        // settings_mobile_index_real_ui_test.dart.
        final widget = tester.widget<SelectableText>(
          find.byKey(UiKeys.settingsCopyToxIdButton),
        );
        expect(widget.data, kSettingsToxId);
        expect(
          widget.selectionEnabled,
          isTrue,
          reason:
              'interactive selection must survive the copy fix — long press '
              'still means "select a word" here, tap means "copy everything"',
        );
      },
    );
  });

  group('gesture arena: why an ancestor long-press is dead', () {
    // Standalone widgets, no app tree: these pin the Flutter behaviour the
    // production comment in settings_page.dart relies on. They do NOT change
    // colour with the app fix — they change colour if Flutter does.

    testWidgets(
      'CONTROL: an ancestor GestureDetector.onLongPress over a plain Text DOES '
      'fire (so the harness long-press itself is sound)',
      (WidgetTester tester) async {
        var fired = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: GestureDetector(
                  onLongPress: () {
                    fired++;
                  },
                  child: const Text('0123456789ABCDEF'),
                ),
              ),
            ),
          ),
        );

        await tester.longPress(find.text('0123456789ABCDEF'));
        // Bounded pump (never pumpAndSettle): the long-press aftermath on the
        // mobile branches spins up magnifier / selection-toolbar overlays.
        await settleSettings(tester);

        expect(
          fired,
          1,
          reason:
              'RenderParagraph.hitTestSelf is true (rendering/paragraph.dart'
              ':796), the ancestor detector is the only arena member, and '
              'tester.longPress uses a touch pointer — so this MUST fire. If it '
              'does not, every other assertion in this group is meaningless.',
        );
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }),
    );

    testWidgets(
      'THE BUG: the identical ancestor GestureDetector.onLongPress over a '
      'SelectableText NEVER fires for a touch pointer, on every platform',
      (WidgetTester tester) async {
        var fired = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: GestureDetector(
                  // Byte-for-byte the shape the mobile Account info card used
                  // before the fix.
                  onLongPress: () {
                    fired++;
                  },
                  child: const Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText('0123456789ABCDEF'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.longPress(find.byType(SelectableText));
        await settleSettings(tester);

        expect(
          fired,
          0,
          reason:
              "SelectableText's own touch-only LongPressGestureRecognizer "
              '(widgets/text_selection.dart:3668-3686) sits DEEPER in the '
              'hit-test path, so its equal-duration deadline timer fires first '
              'and it wins the arena — the ancestor is rejected. If this ever '
              'starts firing, revisit the comment on the Tox ID control in '
              'lib/ui/settings/settings_page.dart.',
        );
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }),
    );

    testWidgets(
      'and disabling interactive selection does NOT hand the long press back '
      '(the recognizer is registered unconditionally)',
      (WidgetTester tester) async {
        var fired = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: GestureDetector(
                  onLongPress: () {
                    fired++;
                  },
                  child: const Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(
                      '0123456789ABCDEF',
                      enableInteractiveSelection: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.longPress(find.byType(SelectableText));
        await settleSettings(tester);

        expect(
          fired,
          0,
          reason:
              'buildGestureDetector passes onSingleLongTapStart as a non-null '
              'tear-off regardless of selectionEnabled '
              '(widgets/text_selection.dart:3385); only the HANDLER '
              'early-returns (:2720-2723). The recognizer still joins and still '
              'wins the arena, so "just turn selection off" is not a fix.',
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });
}
