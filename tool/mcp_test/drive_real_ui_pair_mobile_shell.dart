// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Mobile-shell / tablet-layout FORM-FACTOR cases.
//
// WHY THIS FILE EXISTS. The `rui-ios-*` / `rui-ipad-*` campaigns re-run the
// DESKTOP sweeps on a phone/iPad simulator. That is layout REUSE, not layout
// COVERAGE: before this file no scenario ever touched a control that exists
// ONLY on the mobile shell (the bottom navigation bar, the mobile composer's
// send button, the long-press message menu) or asserted the tablet-only
// master-detail split. These cases close that gap.
//
// INPUT-PATH DISCIPLINE (the hard rule for anything added here). On iOS the
// whole `osa*` surface is a SILENT NO-OP: `Inst._osa` starts with
// `if (isIos || _isHeadlessRealUi) return;`, and only `focusType` has an iOS
// branch. So Return-to-send, Escape-to-close, Cmd+A-clear, paste and
// window-resize DO NOTHING on iOS/Android — a case built on them "runs", asserts
// nothing, and reports PASS. Every case below therefore drives ONLY:
//   * flutter_skill synthetic input (tap / tapAt / enterText / waitForElement),
//   * the ungated `ui_*` pointer tools (ui_key_center / ui_long_press), and
//   * the ungated `l3_composer_set_text` / `l3_composer_send` composer seams
//     (the production `_submitTextMessage` path the send BUTTON's onTap calls).
// Where a surface genuinely does not exist in the running layout tier, the case
// returns a SKIP (null -> exit 75), never a FAIL — a form-factor mismatch is an
// environment fact, not a defect.
//
// LAYOUT TIERS (lib/util/responsive_layout.dart), and how each is DETECTED
// here from live signals rather than from the platform name (a landscape phone
// is wider than a portrait tablet, so `isIos` proves nothing about layout):
//   * phone / bottom-nav tier  — width < 720pt. Detected by `home_bottom_nav`
//     resolving to an onstage RenderBox (`ui_key_center`). That key exists for
//     exactly this purpose (see UiKeys.homeBottomNav).
//   * master-detail tier       — width >= 800pt. Detected by the dump's
//     `homeShellShouldShowMasterDetail` (HomePage's live `_lastShouldShowMaster
//     Detail`). True on both iPad orientations and on desktop.
//   * the 720..800 band has neither; cases that need one of the two SKIP there.
//
// MOBILE PARITY. All widgets driven here are shared Dart (lib/ui/home_page.dart
// bottom nav, the vendored UIKit mobile composer/menu, lib/ui/add_*_dialog.dart),
// so an Android run exercises exactly the same code as iOS. Android has NEVER
// reached the business layer in this harness (no `pair.json` under
// `.android_runtime`), so nothing here is claimed as Android-verified.
//
// NOT VERIFIED BY EXECUTION: authored offline (no dart/flutter available in the
// authoring environment); the geometry thresholds below are derived from the
// widget source, not from a live measurement.

const _mobileShellCases = {
  'mobile_bottom_nav_tab_switch',
  'mobile_composer_send_button_reveals',
  'mobile_composer_send_delivers',
  'mobile_message_long_press_menu',
  'tablet_master_detail_row_opens_chat',
  'dialog_width_form_factor_tier',
};

bool _isMobileShellCaseScenario(String scenario) =>
    _mobileShellCases.contains(scenario);

/// Cases that need a live A<->B friendship (a real C2C conversation to open).
/// The rest drive A only and never form one.
const _mobileShellFriendshipCases = {
  'mobile_composer_send_button_reveals',
  'mobile_composer_send_delivers',
  'mobile_message_long_press_menu',
  'tablet_master_detail_row_opens_chat',
};

/// Map a case body's tri-state result onto the runner's exit contract:
/// null -> SKIP (75), true -> PASS (0), false -> FAIL (1).
int _mobileShellExit(bool? result) => switch (result) {
  true => 0,
  false => 1,
  null => 75,
};

