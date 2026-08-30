// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// KEYED-BUT-NEVER-DRIVEN gap batch #4 — the tranche that batches #2/#3 left
// behind, RE-DERIVED from scratch rather than inherited from an older todo
// list. The derivation was: enumerate every key string in the three registries
// (`lib/ui/testing/ui_keys{,_fork,_login}.dart`) PLUS every `ValueKey('…')` /
// `Key('…')` literal under `lib/ui`, `lib/call` and
// `third_party/chat-uikit-flutter`, then subtract every string that appears in
// NON-COMMENT driver code under `tool/mcp_test/drive_*.dart`. That yields 282
// distinct UI keys, of which 246 were already driven, 13 appeared only in prose
// (a comment is not coverage) and 23 never appeared at all.
//
// Two of those 13 were FALSE POSITIVES of the substring test and are in fact
// driven, by a key string assembled at runtime rather than written out:
// `contact_application_decline_button:<uid>` (drive_real_ui_pair_friends.dart
// builds `'$keyBase:$userId'` for the `decline` scenario) and
// `search_result_contact:<uid>` (c2c_extra / conv). A third, the literal
// `message_menu_item:<action>`, is a documentation placeholder, not a key. So
// the honest undriven total is 10 prose-only + 23 absent = 33.
//
// This batch drives 16 of those 33. The other 17 are UNREACHABLE, dead, or
// redundant handles on an already-asserted observable, and are documented as
// verify-first exclusions at the bottom of this header — do NOT "fix" them by
// writing a scenario that could only ever SKIP or that re-reads something an
// existing case already gates on.
//
// One key sat in a THIRD class that the count above cannot see:
// `message_attachment_options_button` appeared in driver CODE
// (drive_real_ui_pair_keyed_gaps3_contacts.dart uses it to tell the mobile
// composer from the desktop toolbar) but was attached to NO widget, so that
// probe could never resolve and `personal_card_send_c2c`'s mobile SKIP branch
// was unreachable. This batch attaches it.
//
// SHAPE. `sweep_keyed_gaps4` is TWO-PROCESS, `required=no-friend` (it runs its
// own handshake and REUSES an existing one) / `result=friends` (nothing here
// deletes the friend; the four @-mention cases share ONE throwaway group that
// the shared `_kg3WithGroup` helper leaves in cleanup). `sweep_keyed_gaps4_login`
// is SINGLE-instance (A only) and `required=no-friend` / `result=no-friend`
// because its one case logs out, provisions a THROWAWAY account and deletes it
// again from the LoginPage. They are separate sweeps precisely because their
// state contracts differ — merging them would force the runner to insert a
// reset it does not need.
//
// ASSERTION DISCIPLINE (same bar as batches #2/#3). Every case observes a real
// side effect: a keyed widget mounting or UNmounting, a live counter that
// changes value, a control present on one render of a generator and ABSENT on
// another (a gating PAIR — never a bare negative), a route that binds a
// different conversation, or a saved account that leaves the login list. No
// case passes because "the tap did not throw". Where the next step leaves the
// app (an OS gallery write, an OS file manager) the case stops at the boundary
// and says so instead of pretending a side-effect-free tap is an assertion.
//
// PRODUCT/FORK KEYS ADDED WITH THIS BATCH. Five controls had NO key at all, so
// no driver could ever have targeted them. Every addition is ADDITIVE
// (an optional parameter or a `key:` argument), changes no behaviour, layout or
// callback, and uses a key STRING that `lib/ui/testing/ui_keys.dart` already
// declared and documented — the registries needed no new entries, which also
// keeps the pinned `ui_keys.dart` untouched:
//
//   * `message_attachment_options_button` — the mobile composer's "+" icon.
//     `_buildInputAreaIcon` gained an optional `iconKey` (defaulting to null,
//     so every other call site is byte-identical) applied to its `InkWell`.
//     ui_keys.dart ALREADY claimed the helper took this parameter; it did not.
//     Side effect of fixing that: `personal_card_send_c2c`
//     (batch #3) probes this key to decide "mobile composer vs desktop
//     toolbar" — until now the probe could never resolve, so its mobile SKIP
//     branch was unreachable and the case reported the wrong diagnosis.
//   * `message_attachment_{file,camera}_button` in the MOBILE attachment panel
//     — the panel is data-driven, so the key is derived from the option's
//     `IconData` (the contract ui_keys.dart documents). Only the two icons
//     toxee actually injects are mapped; anything else returns null and renders
//     exactly as before, so duplicate sibling keys are impossible.
//   * `chat_voice_record_button` — the hold-to-record mic `Listener`. Placed on
//     the Listener (a plain `RenderPointerListener` around a padded Icon) and
//     NOT on the `Transform`/`AnimatedBuilder` above it: a state-encoding key
//     on an animated widget remounts it on every flip and destroys the
//     animation (the password-strength-bar regression precedent). The mic and
//     `chat_send_button` are the two arms of the same ternary, so presence of
//     this key IS `_showSendButton == false`.
//   * `mention_member:<uid>` / `mention_member:atAll`,
//     `mention_member_list_{back,confirm}_button` — the MOBILE @-mention
//     picker had ZERO keys while the desktop inline panel had the full
//     `mention_member:*` contract, so ui_keys.dart's claim that "the two
//     surfaces share this key contract" was half true. The picker route is
//     pushed only from the mobile composer's `_onChooseGroupMembers`, and the
//     desktop composer never calls it, so the two surfaces cannot both be in
//     the tree.
//
// ===========================================================================
// VERIFY-FIRST EXCLUSIONS — keys that stay undriven ON PURPOSE
// ===========================================================================
//
//   * `av_conference_{join,mute,enable,leave}_button` — re-verified, still no
//     constructible precondition. The header action renders only when
//     `conversation.groupType == 'av_conference'`
//     (lib/ui/home_page_bootstrap.dart), and the ONLY producer of that type is
//     an INBOUND `TOX_CONFERENCE_TYPE_AV` invite (V2TIMManagerImpl.cpp:
//     `is_av_invite ? "av_conference" : "conference"`). AddGroupDialog creates
//     exactly `group` / `privateGroup` / `conference` and `l3_create_group`
//     maps only public/private, so neither the app nor the harness can make
//     one. A bare "absent on a normal conference" probe would be a negative
//     leg with no positive leg — the thing this batch refuses to ship.
//   * `call_camera_switch_button` — needs a LIVE video call plus
//     `CallMediaCapabilities.supportsCameraSwitch()`. It belongs next to the
//     video-call cases in `drive_real_ui_pair_calls_misc_video.dart`, not here.
//   * `add_group_copy_id_button` — unreachable in production:
//     `_buildCreatedInfo()` renders only while `_createdGroupId != null`, but
//     `_createGroup` pops the dialog on success unless `closeOnCreateSuccess`
//     is false, and nothing in `lib/` ever passes that flag.
//   * `message_menu_item:{translate,convertToText}`,
//     `contact_group_notifications_tab`, `group_invite_accept_button:<gid>`,
//     `contact_app_bar_add_group_item` — DEAD; the five verify-first findings
//     of batch #3 (see drive_real_ui_pair_keyed_gaps3.dart) still hold.
//   * `draft_persistence_text` — NOT a production control. Both composers emit
//     it only under `widget.debugDraftPersistenceOnly`, a flag set by the
//     fork's own WidgetTester draft test; the real app never passes it.
//   * `pairing_qr_url:<url>` — behind `FeatureFlags.enableQRPairing`, which is
//     a `static const bool … = false`. The Settings entry that pushes
//     PairingHostPage is inside `if (FeatureFlags.enableQRPairing)`, so the
//     page cannot be reached at all in a shipped build.
//   * `group_avatar_<gid>_<version>` — not an interactive control. It is a
//     cache-busting `KeyedSubtree` whose `_version` suffix exists purely to
//     force a rebuild after an avatar re-pick; the observable it protects (the
//     new art rendering) is what the avatar cases already assert.
//   * `message_attachment_call_button` — toxee never injects a call entry into
//     the mobile attachment panel (`buildToxeeMobileAttachmentOptions` returns
//     exactly File + Camera), so the option the key would ride on does not
//     exist. Left unmapped rather than given a key that can never render.
//   * `register_password_strength_label` — not an undriven CONTROL but an
//     undriven HANDLE: `register_password_strength_flips` already asserts that
//     caption's content by text and `register_strength_segments_ramp` (batch
//     #2) asserts the same state through the per-segment keys. Adding a third
//     read of the same observable would inflate the case count, not coverage.
//   * `user_profile_modify_remark_dialog` and
//     `user_profile_delete_friend_dialog` — same class: both are CONTAINER keys
//     on dialogs whose mount/dismiss is already asserted through their keyed
//     CHILDREN. `friendprof_remark_edit_persists` gates on
//     `user_profile_modify_remark_text_field` +
//     `user_profile_modify_remark_confirm_button`, and
//     `c2c_delete_friend_cancel` gates on
//     `user_profile_delete_friend_cancel_button` plus a real `areFriends`
//     re-check. A case that only resolved the container key would observe
//     strictly less than those already do.
//
// NOT VERIFIED BY EXECUTION: authored offline against the widget source. No
// campaign run has driven any case in this batch yet.

