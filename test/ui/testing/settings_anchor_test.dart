// Settings-screen automation anchors.
//
// History: this file used to be `settings_anchor_source_test.dart`. It had NO
// `test()` and NO `expect()` — a bare `main()` that read four source files with
// `readAsStringSync` and threw `StateError` on a missing substring. Worse, six
// of its twelve assertions matched on *formatted source text* including the
// exact line wrapping (`"= Key(\n    'settings_set_password_button'"`), so
// running `dart format` could turn it red without any behaviour changing.
//
// It was split in two:
//   * The `UiKeys` constants are pinned HERE against the real catalog. The
//     string inside each key is a wire contract with out-of-process tooling
//     (`tool/mcp_test` drivers, marionette MCP `tap(key: ...)`), so it is worth
//     a real assertion; the Dart field name is not.
//   * The "…and the key is attached at this call site" greps moved to
//     `tool/check_source_contracts.py` (group `ui-anchors`). They cannot become
//     behaviour tests: the widgets live in `settings_page_widgets.dart`, which
//     is a `part of` file of private classes, and rendering them needs a fully
//     booted session. A grep is all that is available there — and a grep is a
//     lint, not a test.

library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

void main() {
  group('settings UiKeys wire contract', () {
    test('account-card action keys keep their automation strings', () {
      expect(
        UiKeys.settingsCopyToxIdButton,
        const Key('settings_copy_tox_id_button'),
      );
      expect(
        UiKeys.settingsSetPasswordButton,
        const Key('settings_set_password_button'),
      );
      expect(UiKeys.settingsLogoutButton, const Key('settings_logout_button'));
    });

    test('confirmation-dialog keys keep their automation strings', () {
      expect(
        UiKeys.settingsLogoutConfirmButton,
        const Key('settings_logout_confirm_button'),
      );
      expect(
        UiKeys.settingsAccountSwitchConfirmButton,
        const Key('settings_account_switch_confirm_button'),
      );
      expect(
        UiKeys.settingsAccountSwitchCancelButton,
        const Key('settings_account_switch_cancel_button'),
      );
    });

    test('confirm and cancel anchors are never the same key', () {
      // Drivers pick "confirm" vs "cancel" purely by key. If a copy/paste ever
      // gave them the same string, a destructive scenario (logout, account
      // switch) would tap the wrong button — the exact class of bug the old
      // source-grep was structurally unable to see.
      expect(
        UiKeys.settingsAccountSwitchConfirmButton,
        isNot(UiKeys.settingsAccountSwitchCancelButton),
      );
      expect(
        UiKeys.settingsLogoutConfirmButton,
        isNot(UiKeys.settingsLogoutButton),
      );
    });
  });
}