Future<int> runMobileShellCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  // A-only cases skip the handshake cost entirely; the rest need a live C2C
  // conversation, so they establish (or reuse) the A<->B friendship first.
  if (!_mobileShellFriendshipCases.contains(scenario)) {
    await ensureHome(a, nickA);
    final result = switch (scenario) {
      'mobile_bottom_nav_tab_switch' => await _msBottomNavTabSwitch(a),
      'dialog_width_form_factor_tier' => await _msDialogWidthFormFactorTier(a),
      _ => throw ArgumentError('unsupported mobile-shell scenario: $scenario'),
    };
    _printMobileShellOutcome(scenario, result);
    return _mobileShellExit(result);
  }
  final ids = await _msEnsureFriendship(a, b, nickA, nickB);
  if (ids == null) {
    print('[pair] $scenario: could not establish the A<->B friendship');
    return 1;
  }
  final result = switch (scenario) {
    'mobile_composer_send_button_reveals' => await _msComposerSendButtonReveals(
      a,
      ids.toxB,
    ),
    'mobile_composer_send_delivers' => await _msComposerSendDelivers(
      a,
      b,
      ids.toxA,
      ids.toxB,
    ),
    'mobile_message_long_press_menu' => await _msMessageLongPressMenu(
      a,
      ids.toxB,
    ),
    'tablet_master_detail_row_opens_chat' => await _msTabletMasterDetailRow(
      a,
      ids.toxB,
    ),
    _ => throw ArgumentError('unsupported mobile-shell scenario: $scenario'),
  };
  _printMobileShellOutcome(scenario, result);
  return _mobileShellExit(result);
}

void _printMobileShellOutcome(String scenario, bool? result) {
  final label = result == null ? 'SKIP' : (result ? 'PASS' : 'FAIL');
  print('[pair] $label: $scenario');
}

/// Phone-shell sweep: every mobile-ONLY control on one launch (one handshake at
/// the top, reused by the composer/menu cases). On a wide shell (iPad/desktop)
/// each mobile-only case SKIPs with its reason — the sweep is intentionally NOT
/// registered in the `rui-ipad-*` campaigns for that reason.
Future<int> runMobileShellSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final ids = await _msEnsureFriendship(a, b, nickA, nickB);
  if (ids == null) {
    print(
      '[sweep] sweep_mobile_shell: could not establish the A<->B friendship',
    );
    return 1;
  }
  final tally = _MobileShellTally('sweep_mobile_shell');
  // EVERY case here is `expectedSkip: true`: this whole file exists to drive
  // controls that render only in ONE layout tier, and each body prints the tier
  // probe that made it skip (see the LAYOUT TIERS block at the top). That is a
  // capability assertion, not a swallowed failure — the contract
  // `_MobileShellTally` now demands before it lets a skip go green.
  await tally.run(
    'mobile_bottom_nav_tab_switch',
    () => _msBottomNavTabSwitch(a),
    expectedSkip: true,
  );
  await tally.run(
    'mobile_composer_send_button_reveals',
    () => _msComposerSendButtonReveals(a, ids.toxB),
    expectedSkip: true,
  );
  await tally.run(
    'mobile_composer_send_delivers',
    () => _msComposerSendDelivers(a, b, ids.toxA, ids.toxB),
    expectedSkip: true,
  );
  await tally.run(
    'mobile_message_long_press_menu',
    () => _msMessageLongPressMenu(a, ids.toxB),
    expectedSkip: true,
  );
  // The dialog tier assertion is form-factor AWARE (it asserts the phone tier
  // here and the tablet tier in sweep_tablet_layout), so it belongs in both.
  await tally.run(
    'dialog_width_form_factor_tier',
    () => _msDialogWidthFormFactorTier(a),
    expectedSkip: true,
  );
  await _msLandHome(a, 'sweep_mobile_shell');
  return tally.finish();
}

/// Tablet/master-detail sweep: the wide-layout-only behaviours. On a compact
/// phone the master-detail case SKIPs and the dialog tier case asserts the
/// phone tier, so the sweep stays honest wherever it is pointed.
Future<int> runTabletLayoutSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final ids = await _msEnsureFriendship(a, b, nickA, nickB);
  if (ids == null) {
    print(
      '[sweep] sweep_tablet_layout: could not establish the A<->B friendship',
    );
    return 1;
  }
  final tally = _MobileShellTally('sweep_tablet_layout');
  // Same `expectedSkip: true` rationale as `runMobileShellSweep`: both cases
  // gate on the live layout tier and print the probe that decided it.
  await tally.run(
    'tablet_master_detail_row_opens_chat',
    () => _msTabletMasterDetailRow(a, ids.toxB),
    expectedSkip: true,
  );
  await tally.run(
    'dialog_width_form_factor_tier',
    () => _msDialogWidthFormFactorTier(a),
    expectedSkip: true,
  );
  await _msLandHome(a, 'sweep_tablet_layout');
  return tally.finish();
}

/// End-guard: land back on the chats home so a REUSED launch (the optimized /
/// `rui-*-main` bundles chain sweeps on one pair) starts from a known shell.
Future<void> _msLandHome(Inst inst, String label) async {
  try {
    await returnToChatsHome(inst, rounds: 4);
  } on Object catch (e) {
    print('[sweep] $label: return-home end-guard best-effort: $e');
  }
}

// ---------------------------------------------------------------------------
// Layout-tier probes + shared preconditions
// ---------------------------------------------------------------------------