/// Every batch-#4 scenario name that is NOT a sweep. Used by the dispatch to
/// decide whether to claim a scenario.
const _keyedGaps4Cases = {
  'msg_select_clear_button_resets_count',
  'msg_select_forward_combined_absent_gating',
  'attachment_toolbar_disabled_entries_gating',
  'message_viewer_save_and_zoom_surface',
  'mobile_attachment_panel_entries',
  'mobile_voice_record_button_reveals',
  'mobile_chats_unread_badge_flips',
  'mobile_chat_back_clears_active_peer',
  'mobile_mention_picker_confirm_inserts',
  'mobile_mention_picker_back_empty_selection',
  'mobile_mention_at_all_inserts',
  'mobile_mention_deletion_clears_token',
  'mobile_search_contact_back_unbinds',
  'login_account_delete_confirm_removes_card',
};

/// The cases that need a live two-process GROUP (the mobile @-mention picker
/// only exists in a group conversation: the composer's `@` branch is gated on
/// `inputData.groupID != null`). They share ONE established group.
const _keyedGaps4GroupCases = <String>[
  'mobile_mention_picker_confirm_inserts',
  'mobile_mention_picker_back_empty_selection',
  'mobile_mention_at_all_inserts',
  'mobile_mention_deletion_clears_token',
];

