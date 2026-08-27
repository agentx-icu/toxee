// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// TAP / KEY-RESOLUTION DIAGNOSTICS — shared by every case in the campaign.
//
// WHY THIS EXISTS. `Inst.tryTapKey` used to swallow the `skill('tap')` payload
// entirely: it looped, compared `success`, and returned a bare bool. That made
// three PHYSICALLY DIFFERENT failures indistinguishable in every campaign log:
//
//   1. the key is not in the widget tree at all      -> error.code E001
//      (`elementNotFound`, with flutter_skill's own `suggestions` list)
//   2. the key IS in the tree but its resolved centre lies outside the view
//      ±50 px, so flutter_skill REFUSES to dispatch  -> error.code E002
//      (`elementNotVisible`, carrying `position: {x, y}`)
//   3. the tap really was dispatched and the widget's callback did nothing
//      -> `success: true` and no observable effect
//
// Case (2) is the nasty one, because `ui_key_center` has NO viewport check
// while `tap` does: an off-edge control is "found" by `keyCenter` and "missing"
// to `tap`. Reading only the bool, a driver concludes "the sheet never mounted"
// when the truth is "the opener is off the right edge of this device". These
// helpers keep the payload so the FAIL message can say which of the three it
// was. Shared Dart in the driver — every platform's campaign benefits.