/// True when the COMPACT phone shell is up: HomePage's bottom navigation bar
/// (`UiKeys.homeBottomNav`) resolves to a laid-out, painting RenderBox. That bar
/// renders ONLY under `ResponsiveLayout.shouldShowBottomNav` (< 720pt), so its
/// presence IS the tier signal — and it is a pure width check, so this is true
/// on a narrow desktop window too (by design: the same mobile widgets are up).
Future<bool> _msPhoneShell(Inst inst) async =>
    await inst.keyCenter('home_bottom_nav') != null;

/// The MEASURED bottom edge (in logical pixels) of the keyed widget [key], from
/// `ui_key_center`'s `y` + `h / 2`. Null when the key does not resolve.
///
/// `Inst.keyCenter` drops the RenderBox size, so every "is that row inside this
/// scrollable's viewport?" question used to be answered against a GUESSED
/// constant (`2 * view.y - <fudge>`). A guess silently changes meaning whenever
/// the surrounding chrome changes height — which turns a genuine red into a
/// swallowed SKIP. This reads the box the framework actually laid out.
Future<double?> _measuredBottomEdge(Inst inst, String key) async {
  try {
    final r = await inst.l3('ui_key_center', {'key': key});
    if (r['ok'] != true) return null;
    final y = (r['y'] as num?)?.toDouble();
    final h = (r['h'] as num?)?.toDouble();
    if (y == null || h == null) return null;
    return y + h / 2;
  } on DriveError {
    return null;
  }
}

/// True when the WIDE master-detail shell is up (>= 800pt: both iPad
/// orientations, desktop). Read from the live dump (HomePage's own computed
/// value) rather than guessed from the platform.
Future<bool> _msWideShell(Inst inst) async =>
    (await inst.dumpState())['homeShellShouldShowMasterDetail'] == true;

/// Ensure both peers are home and friends, reusing an existing friendship (so a
/// sweep chained after another friendship-forming sweep pays nothing). Returns
/// both tox ids, or null when the precondition could not be met.
Future<({String toxA, String toxB})?> _msEnsureFriendship(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    print('[pair] mobile-shell: missing tox ids (A=$toxA B=$toxB)');
    return null;
  }
  if (await areFriends(a, toxB) && await areFriends(b, toxA)) {
    return (toxA: toxA, toxB: toxB);
  }
  if (!await _establishFriendshipForSweep(a, b, toxA, toxB, nickA, nickB)) {
    return null;
  }
  return (toxA: toxA, toxB: toxB);
}

// ===========================================================================
// mobile_bottom_nav_tab_switch — the MOBILE-ONLY home navigation control
// ===========================================================================
/// Tap each real bottom-nav item (`bottom_nav_contacts_tab` ->
/// `bottom_nav_applications_tab` -> `bottom_nav_settings_tab` ->
/// `bottom_nav_chats_tab`) and assert the home shell ACTUALLY switched, via the
/// dump's `homeShellTab` (HomePage's live IndexedStack `_index`).
///
/// Why `homeShellTab` and not a widget probe: every tab's subtree stays MOUNTED
/// in the IndexedStack, so a whole-tree `waitForElement` matches the target
/// tab's widgets even when the tab never switched (the exact false-pass the
/// settings driver documents). The dump field is the only authoritative signal.
///
/// Why this is not covered by the desktop sweeps: they drive `sidebar_*_tab`,
/// which does not exist below 720pt; the bottom-nav items are a different
/// widget tree with a different callback (`BottomNavigationBar.onTap`).
///
/// The nav items are keyed on their `Icon`/`Stack` (not on the tappable), so a
/// key tap resolves through `ui_key_center` + `tapAt` — a real pointer event
/// landing inside the item's InkWell.
Future<bool?> _msBottomNavTabSwitch(Inst inst) async {
  await inst.foreground();
  await returnToChatsHome(inst, rounds: 4);
  if (!await _msPhoneShell(inst)) {
    print(
      '[pair] mobile_bottom_nav_tab_switch: SKIP — this shell has no bottom '
      'navigation bar (home_bottom_nav unresolvable): a >=720pt wide/tablet/'
      'desktop layout renders the sidebar rail instead, which sweep_settings2 '
      'and the shell helpers already drive',
    );
    return null;
  }
  final steps = <(String, String)>[
    ('bottom_nav_contacts_tab', 'contacts'),
    ('bottom_nav_applications_tab', 'applications'),
    ('bottom_nav_settings_tab', 'settings'),
    ('bottom_nav_chats_tab', 'chats'),
  ];
  var ok = true;
  for (final step in steps) {
    final landed = await _msTapBottomNavAndWait(inst, step.$1, step.$2);
    print(
      '[pair] mobile_bottom_nav_tab_switch: ${step.$1} -> '
      'homeShellTab=${step.$2}: $landed',
    );
    if (!landed) ok = false;
  }
  await inst.shot('/tmp/ui_mobile_bottom_nav_${inst.name}.png');
  return ok;
}

