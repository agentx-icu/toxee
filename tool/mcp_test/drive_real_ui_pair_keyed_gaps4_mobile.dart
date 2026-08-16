// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Keyed-gaps batch #4 — the NARROW-SHELL half: three surfaces that exist ONLY
// on the mobile composer / bottom-nav shell and that no scenario had ever
// touched. Spine and dispatch live in `drive_real_ui_pair_keyed_gaps4.dart`;
// this file holds only case bodies so each part stays under the 500-LOC cap.

// ===========================================================================
// case — mobile_voice_record_button_reveals
// ===========================================================================
/// `chat_voice_record_button` — the hold-to-record mic. The key was declared in
/// `ui_keys.dart` but the fork attached NOTHING, so the control was invisible to
/// every driver; this batch keys the `Listener` itself (see the spine header for
/// why not the animated ancestor).
///
/// WHAT IS ASSERTED — the MUTUAL EXCLUSION of the composer's trailing control.
/// The mic and `chat_send_button` are the two arms of ONE ternary on
/// `_showSendButton`, which `_onTextChanged` flips on the empty/non-empty
/// transition. So:
///   empty composer  -> mic MOUNTED   and send ABSENT
///   text in composer-> send MOUNTED  and mic  ABSENT
///   cleared again   -> mic MOUNTED   and send ABSENT
/// `mobile_composer_send_button_reveals` already watches the send arm, but it
/// cannot see the mic arm at all — "the send button is gone" is satisfied just
/// as well by a composer that rendered NOTHING. Driving both arms is what turns
/// that into a real invariant.
///
/// THE MIC IS NOT PRESSED. `_onStartRecording` asks for the microphone
/// permission and starts a recorder; the recorded artefact is not observable
/// through any seam, and a permission sheet would block the rest of the sweep.
/// The reveal/hide state machine is the assertable part and is what this case
/// takes; the recording itself stays on the documented "not covered on mobile"
/// list.
///
/// SKIP on the desktop composer (live probe): it has no trailing send/mic
/// control at all — sending is Enter-driven.
Future<bool?> _kg4VoiceRecordReveals(Inst a, String toxB) async {
  const label = 'mobile_voice_record_button_reveals';
  const mic = 'chat_voice_record_button';
  const send = 'chat_send_button';
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] $label: A could not open the C2C chat');
    return false;
  }
  if (await _kg4ComposerKind(a) != _Kg4Composer.mobile) {
    print(
      '[pair] $label: SKIP — this shell renders the DESKTOP composer, which '
      'has no trailing send/mic control (sending is Enter-driven), so neither '
      'arm of the ternary exists here.',
    );
    return null;
  }
  if (!await _kg4SetComposerText(a, '')) return false;
  final micEmpty = await a.waitKeyCenter(mic, timeoutSecs: 8);
  final sendEmpty = await a.keyCenter(send) != null;
  if (!micEmpty) {
    await a.shot('/tmp/ui_kg4_mic_absent_${a.name}.png');
    print(
      '[pair] $label: FAIL — the mic control did not render on an EMPTY mobile '
      'composer. It is the else-arm of the `_showSendButton` ternary in '
      'tencent_cloud_chat_message_input_mobile.dart, so either the key was not '
      'attached in this build or the composer rendered no trailing control.',
    );
    return false;
  }

  final probe = 'KG4MIC${DateTime.now().microsecondsSinceEpoch % 100000}';
  if (!await _kg4SetComposerText(a, probe)) return false;
  final sendTyped = await a.waitKeyCenter(send, timeoutSecs: 8);
  final micTyped = await _kg4WaitKeyCenterGone(a, mic, timeoutSecs: 8);

  if (!await _kg4SetComposerText(a, '')) return false;
  final micBack = await a.waitKeyCenter(mic, timeoutSecs: 8);
  final sendBack = await _kg4WaitKeyCenterGone(a, send, timeoutSecs: 8);
  await a.shot('/tmp/ui_kg4_mic_${a.name}.png');

  print(
    '[pair] $label: empty{mic=$micEmpty sendPresent=$sendEmpty} '
    'typed{send=$sendTyped micGone=$micTyped} '
    'cleared{mic=$micBack sendGone=$sendBack}',
  );
  return micEmpty && !sendEmpty && sendTyped && micTyped && micBack && sendBack;
}

