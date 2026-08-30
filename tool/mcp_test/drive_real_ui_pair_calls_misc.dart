// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Batch 8 of the real-UI sweep campaign — "Calls + misc" (11 cases, FINAL write
// batch). See tool/mcp_test/REAL_UI_GATES.md.
//
// `sweep_calls_misc` drives BOTH instances. ONE handshake at the top establishes
// the A<->B friendship; the call cases CHAIN the live call state efficiently
// (a voice block then a video block) so the campaign reuses ringing/inCall
// transitions instead of tearing every call fully down between cases:
//
//   86 mute-toggle-in-voice-call  — B calls A, A accepts, DON'T hang up →
//        toggle `call_mic_mute_button`; `call.isMuted` flips both ways.
//   89 callee-hangup — A ends the SAME call (`call_hangup_button`) → idle.
//   90 call-record-bubble-renders — that completed call's `call_record`
//        bubble renders in A's chat history.
//   88 missed-record              — B calls A and cancels BEFORE A answers →
//        A's missed-call record (`actionType==2` cancel) renders.
//   85 video-accept-hangup — video button → accept → inCall video → hangup.
//   87 camera-toggle-in-video-call— same call: `call_camera_toggle_button`,
//        `call.isVideoEnabled` flips both ways.
//   87b camera-switch-in-video-call — same call: desktop asserts the switch
//        button ABSENT; Android/iOS REAL-tap it, `call.cameraLens` flips.
//
// Then the misc cases (single-instance unless noted):
//   91 home-tabs-cycle            — tab round-trip with a chat open; the
//        IndexedStack retains it (offstage-aware waits).
//   92 theme-switch-chat-open     — open the C2C chat, flip dark/light via the
//        real settings control, assert the chat re-renders (bubbles intact + no
//        crash), flip back.
//   94 search-window-open        — seed a unique term, global search
//        (Cmd+Ctrl+F) → result row → tap → SearchChatHistoryWindow mounts.
//   93 window-resize-responsive  — LAST. Narrow past the 720pt breakpoint
//        (osascript) → `home_bottom_nav` appears → restore. SKIP if refused.
//
// State contract (fixture_c_unified_runner.dart): required=no-friend (own
// handshake via `_establishFriendshipForSweep`) / result=friends (nothing
// deletes the friend; the end-guard lands home + recomputes endFriends).
//
// CALL-ISOLATION DISCIPLINE: every call case asserts BOTH sides idle before
// the next call begins (the "double-invite miscount" lesson); the voice and
// video blocks each settle to idle first — `_ensureBothIdle` is the guard.
//
// CALL DOCK KEYS (verified in the fork + lib/call):
//   - chat header start buttons: `chat_call_voice_button` / `chat_call_video_button`
//     (tencent_cloud_chat_message_header_actions.dart).
//   - incoming-call dock: `call_accept_button` / `call_decline_button`
//     (incoming_call_view.dart → UiKeys.callAcceptButton / callDeclineButton).
//   - in-call dock: `call_mic_mute_button` / `call_camera_toggle_button` (video
//     only) / `call_hangup_button` (in_call_view.dart → UiKeys.call*).
// All are CallDockAction keys plumbed onto the actual tappable InkWell
// (call_ui_components.dart:386), so flutter_skill/find.byKey lands them.

/// Read a sub-field of the dump `call` object (e.g. `isMuted`, `isVideoEnabled`,
/// `mode`), or null when there is no live call state.
Future<Object?> _callField(Inst inst, String field) async {
  final s = await inst.dumpState();
  final call = (s['call'] as Map?)?.cast<String, dynamic>();
  return call?[field];
}