Future<bool> _msTapBottomNavAndWait(
  Inst inst,
  String key,
  String expectedTab,
) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    // Bounded waitKey inside tapKeyCenter: the nav item is keyed on a plain
    // Icon, which flutter_skill's interactiveStructured does not surface, so the
    // element-tree fallback (`ui_key_center` + tapAt) is the expected path.
    if (!await inst.tapKeyCenter(key, timeoutSecs: 2)) {
      await inst.tryTapKey(key, retries: 1);
    }
    for (var poll = 0; poll < 10; poll++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (await _homeShellTab(inst) == expectedTab) return true;
    }
  }
  return false;
}

// ===========================================================================
// mobile_composer_send_button_reveals — the MOBILE-ONLY send affordance
// ===========================================================================
/// The mobile composer swaps a MIC affordance for a real send button as soon as
/// the field is non-empty (`_onTextChanged` -> `_showSendButton` ->
/// `ValueKey('chat_send_button')` mounts). The desktop composer has NO send
/// button at all (send is Enter-driven), so this state machine exists only on
/// the mobile shell.
///
/// Text is set through `l3_composer_set_text`, which mutates the REAL
/// controller (`_textEditingController.text = text`) and therefore fires the
/// production `_onTextChanged` listener. flutter_skill's synthetic `enterText`
/// cannot drive this ExtendedTextField, and osascript keystrokes are a silent
/// no-op on iOS/Android — both would make this case assert nothing.
///
/// SKIPs when no MOBILE composer is mounted: the seam is registered by the
/// mobile input only, so `no_composer` is the authoritative "this shell renders
/// the desktop composer" signal (iPad/desktop).
Future<bool?> _msComposerSendButtonReveals(Inst a, String toxB) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print(
      '[pair] mobile_composer_send_button_reveals: could not open the C2C chat',
    );
    return false;
  }
  final probe = 'RUIMOB-REVEAL-${DateTime.now().microsecondsSinceEpoch}';
  final set = await a.l3('l3_composer_set_text', {'text': probe});
  if (set['ok'] != true) {
    print(
      '[pair] mobile_composer_send_button_reveals: SKIP — no MOBILE composer '
      'mounted (l3_composer_set_text: ${set['error'] ?? set}); this shell '
      'renders the DESKTOP composer, which has no send button (its Enter-send '
      'is covered by the chat sweeps)',
    );
    return null;
  }
  final revealed = await a.waitKeyCenter('chat_send_button', timeoutSecs: 8);
  // Clearing the field must take the send button back OUT of the tree (the mic
  // affordance returns) — the other half of the state machine, and it also
  // leaves the composer clean for the next case.
  await a.l3('l3_composer_set_text', {'text': ''});
  var hidden = false;
  for (var poll = 0; poll < 20; poll++) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (await a.keyCenter('chat_send_button') == null) {
      hidden = true;
      break;
    }
  }
  await a.shot('/tmp/ui_mobile_send_button_${a.name}.png');
  print(
    '[pair] mobile_composer_send_button_reveals: revealed=$revealed '
    'hiddenAfterClear=$hidden',
  );
  return revealed && hidden;
}