// ===========================================================================
// case — mobile_chats_unread_badge_flips
// ===========================================================================
/// `home_chats_unread_badge` — the MOBILE bottom-nav twin of
/// `sidebar_chats_unread_badge`. The desktop key is driven by
/// `unread_badge_total_sidebar` (sweep_p1_chat, iPad-only); the mobile one is a
/// DIFFERENT widget in a different subtree, deliberately given its own key so an
/// offstage twin can never false-positive the other's probe — and nothing had
/// ever driven it.
///
/// WHAT IS ASSERTED. The badge exists in the tree only while
/// `totalUnreadCount > 0` (count == 0 renders `SizedBox.shrink`), so its
/// presence/absence IS the state:
///   1. a drained 0 baseline with the badge ABSENT — asserted, not assumed, and
///      a baseline that will not drain FAILS rather than being papered over
///      (the same "refuse a fuzzy baseline" rule the sidebar case uses);
///   2. after ONE real inbound from B, `totalUnreadCount == 1` in the dump AND
///      the badge MOUNTS;
///   3. after A opens the conversation for real, the total returns to 0 AND the
///      badge UNMOUNTS.
/// The dump total and the widget are asserted TOGETHER: the dump alone would
/// not prove the bottom-nav rendered it, and the key alone would not prove the
/// count was right.
///
/// SKIP on any shell without a bottom navigation bar — the wide/desktop layout
/// renders the sidebar rail and its own already-covered badge.
Future<bool?> _kg4MobileUnreadBadgeFlips(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  const label = 'mobile_chats_unread_badge_flips';
  const badge = 'home_chats_unread_badge';
  await a.foreground();
  await returnToChatsHome(a, rounds: 4);
  if (!await _msPhoneShell(a)) {
    print(
      '[pair] $label: SKIP — this shell has no bottom navigation bar '
      '(home_bottom_nav unresolvable), so the mobile badge does not exist. The '
      'wide layout renders sidebar_chats_unread_badge, which '
      'unread_badge_total_sidebar already drives.',
    );
    return null;
  }

  // --- 1. drain to a real 0 baseline ---
  //
  // The C2C row must be PRESENT in the dump, not merely absent-and-therefore-0:
  // the sidebar twin (`unread_badge_total_sidebar`) already refuses that
  // vacuous baseline via its `tracked` guard, and without the same guard a
  // conversation list that never hydrated would drain "clean" here and then
  // make the up-phase unfalsifiable.
  //
  // THE CLEAR IS MARKED, AND IT IS NOT SWALLOWED. `l3_clear_active_conversation`
  // is test-gated, and a real-UI account registered by this sweep is a PRODUCT
  // account, so an unmarked call answers `non_test_account`. That refusal used
  // to be swallowed as benign — and it is anything but: the ACTIVE peer reads
  // unread 0 by construction (`FfiChatService.getC2CUnreadCount` short-circuits
  // on `_activePeerId`), so the baseline "drained to 0" while the conversation
  // was still bound, the inbound was marked read on arrival, and the case
  // reported a broken badge that was really a live diagnosis of its own
  // precondition. Live-proved on iPhone 2026-08-16: no
  // `l3_clear_active_conversation: cleared …` line ever reached A's log while
  // `l3_force_home_root` — which already marks around its retry — logged its
  // clears fine. Same `markAccountTest` idiom `_kg4ViewerSaveAndZoom` uses for
  // `l3_send_file`; the mark is revoked in the `finally`.
  final c2cId = _c2cConvId(toxB);
  var drained = false;
  var baseline = -1;
  var baselinePerConv = const <String, int>{};
  final aMarked = await a.markAccountTest();
  try {
    for (var pass = 0; pass < 4 && !drained; pass++) {
      await openChat(a, toxB);
      await returnToChatsHome(a, rounds: 4);
      try {
        await a.clearActiveConversation();
      } on DriveError catch (e) {
        print(
          '[pair] $label: the active conversation could not be unbound '
          '(${e.message}) — every unread assertion below would be vacuous',
        );
        return false;
      }
      final (zero, total) = await _p1cWaitTotalUnread(
        a,
        (u) => u == 0,
        timeoutSecs: 15,
      );
      baseline = total;
      baselinePerConv = await _p1cConvUnreads(a);
      final tracked = baselinePerConv.containsKey(c2cId);
      print(
        '[pair] $label: baseline pass $pass total=$total tracked=$tracked '
        'perConv=$baselinePerConv',
      );
      drained = zero && tracked;
    }
    if (!drained) {
      print(
        '[pair] $label: the unread baseline never drained to a tracked 0 '
        '(totalUnreadCount=$baseline perConv=$baselinePerConv) — refusing a '
        'fuzzy-baseline assert',
      );
      return false;
    }
    final badgeGoneAtBaseline = await _kg4WaitKeyCenterGone(
      a,
      badge,
      timeoutSecs: 6,
    );
    print('[pair] $label: post-drain ${await _kg4ActiveConvSnapshot(a)}');

    // --- 2. one real inbound ---
    final nonce = DateTime.now().microsecondsSinceEpoch % 1000000;
    final probe = 'KG4BADGE-$nonce';
    await b.foreground();
    await openChat(b, toxA);
    if (!await sendComposerMessage(b, probe)) {
      print('[pair] $label: B could not send through its real composer');
      return false;
    }
    await a.foreground();
    print('[pair] $label: pre-assert ${await _kg4ActiveConvSnapshot(a)}');
    final (bumped, total) = await _p1cWaitTotalUnread(
      a,
      (u) => u == 1,
      timeoutSecs: 45,
    );
    final badgeShown =
        await a.waitKeyCenter(badge, timeoutSecs: bumped ? 10 : 2) ||
        await a.waitKey(badge, timeoutSecs: 2);
    final badgeText = await _keyedText(a, badge); // breadcrumb only
    await a.shot('/tmp/ui_kg4_badge_up_${a.name}.png');
    if (!bumped || !badgeShown) {
      // Separate the three ways this phase can fail, which the bare
      // "totalUnreadCount=0 want 1" line could not tell apart:
      //   delivered=false          -> the inbound never reached A at all
      //   delivered, perConv 0     -> it arrived but was counted as READ
      //                               (an active-conversation / mark-read path)
      //   perConv 1, total 0       -> the per-row count is right and the UIKit
      //                               store aggregate is stale
      final upPerConv = await _p1cConvUnreads(a);
      final delivered = (await _c2cMessages(
        a,
        toxB,
      )).any((m) => (m['text']?.toString() ?? '').contains(probe));
      final st = await a.dumpState();
      // When the COUNT is right but the badge will not resolve, the question is
      // whether the widget is missing or merely unprobeable: it is a
      // `Positioned(top:-5, right:-6)` in a `Stack(clipBehavior: Clip.none)`
      // inside `BottomNavigationBarItem.icon`, so it paints OUTSIDE its parent's
      // bounds and a hit-test-validating centre probe can refuse it. Report the
      // PARENT stack and the rendered digit: parent resolvable + digit on screen
      // means the driver's geometry rule, not a missing badge.
      final navChats = await a.keyCenter('bottom_nav_chats_tab') != null;
      final digitUp = await a.waitText('$total', timeoutSecs: 2);
      print(
        '[pair] $label: up-phase failed (totalUnreadCount=$total want 1, '
        'badgeShown=$badgeShown delivered=$delivered perConv=$upPerConv '
        'navChatsResolvable=$navChats digitOnScreen=$digitUp '
        'currentConversation=${st['currentConversation']})',
      );
      return false;
    }

    // --- 3. read it and watch the badge go ---
    await openChat(a, toxB);
    await returnToChatsHome(a, rounds: 4);
    await a.clearActiveConversation();
    final (cleared, afterTotal) = await _p1cWaitTotalUnread(
      a,
      (u) => u == 0,
      timeoutSecs: 30,
    );
    final badgeGone = await _kg4WaitKeyCenterGone(a, badge, timeoutSecs: 12);
    print(
      '[pair] $label: baselineBadgeGone=$badgeGoneAtBaseline badgeText=$badgeText '
      'bumped=$bumped cleared=$cleared afterTotal=$afterTotal '
      'badgeGone=$badgeGone',
    );
    return badgeGoneAtBaseline && cleared && badgeGone;
  } finally {
    if (aMarked) await a.unmarkAccountTest();
  }
}