/// The friendship-only (non-group, non-login) cases, in sweep execution order.
/// Ordered cheapest-first: the composer/select-mode probes need only an open
/// C2C chat, the viewer case pays a file transfer, and the unread-badge case is
/// last of the flat set because it drains and re-dirties the unread state,
/// which every earlier case would otherwise perturb.
const _keyedGaps4FlatCases = <String>[
  'msg_select_clear_button_resets_count',
  'msg_select_forward_combined_absent_gating',
  'attachment_toolbar_disabled_entries_gating',
  'mobile_attachment_panel_entries',
  'mobile_voice_record_button_reveals',
  'message_viewer_save_and_zoom_surface',
  'mobile_chats_unread_badge_flips',
  'mobile_chat_back_clears_active_peer',
  'mobile_search_contact_back_unbinds',
];

bool _isKeyedGaps4CaseScenario(String scenario) =>
    _keyedGaps4Cases.contains(scenario);

/// The runner's SKIP exit code (`_realUiSkipExitCode`). Mirrored here because
/// the driver runs as a separate process.
const _keyedGaps4SkipExit = 75;

/// Dispatch for both batch-#4 sweeps and their individual cases. Called from
/// `dispatchFormFactor` (drive_real_ui_pair_msg_select.dart) for the same
/// reason batches #2 and #3 are: the aggregator `drive_real_ui_pair.dart` is
/// pinned in `tool/.complexity_baseline.txt` and the ratchet forbids growth.
/// Returns null when [scenario] is not ours so the caller keeps walking.
Future<int?> dispatchKeyedGaps4(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  if (scenario == 'sweep_keyed_gaps4') {
    return runKeyedGaps4Sweep(a, b, nickA, nickB);
  }
  if (scenario == 'sweep_keyed_gaps4_login') {
    return runKeyedGaps4LoginSweep(a, nickA);
  }
  if (_isKeyedGaps4CaseScenario(scenario)) {
    return runKeyedGaps4Case(a, b, nickA, nickB, scenario);
  }
  return null;
}

/// Standalone dispatch for ONE case (focused debugging). Shares the sweep's
/// preconditions; the group cases establish their own throwaway group and the
/// login case its own throwaway account.
Future<int> runKeyedGaps4Case(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario,
) async {
  bool? result;
  if (scenario == 'login_account_delete_confirm_removes_card') {
    result = await _kg4RunLoginCase(a, nickA);
  } else {
    final ids = await _kg3EnsureFriendship(a, b, nickA, nickB);
    if (ids == null) {
      print('[pair] $scenario: could not establish the A<->B friendship');
      return 1;
    }
    if (_keyedGaps4GroupCases.contains(scenario)) {
      result = await _kg3WithGroup(
        a,
        b,
        nickA,
        nickB,
        namePrefix: 'RUI-KG4-ONE',
        run: (est, _) => _kg4RunGroupCase(a, est, scenario),
      );
    } else {
      result = await _kg4RunFlatCase(a, b, ids.toxA, ids.toxB, scenario);
    }
  }
  await _msLandHome(a, scenario);
  final label = result == null ? 'SKIP' : (result ? 'PASS' : 'FAIL');
  print('[pair] $label: $scenario');
  return switch (result) {
    true => 0,
    false => 1,
    null => _keyedGaps4SkipExit,
  };
}