extension InstTapDiagnostics on Inst {
  /// [tryTapKey] that KEEPS the diagnosis.
  ///
  /// Same retry/backoff semantics as [tryTapKey] (that method is now a thin
  /// wrapper over this one, so no call site changes behaviour); the difference
  /// is that the LAST attempt's raw `skill('tap')` map comes back with the
  /// verdict instead of being dropped on the floor.
  Future<({bool ok, Map<String, dynamic> result})> tryTapKeyDetailed(
    String key, {
    int retries = 3,
  }) async {
    var last = <String, dynamic>{};
    for (var i = 0; i < retries; i++) {
      last = await skill('tap', {'key': key});
      if (last['success'] == true) return (ok: true, result: last);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return (ok: false, result: last);
  }

  /// Wait until [key]'s resolved centre STOPS MOVING, and report whether it did.
  ///
  /// WHY THIS IS NEEDED (root cause of a whole class of phantom "the control did
  /// nothing" failures). A coordinate tap is a two-step operation: the driver
  /// reads a centre over RPC, then dispatches a pointer at that point over a
  /// SECOND RPC. If the widget is mid-animation, it has moved between the two
  /// and the pointer lands on empty space — with no error anywhere, because
  /// every step "succeeded". Live on Android the multi-select toolbar resolved
  /// at x=419.4 and x=200.8 for a button that settles at x=40.0: the mobile
  /// composer swaps in the select-mode toolbar through an AnimatedSwitcher whose
  /// transitionBuilder is a `SlideTransition` from `Offset(1, 0)`
  /// (`..._message_input_mobile.dart:972-983`), i.e. it flies in from the RIGHT
  /// edge, so x sweeps the full viewport width while y stays put.
  ///
  /// Element-resolved `skill('tap')` is immune (it invokes the callback rather
  /// than a point), which is exactly why some cases appeared to work and others
  /// did not — the difference was never the control, it was the input path.
  ///
  /// Returns the settled `ui_key_center` map once [stableSamples] consecutive
  /// reads agree to within half a logical pixel, or null on timeout. Platform
  /// agnostic: iOS/iPad run the same AnimatedSwitcher, so this fixes them too.
  Future<Map<String, dynamic>?> waitKeyCenterSettled(
    String key, {
    int timeoutSecs = 10,
    int stableSamples = 2,
    Duration interval = const Duration(milliseconds: 150),
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    Map<String, dynamic>? previous;
    var stable = 0;
    while (DateTime.now().isBefore(deadline)) {
      final current = await keyCenterDetail(key);
      if (current != null && previous != null) {
        final dx = ((current['x'] as num) - (previous['x'] as num)).abs();
        final dy = ((current['y'] as num) - (previous['y'] as num)).abs();
        stable = (dx < 0.5 && dy < 0.5) ? stable + 1 : 0;
        if (stable >= stableSamples) return current;
      } else {
        stable = 0;
      }
      previous = current;
      await Future<void>.delayed(interval);
    }
    return null;
  }

  /// The RAW `ui_key_center` map for [key] (`x`, `y`, `w`, `h`, `onstage`,
  /// `candidates`, and the view's logical `viewWidth`/`viewHeight`), or null
  /// when the resolver could not find the key.
  ///
  /// [Inst.keyCenter] deliberately narrows this to (x, y); a case that is
  /// diagnosing a tap rejection needs the rest — above all the view extent the
  /// centre has to be compared against.
  Future<Map<String, dynamic>?> keyCenterDetail(String key) async {
    try {
      final r = await l3('ui_key_center', {'key': key});
      if (r['ok'] != true) return null;
      return r;
    } on DriveError {
      return null;
    }
  }
}

/// One-line rendering of a `skill('tap')` payload for campaign logs.
///
/// Deliberately prints the error CODE verbatim (E001 vs E002 is the whole
/// diagnosis) plus `position` when flutter_skill supplied it — that field is
/// only present on the off-screen rejection, so its presence alone identifies
/// the layout-overflow case.
String describeTapResult(Map<String, dynamic> r) {
  if (r.isEmpty) return '<no tap attempted>';
  final err = r['error'];
  final code = err is Map ? err['code'] : null;
  final message = err is Map ? err['message'] : null;
  final pos = r['position'];
  return [
    'success=${r['success']}',
    if (code != null) 'code=$code',
    if (pos != null) 'position=$pos',
    if (message != null) 'message=$message',
  ].join(' ');
}

/// EVERY `interactiveStructured` element carrying [key], in tree order, with the
/// bounds flutter_skill reports for it.
///
/// This is the view `Inst.tapKeyCenter` actually acts on: it scans the same list
/// and taps the LAST match with positive bounds. `interactiveStructured` has no
/// paint/cover/onstage guard, so a stale copy left behind by an AnimatedSwitcher
/// or a popped route is reported exactly like the live widget — and if the stale
/// one sorts last, the coordinate tap lands on it and silently does nothing.
/// Printing the whole list is the only way to see that from a log; a single
/// resolved centre cannot show it.
Future<List<String>> describeKeyMatches(Inst a, String key) async {
  try {
    final r = await a.skill('interactiveStructured', const {});
    final data = r['data'];
    final elements = data is Map ? data['elements'] : null;
    if (elements is! List) return const <String>[];
    final out = <String>[];
    for (final e in elements) {
      if (e is! Map || e['key'] != key) continue;
      final b = e['bounds'];
      out.add(
        b is Map
            ? 'bounds(x=${b['x']} y=${b['y']} w=${b['w']} h=${b['h']})'
            : 'bounds=<none>',
      );
    }
    return out;
  } on Object catch (e) {
    return <String>['<dump unavailable: $e>'];
  }
}

/// One-line rendering of a `ui_key_center` payload, with an explicit verdict on
/// whether the centre is inside the window `tap` will accept.
String describeKeyCenter(Map<String, dynamic>? r) {
  if (r == null) return '<unresolved>';
  final x = (r['x'] as num?)?.toDouble();
  final y = (r['y'] as num?)?.toDouble();
  final vw = (r['viewWidth'] as num?)?.toDouble();
  final vh = (r['viewHeight'] as num?)?.toDouble();
  final parts = <String>[
    'x=$x',
    'y=$y',
    'w=${r['w']}',
    'h=${r['h']}',
    'onstage=${r['onstage']}',
    'candidates=${r['candidates']}',
    'view=${vw}x$vh',
  ];
  if (x != null && y != null && vw != null && vh != null) {
    // The exact predicate flutter_skill applies before dispatching (±50 px of
    // slack on every edge); recomputing it here turns "tap said no" into a
    // statement about geometry rather than a guess.
    final tappable = x >= -50 && x <= vw + 50 && y >= -50 && y <= vh + 50;
    parts.add('withinTapWindow=$tappable');
  }
  return parts.join(' ');
}

/// One-shot diagnostic for "the group/conference I just created through the
/// real AddGroupDialog never showed up": what the app thinks its shell and
/// conversation list are, and whether the dialog is still mounted. Printed on
/// the failure path only, so a red run explains itself instead of needing an
/// interactive replay (the iPhone pair, which has no on-disk app log, is where
/// this first mattered — 2026-08-23, every group2/account_conf create case).
Future<void> _printGroupCreateDiag(Inst inst, String name) async {
  await inst.shot('/tmp/ui_group_create_fail_${inst.name}.png');
  try {
    final st = await inst.dumpState();
    final convs = ((st['conversations'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (c) =>
              '${c['type']}:${c['showName']}'
              '(${c['conversationID']})',
        )
        .take(12)
        .join(', ');
    final dialogStillUp = await inst.waitKey(
      'add_group_create_name_input',
      timeoutSecs: 1,
    );
    final submitStillUp = await inst.waitKey(
      'add_group_create_submit_button',
      timeoutSecs: 1,
    );
    print(
      '[pair] group-create diag for "$name": homeShellTab=${st['homeShellTab']} '
      'sessionReady=${st['sessionReady']} mobileShell=${inst.isMobileShell} '
      'currentConversation=${st['currentConversation']} '
      'activePeerId=${st['activePeerId']} '
      'dialogStillUp=$dialogStillUp submitStillUp=$submitStillUp '
      'conversations=[$convs]',
    );
  } on DriveError catch (e) {
    print('[pair] group-create diag for "$name": unavailable: ${e.message}');
  }
}

/// Mobile shells: the soft keyboard left up by the name entry pads the
/// AddGroupDialog's SingleChildScrollView by the keyboard inset, so a
/// key-addressed tap on the submit button lands on the modal barrier and
/// DISMISSES the dialog without creating anything (live iPhone 2026-08-23:
/// dialog gone, knownGroups unchanged — the same tap after `ui_hide_keyboard`
/// created the group). Hide the keyboard first; do NOT "reveal" the button
/// afterwards — `_revealDialogKey` drags at y=400, which on a phone starts on
/// the modal barrier above the dialog card and dismisses it the same way
/// (the key-addressed `tapKey` needs no visible-band nudge). Desktop shells
/// have no soft keyboard: no-op.
Future<void> _prepareDialogSubmit(Inst inst, String key) async {
  if (!inst.isMobileShell) return;
  await inst.hideKeyboard();
  await Future<void>.delayed(const Duration(milliseconds: 400));
}

/// True (and a declared SKIP printed) when the shell is NOT master-detail: the
/// global search OVERLAY (`message_search_field`, Cmd/Ctrl+F route /
/// `l3_open_global_search`) exists only on the wide shell — a compact shell
/// (Android, and the iPhone as proven live 2026-08-23) has the in-list Search
/// field instead, so the desktop-overlay cases cannot be honest there. Decided
/// from the shell's own live value, never from the platform.
Future<bool> _noSearchOverlay(Inst inst, String label) async {
  if (!await _isCompactShell(inst)) return false;
  print(
    '[pair] $label: SKIP — compact shell has no desktop master-detail search '
    'overlay (homeShellShouldShowMasterDetail=false)',
  );
  return true;
}

/// The shell's OWN live answer to "is this the wide master-detail layout?";
/// false on a phone, a narrow window, or when the dump has no answer.
Future<bool> _isCompactShell(Inst inst) async =>
    (await inst.dumpState())['homeShellShouldShowMasterDetail'] != true;

/// Why did the keyed group-profile edit-name dialog not open? Print what the
/// profile looks like at that moment (button centre / onstage, the profile id
/// text, the shell tab) and keep a screenshot — macOS `conference_rename_leave`
/// hit this 3/3 inside `sweep_p1_single` while the same tap works live.
Future<void> _printEditNameDiag(Inst inst, String label) async {
  try {
    final btn = await inst.l3('ui_key_center', {
      'key': 'group_profile_edit_name_button',
    });
    final idText = await inst.keyCenter('group_profile_id_text');
    final st = await inst.dumpState();
    final dialogs = await inst.l3('ui_key_center', {
      'key': 'group_profile_edit_name_dialog',
    });
    // `tapKeyCenter` taps the LAST `interactiveStructured` element carrying
    // the key: list every match, so a duplicate (a stale profile route still
    // on the stack) shows up here as two bounds.
    final structured = await inst.skill('interactiveStructured', const {});
    final data = structured['data'];
    final matches = <String>[];
    if (data is Map && data['elements'] is List) {
      for (final e in data['elements'] as List) {
        if (e is Map && e['key'] == 'group_profile_edit_name_button') {
          matches.add('${e['bounds']}');
        }
      }
    }
    print(
      '[pair] $label: edit-name dialog did not open — '
      'button=${btn['ok']}/${btn['onstage']}@${btn['x']},${btn['y']} '
      'structured=${matches.length}:${matches.join('|')} '
      'idText=${idText != null} dialogKey=${dialogs['ok']} '
      'homeShellTab=${st['homeShellTab']} '
      'currentConversation=${st['currentConversation']}',
    );
  } on DriveError catch (e) {
    print('[pair] $label: edit-name diag unavailable: ${e.message}');
  }
  try {
    // The full widget tree tells us what sits ABOVE the profile route when a
    // correctly-aimed coordinate tap opens nothing (a stale barrier/overlay is
    // invisible to key probes).
    // `_raw` is library-private; tap_diag is a part of the same library.
    final dump = await inst._raw('ext.flutter.debugDumpApp', const {});
    final tree = dump['data']?.toString() ?? '';
    if (tree.isNotEmpty) {
      final path = _portableTmp('/tmp/ui_edit_name_tree_${inst.name}.txt');
      await File(path).writeAsString(tree);
      print('[pair] $label: widget tree -> $path (${tree.length} chars)');
    }
  } on DriveError catch (e) {
    print('[pair] $label: tree dump unavailable: ${e.message}');
  }
  await _dumpWidgetTree(inst, 'edit_name', label);
  await inst.shot('/tmp/ui_edit_name_diag_${inst.name}.png');
}

/// iOS / Android member list: there is no desktop right-click popup
/// (`group_member_desktop_kick_item` — the desktop Listener is disabled when
/// `isDesktop` is false, iPad included); a plain tap on the member row opens
/// the mobile CupertinoActionSheet whose kick action is keyed
/// `group_member_action_kick_button`. Returns false on desktop shells and
/// when the sheet / kick action never shows, so the caller's desktop path can
/// still run.
Future<bool> _kickViaMobileSheet(Inst inst, String rowKey) async {
  if (!(inst.isIos || inst.isAndroid)) return false;
  for (var attempt = 0; attempt < 3; attempt++) {
    await inst.tapKeyCenter(rowKey, timeoutSecs: 6);
    if (await inst.waitKeyCenter(
      'group_member_action_kick_button',
      timeoutSecs: 4,
    )) {
      return inst.tapKeyCenter(
        'group_member_action_kick_button',
        timeoutSecs: 6,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
  print('[pair] _kickViaMobileSheet: kick action never surfaced for $rowKey');
  return false;
}

/// Move a keyed scroll surface by [dy] (wheel semantics: positive reveals
/// content further DOWN). Desktop shells take the mouse wheel; mobile shells
/// ignore wheel events, so they get a bounded touch drag in the opposite
/// direction — the reason the narrow Settings page never reached its
/// Account-Management buttons on iPhone (2026-08-24).
Future<void> _scrollSurface(Inst inst, String scrollKey, double dy) async {
  if (!inst.isMobileShell) {
    await inst.scrollAt(scrollKey, dy: dy);
    return;
  }
  var remaining = dy.abs();
  for (var i = 0; i < 6 && remaining > 0; i++) {
    final step = remaining.clamp(0.0, 500.0);
    await inst.dragBy(scrollKey, dy: dy > 0 ? -step : step, steps: 12);
    remaining -= step;
  }
}

/// Make `message_attachment_file_button` tappable on whichever composer is
/// mounted. Desktop renders it inline in the merged toolbar; the mobile
/// composer hides it behind the `message_attachment_options_button` "+"
/// sheet (toxee injects File + Camera there — lib/ui/home/
/// mobile_attachment_policy.dart), and the sheet closes after every pick, so
/// call this before EACH pick. iPhone `attachment_entry_buttons_render`
/// (2026-08-24) waited for the inline button and reported file=false.
Future<bool> _revealAttachmentFileButton(Inst inst) async {
  if (await inst.waitKey('message_attachment_file_button', timeoutSecs: 2)) {
    return true;
  }
  if (!await inst.waitKey(
    'message_attachment_options_button',
    timeoutSecs: 6,
  )) {
    return false;
  }
  await inst.tapKeyCenter('message_attachment_options_button', timeoutSecs: 6);
  return inst.waitKey('message_attachment_file_button', timeoutSecs: 6);
}

/// `l3_simulate_notification_tap` answers `no_listener` until HomePage has
/// subscribed to the tap stream (it does so after its initial load); poll
/// instead of asserting on an event the broadcast would have dropped.
Future<Map<String, dynamic>> _injectNotificationTapWhenListening(
  Inst inst,
  String conversationId,
) async {
  Map<String, dynamic> tap = const {};
  for (var attempt = 0; attempt < 25; attempt++) {
    tap = await inst.l3('l3_simulate_notification_tap', {
      'conversationId': conversationId,
    });
    if (tap['ok'] == true || tap['error'] != 'no_listener') return tap;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return tap;
}

/// Logical height of the app's view, as `ui_key_center` reports it alongside
/// any resolvable [key] (null when the seam has no view). Lets a reach helper
/// decide "visible" from the real window instead of a phone-sized constant.
Future<double?> _viewHeight(Inst inst, String key) async {
  try {
    final r = await inst.l3('ui_key_center', {'key': key});
    final h = r['viewHeight'];
    return h is num ? h.toDouble() : null;
  } on DriveError {
    return null;
  }
}

/// Save `ext.flutter.debugDumpApp` to /tmp — the only way to see the stale
/// barrier/overlay that eats a correctly-aimed coordinate tap while every key
/// probe still reports the target onstage (in-sweep-only failures of
/// conference_rename_leave and group_at_member_send, 2026-08-24).
/// The full `debugDumpApp` text ('' when unavailable). Includes every
/// EditableText's TextEditingValue, so callers can verify composer content.
Future<String> _appTreeText(Inst inst) async {
  try {
    // `_raw` is library-private; tap_diag is a part of the same library.
    final dump = await inst._raw('ext.flutter.debugDumpApp', const {});
    return dump['data']?.toString() ?? '';
  } on DriveError {
    return '';
  }
}

Future<void> _dumpWidgetTree(Inst inst, String tag, String label) async {
  final tree = await _appTreeText(inst);
  if (tree.isEmpty) {
    print('[pair] $label: tree dump unavailable');
    return;
  }
  final path = _portableTmp('/tmp/ui_${tag}_tree_${inst.name}.txt');
  await File(path).writeAsString(tree);
  print('[pair] $label: widget tree -> $path (${tree.length} chars)');
}

/// A stale text-selection toolbar/handle overlay (left by an earlier case's
/// select-all or a tap on a SelectableText) parks a FULL-SCREEN gesture layer
/// above every route and eats the next coordinate tap — the in-sweep-only
/// "correctly aimed tap does nothing" failures (tree-dump-proven 2026-08-24).
/// One tap on a neutral spot consumes/dismisses it, exactly like a user's
/// first click; a no-op when nothing is stale.
Future<void> _dismissStaleSelectionOverlay(Inst inst) async {
  try {
    await inst.tapAt(14, 350);
  } on DriveError {
    // best-effort
  }
  await Future<void>.delayed(const Duration(milliseconds: 250));
}

/// The call overlay minimizes to the floating PiP card when a route is pushed
/// over it; the full-screen `call_hangup_button` is then unmounted. Restore it
/// by tapping the card (its onTap is `callState.restore()`).
Future<void> _restoreCallOverlayIfMinimized(Inst inst) async {
  if (await inst.waitKey('call_hangup_button', timeoutSecs: 1)) return;
  if (await inst.waitKey('floating-call-card', timeoutSecs: 2)) {
    await inst.tapKeyCenter('floating-call-card', timeoutSecs: 4);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