// ===========================================================================
// mobile_composer_send_delivers — mobile composer -> real delivery to the peer
// ===========================================================================
/// Two-process: A composes in the REAL mobile composer and sends; B must
/// receive the exact text.
///
/// SEND PATH. The preferred path is a real tap on the revealed
/// `chat_send_button`. The harness has a live-diagnosed limitation here (a
/// synthetic tap on that InkWell does not reliably fire on a compact phone —
/// see `_sendComposerMessageIos`), so when the tap does not deliver, the case
/// falls back to `l3_composer_send`, which invokes the SAME production
/// `_submitTextMessage` the button's `onTap` calls. The HARD gate is DELIVERY
/// TO B; the path that achieved it is printed (`sendPath=real_button|l3_seam`)
/// so a regression in the button tap is visible rather than hidden. Enter-to-send
/// (osaReturn) is NOT used: it is a silent no-op on iOS/Android.
Future<bool?> _msComposerSendDelivers(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] mobile_composer_send_delivers: could not open the C2C chat');
    return false;
  }
  final text = 'RUIMOB-SEND-${DateTime.now().microsecondsSinceEpoch}';
  final set = await a.l3('l3_composer_set_text', {'text': text});
  if (set['ok'] != true) {
    print(
      '[pair] mobile_composer_send_delivers: SKIP — no MOBILE composer mounted '
      '(l3_composer_set_text: ${set['error'] ?? set}); this shell renders the '
      'DESKTOP composer (covered by the chat sweeps)',
    );
    return null;
  }
  if (!await a.waitKeyCenter('chat_send_button', timeoutSecs: 8)) {
    print(
      '[pair] mobile_composer_send_delivers: chat_send_button never mounted '
      'after the real controller set-text',
    );
    return false;
  }
  var sendPath = 'real_button';
  var sent = false;
  for (var attempt = 0; attempt < 3 && !sent; attempt++) {
    await a.tapKeyCenter('chat_send_button', timeoutSecs: 4);
    sent = await _msWaitOwnSent(a, text);
  }
  if (!sent) {
    sendPath = 'l3_seam';
    print(
      '[pair] mobile_composer_send_delivers: WARN the real chat_send_button tap '
      'did not deliver after 3 attempts — falling back to l3_composer_send (the '
      'identical production _submitTextMessage path). This is the documented '
      'compact-phone synthetic-tap limitation, not a delivery failure yet.',
    );
    try {
      await a.l3('l3_composer_send', {'text': text});
    } on DriveError catch (e) {
      print(
        '[pair] mobile_composer_send_delivers: send seam failed: ${e.message}',
      );
    }
    sent = await _msWaitOwnSent(a, text);
  }
  if (!sent) {
    print('[pair] mobile_composer_send_delivers: the message never left A');
    return false;
  }
  final received = await _waitC2cMessageText(
    b,
    toxA,
    text,
    isSelf: false,
    timeoutSecs: 60,
  );
  await a.shot('/tmp/ui_mobile_send_A.png');
  print(
    '[pair] mobile_composer_send_delivers: sendPath=$sendPath '
    'receivedByPeer=$received',
  );
  return received;
}

/// Poll until the composed [text] shows up as A's own last message.
Future<bool> _msWaitOwnSent(Inst inst, String text) async {
  for (var poll = 0; poll < 10; poll++) {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (await _anyConversationLastMessageIs(inst, text)) return true;
  }
  return false;
}