/// Thirteen cases (nine flat + four group) on ONE launch, ONE friendship
/// and ONE group.
///
/// ORDER: the friendship-only cases first (cheap, none of them mutates group
/// state), then the four group cases (both @-mention picker legs, @All, and
/// the atomic deletion) inside a single `_kg3WithGroup`. `_kg4Normalize` runs between every case
/// so a half-finished one cannot strand a modal onto the next.
Future<int> runKeyedGaps4Sweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final ids = await _kg3EnsureFriendship(a, b, nickA, nickB);
  if (ids == null) {
    print(
      '[sweep] sweep_keyed_gaps4: could not establish the A<->B friendship',
    );
    return 1;
  }
  final tally = _MobileShellTally('sweep_keyed_gaps4');
  for (final name in _keyedGaps4FlatCases) {
    await tally.run(
      name,
      () => _kg4RunFlatCase(a, b, ids.toxA, ids.toxB, name),
      expectedSkip: _keyedGaps4ExpectedSkipCases.contains(name),
    );
    await _kg4Normalize(a);
  }
  // A null from `_kg3WithGroup` means the GROUP itself could not be
  // established — a hard failure of the whole half, not a per-case skip.
  final groupHalfOk = await _kg3WithGroup(
    a,
    b,
    nickA,
    nickB,
    namePrefix: 'RUI-KG4',
    run: (est, toxB) async {
      for (final name in _keyedGaps4GroupCases) {
        await tally.run(
          name,
          () => _kg4RunGroupCase(a, est, name),
          expectedSkip: _keyedGaps4ExpectedSkipCases.contains(name),
        );
        await _kg4Normalize(a);
      }
      return true;
    },
  );
  await _msLandHome(a, 'sweep_keyed_gaps4');
  final endFriends =
      await areFriends(a, ids.toxB) && await areFriends(b, ids.toxA);
  print(
    '[sweep] sweep_keyed_gaps4: groupHalf=$groupHalfOk endFriends=$endFriends',
  );
  final tallyExit = tally.finish();
  if (groupHalfOk != true || !endFriends) return 1;
  return tallyExit;
}

Future<bool?> _kg4RunFlatCase(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
  String scenario,
) => switch (scenario) {
  'msg_select_clear_button_resets_count' => _kg4SelectClearResetsCount(a, toxB),
  'msg_select_forward_combined_absent_gating' => _kg4ForwardCombinedGating(
    a,
    toxB,
  ),
  'attachment_toolbar_disabled_entries_gating' => _kg4AttachmentToolbarGating(
    a,
    toxB,
  ),
  'mobile_attachment_panel_entries' => _kg4MobileAttachmentPanel(a, toxB),
  'mobile_voice_record_button_reveals' => _kg4VoiceRecordReveals(a, toxB),
  'message_viewer_save_and_zoom_surface' => _kg4ViewerSaveAndZoom(
    a,
    b,
    toxA,
    toxB,
  ),
  'mobile_chats_unread_badge_flips' => _kg4MobileUnreadBadgeFlips(
    a,
    b,
    toxA,
    toxB,
  ),
  'mobile_chat_back_clears_active_peer' => _kg4MobileChatBackClearsActivePeer(
    a,
    b,
    toxA,
    toxB,
  ),
  'mobile_search_contact_back_unbinds' => _kg4SearchContactBindsBack(
    a,
    b,
    toxA,
    toxB,
  ),
  _ => throw ArgumentError('unsupported keyed-gaps4 flat case: $scenario'),
};