/// `{homeShellTab, currentConversation}` in one line.
///
/// The unread contract is ACTIVE-CONVERSATION-gated end to end
/// (`FfiChatService.getC2CUnreadCount` returns 0 for `_activePeerId`, and the
/// facade's `currentConversation` is set/cleared alongside it), so an inbound
/// that lands while the conversation still counts as open is READ on arrival
/// and can never raise the badge. Sampling this on both sides of the send is
/// what separates "the count is broken" from "the conversation was never
/// deactivated".
Future<String> _kg4ActiveConvSnapshot(Inst inst) async {
  final st = await inst.dumpState();
  final cur = st['currentConversation'];
  final id = cur is Map ? cur['conversationID'] : cur;
  return 'homeShellTab=${st['homeShellTab']} currentConversation=$id';
}

// ===========================================================================
// cases — mobile_mention_picker_{confirm_inserts,back_empty_selection}
// ===========================================================================
/// The MOBILE @-mention picker (`TencentCloudChatAtGroupMemberList`). Before
/// this batch it had ZERO keys of any kind while the desktop inline panel had
/// the whole `mention_member:*` contract — so `ui_keys.dart`'s claim that "the
/// DESKTOP inline panel and the MOBILE full-screen picker share this key
/// contract" was only half true, and no driver could reach the mobile surface.
/// This batch keys the row (`mention_member:<uid>` / `mention_member:atAll`),
/// the app-bar back affordance and the app-bar confirm action.
///
/// WHY THIS IS NOT `sweep_group_mention` ON A PHONE. That sweep's assertion IS
/// the `osaType('@')` keystroke reaching the desktop composer, which is why it
/// must SKIP on a device. Here the `@` is PLUMBING for the surface under test:
/// the composer's controller listener is what opens the picker, and
/// `l3_composer_set_text` drives that exact production controller. The thing
/// asserted is the picker route and what it inserts, not the keystroke.
///
/// HOW THE `@` IS DELIVERED. `_onTextChanged` opens the picker only when
/// `compareString(old, new)` reports a single ADDED character equal to `@`, so
/// the case sets the prefix FIRST and then appends the `@` in a second call —
/// setting `"KG4…@"` in one shot would report an added `K` and never trigger.
Future<bool?> _kg4MentionPickerConfirm(Inst a, _EstablishedGroup est) =>
    _kg4MentionPicker(
      a,
      est,
      confirm: true,
      label: 'mobile_mention_picker_confirm_inserts',
    );