// ===========================================================================
// mobile_message_long_press_menu — the MOBILE trigger for the message menu
// ===========================================================================
/// On the mobile shell the message action menu opens via LONG-PRESS
/// (`_onLongPressMessageOnMobile` on the bubble's GestureDetector); on desktop
/// it is a right-click (`chat_msg_menu_surface` covers that). This case drives
/// the mobile trigger with a genuine touch down -> hold -> up (`ui_long_press`,
/// 800 ms — past both the 500 ms framework deadline and the fork's 650 ms
/// recognizer) and asserts the real menu items mounted.
///
/// The menu lives in an `Overlay.insert` entry that flutter_skill does not
/// traverse, so presence is read with `waitKeyCenter` (the element-tree walk),
/// exactly like the desktop menu case.
Future<bool?> _msMessageLongPressMenu(Inst a, String toxB) async {
  // Gated on a MOBILE PLATFORM + the compact shell, not on width alone: UIKit
  // picks the long-press builder from its own `deviceScreenType` classifier, so
  // a merely narrowed DESKTOP window may still build the right-click desktop
  // menu. Asserting the mobile trigger there would be a false red.
  if (!a.isMobileShell || !await _msPhoneShell(a)) {
    print(
      '[pair] mobile_message_long_press_menu: SKIP — the long-press menu path '
      '(_onLongPressMessageOnMobile) is only built on the compact MOBILE shell '
      '(platform=${a.platform}); a desktop/wide shell opens the same menu by '
      'right-click, covered by chat_msg_menu_surface',
    );
    return null;
  }
  final text = 'RUIMOB-MENU-${DateTime.now().microsecondsSinceEpoch}';
  final msgId = await _sendAndIdentify(a, toxB, text);
  if (msgId == null) {
    print(
      '[pair] mobile_message_long_press_menu: could not send/identify an own '
      'message to long-press',
    );
    return false;
  }
  final rowKey = 'message_list_item:$msgId';
  if (!await a.waitKey(rowKey, timeoutSecs: 8)) {
    print('[pair] mobile_message_long_press_menu: row $rowKey not present');
    return false;
  }
  final rowCenter = await a.keyCenter(rowKey);
  // A SELF bubble is right-aligned inside the row, so the row's geometric centre
  // can be empty space. Bias the press toward the right portion of the row (and
  // cover the centre / left as a fallback), mirroring the desktop menu opener's
  // live-probed factors.
  const biasFactor = <double>[1.24, 1.32, 1.12, 1.0, 0.6];
  var opened = false;
  for (var attempt = 0; attempt < biasFactor.length && !opened; attempt++) {
    final bias = biasFactor[attempt];
    try {
      if (rowCenter != null && bias != 1.0) {
        final r = await a.l3('ui_long_press', {
          'x': '${rowCenter.x * bias}',
          'y': '${rowCenter.y}',
          'holdMs': '800',
        });
        if (r['ok'] != true) {
          print(
            '[pair] mobile_message_long_press_menu: ui_long_press warn: $r',
          );
        }
      } else {
        await a.longPressKey(rowKey);
      }
    } on DriveError catch (e) {
      print(
        '[pair] mobile_message_long_press_menu: long-press warn: ${e.message}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    opened =
        await a.waitKeyCenter('message_menu_item:copy', timeoutSecs: 3) ||
        await a.waitKeyCenter('message_menu_item:delete', timeoutSecs: 2);
  }
  if (!opened) {
    await a.shot('/tmp/ui_mobile_longpress_fail_${a.name}.png');
    print(
      '[pair] mobile_message_long_press_menu: the mobile menu did not open for '
      '$rowKey (rowCenter=$rowCenter)',
    );
    return false;
  }
  final hasCopy = await a.waitKeyCenter(
    'message_menu_item:copy',
    timeoutSecs: 3,
  );
  final hasDelete = await a.waitKeyCenter(
    'message_menu_item:delete',
    timeoutSecs: 3,
  );
  await a.shot('/tmp/ui_mobile_longpress_menu_${a.name}.png');
  // Dismiss via the overlay's full-screen barrier (a tap outside the menu runs
  // `_cancelMobileMessageActions`). Escape is a no-op on mobile.
  var closed = false;
  for (var i = 0; i < 2 && !closed; i++) {
    await _dismissMessageMenu(a);
    closed = await a.keyCenter('message_menu_item:copy') == null;
  }
  print(
    '[pair] mobile_message_long_press_menu: copy=$hasCopy delete=$hasDelete '
    'dismissed=$closed',
  );
  return hasCopy && hasDelete;
}

// ===========================================================================
// tablet_master_detail_row_opens_chat — the TABLET-ONLY two-pane binding
// ===========================================================================
/// In the master-detail tier the conversation LIST stays on screen and a row tap
/// binds the chat into the RIGHT pane; on a compact phone the same tap pushes a
/// full-screen chat route that COVERS the list. Both report the same
/// `currentConversation` in the dump, so the data layer cannot tell them apart —
/// the discriminator has to be geometric.
///
/// SELF-CALIBRATING GEOMETRY (no hardcoded screen size, which is unreadable on
/// iOS: `l3_window_state` is desktop/window_manager-only and osascript cannot
/// see the Simulator): after the row tap, compare the on-screen centre x of the
/// conversation ROW with that of the chat composer. Two panes => the composer
/// sits well to the RIGHT of the list row. A pushed full-screen chat => both are
/// centred on the same viewport and the delta collapses to ~0.
///
/// SKIPs when the shell is not master-detail (compact phone / the 720..800 band).
Future<bool?> _msTabletMasterDetailRow(Inst a, String toxB) async {
  await a.foreground();
  await returnToChatsHome(a, rounds: 4);
  if (!await _msWideShell(a)) {
    print(
      '[pair] tablet_master_detail_row_opens_chat: SKIP — the shell is not in '
      'the master-detail tier (homeShellShouldShowMasterDetail != true), so '
      'there is no right pane to bind; a compact phone pushes a full-screen '
      'chat route instead (covered by chat_open_from_row)',
    );
    return null;
  }
  if (!await _seedConvRow(a, toxB)) {
    print(
      '[pair] tablet_master_detail_row_opens_chat: could not seed a C2C row',
    );
    return false;
  }
  await returnToChatsHome(a, rounds: 4);
  final rowKey = _convRowKey(toxB);
  final convId = _c2cConvId(toxB);
  if (!await a.waitKey(rowKey, timeoutSecs: 8)) {
    print(
      '[pair] tablet_master_detail_row_opens_chat: row $rowKey not present',
    );
    return false;
  }
  var bound = false;
  for (var attempt = 0; attempt < 3 && !bound; attempt++) {
    if (!await a.tapKeyCenter(rowKey, timeoutSecs: 3)) {
      await a.tryTapKey(rowKey, retries: 1);
    }
    bound = await _chatSurfaceReady(a, convId, timeoutSecs: 8);
  }
  if (!bound) {
    print(
      '[pair] tablet_master_detail_row_opens_chat: the row tap did not bind '
      '$convId to the chat surface',
    );
    return false;
  }
  final composer = await a.keyCenter('chat_input_text_field');
  final rowAfter = await a.keyCenter(rowKey);
  await a.shot('/tmp/ui_tablet_master_detail_${a.name}.png');
  if (composer == null || rowAfter == null) {
    print(
      '[pair] tablet_master_detail_row_opens_chat: could not resolve the pane '
      'anchors (composer=$composer row=$rowAfter)',
    );
    return false;
  }
  final dx = composer.x - rowAfter.x;
  // 60pt is a deliberately loose floor: any genuine two-pane split puts the
  // composer hundreds of points right of the list, while a single-pane push
  // gives ~0. It is NOT a pixel-perfect layout assertion.
  final split = dx > 60;
  print(
    '[pair] tablet_master_detail_row_opens_chat: rowCenterX=${rowAfter.x} '
    'composerCenterX=${composer.x} dx=$dx split=$split',
  );
  return split;
}

// ===========================================================================
// dialog_width_form_factor_tier — the per-form-factor dialog width caps
// ===========================================================================
/// `add_friend_dialog.dart` / `add_group_dialog.dart` each pick a dialog width
/// from a per-form-factor cap (mobile 480/560 vs tablet-desktop 720/820, minus
/// the viewport inset). Nothing in the suite ever checked that a tablet actually
/// gets the wide cap — the dialogs were only ever opened for their FORM content.
///
/// MEASUREMENT (again self-calibrating; there is no readable screen size on
/// iOS). Both dialogs put a full-width id `TextFormField` in the body and a
/// trailing Paste `IconButton` in that field's `suffixIcon`. The horizontal
/// distance between the field's centre and the paste button's centre is
/// therefore (field width / 2) minus a fixed icon inset — i.e. it scales
/// linearly with the dialog width and needs no absolute screen reference.
///
/// Derived from the widget source (dialog width minus the body padding):
///   * phone (iPhone-class, <=480/560 cap): span ~110..150pt
///   * tablet/desktop (720/820 cap):        span ~280..390pt
/// The gate uses a wide margin around that gap (>=200 wide, <=190 compact) so it
/// discriminates the TIER, not a pixel-exact layout.
///
/// WHICH TIER TO EXPECT is deliberately NOT read from the home-shell width
/// alone: `_dialogMaxWidth` branches on `ResponsiveLayout.isDesktop`, which is
/// PLATFORM-driven (true on every desktop OS at any window width) and also true
/// for tablets (`isTablet -> isDesktop`), whereas the home shell's bottom-nav /
/// master-detail tiers are pure WIDTH checks. Mapping straight from the shell
/// width would fail a narrowed desktop window (bottom-nav shell, desktop dialog
/// cap). The resolution below mirrors the dialog's own branching.
///
/// KNOWN AMBIGUITY (documented, not silently ignored): a LANDSCAPE phone has a
/// master-detail-wide shell but still takes the MOBILE dialog cap
/// (`shortestSide < 600`), and neither the dump nor the ui_* tools expose the
/// shortest side, so it would be misread as a tablet. The harness never rotates
/// a simulator (the launchers boot the default portrait orientation and
/// `TOXEE_IOS_DEVICE_TYPE=tablet` is what selects an iPad), so this cannot occur
/// in the wired campaigns; if a rotated run is ever added, this case must gain a
/// real device-class signal instead of the width heuristic.
///
/// The add-GROUP measurement is advisory-with-gate: it is asserted when the
/// dialog opened and both anchors resolved, and downgraded to a printed WARN
/// otherwise (its open path is new here, and a harness miss must not manufacture
/// a red). The add-FRIEND measurement is the hard gate — it uses the same
/// `_openAddFriendDialog` helper the passing contacts cases use.
Future<bool?> _msDialogWidthFormFactorTier(Inst a) async {
  await a.foreground();
  await returnToChatsHome(a, rounds: 4);
  final wideShell = await _msWideShell(a);
  final phoneShell = await _msPhoneShell(a);
  final bool wide;
  if (!a.isMobileShell) {
    // Desktop OS: `isDesktop(context)` is true at ANY window width, so the
    // dialog always takes the desktop cap — even in a narrowed bottom-nav window.
    wide = true;
  } else if (phoneShell && !wideShell) {
    wide = false;
  } else if (wideShell && !phoneShell) {
    wide = true;
  } else {
    print(
      '[pair] dialog_width_form_factor_tier: SKIP — ambiguous form factor on a '
      'mobile platform (bottomNav=$phoneShell masterDetail=$wideShell): the '
      'dialog cap branches on shortestSide/platform, which this harness cannot '
      'read, so no expectation can be asserted honestly',
    );
    return null;
  }
  final tier = wide ? 'wide(tablet/desktop)' : 'compact(phone)';
  if (!await _openAddFriendDialog(a)) {
    print(
      '[pair] dialog_width_form_factor_tier: add-friend dialog did not open',
    );
    return false;
  }
  final friendSpan = await _msDialogSpan(
    a,
    'add_friend_id_input',
    'add_friend_paste_button',
  );
  await a.shot('/tmp/ui_dialog_tier_friend_${a.name}.png');
  await _closeAddFriendDialog(a);
  if (friendSpan == null) {
    print(
      '[pair] dialog_width_form_factor_tier: SKIP — could not resolve the '
      'add-friend field/paste anchors (ui_key_center), so no width can be '
      'measured on this build',
    );
    return null;
  }
  final friendOk = wide ? friendSpan >= 200 : friendSpan <= 190;

  var groupOk = true;
  final groupSpan = await _msMeasureAddGroupDialog(a);
  if (groupSpan == null) {
    print(
      '[pair] dialog_width_form_factor_tier: WARN the add-group dialog could '
      'not be opened/measured — reporting the add-friend tier only (not counted '
      'as a failure)',
    );
  } else {
    groupOk = wide ? groupSpan >= 200 : groupSpan <= 190;
  }
  print(
    '[pair] dialog_width_form_factor_tier: tier=$tier '
    'addFriendSpan=$friendSpan (ok=$friendOk) '
    'addGroupSpan=$groupSpan (ok=$groupOk)',
  );
  return friendOk && groupOk;
}

/// Open the AddGroupDialog, measure its width proxy, close it again. Null when
/// the dialog could not be opened or its anchors did not resolve (the caller
/// downgrades that to a printed WARN rather than a failure).
Future<double?> _msMeasureAddGroupDialog(Inst inst) async {
  if (!await _msOpenAddGroupDialog(inst)) return null;
  final span = await _msDialogSpan(
    inst,
    'add_group_join_id_input',
    'add_group_join_paste_button',
  );
  await inst.shot('/tmp/ui_dialog_tier_group_${inst.name}.png');
  await _msCloseAddGroupDialog(inst);
  return span;
}

/// Horizontal distance between a dialog id field's centre and its trailing
/// paste button's centre — a screen-size-free proxy for the dialog's width.
/// Null when either anchor cannot be resolved on-screen.
Future<double?> _msDialogSpan(
  Inst inst,
  String fieldKey,
  String pasteKey,
) async {
  if (!await inst.waitKeyCenter(fieldKey, timeoutSecs: 8)) return null;
  final field = await inst.keyCenter(fieldKey);
  final paste = await inst.keyCenter(pasteKey);
  if (field == null || paste == null) return null;
  return paste.x - field.x;
}

/// Open the REAL AddGroupDialog through the conversation-list "+" popup
/// (`new_entry_menu_button` -> `new_entry_create_group_item`). Falls back to the
/// UNGATED `l3_open_add_group_dialog` invoker (the same production dialog) for
/// NAVIGATION STABILITY only — the asserted work is the geometry read afterwards.
Future<bool> _msOpenAddGroupDialog(Inst inst) async {
  if (await inst.waitKey('add_group_join_id_input', timeoutSecs: 1)) {
    return true;
  }
  await ensureNewEntryShell(inst);
  for (var attempt = 0; attempt < 2; attempt++) {
    await inst.foreground();
    // The "+" popup opens from flutter_skill's DIRECT onTap invocation
    // (`tryTapKey`); a coordinate tap does not trigger `showButtonMenu` — the
    // live-diagnosed recipe the app-entry case documents.
    if (!await inst.tryTapKey('new_entry_menu_button', retries: 2)) {
      await _tryTapText(inst, 'New Chat');
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!await inst.tryTapKey('new_entry_create_group_item', retries: 2)) {
      await _tryTapText(inst, 'Create Group');
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (await inst.waitKey('add_group_join_id_input', timeoutSecs: 3)) {
      return true;
    }
  }
  try {
    final r = await inst.l3('l3_open_add_group_dialog');
    if (r['ok'] != true) return false;
  } on DriveError catch (e) {
    print('[pair] mobile-shell: l3_open_add_group_dialog failed: ${e.message}');
    return false;
  }
  return inst.waitKey('add_group_join_id_input', timeoutSecs: 8);
}

/// Dismiss the AddGroupDialog. The keyed AppDialog close (X) button is the
/// affordance a mobile user taps — Escape is a host-keyboard chord that never
/// reaches the Simulator / device.
Future<void> _msCloseAddGroupDialog(Inst inst) async {
  if (!await inst.waitKey('add_group_join_id_input', timeoutSecs: 1)) return;
  if (!await inst.tapKeyCenter('add_group_close_button', timeoutSecs: 6)) {
    try {
      await inst.osaEscape();
    } on DriveError {
      // best-effort — the waitKeyGone below reports the real outcome.
    }
  }
  final gone = await inst.waitKeyGone(
    'add_group_join_id_input',
    timeoutSecs: 6,
  );
  if (!gone) {
    print('[pair] mobile-shell: WARN the add-group dialog did not dismiss');
  }
}