Future<bool?> _kg4RunGroupCase(
  Inst a,
  _EstablishedGroup est,
  String scenario,
) => switch (scenario) {
  'mobile_mention_picker_confirm_inserts' => _kg4MentionPickerConfirm(a, est),
  'mobile_mention_picker_back_empty_selection' => _kg4MentionPickerBack(a, est),
  'mobile_mention_at_all_inserts' => _kg4MentionAtAllInserts(a, est),
  'mobile_mention_deletion_clears_token' => _kg4MentionDeletionClearsToken(
    a,
    est,
  ),
  _ => throw ArgumentError('unsupported keyed-gaps4 group case: $scenario'),
};

Future<bool?> _kg4RunLoginCase(Inst a, String nickA) =>
    _kg4LoginDeleteConfirm(a, nickA);

// ===========================================================================
// Shared teardown + probes
// ===========================================================================

/// Between-case teardown: leave select mode, dismiss anything modal, pop back
/// to the root. Never asserts — the cases do that.
Future<void> _kg4Normalize(Inst inst) async {
  try {
    await _mselForceLeaveSelectMode(inst);
    await _dismissMessageMenu(inst);
    await _kg3PopToRoot(inst);
  } on Object catch (e) {
    print('[pair] keyed-gaps4 normalize: best-effort: $e');
  }
}

/// Which composer is actually mounted in the currently open chat.
///
/// A LIVE probe, never a platform name: the desktop input builder stays in use
/// on a narrowed desktop window, so a width heuristic would mis-route. Returns
/// `desktop`, `mobile`, or `unknown` when neither anchor resolves (which is a
/// case failure, not a skip — it means no composer rendered at all).
enum _Kg4Composer { desktop, mobile, unknown }

Future<_Kg4Composer> _kg4ComposerKind(Inst inst) async {
  // The desktop toolbar always carries the File entry (toxee's
  // `_buildDesktopInputOptions` starts with `Icons.attach_file`); the mobile
  // composer always carries the "+" overlay opener. Probe the MOBILE anchor
  // first: the mobile attachment PANEL also exposes a
  // `message_attachment_file_button`, so a file-first probe would report
  // "desktop" whenever a panel happened to be open.
  if (await inst.waitKeyCenter(
    'message_attachment_options_button',
    timeoutSecs: 4,
  )) {
    return _Kg4Composer.mobile;
  }
  if (await inst.waitKeyCenter(
    'message_attachment_file_button',
    timeoutSecs: 4,
  )) {
    return _Kg4Composer.desktop;
  }
  return _Kg4Composer.unknown;
}

/// Poll until [key] is no longer resolvable through the ELEMENT-TREE walk.
///
/// Same reason batch #3 has `_kg3WaitKeyCenterGone`: `Inst.waitKeyGone` reads
/// flutter_skill's interactive-element index, which never surfaces overlay
/// entries, `KeyedSubtree`s or bare `Listener`s — exactly the widgets this
/// batch asserts on — so it would report "gone" on the first poll while the
/// widget is still on screen, turning the assertion into a no-op.
Future<bool> _kg4WaitKeyCenterGone(
  Inst inst,
  String key, {
  int timeoutSecs = 8,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await inst.keyCenter(key) == null) return true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

/// Set the open chat composer's text through the production controller seam and
/// give the fork's listeners a frame to react.
///
/// `l3_composer_set_text` drives the SAME `TextEditingController` a keystroke
/// would, so `_onTextChanged` (send-button swap, draft save, the `@` branch)
/// runs for real. It is used here strictly as PLUMBING — no case in this batch
/// asserts the keystroke itself, which is why none of them has to SKIP on a
/// device the way `sweep_group_mention` does.
Future<bool> _kg4SetComposerText(Inst inst, String text) async {
  try {
    final r = await inst.l3('l3_composer_set_text', {'text': text});
    if (r['ok'] != true) {
      print('[pair] keyed-gaps4: l3_composer_set_text failed: $r');
      return false;
    }
  } on DriveError catch (e) {
    print('[pair] keyed-gaps4: composer seam error: ${e.message}');
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
  return true;
}

/// Retry [body] until it returns true or [attempts] elapse.
///
/// RELOCATED from `drive_real_ui_pair.dart` (unchanged — same library) so this
/// batch's five `part` directives fit without re-pinning the aggregator, which
/// `tool/.complexity_baseline.txt` holds at a ratchet that forbids growth. This
/// is the same move batch #3 made with `_safeDispose`.
Future<bool> _retryBool(
  Future<bool> Function() body, {
  required String label,
  int attempts = 30,
  int intervalMs = 1000,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (await body()) return true;
    await Future<void>.delayed(Duration(milliseconds: intervalMs));
  }
  print('[retry] "$label" never became true');
  return false;
}