Future<bool?> _kg4MentionPickerBack(Inst a, _EstablishedGroup est) =>
    _kg4MentionPicker(
      a,
      est,
      confirm: false,
      label: 'mobile_mention_picker_back_empty_selection',
    );

/// Shared body for the two @-picker cases.
///
/// [confirm] == true drives: open the picker -> tap a REAL member row (which
/// ticks its checkbox and appends to `selectMembers`) -> tap
/// `mention_member_list_confirm_button`. The `@` in the composer is then
/// REPLACED by `"@<label> "` and the case SENDS through the production submit
/// seam, so the assertion is what the PEER actually received — an end-to-end
/// observable that no in-app probe could fake.
///
/// [confirm] == false drives: open the picker -> select NOTHING -> tap
/// `mention_member_list_back_button`. Back is NOT a cancel here (both app-bar
/// affordances call the same `_submitAtMemberList()`), so the contract under
/// test is that an EMPTY selection inserts nothing: `_onTextChanged` only
/// rewrites the text `if (memberList.isNotEmpty)`. The peer must receive the
/// probe text with a bare trailing `@` and no member label — which is a real
/// negative that the positive case above proves is reachable.
///
/// SKIP on the desktop composer: it uses the inline mention PANEL, which
/// `sweep_group_mention` already drives, and never pushes this route.
Future<bool?> _kg4MentionPicker(
  Inst a,
  _EstablishedGroup est, {
  required bool confirm,
  required String label,
}) async {
  const backKey = 'mention_member_list_back_button';
  const confirmKey = 'mention_member_list_confirm_button';
  final gid = est.groupIdA;
  await openGroupChat(
    a,
    groupId: gid,
    groupName: est.groupName,
    viaL3Seam: true,
  );
  if (await _kg4ComposerKind(a) != _Kg4Composer.mobile) {
    print(
      '[pair] $label: SKIP — this shell renders the DESKTOP composer, which '
      'resolves @-mentions through the INLINE panel '
      '(..._input_member_mention_panel.dart) and never pushes '
      'TencentCloudChatAtGroupMemberList. sweep_group_mention covers that '
      'surface.',
    );
    return null;
  }
  final member = await _kg4PickPeerMember(a, gid, label);
  if (member == null) return false;

  final nonce = DateTime.now().microsecondsSinceEpoch % 1000000;
  final prefix = confirm ? 'KG4MENT$nonce' : 'KG4BACK$nonce';
  if (!await _kg4SetComposerText(a, prefix)) return false;
  if (!await _kg4SetComposerText(a, '$prefix@')) return false;

  final routeUp =
      await a.waitKeyCenter(confirmKey, timeoutSecs: 12) &&
      await a.waitKeyCenter(backKey, timeoutSecs: 4);
  if (!routeUp) {
    await a.shot('/tmp/ui_kg4_mention_noroute_${a.name}.png');
    await _kg3PopToRoot(a);
    print(
      '[pair] $label: the @-mention picker route never mounted after the '
      'composer gained a single "@" — `_onTextChanged` should have called '
      '`onChooseGroupMembers()` and pushed TencentCloudChatAtGroupMemberList',
    );
    return false;
  }
  final rowKey = 'mention_member:${member.userId}';
  final rowUp = await a.waitKeyCenter(rowKey, timeoutSecs: 8);
  if (!rowUp) {
    await a.shot('/tmp/ui_kg4_mention_norow_${a.name}.png');
    await a.tapKeyCenter(backKey, timeoutSecs: 6);
    await _kg3PopToRoot(a);
    print(
      '[pair] $label: the picker mounted but member row $rowKey did not — the '
      'list is built from `_dataProvider.groupMemberList` minus self, and '
      'l3_group_member_list reported this member as a non-self peer',
    );
    return false;
  }

  if (confirm && !await a.tapKeyCenter(rowKey, timeoutSecs: 6)) {
    await a.tapKeyCenter(backKey, timeoutSecs: 6);
    await _kg3PopToRoot(a);
    print('[pair] $label: the member row could not be tapped');
    return false;
  }
  final exitKey = confirm ? confirmKey : backKey;
  if (!await a.tapKeyCenter(exitKey, timeoutSecs: 8)) {
    await _kg3PopToRoot(a);
    print('[pair] $label: $exitKey could not be tapped');
    return false;
  }
  final routeGone =
      await _kg4WaitKeyCenterGone(a, confirmKey, timeoutSecs: 10) &&
      await _kg4WaitKeyCenterGone(a, backKey, timeoutSecs: 6);
  await Future<void>.delayed(const Duration(milliseconds: 800));

  // The composer text is not readable through any seam, so the insertion is
  // asserted where it is genuinely observable: in what the GROUP receives.
  await a.l3('l3_composer_send', const {});
  final sent = await _kg4WaitGroupTextStartingWith(a, gid, prefix);
  await a.shot(
    '/tmp/ui_kg4_mention_${confirm ? 'confirm' : 'back'}_${a.name}.png',
  );
  if (sent == null) {
    print(
      '[pair] $label: the composer message never reached the group, so the '
      'insertion could not be asserted',
    );
    return false;
  }
  final labels = <String>[
    if (member.nickName.isNotEmpty) member.nickName,
    member.userId,
  ];
  final mentioned = labels.any((l) => sent.contains('@$l'));
  print(
    '[pair] $label: routeGone=$routeGone member=${member.userId} '
    'nick="${member.nickName}" sentText="$sent" mentionInserted=$mentioned',
  );
  if (!routeGone) return false;
  if (confirm) return mentioned;
  // Empty-selection contract: the bare "@" survives and NO label was inserted.
  return !mentioned && sent == '$prefix@';
}

