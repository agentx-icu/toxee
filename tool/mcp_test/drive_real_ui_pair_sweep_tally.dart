// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// PASS / FAIL / SKIP bookkeeping shared by the sweeps that run a list of
// tri-state case bodies (`sweep_mobile_shell`, `sweep_tablet_layout`,
// `sweep_keyed_gaps3`, `sweep_keyed_gaps4`, `sweep_keyed_gaps4_login`,
// `sweep_msg_select`).
//
// EXTRACTED from drive_real_ui_pair_mobile_shell.dart, where it was declared
// because the mobile-shell sweep was its first caller. It stopped being that
// file's business the moment three unrelated batches adopted it, and the
// expected/unexpected-skip contract below is the shared verdict rule for all of
// them, so it lives on its own.

/// PASS/FAIL/SKIP bookkeeping for one sweep. A SKIP is COUNTED (never silently
/// `continue`d) so an all-skipped chain can't read as green.
///
/// EXPECTED vs UNEXPECTED SKIPS — the distinction this class exists to make.
/// The original `finish()` was `failed != 0 -> 1; passed == 0 && skipped != 0
/// -> 75; else 0`, i.e. **any** mix of `passed > 0 && skipped > 0` was GREEN.
/// That is defensible for the two FORM-FACTOR sweeps it was written for
/// (`sweep_mobile_shell` / `sweep_tablet_layout`), where a case whose surface
/// does not exist in the running layout tier declares that as a capability
/// assertion and skipping is the honest verdict. It is NOT defensible for the
/// sweeps that later adopted it (`sweep_keyed_gaps3`, `sweep_keyed_gaps4`,
/// `sweep_msg_select`), where every case is supposed to run on every form
/// factor: there a SKIP means a surface that was supposed to mount did not, and
/// swallowing it inside a mostly-green chain is exactly how coverage evaporates
/// unnoticed. The sibling `runKeyedGapsSweep`
/// (drive_real_ui_pair_keyed_gaps.dart) — written in the same batch — already
/// tracked `unexpectedSkipped` and returned 1 for it; this class now matches
/// that contract.
///
/// So [run] takes `expectedSkip`, which DEFAULTS TO FALSE (a skip is a failure
/// unless the call site says otherwise). Only a case that gates on a
/// product-shaped precondition — the layout tier, the live composer/menu
/// surface, a documented and source-proven bridge gap — passes
/// `expectedSkip: true`, and the reason must be printed by the case body.
/// THE EXPECTED-SKIP REGISTRY. Every case in the two keyed-gaps sweeps that is
/// allowed to return null, with the LIVE PROBE that decides it. Centralised here
/// (rather than next to each sweep) so the whole "which skips are green" surface
/// is auditable in one place — the failure mode this batch exists to close is a
/// skip nobody notices, and a registry scattered across four files is exactly
/// how one gets added by accident.
///
/// `sweep_msg_select` and `sweep_keyed_gaps4_login` are deliberately absent:
/// neither has a skip path left (the multi-select driver's last SKIP was
/// retracted as false), so any skip there is unexpected.
///
/// keyed-gaps #3:
///   * `personal_card_send_c2c` — the personal-card button is attached only in
///     the fork's DESKTOP input builder; the mobile attachment overlay is
///     data-driven (File + Camera only). Probed live, not by platform name.
///   * `group_member_action_cancel_closes_sheet` — the desktop member POPUP has
///     no Cancel item; the case opens the menu and probes which surface came up.
///   * `group_profile_scroll_view_scrolls` — a ListView whose content already
///     fits has zero scroll extent. Decided against the scroll view's MEASURED
///     bottom edge (`_measuredBottomEdge`), not a guessed constant.
///   * `msgmenu_read_receipt_group_gating` — the NEGATIVE leg (no receipt entry
///     on a peer bubble) is always asserted; the POSITIVE leg needs
///     `needReadReceipt` to survive onto the rendered message, which
///     `Tim2ToxSdkPlatform.sendMessage` drops today.
const _keyedGaps3ExpectedSkipCases = <String>{
  'personal_card_send_c2c',
  'group_member_action_cancel_closes_sheet',
  'group_profile_scroll_view_scrolls',
  'msgmenu_read_receipt_group_gating',
};

/// keyed-gaps #4 — all nine gate on the running LAYOUT TIER:
///   * the three composer-shaped cases gate on `_kg4ComposerKind` (mobile vs
///     desktop input builder) — an `unknown` composer is a FAIL, not a skip;
///   * `mobile_chats_unread_badge_flips` gates on `_msPhoneShell`
///     (`home_bottom_nav` resolving), because the wide shell renders
///     `sidebar_chats_unread_badge`, which another case already drives;
///   * `mobile_chat_back_clears_active_peer` gates on `_msPhoneShell` too: a
///     master-detail shell rebinds its right pane instead of pushing the chat
///     route, so there is no route pop for the observer to react to;
///   * the three @-mention cases (both picker legs + @All) gate on
///     `_kg4ComposerKind` too — the desktop composer resolves mentions
///     through an inline panel and never pushes
///     `TencentCloudChatAtGroupMemberList`;
///   * `mobile_search_contact_back_unbinds` gates on `_msPhoneShell` like
///     the conversation-row bind case.
const _keyedGaps4ExpectedSkipCases = <String>{
  // batch 2: the @All case gates on _kg4ComposerKind like its picker
  // siblings; the search-contact bind case gates on _msPhoneShell like the
  // conversation-row bind case.
  'mobile_mention_at_all_inserts',
  'mobile_search_contact_back_unbinds',
  'attachment_toolbar_disabled_entries_gating',
  'mobile_attachment_panel_entries',
  'mobile_voice_record_button_reveals',
  'mobile_chats_unread_badge_flips',
  'mobile_chat_back_clears_active_peer',
  'mobile_mention_picker_confirm_inserts',
  'mobile_mention_picker_back_empty_selection',
};

class _MobileShellTally {
  _MobileShellTally(this.label);

  final String label;
  int passed = 0;
  int failed = 0;
  int skipped = 0;

  /// Skips from cases that did NOT declare skipping as a legitimate outcome.
  /// Counted separately and treated as failures by [finish].
  int unexpectedSkipped = 0;

  Future<void> run(
    String name,
    Future<bool?> Function() body, {
    bool expectedSkip = false,
  }) async {
    bool? result;
    try {
      result = await body();
    } on PermissionBlockedError {
      rethrow;
    } on Object catch (e, st) {
      result = false;
      print('[sweep] $label EXCEPTION in $name: $e');
      print(st);
    }
    if (result == null) {
      skipped++;
      if (expectedSkip) {
        print('[sweep] $label SKIP: $name');
      } else {
        unexpectedSkipped++;
        print('[sweep] $label SKIP(unexpected): $name');
      }
      return;
    }
    if (result) {
      passed++;
    } else {
      failed++;
    }
    print('[sweep] $label ${result ? 'PASS' : 'FAIL'}: $name');
  }

  int finish() {
    print(
      '[sweep] $label summary: passed=$passed failed=$failed skipped=$skipped '
      'unexpectedSkipped=$unexpectedSkipped',
    );
    if (failed != 0 || unexpectedSkipped != 0) return 1;
    // Every case declared its skip as a form-factor/capability fact and none
    // ran: the whole sweep is inapplicable to this shell, not broken.
    if (passed == 0 && skipped != 0) return 75;
    return 0;
  }
}
