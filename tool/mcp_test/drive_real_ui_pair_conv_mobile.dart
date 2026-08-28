// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Conversation-row context-menu TRIGGER, split per shell. Extracted from
// `drive_real_ui_pair_conv.dart` (Batch 5) because the MOBILE trigger needs a
// materially different strategy — and its own diagnostics — from the desktop
// right-click, and the conv file is at its complexity-baseline pin.
//
// DESKTOP: `ui_secondary_tap` (a kSecondaryMouseButton PointerDown/Up) on the
// row → the fork's InkWell `onSecondaryTapDown` → toxee's
// `onSecondaryTapConversationItem` → `_showConversationContextMenu`.
//
// MOBILE (iOS/Android, phone AND tablet): there is no secondary mouse button at
// all, so the twin trigger is a genuine touch down→hold→up (`ui_long_press`)
// which drives the fork's `TencentCloudChatGesture` →
// `LongPressGestureRecognizer(duration: 650)` → `onLongPressStart` → toxee's
// `onLongPressConversationItem` → the SAME `_showConversationContextMenu`. Both
// shells therefore assert the SAME keyed items.

/// Whether [key] resolves to a point the user can actually TOUCH — i.e. the
/// app's `ui_key_center` found it on the ONSTAGE walk, not via the full-tree
/// fallback that also digs up boxes buried under an opaque pushed route.
///
/// A build without the `onstage` field (an older binary) is treated as onstage,
/// so this degrades to the previous lenient behaviour instead of hard-failing.
Future<bool> _keyOnstage(Inst inst, String key) async {
  try {
    final r = await inst.l3('ui_key_center', {'key': key});
    if (r['ok'] != true) return false;
    return r['onstage'] != false;
  } on DriveError {
    return false;
  }
}

/// MOBILE two-step Search-Chat-History layout: the window first lists
/// CONVERSATIONS; the keyed `search_history_message_*` rows only exist after
/// tapping a conversation into `_showMobileDetail`. Desktop shows both panels
/// at once, so this is a compact-only extra step.
Future<bool> _openSearchHistoryMobileDetail(Inst inst, String convId) async {
  if (!inst.isMobileShell) return false;
  if (!await inst.tapKeyCenter(
    'search_history_conversation:$convId',
    timeoutSecs: 4,
  )) {
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 600));
  return true;
}

/// Print the flutter_skill bounds of [keys] — live diagnostics for taps that
/// land on an adjacent control (resolved center vs actual layout).
Future<void> _dumpKeyBounds(Inst inst, List<String> keys) async {
  try {
    final r = await inst.skill('interactiveStructured', const {});
    final data = r['data'];
    final els = data is Map ? data['elements'] : null;
    final hits = <String>[
      if (els is List)
        for (final e in els)
          if (e is Map && keys.contains(e['key'])) '${e['key']}=${e['bounds']}',
    ];
    final centers = <String>[
      for (final k in keys) '$k@${await inst.keyCenter(k)}',
    ];
    print('[${inst.name}] key bounds: $hits elementCenters: $centers');
  } on DriveError {
    // diagnostics only
  }
}

/// All onstage element keys starting with [prefix] (flutter_skill walk) —
/// live diagnostics for "row not found" failures in keyed virtual lists.
Future<List<String>> _visibleKeysWithPrefix(Inst inst, String prefix) async {
  try {
    final r = await inst.skill('interactiveStructured', const {});
    final data = r['data'];
    final els = data is Map ? data['elements'] : null;
    return <String>[
      if (els is List)
        for (final e in els)
          if (e is Map && '${e['key']}'.startsWith(prefix)) '${e['key']}',
    ];
  } on DriveError {
    return const [];
  }
}