/// One NON-SELF member of [gid] from `l3_group_member_list`, or null.
///
/// The userID is the NGC GROUP-SPECIFIC public key (the identity the mention
/// row keys on), NOT the peer's friend Tox id — which is exactly why the case
/// cannot just use `toxB`.
Future<({String userId, String nickName})?> _kg4PickPeerMember(
  Inst a,
  String gid,
  String label,
) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    final r = await a.l3('l3_group_member_list', {'groupId': gid});
    final raw = (r['members'] as List?) ?? const [];
    for (final m in raw) {
      if (m is! Map) continue;
      if (m['isSelf'] == true) continue;
      final uid = m['userID']?.toString() ?? '';
      if (uid.isEmpty) continue;
      return (userId: uid, nickName: m['nickName']?.toString() ?? '');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  print('[pair] $label: no non-self member ever appeared in $gid');
  return null;
}

/// A's newest OWN group message whose text starts with [prefix], or null.
Future<String?> _kg4WaitGroupTextStartingWith(
  Inst inst,
  String gid,
  String prefix, {
  int timeoutSecs = 40,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    for (final m in await _kg3GroupMessages(inst, gid)) {
      if (m['isSelf'] != true) continue;
      final t = m['text']?.toString() ?? '';
      if (t.startsWith(prefix)) return t;
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  return null;
}
