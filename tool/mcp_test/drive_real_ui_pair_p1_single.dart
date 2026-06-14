// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch II of the P1/P2/P3 real-UI campaign — "P1 single-instance quintet"
// (5 cases, single instance: drive only A, B launched-but-idle). WRITTEN,
// UNRUN (write phase). See tool/mcp_test/REAL_UI_P1P2P3_CAMPAIGN.md (Batch II)
// and doc/research/REAL_APP_UI_TEST_INVENTORY.md §P1 rows 8–12.
//
// Cases (sweep order, state-machine reasoning):
//   1. zh_locale_page_walk        (P1#12) — switch the REAL Settings language
//      expander to 简体中文, assert zh labels on EVERY home surface (settings
//      header 外观, sidebar 聊天/联系人/设置, contacts 新联系人, self-profile
//      用户ID/保存图片), revert to English, assert an EN label. A `finally`
//      guard re-reverts the locale even on a mid-case FAIL (batch-1 lesson:
//      locale poison breaks every later EN-text assertion).
//   2. conference_rename_leave    (P1#11) — create a conference (AVChatRoom)
//      via the REAL AddGroupDialog conference segment (batch-7 helper
//      `_confCreateDialogSurface`), rename it via the keyed group-profile
//      edit-name dialog (S138 pattern; the toxee override renders the edit
//      button UNCONDITIONALLY for all group types —
//      group_builder_override.dart `defaultBuilder`), assert the renamed
//      conversation-row showName AND the open-chat header title, then leave
//      via `group_profile_leave_button` + Confirm-by-label (batch-7 case 75
//      precedent — AVChatRoom has no roles, so no owner/dissolve-specific
//      asserts) → the conversation row leaves the sidebar.
//   3. settings_switch_account_entry (P1#10) — register account #2 ONCE via
//      the REAL RegisterPage (the campaign's only extra account, nick
//      'RuiP1Sw'), land on #2's Home (toxId flips AWAY from primary), then
//      drive the REAL Settings account-management list: the primary row's
//      swap IconButton (`settings_account_switch_button:<toxId>`, an
//      automation key added this batch — the icon-only button had no key and
//      no text to match) → the keyed confirm dialog
//      (`settings_account_switch_confirm_button`) → `AccountSwitcher
//      .switchAccount` tears down #2, boots the primary, and lands DIRECTLY
//      on the primary's HomePage (verify-first finding: the production
//      switch entry does NOT route through the LoginPage cards —
//      account_switcher.dart pushes HomePage straight away; the case asserts
//      the direct in-place flip, sessionReady + currentAccountToxId).
//   4. account_card_management_menu (P1#8) — on the LoginPage, REAL
//      long-press (`Inst.longPressKey`, Batch-I primitive, 800 ms >
//      kLongPressTimeout) on a saved-account card → the account-management
//      bottom sheet mounts with its production-keyed items
//      (`login_account_management_export_option` / `_delete_option` —
//      verify-first: the surface already exists FULLY KEYED in
//      login_page.dart, onLongPress + onSecondaryTapUp both wired) → dismiss
//      NON-destructively (ESC; barrier-tap fallback) → card still present,
//      still logged out.
//   5. account_delete_full_flow   (P1#9, S45 real-UI half) — quick-login
//      INTO account #2 via its real card, Settings → the Delete Account
//      button (`settings_delete_account_button`, automation key added this
//      batch) → the confirm dialog (random confirm-word branch on a
//      password-less account: settings_page.dart `_kDeleteConfirmWords`) →
//      read the word from the live prompt Text via flutter_skill
//      getTextContent (EN template prefix-strip + candidate sanity check),
//      type it via the keyed input (`settings_delete_account_confirm_input`),
//      single-fire the keyed destructive confirm
//      (`settings_delete_account_confirm_button`) →
//      `AccountService.deleteAccountCompletely` lands back on the LoginPage
//      with #2's card GONE (`Prefs.removeAccount`) → quick-login the primary.
//      PERMANENTLY deletes #2 — runs LAST; the sweep end-guard then verifies
//      the documented end state (primary logged in, locale EN).
//
// Production automation keys added by this batch (shared Dart → mobile
// covered; documented in the campaign anchor + commit message):
//   * settings_account_switch_button:<toxId> — the per-account swap_horiz
//     IconButton in the Settings account list (`_AccountCardItem`). Icon-only
//     (no text) and previously keyless → text-matching impossible.
//   * settings_delete_account_button — the Delete Account opener
//     (settings_page_build.dart). Its "Delete Account" label COLLIDES with
//     the confirm dialog's title AND confirm-button label once the dialog is
//     up, so text-driving the flow is ambiguous.
//   * settings_delete_account_confirm_input — the dialog's confirm TextField
//     (both the password and confirm-word branches, mirroring the login
//     page's `login_delete_account_confirm_input` precedent).
//   * settings_delete_account_confirm_button — the destructive Delete
//     TextButton ("Delete" label is short/generic; keyed like the login
//     page's `login_delete_account_confirm_button`).

const _p1SecondNick = 'RuiP1Sw';

/// Mirror of settings_page.dart `_kDeleteConfirmWords` (private const in
/// production). Used ONLY as a sanity gate on the word extracted from the live
/// prompt — a mis-extraction types a wrong word, which production rejects
/// (snackbar + dialog stays), so the failure mode is a loud FAIL, never a
/// stray deletion.
const _p1DeleteConfirmWordCandidates = <String>{
  'delete', 'confirm', 'remove', 'account', 'permanent', 'cancel',
  'proceed', 'warning', 'caution', 'irreversible', 'data', 'erase',
  'type', 'word', 'verify', 'submit', 'final', 'accept', 'continue',
};

/// EN template of `deleteAccountConfirmWordPrompt` (lib/l10n/app_en.arb):
/// "Type the following word in the box below to confirm: {word}". The driver
/// runs the sweep in EN (case 1 reverts zh before any later case), so the
/// prompt Text's data is this prefix + the random word.
const _p1DeleteWordPromptPrefixEn =
    'Type the following word in the box below to confirm: ';