/// Poll until [inst]'s dump `call.<field>` equals [want] (no throw).
Future<bool> _waitCallField(
  Inst inst,
  String field,
  Object? want, {
  int timeoutSecs = 12,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _callField(inst, field) == want) return true;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

/// Both peers must be back to idle before the next call case begins (the
/// call-isolation lesson). Best-effort hangs up any lingering call on each side,
/// then waits for idle. Returns whether BOTH reached idle.
Future<bool> _ensureBothIdle(Inst a, Inst b, {int timeoutSecs = 15}) async {
  for (final inst in [a, b]) {
    final st = await _callState(inst);
    if (st != null && st != 'idle') {
      await inst.foreground();
      await inst.tryTapKey('call_hangup_button', retries: 2);
    }
  }
  final aIdle = await _waitCallStateAny(a, {'idle'}, timeoutSecs: timeoutSecs);
  final bIdle = await _waitCallStateAny(b, {'idle'}, timeoutSecs: timeoutSecs);
  return aIdle && bIdle;
}

// ===========================================================================
// case 91 — home_tabs_cycle_state_retained  [single-instance]
// ===========================================================================
/// Read the home shell's snapshot of the OPEN chat-tab conversation id
/// (`homeShellCurrentConversationId`) — the value the chats tab's IndexedStack
/// branch holds, distinct from the live `currentConversation` which a tab swap
/// to contacts/settings changes. Null when the chats tab has no open detail.
Future<String?> _homeShellCurrentConversationId(Inst inst) async {
  final s = await inst.dumpState();
  return s['homeShellCurrentConversationId']?.toString();
}

/// Open the C2C chat, then cycle chats→contacts→settings→chats by tapping the
/// REAL home tabs (a plain IndexedStack `_index` setState — NOT
/// `_forceHomeRootAndWait`, which RESETS the chats-tab detail and would make the
/// retention assertion vacuous; codex P1). Assert the IndexedStack RETAINS the
/// open chat: `homeShellCurrentConversationId` stays the C2C id THROUGH the
/// contacts/settings detour AND is still the C2C id after returning to chats,
/// where the chat surface re-renders WITHOUT any re-open. Drives the production
/// tab widgets (sidebar rail or bottom nav — see [_tapHomeTabUntil]); reads the
/// home-shell snapshot.
///
/// SKIPs (null) when the shell is NOT master-detail. The premise is a chat
/// bound into the RETAINED chats-tab branch, which only exists on the wide
/// (>=800pt) layout: "Mobile pushes a ChatPage route instead of binding the
/// pane" (home_page_bootstrap.dart:439). On a compact shell the open chat is a
/// route ABOVE the home Scaffold, so (a) there is no tab-branch detail to
/// retain and (b) the tab bar is covered — a tab tap would land on the chat
/// route. Asserting there would be a false red, and "passing" it would prove
/// nothing. Read from the live `homeShellShouldShowMasterDetail` (the shell's
/// OWN computed value) rather than the platform, so an iPad/wide window runs it
/// and a narrowed desktop window skips it, correctly.
Future<bool?> _homeTabsCycleStateRetained(Inst inst, String toxB) async {
  final masterDetail =
      (await inst.dumpState())['homeShellShouldShowMasterDetail'] == true;
  if (!masterDetail) {
    print(
      '[pair] home_tabs_cycle_state_retained: SKIP — this shell is not '
      'master-detail (homeShellShouldShowMasterDetail=false), so the chat '
      'opens as a PUSHED route over the home Scaffold: there is no retained '
      'chats-tab detail to assert and the tab bar is covered while it is up',
    );
    return null;
  }
  final c2c = 'c2c_${_pubkey(toxB)}';
  // Open the chat so the chats-tab IndexedStack branch holds a detail.
  await openChat(inst, _pubkey(toxB));
  final openConv = await _homeShellCurrentConversationId(inst);
  if (openConv != c2c) {
    print(
      '[pair] home_tabs_cycle: chat did not open '
      '(homeShellCurrentConversationId=$openConv)',
    );
    return false;
  }
  // Tap the REAL sidebar Contacts tab (IndexedStack index switch). The chats
  // tab branch is KEPT ALIVE off-stage, so its open-chat detail must survive.
  // A synthetic center-tap on the sidebar tab occasionally doesn't fire its
  // onTap on the headless Windows VM, so re-tap until the shell tab switches
  // (still the production tab widget — retention assertion stays valid).
  final onContacts = await _tapHomeTabUntil(
    inst,
    'sidebar_contacts_tab',
    'contacts',
  );
  final retainedThroughContacts =
      await _homeShellCurrentConversationId(inst) == c2c;
  final onSettings = await _tapHomeTabUntil(
    inst,
    'sidebar_settings_tab',
    'settings',
  );
  final retainedThroughSettings =
      await _homeShellCurrentConversationId(inst) == c2c;
  // Tap back to the REAL sidebar Chats tab — the retained IndexedStack branch
  // re-stages the SAME open chat WITHOUT re-opening it.
  final onChats = await _tapHomeTabUntil(inst, 'sidebar_chats_tab', 'chats');
  // The retained chat detail surfaces with NO re-open — assert the chat surface
  // is ready AND the open conversation is still the C2C one.
  final retained =
      onChats &&
      await _homeShellCurrentConversationId(inst) == c2c &&
      await _chatSurfaceReady(inst, c2c, timeoutSecs: 8);
  await inst.shot('/tmp/ui_b8_tabs_${inst.name}.png');
  await returnToChatsHome(inst, rounds: 4);
  print(
    '[pair] home_tabs_cycle: onContacts=$onContacts '
    'retainedThroughContacts=$retainedThroughContacts onSettings=$onSettings '
    'retainedThroughSettings=$retainedThroughSettings onChats=$onChats '
    'retained=$retained',
  );
  return onContacts &&
      retainedThroughContacts &&
      onSettings &&
      retainedThroughSettings &&
      retained;
}

/// True when the COMPACT phone shell is up: HomePage's bottom navigation bar
/// (`UiKeys.homeBottomNav`) resolves to a laid-out RenderBox. That bar renders
/// ONLY under `ResponsiveLayout.shouldShowBottomNav` (< 720pt), so its presence
/// IS the tier signal — a LAYOUT check, not a platform check, which is what the
/// tab-key choice must key off: an iPad (or any >=720pt shell) is `isMobileShell`
/// yet still renders the sidebar rail, and a narrowed DESKTOP window renders the
/// bottom nav. Mirrors `_msPhoneShell` in drive_real_ui_pair_mobile_shell.dart.
Future<bool> _homeShellHasBottomNav(Inst inst) async =>
    await inst.keyCenter('home_bottom_nav') != null;

/// The bottom-nav twin of a `sidebar_*_tab` key, or null when there is none.
String? _bottomNavTwinOf(String sidebarTabKey) => switch (sidebarTabKey) {
  'sidebar_chats_tab' => 'bottom_nav_chats_tab',
  'sidebar_contacts_tab' => 'bottom_nav_contacts_tab',
  'sidebar_settings_tab' => 'bottom_nav_settings_tab',
  _ => null,
};

/// Tap a home tab and wait for the shell tab to switch, re-tapping if a
/// synthetic center-tap didn't fire the tab's onTap (headless Windows). Returns
/// true once the shell reports [tab]. Tapping a tab you're already on is a no-op,
/// so the retries are safe.
///
/// SHELL-AWARE TAB KEY: the compact phone shell renders NO sidebar — the same
/// IndexedStack index is switched by `bottom_nav_*_tab` items instead. Passing
/// only `sidebar_*_tab` there made `tapKeyCenter` fail on the very first attempt
/// and the case returned false before any retention could be asserted. Resolve
/// the twin key by LAYOUT (bottom nav present?), not by platform, and keep both
/// as fallbacks so a mid-run resize/rotation can't strand the loop. Same
/// dual-path shape as `_selectChatsTab` / `_selectContactsTab` in
/// drive_real_ui_pair_shell.dart.
Future<bool> _tapHomeTabUntil(Inst inst, String tabKey, String tab) async {
  final twin = _bottomNavTwinOf(tabKey);
  final preferTwin = twin != null && await _homeShellHasBottomNav(inst);
  // The `twin != null` repeats are load-bearing: a `bool` local does not promote
  // `twin`, so the collection-if needs the null test inline to yield String.
  final keys = <String>[
    if (twin != null && preferTwin) twin,
    tabKey,
    if (twin != null && !preferTwin) twin,
  ];
  for (var attempt = 0; attempt < 5; attempt++) {
    // Foreground first: after the in-call cases the window can lose focus, so a
    // synthetic tab tap silently misses until the app window is active again.
    await inst.foreground();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    var tapped = false;
    for (final key in keys) {
      // Full timeout for the shell's EXPECTED key; a short one for the other
      // shell's key so a genuinely-failing desktop run isn't slowed by five
      // 6-second waits on a bottom nav that this shell never renders.
      final first = key == keys.first;
      if (await inst.tapKeyCenter(key, timeoutSecs: first ? 6 : 2)) {
        tapped = true;
        break;
      }
    }
    if (!tapped) {
      print('[pair] home_tabs_cycle: no tappable tab among $keys');
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (await _waitHomeShellTab(inst, tab, timeoutSecs: 3)) return true;
  }
  return false;
}

/// Poll until the home shell's tab equals [tab] ('chats'|'contacts'|'settings').
Future<bool> _waitHomeShellTab(
  Inst inst,
  String tab, {
  int timeoutSecs = 6,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _homeShellTab(inst) == tab) return true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

// ===========================================================================
// case 92 — theme_switch_chat_open (S57)  [two-process state, drives A only]
// ===========================================================================
/// With the C2C chat OPEN, flip the theme dark→light via the REAL settings
/// Appearance control, then assert the chat re-renders intact (the composer +
/// at least one bubble survive the rebuild, no crash) and the dump themeMode
/// persisted. Flip back to the original mode at the end (poison guard).
Future<bool> _themeSwitchChatOpen(Inst inst, String toxB) async {
  // Seed at least one bubble so "bubbles intact after rebuild" is assertable.
  await openChat(inst, _pubkey(toxB));
  final seedText = 'B8THEME-${DateTime.now().microsecondsSinceEpoch}';
  final seeded = await sendComposerMessage(inst, seedText);
  final c2c = 'c2c_${_pubkey(toxB)}';
  if (!seeded) {
    print('[pair] theme_switch_chat_open: could not seed a bubble');
    return false;
  }
  final originalMode =
      (await inst.dumpState())['themeMode']?.toString() ?? 'system';
  // Pick the flip target distinct from the current rendered brightness.
  final flipTo = originalMode == 'dark' ? 'Light' : 'Dark';
  final flipMode = flipTo == 'Dark' ? 'dark' : 'light';
  // Flip the theme via the real Appearance segment (settings), then return to
  // the chat and assert it re-rendered intact.
  await _openSettings(inst);
  final flipped = await _tapThemeSegment(inst, flipTo);
  final persisted =
      flipped && await _waitStringState(inst, 'themeMode', flipMode);
  // Re-open the chat — it must still render (composer + the seeded bubble).
  // Use the robust multi-strategy `openChat` (ready-check → conv-list tap →
  // returnToChatsHome+tap → l3 deep-link fallback), not
  // `_reopenChatFromConversationList`: the latter relies on a flutter_skill
  // `tapKey('conversation_list_item:…')` that doesn't reliably land + a
  // test-gated `clearActiveConversation` (refused on the restored non-test
  // accounts), so the chat never reopened (root-caused live: chatReady=false
  // even individually, though the theme flip itself worked).
  await returnToChatsHome(inst, rounds: 4);
  await openChat(inst, _pubkey(toxB));
  final chatReady = await _chatSurfaceReady(inst, c2c, timeoutSecs: 10);
  // BUBBLE INTACT = the seeded message's actual chat-surface ROW renders after
  // the theme rebuild (codex P1: `_lastMessage` reads the conversation-LIST
  // preview text, NOT the open chat surface — a broken bubble render would still
  // pass). Resolve the own message's msgID and assert `message_list_item:<id>`
  // is in the tree.
  var bubbleIntact = false;
  if (chatReady) {
    final msgId = await _ownMessageId(inst, toxB, seedText);
    if (msgId != null) {
      bubbleIntact = await inst.waitKey(
        'message_list_item:$msgId',
        timeoutSecs: 8,
      );
    }
  }
  final alive = (await inst.dumpState())['sessionReady'] == true;
  await inst.shot('/tmp/ui_b8_theme_${inst.name}.png');
  // Restore the original theme (poison guard for later cases).
  await _openSettings(inst);
  final restoreLabel = originalMode == 'dark'
      ? 'Dark'
      : (originalMode == 'light' ? 'Light' : 'System');
  await _tapThemeSegment(inst, restoreLabel);
  await _waitStringState(inst, 'themeMode', originalMode);
  await returnToChatsHome(inst, rounds: 4);
  print(
    '[pair] theme_switch_chat_open: originalMode=$originalMode flipTo=$flipMode '
    'flipped=$flipped persisted=$persisted chatReady=$chatReady '
    'bubbleIntact=$bubbleIntact alive=$alive',
  );
  return flipped && persisted && chatReady && bubbleIntact && alive;
}

// ===========================================================================
// case 94 — search_chat_history_window_open (S93)  [two-process state, drives A]
// ===========================================================================
/// Seed a UNIQUE message term in the C2C chat, open the GLOBAL search overlay
/// (Cmd+Ctrl+F — the only entry), type the term → the MESSAGE-result row
/// (`search_result_message_<convId>`) renders → tap it → the in-conversation
/// `SearchChatHistoryWindow` mounts ("Search Chat History" AppBar title).
Future<bool?> _searchChatHistoryWindowOpen(Inst inst, String toxB) async {
  final c2c = 'c2c_${_pubkey(toxB)}';
  // Seed a unique searchable term as a real message.
  await openChat(inst, _pubkey(toxB));
  final term = 'B8SEARCHTERM${DateTime.now().microsecondsSinceEpoch}';
  if (!await sendComposerMessage(inst, term)) {
    print('[pair] search_chat_history_window_open: could not seed search term');
    return false;
  }
  await returnToChatsHome(inst, rounds: 4);
  // Global search overlay via `_openGlobalSearch`; wide shells only (compact
  // shells SKIP). The asserted result-row tap stays a real gesture.
  if (await _noSearchOverlay(inst, 'search_chat_history_window_open')) {
    return null;
  }
  await inst.foreground();
  final searchOpened = await _openGlobalSearch(inst);
  if (!await inst.waitKey('message_search_field', timeoutSecs: 10)) {
    print(
      '[pair] search_chat_history_window_open: search overlay did not open '
      '(opener reported $searchOpened)',
    );
    return false;
  }
  await inst.focusType('message_search_field', term);
  await Future<void>.delayed(const Duration(milliseconds: 900));
  // The MESSAGE-result row keyed by the conversation id must render (the chat
  // history match surface). Wait through the 300ms debounce + FFI search.
  final resultKey = await _c2ceFirstVisibleKey(inst, [
    'search_result_message_$c2c',
    'search_result_message:$c2c',
  ]);
  final resultRow = resultKey != null;
  var windowOpened = false;
  if (resultKey != null) {
    // Tap the result → the in-conversation SearchChatHistoryWindow opens.
    await inst.tapKeyCenter(resultKey, timeoutSecs: 6);
    // The window's AppBar title is "Search Chat History" (distinct from the
    // global overlay, which shares message_search_field).
    windowOpened = await inst.waitText('Search Chat History', timeoutSecs: 8);
  }
  await inst.shot('/tmp/ui_b8_search_${inst.name}.png');
  // Close everything back to the chats home. Tapping the result pushes the
  // SearchChatHistoryWindow as a ROUTE (it carries its own message_search_field),
  // and Escape does NOT pop a pushed route — so pop it via the "<" back
  // affordance FIRST, then Escape the underlying global overlay. (A plain
  // Escape loop left message_search_field present → closed=false.)
  for (var i = 0; i < 4; i++) {
    if (!await inst.waitKey('message_search_field', timeoutSecs: 1)) break;
    try {
      await _popSearchLayerBack(inst);
    } on DriveError {
      // best-effort
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!await inst.waitKey('message_search_field', timeoutSecs: 1)) break;
    try {
      await inst.osaEscape();
    } on DriveError {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  await returnToChatsHome(inst, rounds: 4);
  final closed = await inst.waitKeyGone('message_search_field', timeoutSecs: 4);
  print(
    '[pair] search_chat_history_window_open: resultRow=$resultRow '
    'windowOpened=$windowOpened closed=$closed',
  );
  return resultRow && windowOpened && closed;
}

/// Dismiss whichever search layer is on top: the global CustomSearch overlay
/// (its AppBar close "X" IS keyed — `UiKeys.messageSearchCloseButton`,
/// custom_search.dart:627/703) or the pushed SearchChatHistoryWindow (AppBar
/// leading BackButton, which carries NO key).
///
/// The window's back button is unkeyed, so it still needs a coordinate — but a
/// FIXED (28,72) was a 1280x768 desktop constant: the leading x is
/// layout-invariant (Material's NavigationToolbar reserves 56pt → centre 28),
/// while the y depends entirely on the status-bar inset (0 on desktop, 24 on
/// Android, 47-59 on a notched iPhone), so the desktop y could land below/above
/// the real button on mobile. Derive y from the window's OWN keyed search field
/// instead (it lives in the same AppBar's `bottom` band, ~52pt under the title
/// row), and only fall back to the desktop constant when nothing resolves.
Future<void> _popSearchLayerBack(Inst inst) async {
  // WHICH LAYER IS ON TOP matters: `ui_key_center` has no paint/cover guard, so
  // the COVERED global overlay's close button still resolves while the history
  // window is up — tapping its coordinate would land on the window's empty
  // AppBar trailing and pop nothing. The window's own AppBar title is the
  // unambiguous top-layer marker.
  if (await inst.waitText('Search Chat History', timeoutSecs: 1)) {
    final field = await inst.keyCenter('message_search_field');
    await inst.tapAt(
      28,
      field != null ? (field.y - 52).clamp(8.0, field.y) : 72,
    );
    return;
  }
  if (await inst.tapKeyCenter('message_search_close_button', timeoutSecs: 2)) {
    return;
  }
  await inst.tapAt(28, 72);
}

// ===========================================================================
// case 93 — window_resize_responsive (S60)  [single-instance; SKIP-able]
// ===========================================================================
/// Narrow the macOS window past the 720pt bottom-nav breakpoint via osascript,
/// then assert the MOBILE layout-swap signal (`home_bottom_nav` appears — it
/// renders ONLY when `shouldShowBottomNav`, a pure width check). While narrow,
/// also DRIVE the mobile bottom-nav routing (tap the Contacts item → homeShellTab
/// goes 'contacts', tap Chats → back to 'chats') so the swap isn't only proven
/// visually — the bottom nav actually NAVIGATES (codex P3 mobile-parity: the
/// desktop sidebar and the mobile bottom nav share the same `onTap` → `_index`
/// setState, so this exercises the mobile routing path the desktop harness can't
/// otherwise reach). Then restore the width and assert the bar is GONE. Returns:
///   - true  : the swap + bottom-nav routing worked in BOTH directions (PASS)
///   - false : the window resized but the swap/routing did NOT happen (FAIL —
///             a real bug)
///   - null  : the window refused scripted resize (SKIP(resize-refused) — the
///             raw-launched window can't be sized; never a fake pass)
Future<bool?> _windowResizeResponsive(Inst inst) async {
  // The window resize + size query + the min-size override all go through
  // l3_window_state, which is test-account-gated. Grant the seed marker for the
  // case's duration on BOTH platforms (the min-size override is needed on macOS
  // too — desktop_shell_bootstrap sets a 960x600 minimum for ALL desktop OSes,
  // which is ABOVE the 720 responsive breakpoint, so it clamps the narrow resize
  // on macOS AND Windows; the old "macOS osascript bypasses the min" claim was
  // wrong — the live run skipped on macOS too).
  final marked = await inst.markAccountTest();
  var loweredMin = false;
  try {
    if (marked) {
      // Lower the desktop min so a below-breakpoint width is reachable.
      final r = await inst.l3('l3_window_state', {
        'state': 'set_min',
        'width': '400',
        'height': '400',
      });
      loweredMin = r['ok'] == true;
    }
    if (!loweredMin) {
      print(
        '[pair] window_resize_responsive: could not lower window min-size '
        '(marked=$marked) — SKIP(min-not-lowered)',
      );
      return null;
    }
    return await _windowResizeResponsiveBody(inst);
  } finally {
    if (loweredMin) {
      // Restore the product default min (there is no getMinimumSize).
      try {
        await inst.l3('l3_window_state', {
          'state': 'set_min',
          'width': '960',
          'height': '600',
        });
      } on DriveError {
        /* best-effort */
      }
    }
    if (marked) await inst.unmarkAccountTest();
  }
}

Future<bool?> _windowResizeResponsiveBody(Inst inst) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  final original = await inst.windowSize();
  if (original == null) {
    print(
      '[pair] window_resize_responsive: window size unreadable — '
      'SKIP(resize-refused)',
    );
    return null;
  }
  // In desktop layout the bottom nav must be ABSENT to start.
  final beforeNav = await inst.waitKey('home_bottom_nav', timeoutSecs: 1);
  // Narrow well below the 720pt breakpoint.
  final narrowed = await inst.resizeWindow(560, original.h);
  if (!narrowed) {
    print(
      '[pair] window_resize_responsive: resize refused — SKIP(resize-refused)',
    );
    return null;
  }
  final applied = await inst.windowSize();
  // The OS may clamp the minimum width (window_manager min-size). If it didn't
  // actually narrow past the breakpoint, treat as SKIP (can't prove the swap).
  if (applied == null || applied.w >= 720) {
    // With the min-size already lowered to 400 by the caller, a still-clamped
    // width means the scripted resize itself flaked (osascript / window_manager
    // did not take), not the product min — SKIP rather than a false FAIL.
    print(
      '[pair] window_resize_responsive: width not applied past breakpoint '
      '(applied=$applied) even after lowering the min — SKIP(resize-flaked)',
    );
    // Restore best-effort before bailing.
    await inst.resizeWindow(original.w, original.h);
    return null;
  }
  // The mobile bottom nav must now appear (the responsive swap signal).
  final swapped = await inst.waitKey('home_bottom_nav', timeoutSecs: 8);
  await inst.shot('/tmp/ui_b8_resize_narrow_${inst.name}.png');
  // Drive the mobile bottom-nav ROUTING while narrow: tap Contacts → tab moves;
  // tap Chats → back. The items are Material `BottomNavigationBarItem`s (data, not
  // keyed widgets), so a label-TEXT tap does not reliably fire the bar's
  // index-based `onTap` (the tap target is the internal per-item InkResponse, not
  // the nested Text). Tap the item's KEYED ICON via `tapKeyCenter` — a real
  // coordinate pointer at the icon center lands inside that InkResponse and fires
  // `onTap(index)` (single fire; a double-tap would hit the already-active tab and
  // no-op). Assert homeShellTab actually changed.
  var navRouted = false;
  if (swapped) {
    await inst.tapKeyCenter('bottom_nav_contacts_tab', timeoutSecs: 6);
    final onContacts = await _waitHomeShellTab(
      inst,
      'contacts',
      timeoutSecs: 6,
    );
    await inst.tapKeyCenter('bottom_nav_chats_tab', timeoutSecs: 6);
    final backToChats = await _waitHomeShellTab(inst, 'chats', timeoutSecs: 6);
    navRouted = onContacts && backToChats;
    print(
      '[pair] window_resize_responsive: bottom-nav routing '
      'onContacts=$onContacts backToChats=$backToChats',
    );
  }
  // Restore the original width → the bottom nav must go away again.
  final restored = await inst.resizeWindow(original.w, original.h);
  final navGone =
      restored && await inst.waitKeyGone('home_bottom_nav', timeoutSecs: 8);
  await inst.shot('/tmp/ui_b8_resize_wide_${inst.name}.png');
  print(
    '[pair] window_resize_responsive: beforeNav=$beforeNav applied=$applied '
    'swapped=$swapped navRouted=$navRouted restored=$restored navGone=$navGone',
  );
  // PASS only if the swap happened both ways, the bottom nav actually NAVIGATED,
  // and the desktop layout had no bottom nav to begin with.
  return !beforeNav && swapped && navRouted && navGone;
}

// ===========================================================================
// sweep_calls_misc — Batch 8: chain all 11 calls/misc cases on ONE launch.
// ===========================================================================
/// Order (call-isolation + state-poison-aware): handshake once → voice block
/// (86 mute-toggle-in-call, leaves the call inCall → 89 callee-hangup ends it →
/// 90 call-record bubble reads the completed call) → 88 missed-record (B cancels
/// an unanswered ring) → video block (85 video-call + 87 camera-toggle +
/// 87b camera-switch, all DURING the same live video call) → misc (91
/// home-tabs-cycle → 92 theme-switch-with-chat-open → 94 search-window-open → 93
/// window-resize LAST, SKIP-able). The friendship is never deleted → ends
/// FRIENDS. A `finally` end-guard restores the window size + lands both home.
Future<int> runCallsMiscSweep(
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
    print('[sweep] sweep_calls_misc: missing tox ids (A=$toxA B=$toxB)');
    return 1;
  }
  print(
    '[sweep] sweep_calls_misc: A=${_shortId(toxA)} ($nickA) '
    'B=${_shortId(toxB)} ($nickB)',
  );

  var passed = 0;
  var failed = 0;
  var skipped = 0;
  final results = <String, String>{};
  var endFriends = false;

  Future<void> hard(String id, Future<bool> Function() run) async {
    bool ok;
    String? detail;
    try {
      ok = await run();
    } on PermissionBlockedError {
      rethrow;
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
  }

  /// A SKIP-able case (`bool?`): null → SKIP, false → FAIL, true → PASS.
  Future<void> soft(String id, Future<bool?> Function() run) async {
    bool? r;
    String? detail;
    try {
      r = await run();
    } on PermissionBlockedError {
      rethrow;
    } on DriveError catch (e) {
      r = false;
      detail = 'DriveError: ${e.message}';
    }
    if (r == null) {
      skipped++;
      results[id] = 'SKIP';
      print('[sweep] $id: SKIP');
    } else if (r) {
      passed++;
      results[id] = 'PASS';
      print('[sweep] $id: PASS');
    } else {
      failed++;
      results[id] = 'FAIL';
      print('[sweep] $id: FAIL${detail != null ? ' ($detail)' : ''}');
    }
  }

  const callCaseIds = <String>[
    'call_mute_toggle_incall',
    'call_callee_hangup',
    'call_record_bubble_renders',
    'call_missed_record_row',
    'call_video_accept_hangup',
    'call_camera_toggle_incall',
    'call_camera_switch_incall',
  ];

  try {
    // --- Establish the A<->B friendship (real-UI handshake) once. ---
    final friended = await _establishFriendshipForSweep(
      a,
      b,
      toxA,
      toxB,
      nickA,
      nickB,
    );
    if (!friended) {
      print('[sweep] sweep_calls_misc: handshake FAILED — no case can run');
      for (final id in const [
        ...callCaseIds,
        'home_tabs_cycle_state_retained',
        'theme_switch_chat_open',
        'search_chat_history_window_open',
        'window_resize_responsive',
      ]) {
        failed++;
        results[id] = 'FAIL';
      }
    } else {
      // Wait for connectivity + friend-online so the call signaling can reach
      // the peer (calls need a live transport, like runCallVoice).
      await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
      await b.waitState((s) => s['isConnected'] == true, label: 'B connected');
      // The very FIRST call races the friend-connection coming ONLINE after the
      // (norequest-seeded) friendship: isConnected is DHT-level, but a call needs
      // the PEER online. Warm up — poll the friend's online flag both ways — so
      // call_mute_toggle_incall doesn't fail on a cold start.
      Future<bool> friendOnline(Inst inst, String peerTox) async {
        final pk = _pubkey(peerTox);
        final friends =
            ((await inst.dumpState())['friends'] as List?) ?? const [];
        return friends.any(
          (f) =>
              f is Map &&
              _pubkey(f['userId']?.toString() ?? '') == pk &&
              f['online'] == true,
        );
      }

      for (var i = 0; i < 40; i++) {
        if (await friendOnline(a, toxB) && await friendOnline(b, toxA)) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      {
        // --- VOICE BLOCK: 86 (leaves inCall) → 89 (callee hangup) → 90 (record). ---
        // Snapshot the call-record baseline BEFORE the call so case 90 requires a
        // NEW record (codex P2 — a restored launch may carry stale records).
        final recordBaseline = await _callRecordCount(a, toxB);
        await hard(
          'call_mute_toggle_incall',
          () => _callMuteToggleIncall(a, b, toxA),
        );
        await hard('call_callee_hangup', () => _callCalleeHangup(a, b, toxA));
        await hard(
          'call_record_bubble_renders',
          () => _callRecordBubbleRenders(a, toxB, baseline: recordBaseline),
        );

        // --- 88: missed-call record (B cancels an unanswered ring). ---
        await hard(
          'call_missed_record_row',
          () => _callMissedRecordRow(a, b, toxA, toxB),
        );

        // --- VIDEO BLOCK: 85 + 87 driven together (camera toggle DURING the
        // same video call). Tally each separately. ---
        final video = await _callVideoWithCameraToggle(a, b, toxA);
        // A capability SKIP covers all THREE cases (no video entry point =
        // nothing to accept/toggle/switch); the switch leg can also SKIP
        // alone (single-camera device -> null).
        final videoSkip = video.skipReason;
        for (final (id, ok, legSkip) in [
          ('call_video_accept_hangup', video.videoCall, false),
          ('call_camera_toggle_incall', video.cameraToggle, false),
          (
            'call_camera_switch_incall',
            video.cameraSwitch ?? false,
            video.cameraSwitch == null,
          ),
        ]) {
          if (videoSkip != null || legSkip) {
            skipped++;
            results[id] = 'SKIP';
            print(
              '[sweep] $id: SKIP${videoSkip != null ? ' ($videoSkip)' : ''}',
            );
          } else if (ok) {
            passed++;
            results[id] = 'PASS';
            print('[sweep] $id: PASS');
          } else {
            failed++;
            results[id] = 'FAIL';
            print('[sweep] $id: FAIL');
          }
        }
        // Make sure no call lingers into the misc cases.
        await _ensureBothIdle(a, b);
      }

      // --- MISC: 91 → 92 → 94 → 93 (resize last). ---
      // 91 SKIPs on a non-master-detail shell (the chat is a pushed route
      // there — see the case doc), so it runs through `soft`, not `hard`.
      await soft(
        'home_tabs_cycle_state_retained',
        () => _homeTabsCycleStateRetained(a, toxB),
      );
      await hard('theme_switch_chat_open', () => _themeSwitchChatOpen(a, toxB));
      await soft(
        'search_chat_history_window_open',
        () => _searchChatHistoryWindowOpen(a, toxB),
      );
      await soft('window_resize_responsive', () => _windowResizeResponsive(a));
    }
  } finally {
    // END-STATE GUARD: best-effort restore the window to a desktop width + land
    // both on chats home. The friendship is never deleted, so the registered
    // result is FRIENDS — recompute it from the live state so the runner never
    // trusts an unachieved result.
    try {
      await _ensureBothIdle(a, b);
      final sz = await a.windowSize();
      if (sz != null && sz.w < 720) {
        await a.resizeWindow(1280, sz.h);
      }
      await returnToChatsHome(a, rounds: 4);
      await b.foreground();
      await returnToChatsHome(b, rounds: 4);
    } on PermissionBlockedError catch (e) {
      print('[sweep] sweep_calls_misc end-clean: BLOCKED (${e.message})');
    } on DriveError catch (e) {
      print(
        '[sweep] sweep_calls_misc end-clean: best-effort failed: ${e.message}',
      );
    }
    try {
      endFriends = await areFriends(a, toxB) && await areFriends(b, toxA);
    } on DriveError {
      endFriends = false;
    }
    print(
      '[sweep] sweep_calls_misc RESULTS: $passed PASS / $failed FAIL / '
      '$skipped SKIP ($results) | endFriends=$endFriends',
    );
    try {
      await a.shot('/tmp/ui_calls_misc_sweep_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_calls_misc_sweep_B.png');
    } on DriveError {
      // best-effort
    }
    if (!endFriends) {
      print(
        '[sweep] sweep_calls_misc: end state is NOT friends — failing the '
        'sweep so the runner does not trust the result-state contract',
      );
    }
  }
  // FAIL if any HARD case failed OR the launch did not reach the FRIENDS end
  // state. SKIPs do not fail the sweep.
  return (failed == 0 && endFriends) ? 0 : 1;
}

// ===========================================================================
// Individual-case dispatch (each builds its OWN minimal precondition).
// ===========================================================================
/// Whether [scenario] is one of the 11 Batch-8 calls/misc cases.
bool _isCallsMiscCaseScenario(String scenario) => const {
  'call_video_accept_hangup',
  'call_mute_toggle_incall',
  'call_camera_toggle_incall',
  'call_camera_switch_incall',
  'call_missed_record_row',
  'call_callee_hangup',
  'call_record_bubble_renders',
  'home_tabs_cycle_state_retained',
  'theme_switch_chat_open',
  'search_chat_history_window_open',
  'window_resize_responsive',
}.contains(scenario);

/// Cases that need an A<->B friendship (the call cases + the chat-open misc
/// cases). `window_resize_responsive` is single-instance (no friendship).
bool _isCallsMiscFriendshipCase(String scenario) => const {
  'call_video_accept_hangup',
  'call_mute_toggle_incall',
  'call_camera_toggle_incall',
  'call_camera_switch_incall',
  'call_missed_record_row',
  'call_callee_hangup',
  'call_record_bubble_renders',
  'home_tabs_cycle_state_retained',
  'theme_switch_chat_open',
  'search_chat_history_window_open',
}.contains(scenario);

/// Run a single Batch-8 case standalone. The friendship cases establish the
/// A<->B friendship first (or reuse the runner's restored paired_for_e2e); the
/// resize case is single-instance. Returns 0/1 (or 75 for the resize SKIP).
Future<int> runCallsMiscCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario, {
  required bool bootRestored,
}) async {
  if (!bootRestored) {
    await ensureHome(a, nickA);
    await ensureHome(b, nickB, requireHomeMenu: false);
  }

  // window_resize_responsive is single-instance (drive only A).
  if (scenario == 'window_resize_responsive') {
    await ensureHome(a, nickA);
    final r = await _windowResizeResponsive(a);
    return r == null ? _realUiSkipExitCodeForBatch8 : (r ? 0 : 1);
  }

  final cToxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final cToxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (cToxA.isEmpty || cToxB.isEmpty) {
    throw DriveError('missing tox ids for $scenario: A=$cToxA B=$cToxB');
  }
  if (_isCallsMiscFriendshipCase(scenario)) {
    if (!await _establishFriendshipForSweep(a, b, cToxA, cToxB, nickA, nickB)) {
      print('[pair] $scenario: could not establish friendship');
      return 1;
    }
    await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
    await b.waitState((s) => s['isConnected'] == true, label: 'B connected');
  }

  try {
    switch (scenario) {
      case 'call_mute_toggle_incall':
        return await _callMuteToggleIncall(a, b, cToxA) ? 0 : 1;
      case 'call_callee_hangup':
        // Standalone: establish a fresh voice call (the helper re-establishes
        // one when none is live).
        return await _callCalleeHangup(a, b, cToxA) ? 0 : 1;
      case 'call_record_bubble_renders':
        // Standalone: a completed call must exist first — snapshot the baseline,
        // run a quick voice call (start → accept → callee-hangup) to produce a
        // NEW record, then assert it renders (codex P2 — require count > baseline
        // so a restored launch's stale records can't false-pass).
        {
          final baseline = await _callRecordCount(a, cToxB);
          await _callMuteToggleIncall(a, b, cToxA);
          await _callCalleeHangup(a, b, cToxA);
          return await _callRecordBubbleRenders(a, cToxB, baseline: baseline)
              ? 0
              : 1;
        }
      case 'call_missed_record_row':
        return await _callMissedRecordRow(a, b, cToxA, cToxB) ? 0 : 1;
      case 'call_video_accept_hangup':
        return (await _callVideoWithCameraToggle(a, b, cToxA)).videoCall
            ? 0
            : 1;
      case 'call_camera_toggle_incall':
        return (await _callVideoWithCameraToggle(a, b, cToxA)).cameraToggle
            ? 0
            : 1;
      case 'call_camera_switch_incall':
        {
          final r = (await _callVideoWithCameraToggle(
            a,
            b,
            cToxA,
          )).cameraSwitch;
          return r == null ? _realUiSkipExitCodeForBatch8 : (r ? 0 : 1);
        }
      case 'home_tabs_cycle_state_retained':
        {
          // null -> SKIP (non-master-detail shell), false -> FAIL, true -> PASS.
          final r = await _homeTabsCycleStateRetained(a, cToxB);
          return r == null ? _realUiSkipExitCodeForBatch8 : (r ? 0 : 1);
        }
      case 'theme_switch_chat_open':
        return await _themeSwitchChatOpen(a, cToxB) ? 0 : 1;
      case 'search_chat_history_window_open':
        {
          final r = await _searchChatHistoryWindowOpen(a, cToxB);
          return r == null ? _realUiSkipExitCodeForBatch8 : (r ? 0 : 1);
        }
    }
    return 1;
  } finally {
    // Don't leak a live call into the next scenario / a reused launch.
    try {
      await _ensureBothIdle(a, b);
    } on DriveError {
      // best-effort
    }
  }
}

/// Batch-8 individual-dispatch SKIP exit code (mirrors the runner's
/// `_realUiSkipExitCode == 75`; redeclared here so the driver part file doesn't
/// depend on the runner constant).
const _realUiSkipExitCodeForBatch8 = 75;