/// Press the DEVICE back key on an Android instance via adb (device id from
/// pair.json, matched by pid). The only way to dismiss a NATIVE activity that
/// covers the Flutter one — Flutter-side taps can't reach it.
Future<String?> _androidDeviceIdFor(Inst inst) async {
  if (!inst.isAndroid) return null;
  try {
    final pairFile = File(
      Platform.environment['TOXEE_REAL_UI_PAIR_JSON'] ??
          'tool/mcp_test/.multi_instance_runtime/pair.json',
    );
    if (!await pairFile.exists()) return null;
    final root =
        jsonDecode(await pairFile.readAsString()) as Map<String, dynamic>;
    final instances =
        (root['instances'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    for (final entry in instances.values) {
      if (entry is! Map) continue;
      if (int.tryParse('${entry['pid']}') == inst.pid) {
        final device = entry['device_id']?.toString();
        return (device == null || device.isEmpty) ? null : device;
      }
    }
    return null;
  } on Object {
    return null;
  }
}

Future<bool> _androidBackKey(Inst inst) async {
  final device = await _androidDeviceIdFor(inst);
  if (device == null) return false;
  try {
    final r = await Process.run('adb', [
      '-s',
      device,
      'shell',
      'input',
      'keyevent',
      '4',
    ]);
    return r.exitCode == 0;
  } on Object catch (e) {
    print('[${inst.name}] _androidBackKey failed: $e');
    return false;
  }
}

/// Package owning the focused window on [inst]'s device, or null. POSITIVE
/// adb evidence (codex High): onstage probes cannot distinguish "covered by a
/// native activity" from a legitimately blank Flutter root, and a paused
/// Flutter tree may still report the wizard "onstage" behind DocumentsUI.
Future<String?> _androidTopFocusPackage(Inst inst) async {
  final device = await _androidDeviceIdFor(inst);
  if (device == null) return null;
  try {
    final r = await Process.run('adb', [
      '-s',
      device,
      'shell',
      'dumpsys',
      'window',
      'displays',
    ]);
    final m = RegExp(
      r'mCurrentFocus=.*\s([A-Za-z0-9_.]+)/[A-Za-z0-9_.$]+',
    ).firstMatch('${r.stdout}');
    return m?.group(1);
  } on Object {
    return null;
  }
}

/// Recover an Android instance covered by a NATIVE activity (the SAF save
/// dialog the backup wizard's export opens, an OS picker): the Flutter
/// activity is paused, so EVERY onstage probe dies while l3 calls still
/// succeed (observed live: register -> mis-tapped Export now -> SAF ->
/// forceHomeRoot "restored" but homeShellTab stayed unknown). Gate on the
/// POSITIVE signal — the focused window belongs to another package — so a
/// legitimately blank Flutter root is never sent BACK. System BACK dismisses
/// the native activity; if that lands back on the backup wizard (export
/// cancelled), dismiss it properly too.
Future<bool> _recoverAndroidNativeCover(Inst inst) async {
  if (!inst.isAndroid) return false;
  final topPkg = await _androidTopFocusPackage(inst);
  if (topPkg == null || topPkg == 'com.toxee.app') return false;
  print('[${inst.name}] android native cover detected: focus=$topPkg');
  if (!await _androidBackKey(inst)) return false;
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  final uncovered = !await _mobileHomeShellCovered(inst);
  final onWizard = await _keyOnstage(inst, 'firstRunBackupWizard.laterButton');
  print(
    '[${inst.name}] android native-cover BACK => '
    'uncovered=$uncovered wizard=$onWizard',
  );
  if (onWizard) {
    await _dismissBackupWizardIfPresent(inst, timeoutSecs: 6);
    return true;
  }
  return uncovered;
}

/// True when a MOBILE home shell is COVERED by an opaque pushed route — the
/// UIKit chat page being the one that matters here.
///
/// Why this exists: `_chatsHomeReady` accepts as soon as the dump reports
/// `homeShellTab == 'chats'` and a shell landmark RESOLVES. On mobile the chat
/// page is a pushed route, and the home shell underneath it stays laid out with
/// no `Offstage`/`Visibility` ancestor — so the landmark resolved through the
/// full-tree fallback and `returnToChatsHome` returned with the chat page still
/// on screen. Everything downstream then drove the WRONG surface: the
/// conversation-row long-press landed on the message list (no context menu at
/// all), and B's inbound messages arrived while A was still VIEWING the chat, so
/// they were marked read on arrival and unread never accrued. Requiring the
/// landmark ONSTAGE is what tells the two states apart.
Future<bool> _mobileHomeShellCovered(Inst inst) async {
  if (!inst.isMobileShell) return false;
  for (final key in const [
    'bottom_nav_chats_tab',
    'sidebar_chats_tab',
    'new_entry_menu_button',
  ]) {
    if (await _keyOnstage(inst, key)) return false;
  }
  return true;
}

/// Pop whatever route covers the mobile home shell. Returns whether a cover was
/// actually removed; false (cheaply) when nothing covers it, so callers can use
/// this as a no-op-safe first leg.
///
/// ACTION PER LAYOUT — this distinction is load-bearing:
///  * COMPACT shell: the chat IS the covering route, so the REAL affordance is
///    its header back chevron (`chat_header_back_button`). Drive that first.
///  * MASTER-DETAIL shell (iPad): the chat is a PANE inside the home route, and
///    that same chevron runs `popDialogIfCurrent`, which pops the HomePage ROUTE
///    itself — a blank shell whose conversation list unmounts and whose L3
///    invokers de-register (observed live as
///    `key_not_found:conversation_list_item:…` + `invoker not registered`). So a
///    wide shell NEVER taps it; the cover there is some other pushed route (the
///    friend-application Info page after a handshake accept, a profile, a
///    settings sub-page) and the layout-agnostic `l3_pop_to_root` seam — which
///    stops AT HomePage's route — is the safe, correct pop.
Future<bool> _popMobileCoveringRoute(Inst inst) async {
  if (!await _mobileHomeShellCovered(inst)) return false;
  var compact = false;
  try {
    compact =
        (await inst.dumpState())['homeShellShouldShowMasterDetail'] == false;
  } on DriveError {
    // Unknown layout: treat as wide (seam-only) — never risk the chevron.
  }
  for (var attempt = 0; attempt < 3; attempt++) {
    // An OPEN attachment panel ("+"-sheet) overlays the composer area and can
    // swallow pops (seen live on Android: the attachment case left it open
    // and three back-chevron attempts bounced). Detect the panel by its OWN
    // content key — the options button is always in the composer row, so
    // keying on it would toggle a CLOSED panel open instead.
    if (compact && await _keyOnstage(inst, 'message_attachment_file_button')) {
      await inst.tapKeyCenter(
        'message_attachment_options_button',
        timeoutSecs: 1,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (compact &&
        await inst.tapKeyCenter('chat_header_back_button', timeoutSecs: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!await _mobileHomeShellCovered(inst)) return true;
      // Chevron landed but did NOT uncover (live on Android: its
      // popDialogIfCurrent no-ops when a stale route sits ABOVE the chat, so
      // `continue` just burned all three attempts). Fall through to the
      // pop-to-root seam in the SAME attempt instead of retrying the chevron.
    }
    try {
      // Gate-recovering wrapper: a real-UI account is a PRODUCT account and the
      // raw tool answers `non_test_account`, which this used to log as a warn
      // and carry on from — leaving the covering route up.
      if (!await inst.popToRoot()) {
        print('[pair] _popMobileCoveringRoute: popToRoot reported no pop');
      }
    } on DriveError catch (e) {
      print(
        '[pair] _popMobileCoveringRoute: l3_pop_to_root warn: ${e.message}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!await _mobileHomeShellCovered(inst)) return true;
  }
  if (await _recoverAndroidNativeCover(inst)) return true;
  print(
    '[pair] _popMobileCoveringRoute: shell still covered — '
    '${await _convShellDiag(inst)}',
  );
  return false;
}

/// Tap a conversation ROW for real, with a resolver-backed fallback.
///
/// `tryTapKey` goes through flutter_skill, which frequently cannot act on a
/// conversation row: the row key sits on a NON-interactive `KeyedSubtree`
/// wrapper that `interactiveStructured` does not report (observed live as
/// `rowKeys=[]` while the row was plainly on screen), so the tap no-ops. On the
/// iPad master-detail shell that left the right pane unbound and `openChat`
/// burned every leg. The fallback resolves the row's onstage centre through
/// `ui_key_center` and dispatches ONE real `tapAt` there — the same gesture a
/// user makes. Best-effort by contract: callers verify with `_chatSurfaceReady`.
Future<void> _tapConversationRowReal(Inst inst, String rowKey) async {
  // SINGLE-FIRE first (element-tree coordinate tap). flutter_skill's key tap
  // (tryTapKey) DOUBLE-fires: its second synthetic pointer lands ~1s later at
  // the ROW's coordinates — by then the chat page is up and that spot is the
  // top call-record bubble, whose tap REDIALS a real audio call (live on
  // Android: every "video call became audio" red traced back to this).
  if (await inst.tapKeyAt(rowKey)) return;
  // Fallback stays SINGLE-FIRE too (skill's key tap double-fires — the
  // original hazard); rows the coordinate resolvers can't see just miss and
  // the callers' own fallbacks take over.
  await inst.tapKeyCenter(rowKey, timeoutSecs: 4);
}

/// One-line home-shell / session snapshot used by the conversation-list
/// diagnostics. Everything here comes from `l3_dump_state`, so it is safe on a
/// non-test account and costs one RPC.
Future<String> _convShellDiag(Inst inst) async {
  try {
    final s = await inst.dumpState();
    return 'tab=${s['homeShellTab']} '
        'masterDetail=${s['homeShellShouldShowMasterDetail']} '
        'shellConv=${s['homeShellCurrentConversationId']} '
        'activePeer=${s['activePeerId']} '
        'currentConv=${s['currentConversation']} '
        'convIds=${(s['conversationIds'] as List?)?.length ?? 0}';
  } on DriveError catch (e) {
    return 'diag-unavailable(${e.message})';
  }
}

/// The `ui_key_center` resolution for [key] as a printable string, including
/// the resolver's `candidates` count / `error` (`key_offstage_only:…` vs
/// `key_not_found:…`) — the signal that distinguishes "the row is behind a
/// pushed route" from "the row was never built".
Future<String> _convKeyDiag(Inst inst, String key) async {
  try {
    final r = await inst.l3('ui_key_center', {'key': key});
    if (r['ok'] == true) {
      return '(${r['x']},${r['y']}) candidates=${r['candidates']}';
    }
    return 'unresolved error=${r['error']}';
  } on DriveError catch (e) {
    return 'unresolved throw=${e.message}';
  }
}

/// Every key flutter_skill's `interactiveStructured` currently reports that
/// CONTAINS [needle], with its bounds. Used when a menu/row does not appear, to
/// tell "the surface mounted under a different key" from "nothing mounted".
Future<List<String>> _convKeysContaining(Inst inst, String needle) async {
  final out = <String>[];
  try {
    final r = await inst.skill('interactiveStructured', const {});
    final data = r['data'];
    final elements = data is Map ? data['elements'] : null;
    if (elements is! List) return out;
    for (final e in elements) {
      if (e is! Map) continue;
      final k = e['key']?.toString() ?? '';
      if (!k.contains(needle)) continue;
      final b = e['bounds'];
      out.add(b is Map ? '$k@(${b['x']},${b['y']},${b['w']}x${b['h']})' : k);
    }
  } on DriveError {
    // best-effort diagnostic
  }
  return out;
}

/// Whether either keyed conversation-context-menu anchor (Pin or Unpin — which
/// one renders depends on the row's current pin state) is resolvable. Uses the
/// ELEMENT-TREE resolver: the menu renders in a pushed `_PopupMenuRoute` whose
/// items flutter_skill's whole-tree `waitForElement` reaches, but whose bounds
/// only `ui_key_center` reports reliably.
Future<bool> _convMenuItemsVisible(Inst inst, {int timeoutSecs = 3}) async {
  return await inst.waitKeyCenter(
        'conversation_context_menu_pin_item',
        timeoutSecs: timeoutSecs,
      ) ||
      await inst.waitKeyCenter(
        'conversation_context_menu_unpin_item',
        timeoutSecs: 2,
      );
}

/// MOBILE trigger: long-press the conversation row until the real context menu
/// mounts. Returns whether the menu's keyed items appeared.
///
/// Strategy (each element is there for a live-observed failure mode):
///  * The press point is re-resolved EVERY attempt: a long-press that released
///    early degenerates into a TAP, which NAVIGATES into the chat and unmounts
///    the row, so the next attempt must re-find it from the chats home.
///  * The hold grows across attempts (900 → 1300 ms). The fork's recognizer
///    fires at 650 ms, but under 2-process simulator contention the app's event
///    loop can be busy enough that the down→up window collapses; a longer hold
///    is the only lever the harness has over that.
///  * The press alternates between the row's resolved CENTRE and a point in its
///    LEFT third (over the avatar/content, always inside the gesture subtree) —
///    the row centre can land on the trailing time/badge column, which is inside
///    the same `TencentCloudChatGesture`, so this is belt-and-braces rather than
///    a different code path.
Future<bool> _convMobileRowMenu(Inst inst, String rowKey) async {
  const holds = <int>[900, 900, 1300, 1300];
  for (var attempt = 0; attempt < holds.length; attempt++) {
    await inst.foreground();
    // Recover the list when a degenerated tap navigated into the chat.
    if (!await inst.waitKey(rowKey, timeoutSecs: 1)) {
      await returnToChatsHome(inst, rounds: 3);
    }
    final centre = await inst.keyCenter(rowKey);
    if (centre == null) {
      print(
        '[pair] _convMobileRowMenu: row centre unresolved '
        '(${await _convKeyDiag(inst, rowKey)}; ${await _convShellDiag(inst)})',
      );
      await returnToChatsHome(inst, rounds: 3);
      continue;
    }
    final x = attempt.isOdd ? centre.x * 0.35 : centre.x;
    try {
      final r = await inst.l3('ui_long_press', {
        'x': '$x',
        'y': '${centre.y}',
        'holdMs': '${holds[attempt]}',
      });
      if (r['ok'] != true) {
        print('[pair] _convMobileRowMenu: ui_long_press warn: $r');
      }
    } on DriveError catch (e) {
      print('[pair] _convMobileRowMenu: long-press warn: ${e.message}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (await _convMenuItemsVisible(inst)) return true;
    print(
      '[pair] _convMobileRowMenu: attempt $attempt (hold=${holds[attempt]}ms '
      'at $x,${centre.y}) did not mount the menu — '
      'menuKeys=${await _convKeysContaining(inst, 'conversation_context_menu')} '
      'rowKeys=${await _convKeysContaining(inst, 'conversation_list_item')} '
      '${await _convShellDiag(inst)}',
    );
  }
  await inst.shot('/tmp/ui_conv_menu_trigger_fail_${inst.name}.png');
  return false;
}

/// DESKTOP trigger: right-click the row until the menu mounts.
Future<bool> _convDesktopRowMenu(Inst inst, String rowKey) async {
  final rowCenter = await inst.keyCenter(rowKey);
  for (var attempt = 0; attempt < 4; attempt++) {
    await inst.foreground();
    try {
      // Alternate the keyed trigger (which can resolve a stale OFFSTAGE copy
      // and fire on empty space) with a coordinate trigger at the resolved row
      // centre — a full-width conv row is right-clickable anywhere on it.
      if (attempt.isOdd && rowCenter != null) {
        await inst.secondaryTapAt(rowCenter.x, rowCenter.y);
      } else {
        await inst.secondaryTapKey(rowKey);
      }
    } on DriveError catch (e) {
      print('[pair] _convDesktopRowMenu: menu trigger warn: ${e.message}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (await _convMenuItemsVisible(inst)) return true;
  }
  return false;
}

/// Open the REAL C2C conversation-row context menu for [tox] — the production
/// `onSecondaryTapConversationItem` (desktop right-click) /
/// `onLongPressConversationItem` (mobile long-press) path, no gated tool. Both
/// triggers land on the SAME `_showConversationContextMenu` handler
/// (home_page.dart:428/437), so the keyed menu items asserted by the callers are
/// identical on every platform. Lands on the chats home first so the
/// conversation list is mounted. Returns whether the menu's keyed items
/// appeared.
Future<bool> _openConvRowMenuReal(Inst inst, String tox) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  // Pop a leaked contact profile that can cover the conversation list.
  await _dismissFriendProfileToUnderlying(inst);
  final rowKey = _convRowKey(tox);
  if (!await inst.waitKey(rowKey, timeoutSecs: 8)) {
    print(
      '[pair] _openConvRowMenuReal: row $rowKey not present — '
      'keyCenter=${await _convKeyDiag(inst, rowKey)} '
      'rowKeys=${await _convKeysContaining(inst, 'conversation_list_item')} '
      '${await _convShellDiag(inst)}',
    );
    await inst.shot('/tmp/ui_conv_row_missing_${inst.name}.png');
    return false;
  }
  return inst.isMobileShell
      ? _convMobileRowMenu(inst, rowKey)
      : _convDesktopRowMenu(inst, rowKey);
}