/// Read the delete-account confirm word from the LIVE dialog via flutter_skill
/// `getTextContent` (every `Text` widget's exact data). The word is embedded in
/// the prompt Text (the standalone copy is a SelectableText, which
/// getTextContent does NOT surface — it only walks Text/RichText). Returns ''
/// when the prompt is absent or the extracted word fails the candidate check
/// (template drift → loud FAIL, not a guessed word).
Future<String> _p1DeleteConfirmWordFromUi(Inst inst) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    final r = await inst.skill('getTextContent', const {});
    final texts = r['texts'];
    if (texts is List) {
      for (final t in texts) {
        if (t is! Map) continue;
        final s = t['text']?.toString() ?? '';
        if (!s.startsWith(_p1DeleteWordPromptPrefixEn)) continue;
        final word = s.substring(_p1DeleteWordPromptPrefixEn.length).trim();
        if (_p1DeleteConfirmWordCandidates.contains(word)) return word;
        print(
          '[pair] p1 delete-word: extracted "$word" is not a known candidate '
          '(production word list / l10n template drift?) — failing loudly',
        );
        return '';
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  print('[pair] p1 delete-word: confirm-word prompt Text never appeared');
  return '';
}

/// No-throw poll until the session is ready AND the current account is
/// [toxId]. Needed where `_waitBoolState(sessionReady)` alone would
/// short-circuit TRUE on the OLD account during an in-place account switch
/// (teardown → boot flips sessionReady false → true while the toxId changes).
/// Open a dialog via a keyed control with DOUBLE-FIRE discipline (codex P2):
/// single-fire `tapKeyCenter` first; the raw `tapKey` (synthetic tap + direct
/// callback invoke — fires TWICE on an onstage control) fallback is allowed
/// ONLY when the control's bounds do NOT resolve (offstage / below-fold, where
/// the direct invoke fires exactly once). An onstage control whose center-tap
/// failed must NOT be blind re-fired — that stacks two dialogs.
Future<bool> _p1OpenDialogViaKey(
  Inst inst,
  String controlKey,
  String dialogMarkerKey,
) async {
  if (await inst.tapKeyCenter(controlKey, timeoutSecs: 6)) {
    if (await inst.waitKey(dialogMarkerKey, timeoutSecs: 8)) return true;
  }
  if (await inst.keyCenter(controlKey) == null) {
    await inst.tapKey(controlKey);
    return inst.waitKey(dialogMarkerKey, timeoutSecs: 8);
  }
  // Onstage but the dialog isn't up yet — give the first (single) fire a last
  // grace window instead of re-firing.
  return inst.waitKey(dialogMarkerKey, timeoutSecs: 2);
}

Future<bool> _p1WaitAccountReady(
  Inst inst,
  String toxId, {
  int timeoutSecs = 75,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    await inst.foreground();
    final st = await inst.dumpState();
    if (st['sessionReady'] == true &&
        (st['currentAccountToxId']?.toString() ?? '') == toxId) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
  return false;
}

/// Select a home-shell tab by its sidebar key and wait for the authoritative
/// `homeShellTab` dump signal (key-based → locale-independent; usable while
/// the UI is in Chinese). Single-fire taps (a tab re-select is harmless, but
/// tapKeyCenter keeps the discipline uniform).
Future<bool> _p1SelectHomeTab(Inst inst, String tabKey, String tabName) async {
  for (var round = 0; round < 5; round++) {
    await inst.foreground();
    final st = await inst.dumpState();
    if (st['homeShellTab']?.toString() == tabName) return true;
    if (!await inst.tapKeyCenter(tabKey, timeoutSecs: 4)) {
      await inst.tryTapKey(tabKey);
    }
    for (var i = 0; i < 5; i++) {
      if ((await inst.dumpState())['homeShellTab']?.toString() == tabName) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }
  return false;
}

/// Revert the app locale to English using ONLY locale-independent anchors
/// (sidebar settings-tab key, the keyed language-selector scroll anchor, the
/// keyed `settings_language_option_en` option). Safe to call from a `finally`
/// while the UI is stuck in ANY locale. No-throw; returns whether the dump
/// reports languageCode == 'en' afterwards.
Future<bool> _p1RevertLocaleToEnglish(Inst inst) async {
  try {
    if ((await inst.dumpState())['languageCode']?.toString() == 'en') {
      return true;
    }
    if ((await inst.dumpState())['sessionReady'] != true) {
      // The Settings language selector only exists inside a session; a
      // logged-out revert is impossible here. (The locale can only have been
      // mutated by the zh-walk case, which runs logged-in — this guard exists
      // for defense in depth.)
      print('[pair] p1 locale-revert: no session — cannot reach Settings');
      return false;
    }
    await _openSettings(inst);
    for (var attempt = 0; attempt < 4; attempt++) {
      // Anchor the selector in the upper band so the option rows that expand
      // BELOW it are inside the visible viewport (batch-1 lesson: a below-fold
      // option is mounted-but-untappable).
      await _scrollKeyIntoBand(
        inst,
        'settings_language_selector',
        topBand: 110,
        bottomBand: 300,
      );
      // The expander is a TOGGLE — only tap it when the option list is NOT
      // already showing (tapKeyAt is a single real tap, so no double-fire, but
      // a stale-expanded state from a failed prior attempt must not be
      // re-collapsed).
      if (await inst.keyCenter('settings_language_option_en') == null) {
        if (!await inst.tapKeyAt('settings_language_selector')) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (await inst.tapKeyAt('settings_language_option_en') &&
          await _waitStringState(inst, 'languageCode', 'en')) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return (await inst.dumpState())['languageCode']?.toString() == 'en';
  } on DriveError catch (e) {
    print('[pair] p1 locale-revert: best-effort failed: ${e.message}');
    return false;
  } catch (e) {
    print('[pair] p1 locale-revert: unexpected error (ignored): $e');
    return false;
  }
}

// ===========================================================================
// case 1 — zh_locale_page_walk (P1#12, S38 deepened)
// ===========================================================================
/// Switch the REAL Settings language expander to 简体中文, then walk EVERY home
/// surface asserting a zh label on each:
///   settings  — 外观 (app l10n `appearance` section header; batch-1 anchor)
///   sidebar   — 聊天 / 联系人 / 设置 (UIKit delegate `chats`/`contacts`/
///               `settings`, tencent_cloud_chat_intl l10n_zh.arb)
///   contacts  — 新联系人 (UIKit `newContacts` tab item,
///               tencent_cloud_chat_contact.dart builds it from tL10n)
///   profile   — 用户ID (UIKit `userID`, the Tox-ID section label in
///               profile_page.dart) OR 保存图片 (app l10n `saveImage`, the QR
///               save button) — overlay opened via the real sidebar avatar,
///               closed via the keyed `profile_close_button`.
/// Then revert to English via locale-independent KEYS and assert 'Appearance'
/// is back. The `finally` guard re-reverts on ANY mid-case exit so a FAIL here
/// cannot poison later EN-text assertions (batch-1 lesson).
Future<bool> _p1ZhLocalePageWalk(Inst inst) async {
  try {
    await _openSettings(inst);
    // --- Switch to 简体中文 (batch-1 settings_locale_zh_roundtrip recipe:
    // single-fire the label-only expander row, then the keyed option). ---
    await _scrollKeyIntoBand(
      inst,
      'settings_language_selector',
      topBand: 110,
      bottomBand: 300,
    );
    var expanded = false;
    for (var attempt = 0; attempt < 4 && !expanded; attempt++) {
      if (!await inst.tapKeyAt('settings_language_selector')) {
        await _scrollKeyIntoBand(
          inst,
          'settings_language_selector',
          topBand: 110,
          bottomBand: 300,
        );
        if (!await inst.tapKeyAt('settings_language_selector')) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expanded = await inst.waitText('简体中文', timeoutSecs: 2);
    }
    if (!expanded) {
      print('[pair] zh_locale_page_walk: could not expand language selector');
      return false;
    }
    var zhTapped = await inst.tapKeyAt('settings_language_option_zh_Hans');
    if (!zhTapped) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      zhTapped = await inst.tapKeyAt('settings_language_option_zh_Hans');
    }
    if (!zhTapped) {
      print('[pair] zh_locale_page_walk: 简体中文 option not tappable');
      return false;
    }
    final zhPersisted = await _waitStringState(inst, 'languageCode', 'zh_Hans');
    if (!zhPersisted) {
      print('[pair] zh_locale_page_walk: languageCode never became zh_Hans');
      return false;
    }

    // --- (a) settings surface: the Appearance section header reads 外观. ---
    await inst.foreground();
    final settingsZh =
        await inst.waitText('外观', timeoutSecs: 6) ||
        await _scrollToText(inst, '外观');

    // --- (b) sidebar labels (persistent left rail, always onstage on the
    // desktop layout): 聊天 / 联系人 / 设置. ---
    final sidebarChatsZh = await inst.waitText('聊天', timeoutSecs: 6);
    final sidebarContactsZh = await inst.waitText('联系人', timeoutSecs: 3);
    final sidebarSettingsZh = await inst.waitText('设置', timeoutSecs: 3);

    // --- (c) contacts page: navigate via the KEYED sidebar tab (locale-
    // independent). HARD: the contacts tab actually becomes active in the zh
    // session (proves the keyed sidebar nav + the contacts route render under
    // zh). The 新联系人 SUBTAB label is asserted SOFT (logged, not gated):
    // live-confirmed PRODUCT i18n GAP — toxee pushes zh to the UIKit intl
    // singleton (setLocale is synchronous, `_currentLocale` takes precedence)
    // AND keys the contact tab on `languageCode`, yet the UIKit contact-tab
    // TTabItem subtab labels (New Contacts / Blocked Users / Contacts / Groups)
    // still render the PRE-switch locale until app restart — a UIKit contact-tab
    // rebuild/caching subtlety that needs live instrumentation to pin down (the
    // page TITLE + sidebar + settings + profile all localize correctly). Recorded
    // as an owed product i18n investigation in REAL_UI_P1P2P3_CAMPAIGN.md; this
    // case must not HARD-fail on a separate pre-existing UIKit bug.
    final contactsOpened =
        await _p1SelectHomeTab(inst, 'sidebar_contacts_tab', 'contacts');
    final contactsSubtabZh =
        contactsOpened && await inst.waitText('新联系人', timeoutSecs: 4);
    final contactsZh = contactsOpened; // HARD = navigated; subtab = SOFT below

    // --- (d) self-profile overlay: open via the real sidebar avatar (the
    // landmark `profile_edit_toggle` is a KEY → locale-independent), assert a
    // zh marker, close via the keyed close button. ---
    final profileOpened = await _openSelfProfile(inst);
    final profileZh =
        profileOpened &&
        (await inst.waitText('用户ID', timeoutSecs: 6) ||
            await inst.waitText('保存图片', timeoutSecs: 3));
    final profileClosed = await _closeSelfProfile(inst);
    await inst.shot('/tmp/ui_p1_zh_walk_${inst.name}.png');

    // --- (e) revert to English via keys, then assert the EN label is back. ---
    final reverted = await _p1RevertLocaleToEnglish(inst);
    await _openSettings(inst);
    final enBack =
        await inst.waitText('Appearance', timeoutSecs: 6) ||
        await _scrollToText(inst, 'Appearance');
    print(
      '[pair] zh_locale_page_walk: zhPersisted=$zhPersisted '
      'settingsZh=$settingsZh sidebar(chats=$sidebarChatsZh '
      'contacts=$sidebarContactsZh settings=$sidebarSettingsZh) '
      'contactsOpened=$contactsZh contactsSubtabZh=$contactsSubtabZh'
      '(SOFT — UIKit subtab i18n gap) profile(open=$profileOpened zh=$profileZh '
      'closed=$profileClosed) reverted=$reverted enBack=$enBack',
    );
    return zhPersisted &&
        settingsZh &&
        sidebarChatsZh &&
        sidebarContactsZh &&
        sidebarSettingsZh &&
        contactsZh &&
        profileOpened &&
        profileZh &&
        profileClosed &&
        reverted &&
        enBack;
  } finally {
    // LOCALE-POISON GUARD: a mid-case FAIL/throw above may have left the app
    // in zh. Every later case (and the other sweeps on this launch) asserts
    // EN text, so re-revert here unconditionally (cheap no-op when already
    // EN). Best-effort + no-throw — `_p1RevertLocaleToEnglish` swallows its
    // own errors, and the close-overlay below is fenced too.
    try {
      await _closeSelfProfile(inst); // a stranded overlay blocks Settings
    } catch (_) {}
    final guardOk = await _p1RevertLocaleToEnglish(inst);
    if (!guardOk) {
      print('[pair] zh_locale_page_walk: FINALLY-GUARD could not verify EN '
          'locale — later EN-text cases may be poisoned');
    }
  }
}

// ===========================================================================
// case 2 — conference_rename_leave (P1#11, mirrors batch-7 cases 76+75 for
// the AVChatRoom/legacy-conference type)
// ===========================================================================
/// Create a conference via the REAL AddGroupDialog (conference segment), rename
/// it through the keyed group-profile edit-name dialog, assert the renamed
/// conversation-row showName AND the open-chat header title, then leave via the
/// real profile leave button + Confirm-by-label → the row leaves the sidebar.
///
/// AVChatRoom specifics (verified by reading the code, not assumed):
///   * The toxee group-profile override renders the edit-name button
///     UNCONDITIONALLY (group_builder_override.dart `defaultBuilder` — no
///     owner/type gate), and `setGroupInfo` routes through Tim2ToxSdkPlatform
///     to a Prefs-backed, group-type-AGNOSTIC name store → rename works for
///     conferences exactly like private groups.
///   * Conferences have NO roles, so this case asserts NOTHING about
///     quit-vs-dissolve: `_handleQuitGroup` takes either branch depending on
///     the reported role, and BOTH end in `Prefs.addQuitGroup` +
///     `deleteConversation` (row gone) on success — which is the only outcome
///     asserted. The confirm dialog's Confirm label is identical either way.
Future<bool> _p1ConferenceRenameLeave(Inst inst) async {
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final name = 'RUI-P1CONF-$nonce';
  final newName = 'RUI-P1CONF-REN-$nonce';
  // 1. Create the conference through the REAL dialog (batch-7 helper; asserts
  // the conference segment + the new conversation row).
  final gid = await _confCreateDialogSurface(inst, name);
  if (gid.isEmpty) {
    print('[pair] conference_rename_leave: conference create failed');
    return false;
  }
  // 2. Rename via the keyed edit-name dialog. The opener FAB is ON-SCREEN in
  // the profile, so single-fire it (flutter_skill's `tap` double-fires an
  // on-screen button — synthetic pointer + direct callback — which would stack
  // TWO edit dialogs; `_changeGroupName` has no re-entry guard).
  await openGroupChat(inst, groupId: gid, groupName: name, viaL3Seam: true);
  await _openGroupProfile(inst);
  if (!await inst.tapKeyCenter('group_profile_edit_name_button',
      timeoutSecs: 8)) {
    print('[pair] conference_rename_leave: edit-name button not tappable');
    return false;
  }
  if (!await inst.waitKey('group_profile_edit_name_field', timeoutSecs: 10)) {
    print('[pair] conference_rename_leave: edit-name dialog did not open');
    return false;
  }
  await inst.focusType('group_profile_edit_name_field', newName);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  // The confirm pops via popDialogIfCurrent (double-pop absorbed), but keep
  // the single-fire discipline for dialog pop buttons.
  if (!await inst.tapKeyCenter('group_profile_edit_name_confirm_button',
      timeoutSecs: 6)) {
    print('[pair] conference_rename_leave: edit-name confirm not tappable');
    return false;
  }
  // Renamed: the conversation-LIST row showName refreshes (dump) AND the
  // OPEN-chat header title renders the new name (keyed header text — the
  // cheap header check, batch-7 rename precedent).
  final renamed = await _waitGroupShowName(inst, gid, newName, timeoutSecs: 20);
  await returnToChatsHome(inst, rounds: 4);
  await openGroupChat(inst, groupId: gid, groupName: newName, viaL3Seam: true);
  final headerOk = await _waitChatHeaderTitle(inst, newName, timeoutSecs: 12);
  await inst.shot('/tmp/ui_p1_conf_rename_${inst.name}.png');
  // 3. Leave via the real profile leave button + Confirm label; the row must
  // leave the sidebar. Attempted even when the rename asserts failed so the
  // launch does not accumulate conferences (the leave is itself asserted).
  final left = await _groupLeaveViaProfileConfirm(inst, gid, newName);
  print(
    '[pair] conference_rename_leave: created=${_shortId(gid)} '
    'renamed=$renamed headerOk=$headerOk left=$left',
  );
  return renamed && headerOk && left;
}

// ===========================================================================
// case 3 — settings_switch_account_entry (P1#10)
// ===========================================================================
/// Register account #2 ONCE via the REAL RegisterPage (the toxId flips AWAY
/// from the primary), then drive the REAL Settings account-management entry to
/// switch BACK: the primary row's keyed swap IconButton → the keyed confirm
/// dialog → `AccountSwitcher.switchAccount` boots the primary and lands on its
/// HomePage (toxId flips BACK). Captures #2's toxId into [secondToxOut] as soon
/// as registration succeeds so the later cases (and the delete flow) can use it
/// even if the switch half fails.
///
/// Verify-first note (the brief hypothesized "switch entry → LoginPage cards"):
/// the REAL production entry does a DIRECT in-place switch — account_switcher
/// .dart tears down the current session, boots the target, and
/// pushAndRemoveUntil(HomePage) WITHOUT routing through the LoginPage. The
/// case asserts that real behavior.
Future<bool> _p1SettingsSwitchAccountEntry(
  Inst inst,
  String primaryToxId,
  List<String> secondToxOut,
) async {
  if (primaryToxId.isEmpty) {
    print('[pair] settings_switch_account_entry: empty primary toxId');
    return false;
  }
  // 1. Logout the primary → register #2 via the real RegisterPage (the
  // live-passed batch-3 case-29 recipe).
  final loggedOut = await _logoutToLoginPage(inst);
  if (loggedOut != primaryToxId) {
    print(
      '[pair] settings_switch_account_entry: logout toxId '
      '${_shortId(loggedOut)} != primary ${_shortId(primaryToxId)}',
    );
    return false;
  }
  final secondTox = await _p1RegisterSecondAccount(inst, _p1SecondNick);
  if (secondTox.isEmpty || secondTox == primaryToxId) {
    print('[pair] settings_switch_account_entry: second account did not boot');
    return false;
  }
  secondToxOut
    ..clear()
    ..add(secondTox);
  final flippedAway =
      (await inst.dumpState())['currentAccountToxId']?.toString() == secondTox;
  print(
    '[pair] settings_switch_account_entry: on #2 ${_shortId(secondTox)} '
    '(flippedAway=$flippedAway)',
  );
  if (!flippedAway) return false;

  // 2. Settings → account-management list → the PRIMARY row's swap button.
  // The IconButton opens a confirm dialog with NO re-entrancy guard, so
  // single-fire it after scrolling onstage; only fall back to `tapKey` when
  // the bounds cannot resolve (below-fold direct-invoke fires exactly once —
  // the `_openSetPasswordDialog` precedent).
  await _openSettings(inst);
  final swapKey = 'settings_account_switch_button:$primaryToxId';
  if (!await _settingsScrollTo(inst, swapKey)) {
    print('[pair] settings_switch_account_entry: swap button not brought '
        'onstage (continuing — tapKey fallback may still reach it)');
  }
  final dialogUp = await _p1OpenDialogViaKey(
    inst,
    swapKey,
    'settings_account_switch_confirm_button',
  );
  if (!dialogUp) {
    await inst.shot('/tmp/ui_p1_switch_nodialog_${inst.name}.png');
    print('[pair] settings_switch_account_entry: confirm dialog did not open');
    return false;
  }
  // Confirm (single-fire; popDialogIfCurrent absorbs a stray double anyway).
  if (!await inst.tapKeyCenter('settings_account_switch_confirm_button',
      timeoutSecs: 6)) {
    print('[pair] settings_switch_account_entry: confirm not tappable');
    return false;
  }
  // 3. The switch tears down #2 and boots the primary — wait for BOTH
  // sessionReady AND the toxId flip (sessionReady alone is true on #2 before
  // the teardown lands).
  final flippedBack = await _p1WaitAccountReady(inst, primaryToxId);
  await inst.foreground();
  // Home-ready = session back on the PRIMARY + the HomePage shell mounted
  // (homeShellTab set). waitKey('new_entry_menu_button') was a poor proxy: right
  // after a switch-back teardown+boot the button is sometimes not in the
  // (offstage) tree even though the chats home is fully rendered, so the case
  // false-failed despite a correct switch.
  var homeReady = false;
  for (var i = 0; i < 40 && !homeReady; i++) {
    final s = await inst.dumpState();
    final sessionOk = s['sessionReady'] == true &&
        s['currentAccountToxId']?.toString() == primaryToxId;
    // `homeShellTab` is sourced from a HomePage-registered snapshot reader that
    // does not reliably re-register after a switch-back teardown+boot (and
    // `new_entry_menu_button` is likewise sometimes absent then), so accept
    // EITHER the dump tab OR the persistent sidebar avatar key as proof the
    // HomePage shell is mounted + usable.
    homeReady = sessionOk &&
        (s['homeShellTab'] != null ||
            await inst.waitKey('sidebar_user_avatar', timeoutSecs: 1));
    if (!homeReady) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  await inst.shot('/tmp/ui_p1_switch_${inst.name}.png');
  print(
    '[pair] settings_switch_account_entry: flippedAway=$flippedAway '
    'flippedBack=$flippedBack homeReady=$homeReady '
    '(primary=${_shortId(primaryToxId)} second=${_shortId(secondTox)})',
  );
  return flippedAway && flippedBack && homeReady;
}

/// Register a SECOND account via the REAL RegisterPage from the LoginPage and
/// land on its HomePage. Returns the new account's toxId ('' on failure).
/// Verbatim recipe of the live-passed batch-3 `_accountSwitchSecondAccount`
/// register step (focusType nickname → tapKey register → wait sessionReady →
/// dismiss the first-run wizard → home menu).
Future<String> _p1RegisterSecondAccount(Inst inst, String nick) async {
  if (!await _openRegisterPage(inst)) {
    print('[pair] p1 register-second: RegisterPage did not open');
    return '';
  }
  await inst.focusType('register_page_nickname_field', nick);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKey('register_page_register_button');
  await inst.foreground();
  if (!await _waitBoolState(inst, 'sessionReady', true, timeoutSecs: 60)) {
    print('[pair] p1 register-second: session never became ready');
    return '';
  }
  await _dismissFirstRunWizardIfPresent(inst);
  await inst.foreground();
  await inst.waitKey('new_entry_menu_button', timeoutSecs: 25);
  final tox =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  print('[pair] p1 register-second: tox=${_shortId(tox)} (nick "$nick")');
  return tox;
}

// ===========================================================================
// case 4 — account_card_management_menu (P1#8)
// ===========================================================================
/// On the LoginPage, REAL long-press (Batch-I `ui_long_press` primitive,
/// 800 ms hold — the card InkWell uses the framework default 500 ms timeout)
/// on the saved-account card for [targetToxId] → the account-management
/// bottom sheet mounts (production-keyed Export + Delete items,
/// login_page.dart `_showAccountManagementMenu`) → dismiss NON-destructively
/// (ESC; barrier-tap fallback) → the card is still present and the session is
/// still logged out (nothing fired).
Future<bool> _p1AccountCardManagementMenu(
  Inst inst,
  String targetToxId,
) async {
  if (targetToxId.isEmpty) {
    print('[pair] account_card_management_menu: empty target toxId');
    return false;
  }
  final cardKey = 'login_page_account_card:$targetToxId';
  if (!await _waitForAccountCard(inst, targetToxId)) {
    print(
      '[pair] account_card_management_menu: card for '
      '${_shortId(targetToxId)} never rendered (not on the LoginPage?)',
    );
    return false;
  }
  var menuUp = false;
  for (var attempt = 0; attempt < 3 && !menuUp; attempt++) {
    await inst.foreground();
    try {
      await inst.longPressKey(cardKey); // default 800 ms > 500 ms timeout
    } on DriveError catch (e) {
      print('[pair] account_card_management_menu: long-press warn: '
          '${e.message}');
    }
    menuUp = await inst.waitKey(
      'login_account_management_export_option',
      timeoutSecs: 5,
    );
    if (!menuUp) {
      // Abort early if the gesture degenerated into a TAP (a quick-login
      // would be in flight) — never keep long-pressing a logging-in page.
      if ((await inst.dumpState())['sessionReady'] == true) {
        print('[pair] account_card_management_menu: long-press fell through '
            'as a TAP — quick-login fired (gesture regression)');
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
  if (!menuUp) {
    await inst.shot('/tmp/ui_p1_cardmenu_nomenu_${inst.name}.png');
    print('[pair] account_card_management_menu: menu never mounted');
    return false;
  }
  final hasDelete = await inst.waitKey(
    'login_account_management_delete_option',
    timeoutSecs: 3,
  );
  await inst.shot('/tmp/ui_p1_cardmenu_${inst.name}.png');
  // Dismiss WITHOUT any destructive action: ESC pops the modal bottom sheet;
  // fall back to a barrier tap (the sheet is bottom-anchored, so a top-area
  // coordinate hits the barrier).
  try {
    await inst.osaEscape();
  } on DriveError {
    // best-effort
  }
  var dismissed = await inst.waitKeyGone(
    'login_account_management_export_option',
    timeoutSecs: 5,
  );
  if (!dismissed) {
    await inst.tapAt(300, 100);
    dismissed = await inst.waitKeyGone(
      'login_account_management_export_option',
      timeoutSecs: 5,
    );
  }
  // Non-destructive invariants: still logged out, the card still present.
  final stillOut = (await inst.dumpState())['sessionReady'] != true;
  final cardStill = await inst.waitKey(cardKey, timeoutSecs: 6);
  print(
    '[pair] account_card_management_menu: menuUp=$menuUp hasDelete=$hasDelete '
    'dismissed=$dismissed stillOut=$stillOut cardStill=$cardStill',
  );
  return menuUp && hasDelete && dismissed && stillOut && cardStill;
}

// ===========================================================================
// case 5 — account_delete_full_flow (P1#9, S45 real-UI half — DESTRUCTIVE,
// runs LAST in the sweep)
// ===========================================================================
/// From the LoginPage: quick-login INTO the throwaway account #2 via its real
/// card → Settings → the keyed Delete Account button → the confirm dialog
/// (confirm-word branch — #2 has no password) → read the random word from the
/// live prompt, type it via the keyed input, single-fire the keyed destructive
/// confirm → `deleteAccountCompletely` lands back on the LoginPage where #2's
/// card is GONE (`Prefs.removeAccount`) and the primary's card survives →
/// quick-login the primary.
///
/// Self-sufficient: when [secondToxHolder] is empty (standalone dispatch, or
/// the sweep's case 3 failed before registering), it registers its own
/// throwaway #2 first, then logs out so the asserted flow ALWAYS starts with
/// the real card tap.
Future<bool> _p1AccountDeleteFullFlow(
  Inst inst,
  String primaryToxId,
  List<String> secondToxHolder,
) async {
  if (primaryToxId.isEmpty) {
    print('[pair] account_delete_full_flow: empty primary toxId');
    return false;
  }
  // Normalize to the LoginPage (a failed earlier case may have left a session
  // up).
  if ((await inst.dumpState())['sessionReady'] == true) {
    if ((await _logoutToLoginPage(inst)).isEmpty) {
      print('[pair] account_delete_full_flow: could not reach the LoginPage');
      return false;
    }
  }
  var secondTox = secondToxHolder.isNotEmpty ? secondToxHolder.first : '';
  if (secondTox.isEmpty) {
    secondTox = await _p1RegisterSecondAccount(inst, _p1SecondNick);
    if (secondTox.isEmpty) {
      print('[pair] account_delete_full_flow: could not provision account #2');
      return false;
    }
    secondToxHolder
      ..clear()
      ..add(secondTox);
    if ((await _logoutToLoginPage(inst)) != secondTox) {
      print('[pair] account_delete_full_flow: post-register logout failed');
      return false;
    }
  }
  if (secondTox == primaryToxId) {
    print('[pair] account_delete_full_flow: refusing — target IS the primary');
    return false;
  }
  // 1. Log INTO #2 via its real saved-account card.
  if (!await _quickLoginNoPassword(inst, secondTox)) {
    print('[pair] account_delete_full_flow: quick-login into #2 failed');
    return false;
  }
  final onSecond =
      (await inst.dumpState())['currentAccountToxId']?.toString() == secondTox;
  if (!onSecond) {
    print('[pair] account_delete_full_flow: not on #2 after quick-login');
    return false;
  }
  // 2. Settings → Delete Account (keyed opener; single-fire when onstage,
  // tapKey only as the below-fold fallback — direct invoke fires once).
  await _openSettings(inst);
  if (!await _settingsScrollTo(inst, 'settings_delete_account_button')) {
    print('[pair] account_delete_full_flow: delete button not brought '
        'onstage (continuing — tapKey fallback may still reach it)');
  }
  final dialogUp = await _p1OpenDialogViaKey(
    inst,
    'settings_delete_account_button',
    'settings_delete_account_confirm_input',
  );
  if (!dialogUp) {
    await inst.shot('/tmp/ui_p1_delete_nodialog_${inst.name}.png');
    print('[pair] account_delete_full_flow: confirm dialog did not open');
    return false;
  }
  // 3. Read the random confirm word from the live prompt and type it. A
  // failed extraction or a mis-typed word makes production REJECT the confirm
  // (snackbar + dialog stays) — the case then fails honestly with no
  // deletion.
  final word = await _p1DeleteConfirmWordFromUi(inst);
  if (word.isEmpty) {
    try {
      await inst.osaEscape(); // leave the dialog non-destructively
    } on DriveError {
      // best-effort
    }
    return false;
  }
  await inst.focusType('settings_delete_account_confirm_input', word);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!await inst.tapKeyCenter('settings_delete_account_confirm_button',
      timeoutSecs: 6)) {
    print('[pair] account_delete_full_flow: confirm button not tappable');
    return false;
  }
  // 4. Deletion tears down the session and pushes the LoginPage. Wait for the
  // logged-out state, then require the PRIMARY card to render (proves the
  // saved-account list loaded) BEFORE asserting #2's card is gone — "gone
  // because the list hasn't loaded yet" must not false-pass.
  final loggedOut =
      await _waitBoolState(inst, 'sessionReady', false, timeoutSecs: 60);
  if (!loggedOut) {
    print('[pair] account_delete_full_flow: never returned to the LoginPage');
    return false;
  }
  final primaryCardShown = await _waitForAccountCard(inst, primaryToxId);
  final secondCardGone = await inst.waitKeyGone(
    'login_page_account_card:$secondTox',
    timeoutSecs: 8,
  );
  // PERSISTED ground truth (codex P2): the card's visual absence alone could
  // false-pass on an unbuilt/offscreen list — also require #2's toxId gone
  // from the saved-account store (the new `savedAccountToxIds` dump field).
  final savedIds =
      ((await inst.dumpState())['savedAccountToxIds'] as List? ?? const [])
          .map((e) => e.toString())
          .toList();
  // Sentinel (codex confirm-round P2): _savedAccountToxIds returns [] on any
  // Prefs read error, so an empty/short list must not count as "absent". The
  // PRIMARY account is always saved in this campaign — trust the list only
  // when it proves it can see the primary.
  final listTrusted = savedIds.contains(primaryToxId);
  final dumpGone = listTrusted && !savedIds.contains(secondTox);
  await inst.shot('/tmp/ui_p1_delete_${inst.name}.png');
  // 5. Quick-login back into the primary.
  final backOnPrimary = await _quickLoginNoPassword(inst, primaryToxId) &&
      (await inst.dumpState())['currentAccountToxId']?.toString() ==
          primaryToxId;
  if (secondCardGone && dumpGone) {
    secondToxHolder.clear(); // the throwaway is verifiably gone
  }
  print(
    '[pair] account_delete_full_flow: word="$word" loggedOut=$loggedOut '
    'primaryCardShown=$primaryCardShown secondCardGone=$secondCardGone '
    'dumpGone=$dumpGone backOnPrimary=$backOnPrimary '
    '(deleted ${_shortId(secondTox)})',
  );
  return loggedOut &&
      primaryCardShown &&
      secondCardGone &&
      dumpGone &&
      backOnPrimary;
}

// ===========================================================================
// sweep_p1_single — Batch II: chain all 5 cases on ONE launch (A only).
// ===========================================================================

/// Best-effort between-cases normalizer: back out of a stranded RegisterPage /
/// quick-login password dialog (login-part helper), ESC any stray sheet or
/// dialog, and re-verify the locale is EN when a session is up (the zh-walk
/// case has its own finally-guard; this is defense in depth for the later
/// EN-text cases). Idempotent; never throws.
Future<void> _p1NormalizeBetweenCases(Inst inst) async {
  try {
    await _normalizeLoginBetweenCases(inst);
    // A stray bottom sheet / dialog from a failed case: one ESC is harmless
    // on the bare LoginPage/HomePage and pops a stranded surface.
    if (await inst.waitKey('login_account_management_export_option',
            timeoutSecs: 1) ||
        await inst.waitKey('settings_delete_account_confirm_input',
            timeoutSecs: 1)) {
      try {
        await inst.osaEscape();
      } on DriveError {
        // best-effort
      }
    }
    final st = await inst.dumpState();
    if (st['sessionReady'] == true &&
        st['languageCode']?.toString() != 'en') {
      print('[sweep] p1 normalize: locale is ${st['languageCode']} -> en');
      await _p1RevertLocaleToEnglish(inst);
    }
  } on DriveError catch (e) {
    print('[sweep] p1 normalize: best-effort failed (ignored): ${e.message}');
  }
}

/// Best-effort END-STATE guard (mirrors the batch-3 `_ensureCleanPrimaryEnd`
/// shape): regardless of which cases failed, end the launch logged into the
/// PRIMARY account with the locale EN. Never throws; returns whether the end
/// state was verified clean. The throwaway #2 (if a failure left it behind)
/// is only LOGGED — a guard must never run the destructive delete flow.
Future<bool> _p1EnsureCleanEnd(
  Inst inst,
  String primaryToxId,
  String primaryNick,
  List<String> secondToxHolder,
) async {
  try {
    await _p1NormalizeBetweenCases(inst);
    await inst.foreground();
    var st = await inst.dumpState();
    // Logged into a non-primary account? Log out first.
    if (st['sessionReady'] == true &&
        (st['currentAccountToxId']?.toString() ?? '') != primaryToxId) {
      print('[sweep] p1 end-clean: on a non-primary account -> logout');
      await _logoutToLoginPage(inst);
      st = await inst.dumpState();
    }
    // Logged out? Quick-login the primary (no password in this campaign).
    if (st['sessionReady'] != true) {
      if (await _waitForAccountCard(inst, primaryToxId)) {
        await _quickLoginNoPassword(inst, primaryToxId);
      }
    }
    // Locale back to EN (requires the session; runs after the login above).
    final localeEn = await _p1RevertLocaleToEnglish(inst);
    try {
      await returnToChatsHome(inst, rounds: 4);
    } on DriveError catch (e) {
      print('[sweep] p1 end-clean: returnToChatsHome best-effort: ${e.message}');
    }
    final finalState = await inst.dumpState();
    final onPrimary = finalState['sessionReady'] == true &&
        (finalState['currentAccountToxId']?.toString() ?? '') == primaryToxId;
    // No-leftover verdict (codex P1): a non-empty holder means case 5 never
    // verifiably deleted the throwaway — PROVE it against the persisted
    // saved-account store, not the holder alone (a case-5 FAIL after the
    // actual deletion must not false-dirty the verdict). The guard itself
    // never runs the destructive delete; it only verifies.
    final savedIds =
        (finalState['savedAccountToxIds'] as List? ?? const [])
            .map((e) => e.toString())
            .toList();
    // Sentinel (codex confirm-round P2): [] is ambiguous (read error vs truly
    // empty) — only trust an absence verdict when the list can see the
    // always-saved PRIMARY account.
    final listTrusted = savedIds.contains(primaryToxId);
    final noLeftover = secondToxHolder.isEmpty ||
        (listTrusted && !savedIds.contains(secondToxHolder.first));
    final leftover = secondToxHolder.isNotEmpty
        ? _shortId(secondToxHolder.first)
        : 'none';
    final clean = onPrimary && localeEn && noLeftover;
    print(
      '[sweep] p1 end-clean: onPrimary=$onPrimary localeEn=$localeEn '
      'noLeftover=$noLeftover throwawayLeftover=$leftover clean=$clean '
      '(primary=${_shortId(primaryToxId)} nick "$primaryNick")',
    );
    return clean;
  } on PermissionBlockedError catch (e) {
    print('[sweep] p1 end-clean: BLOCKED (osascript perm): ${e.message}');
    return false;
  } on DriveError catch (e) {
    print('[sweep] p1 end-clean: aborted (best-effort, ignored): ${e.message}');
    return false;
  } catch (e) {
    print('[sweep] p1 end-clean: unexpected error (ignored): $e');
    return false;
  }
}

/// sweep_p1_single — chain the 5 Batch-II cases on ONE launch (A only; B
/// idle). Order is the state machine:
///   1 zh-walk (logged-in primary; finally-guard reverts the locale) →
///   2 conference rename+leave (primary Home; the conference is created AND
///     left inside the case) →
///   3 switch-entry (registers the throwaway #2, ends on the primary Home) →
///   logout once (cases 4+5 act on the LoginPage) →
///   4 card management menu (long-press #2's card — falls back to the
///     primary's card if #2 is missing; dismiss-only, non-destructive) →
///   5 delete full flow (deletes #2 — DESTRUCTIVE, LAST; self-provisions a
///     throwaway when #3 failed before registering; ends on the primary).
/// A `finally` end-guard restores the documented end state (primary logged
/// in, locale EN) and logs any leftover throwaway. Prints
/// `[sweep] <case>: PASS|FAIL` per case + final counts; exits non-zero if any
/// HARD case fails (all 5 are hard — every surface was verified to exist by
/// reading the production code, so there are no designed SKIPs).
Future<int> runP1SingleSweep(Inst a, String nickA) async {
  await ensureHome(a, nickA);
  await a.waitState(
    (s) => s['isConnected'] == true,
    label: '$nickA connected',
    timeoutSecs: 90,
  );
  final primaryToxId =
      (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (primaryToxId.isEmpty) {
    print('[sweep] sweep_p1_single: no primary toxId after ensureHome');
    return 1;
  }
  final primaryNick = (await a.dumpState())['nickname']?.toString() ?? nickA;
  print(
    '[sweep] sweep_p1_single: primary=${_shortId(primaryToxId)} '
    '(nick "$primaryNick")',
  );

  var passed = 0;
  var failed = 0;
  // The end-clean verdict participates in the sweep's exit code (codex P1):
  // a launch that ends dirty (wrong account / zh locale / leftover throwaway)
  // must FAIL even when all 5 cases passed — the runner trusts the registered
  // no-friend clean result state.
  var endClean = false;
  final results = <String, String>{};
  final secondToxHolder = <String>[];

  Future<void> hard(String id, Future<bool> Function() run) async {
    bool ok;
    String? detail;
    try {
      ok = await run();
    } on PermissionBlockedError {
      rethrow; // surfaces as BLOCKED(78) at the driver level
    } on DriveError catch (e) {
      ok = false;
      detail = 'DriveError: ${e.message}';
    }
    if (ok) {
      passed++;
      results[id] = 'PASS';
      print('[sweep] $id: PASS');
    } else {
      failed++;
      results[id] = 'FAIL';
      print('[sweep] $id: FAIL${detail != null ? ' ($detail)' : ''}');
    }
    await _p1NormalizeBetweenCases(a);
  }

  try {
    // 1 — zh locale page walk (its finally-guard reverts the locale even on
    // FAIL, so the later EN-text cases stay unpoisoned).
    await hard('zh_locale_page_walk', () => _p1ZhLocalePageWalk(a));
    // 2 — conference rename + leave (creates and destroys its own conference).
    await hard('conference_rename_leave', () => _p1ConferenceRenameLeave(a));
    // 3 — switch entry (registers #2 ONCE; captures its toxId into the holder
    // immediately after registration; ends logged into the primary).
    await hard(
      'settings_switch_account_entry',
      () => _p1SettingsSwitchAccountEntry(a, primaryToxId, secondToxHolder),
    );
    // Cases 4+5 act on the LoginPage — log out once. If the logout fails the
    // cases below fail honestly on their own LoginPage preconditions.
    final lo = await _logoutToLoginPage(a);
    if (lo.isEmpty) {
      print('[sweep] sweep_p1_single: pre-4 logout failed — cases 4/5 will '
          'fail their LoginPage preconditions');
    }
    // 4 — card management menu. Prefer #2's card (the brief's target); fall
    // back to the primary's card when #3 failed before registering so the
    // real menu surface is still exercised.
    final menuTarget = secondToxHolder.isNotEmpty
        ? secondToxHolder.first
        : primaryToxId;
    await hard(
      'account_card_management_menu',
      () => _p1AccountCardManagementMenu(a, menuTarget),
    );
    // 5 — delete full flow (DESTRUCTIVE, LAST): deletes the throwaway #2 and
    // ends logged into the primary.
    await hard(
      'account_delete_full_flow',
      () => _p1AccountDeleteFullFlow(a, primaryToxId, secondToxHolder),
    );
  } finally {
    endClean = await _p1EnsureCleanEnd(
      a,
      primaryToxId,
      primaryNick,
      secondToxHolder,
    );
    print(
      '[sweep] sweep_p1_single RESULTS: $passed PASS / $failed FAIL '
      '($results) | endClean=$endClean',
    );
    try {
      await a.shot('/tmp/ui_p1_single_sweep_${a.name}.png');
    } on DriveError {
      // best-effort
    }
  }
  // Gate on the END-CLEAN verdict too (codex P1) — the runner trusts the
  // registered clean no-friend result state, so an unachieved end state must
  // fail the sweep even with 5/5 case passes.
  return failed == 0 && endClean ? 0 : 1;
}

/// Whether [scenario] is one of the 5 Batch-II P1 single-instance cases.
bool _isP1SingleCaseScenario(String scenario) => const {
      'zh_locale_page_walk',
      'conference_rename_leave',
      'settings_switch_account_entry',
      'account_card_management_menu',
      'account_delete_full_flow',
    }.contains(scenario);

/// Run a single Batch-II case standalone with its minimal prelude (the sweep
/// is the canonical entry). All cases drive only A; B stays launched-but-idle.
Future<int> runP1SingleCase(Inst a, String nickA, String scenario) async {
  await ensureHome(a, nickA);
  await a.waitState(
    (s) => s['isConnected'] == true,
    label: '$nickA connected',
    timeoutSecs: 90,
  );
  final primaryToxId =
      (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (primaryToxId.isEmpty) {
    throw DriveError('missing primary toxId for $scenario');
  }
  switch (scenario) {
    case 'zh_locale_page_walk':
      return await _p1ZhLocalePageWalk(a) ? 0 : 1;
    case 'conference_rename_leave':
      return await _p1ConferenceRenameLeave(a) ? 0 : 1;
    case 'settings_switch_account_entry':
      // Asserted action = the real switch round-trip. CLEANUP (not asserted;
      // codex P1): a standalone run must not leave the throwaway #2 behind —
      // the runner records this scenario as a clean no-friend result, so an
      // unexpressed leftover account would be hidden launch dirt. Delete #2
      // via the SAME real delete flow (here it is cleanup, not the gate's
      // subject) and gate the exit on the cleanup landing too.
      final holder = <String>[];
      final switched =
          await _p1SettingsSwitchAccountEntry(a, primaryToxId, holder);
      var cleaned = true;
      if (holder.isNotEmpty) {
        if ((await _logoutToLoginPage(a)).isEmpty) {
          cleaned = false;
        } else {
          cleaned = await _p1AccountDeleteFullFlow(a, primaryToxId, holder);
        }
      }
      return switched && cleaned ? 0 : 1;
    case 'account_card_management_menu':
      // Standalone: the menu works on ANY saved card — use the primary's own
      // card so no second account needs to be provisioned. Ends logged back
      // into the primary for end-state parity with the other single-instance
      // scenarios.
      if ((await _logoutToLoginPage(a)).isEmpty) return 1;
      final menuOk = await _p1AccountCardManagementMenu(a, primaryToxId);
      final back = await _quickLoginNoPassword(a, primaryToxId);
      return menuOk && back ? 0 : 1;
    case 'account_delete_full_flow':
      // Standalone: self-provisions its own throwaway #2 (the holder starts
      // empty), deletes it, and ends logged into the primary.
      if ((await _logoutToLoginPage(a)).isEmpty) return 1;
      return await _p1AccountDeleteFullFlow(a, primaryToxId, <String>[])
          ? 0
          : 1;
  }
  throw DriveError('unknown p1-single scenario: $scenario');
}
