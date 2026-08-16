// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Keyed-gaps batch #3 — the CONTACTS / FRIEND-PROFILE / C2C-COMPOSER half.
// Spine, dispatch and the message-menu cases live in
// `drive_real_ui_pair_keyed_gaps3.dart`; this file only holds case bodies so
// each part stays under the 500-LOC complexity cap.

// ===========================================================================
// case — contact_application_detail_decline_removes_row
// ===========================================================================
/// The friend-application DETAIL screen has two keyed actions:
/// `contact_application_detail_accept_button:<uid>` — already driven by
/// `handshake_detail` / `driveRespondViaDetail` — and its DECLINE twin
/// `contact_application_detail_decline_button:<uid>`
/// (tencent_cloud_chat_contact_application_info.dart:382 / :398), which nothing
/// had ever touched. The inline row Decline
/// (`contact_application_decline_button:<uid>`) is a DIFFERENT widget on a
/// different route and is covered by `driveRespondToApplication`.
///
/// SINGLE INSTANCE. The applicant is materialised with
/// `l3_inject_friend_application`, so no peer is stopped or re-registered and
/// the A<->B friendship the rest of the sweep depends on is untouched.
///
/// WHAT IS ASSERTED. Before the tap: the application is in
/// `l3_dump_state.friendApplications` AND both detail buttons are mounted (so
/// the route really is the detail screen, not the list). After the tap: the
/// decline button is UNMOUNTED **or** the application is gone from the dump.
/// The disjunction is deliberate — `onRefuseApplication` has TWO legitimate
/// product paths (application_info.dart:319-345): on `resultCode == 0` it
/// swaps the whole action column for the localized result text (both buttons
/// unmount), and on a non-zero code it calls
/// `deleteApplicationList([...])` (the application leaves the model). Either
/// outcome proves the real handler ran; neither can be produced by a tap that
/// merely "did not throw".
Future<bool?> _kg3ApplicationDetailDecline(Inst a) async {
  const label = 'contact_application_detail_decline_removes_row';
  // A deterministic, obviously-synthetic 64-hex public key (16 hex chars x 4).
  // It is never befriended (the case declines it), so it cannot collide with B
  // or with any fixture account.
  const applicantId =
      'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789';
  const nickname = 'KG3 Decline Probe';
  const declineKey =
      'contact_application_detail_decline_button:$applicantId';
  const acceptKey = 'contact_application_detail_accept_button:$applicantId';
  const rowKey = 'contact_application_item:$applicantId';

  await a.foreground();
  final marked = await a.markAccountTest();
  try {
    final seeded = await a.l3('l3_inject_friend_application', {
      'userId': applicantId,
      'nickname': nickname,
      'wording': 'keyed-gaps3 decline probe',
    });
    if (seeded['ok'] != true) {
      print('[pair] $label: l3_inject_friend_application failed: $seeded');
      return false;
    }
  } finally {
    await _kg3Unmark(a, marked);
  }
  if (!await _kg3WaitApplicationPresent(a, applicantId, present: true)) {
    print('[pair] $label: the seeded application never reached the dump');
    return false;
  }

  // Open Contacts -> New Contacts -> the application ROW -> the detail route.
  await ensureContactsShell(a);
  if (!await a.tryTapKey('contact_new_contacts_tab', retries: 2)) {
    print('[pair] $label: the New Contacts sub-tab was not tappable');
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 900));
  var onDetail = false;
  for (var attempt = 0; attempt < 3 && !onDetail; attempt++) {
    if (!await a.tryTapKey(rowKey, retries: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      continue;
    }
    onDetail = await a.waitKeyCenter(declineKey, timeoutSecs: 6);
  }
  final acceptPresent = await a.waitKeyCenter(acceptKey, timeoutSecs: 3);
  if (!onDetail || !acceptPresent) {
    await a.shot('/tmp/ui_kg3_appdetail_${a.name}.png');
    print(
      '[pair] $label: detail route did not render both actions '
      '(decline=$onDetail accept=$acceptPresent)',
    );
    return false;
  }

  if (!await a.tapKeyCenter(declineKey, timeoutSecs: 6)) {
    print('[pair] $label: the detail Decline action was not tappable');
    return false;
  }
  // THE VERDICT IS THE RESULT TEXT, not the row disappearing.
  //
  // `onRefuseApplication` (tencent_cloud_chat_contact_application_info.dart
  // :320-346) has two arms and only ONE of them is success:
  //   * success (`res.userID == application.userID && res.resultCode == 0`)
  //     swaps the whole action body for `Text(tL10n.declined)` — `defaultBuilder`
  //     returns the result container instead of the Agree/Decline pair.
  //   * FAILURE (`invalidApplication`) fires a user-notification event and then
  //     calls `deleteApplicationList([...])` anyway.
  // So "the application is gone" is satisfied by the ERROR path, and `alive`
  // (`sessionReady == true`) is near-tautological — the old
  // `(buttonGone || removed) && alive` passed with `refuseFriendApplication`
  // returning non-zero forever. `tL10n.declined` is reachable ONLY from the
  // success arm, so it is the assertion; the other two stay as diagnosis.
  final declinedShown = await _kg3WaitDeclinedResult(a);
  // "THE ACTIONS WENT AWAY" IS AN **ONSTAGE** ASSERTION, NOT AN EXISTENCE ONE.
  //
  // The row tap that opens this screen goes through `skill('tap')`, which
  // DOUBLE-FIRES (see the `focusType` doc in drive_real_ui_pair_inst.dart:
  // "not the double-firing synthetic `tap`"). The item's `onTap` is
  // `gotoApplicationInfoPage` → `Navigator.push`, so one driver tap can push
  // TWO identical detail routes. The decline lands on the TOP one, which swaps
  // its action column for `Text(tL10n.declined)` exactly as designed; the route
  // UNDERNEATH keeps its own Agree/Decline pair mounted and laid out, because an
  // opaque `MaterialPageRoute` does not `Offstage` the route below it. The old
  // `_kg3WaitKeyCenterGone` resolves through `resolveKeyCenter`'s COVERED
  // full-tree fallback, so it kept finding that buried button and reported
  // "still there" for the full 10s — failing a decline the post-tap screenshot
  // shows working perfectly (live-diagnosed on Android 2026-08-16:
  // `declinedResultShown=true declineButtonGone=false applicationRemoved=true`).
  //
  // This is the SAME correction `_kg3MemberInfoProfileEntry` already made for
  // the same root cause. It is NOT a weakened assertion: if the product failed
  // to swap, the TOP (visible) route's decline button would still be ONSTAGE
  // and this stays false. What is dropped is only the claim that no COVERED
  // duplicate may exist, which was never this case's subject.
  final actionsNotOnstage = await _kg3WaitKeyNotOnstage(
    a,
    declineKey,
    timeoutSecs: 10,
  );
  // Kept as DIAGNOSIS so a future red says which of the two shapes it is:
  // `candidates: 2, onstage: false` is the buried-duplicate shape above;
  // `candidates: 1, onstage: true` is a genuine product regression.
  final declineDetail = await a.keyCenterDetail(declineKey);
  final removed = await _kg3WaitApplicationPresent(
    a,
    applicantId,
    present: false,
    timeoutSecs: 12,
  );
  final alive = (await a.dumpState())['sessionReady'] == true;
  await a.shot('/tmp/ui_kg3_appdetail_after_${a.name}.png');
  await _kg3PopToRoot(a);
  print(
    '[pair] $label: declinedResultShown=$declinedShown '
    'declineActionsNotOnstage=$actionsNotOnstage '
    'declineKeyCandidates=${declineDetail?['candidates']} '
    'declineKeyOnstage=${declineDetail?['onstage']} '
    'applicationRemoved=$removed alive=$alive',
  );
  return declinedShown && actionsNotOnstage && alive;
}

/// Poll for the detail route's post-decline RESULT text (`tL10n.declined`).
///
/// Locale-tolerant by construction: the app under test may run in any of the
/// UIKit's shipped locales, so every translation of that ONE key is accepted
/// (tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations_*.dart
/// `String get declined`). Matching the key's translations — rather than a
/// generic "the buttons went away" — is what keeps the assertion tied to the
/// success arm of `onRefuseApplication`.
Future<bool> _kg3WaitDeclinedResult(Inst inst, {int timeoutSecs = 12}) async {
  const declined = <String>['Declined', '已拒绝', '已拒絕', '拒否済み', '거부됨', 'مرفوض'];
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    for (final text in declined) {
      if (await inst.waitText(text, timeoutSecs: 1)) return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

/// Poll `l3_dump_state.friendApplications` until [applicantId]'s presence
/// matches [present].
Future<bool> _kg3WaitApplicationPresent(
  Inst inst,
  String applicantId, {
  required bool present,
  int timeoutSecs = 20,
}) async {
  final want = _pubkey(applicantId);
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState();
    final apps = (s['friendApplications'] as List?) ?? const [];
    final has = apps.any(
      (e) => e is Map && _pubkey(e['userId']?.toString() ?? '') == want,
    );
    if (has == present) return true;
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
  return false;
}

// ===========================================================================
// case — friendprof_copy_toxid_snackbar
// ===========================================================================
/// The friend profile's Tox-ID copy affordance
/// (`user_profile_copy_id_button`, tencent_cloud_chat_user_profile_body.dart
/// :269) was keyed but never driven — the profile cases only ever drove the
/// remark / mute / block / delete controls.
///
/// WHAT IS ASSERTED. The production `onPressed` does two things: it writes the
/// friend's userID to the clipboard and then shows a SnackBar whose text is a
/// hard-coded, locale-independent `'Tox ID copied'`
/// (user_profile_body.dart:279-287). The snackbar is the in-app observable this
/// case gates on, and it is asserted GONE first so a leftover toast from an
/// earlier case cannot false-pass (the same discipline
/// `profile_qr_copy` needed). The clipboard itself is deliberately NOT read
/// back: the only in-app seam is `l3_set_clipboard` (write-only), and reading
/// the HOST pasteboard is meaningless for an iOS/Android instance — the same
/// scope decision `profile_copy_toxid_snackbar` records.
Future<bool?> _kg3FriendProfileCopyToxId(Inst a, String toxB) async {
  const label = 'friendprof_copy_toxid_snackbar';
  const snack = 'Tox ID copied';
  if (!await _ensureFriendProfileOpen(a, toxB)) {
    print('[pair] $label: the friend profile did not open');
    return false;
  }
  // Clear any lingering toast so the post-tap wait proves THIS tap.
  await a.waitTextGone(snack, timeoutSecs: 6);
  if (!await a.waitKeyCenter('user_profile_copy_id_button', timeoutSecs: 6)) {
    await a.shot('/tmp/ui_kg3_copyid_absent_${a.name}.png');
    print('[pair] $label: user_profile_copy_id_button did not render');
    return false;
  }
  final tapped =
      await a.tapKeyCenter('user_profile_copy_id_button', timeoutSecs: 6) ||
      await a.tryTapKey('user_profile_copy_id_button', retries: 2);
  if (!tapped) {
    print('[pair] $label: the copy button was not tappable');
    return false;
  }
  final shown = await a.waitText(snack, timeoutSecs: 8);
  await a.shot('/tmp/ui_kg3_copyid_${a.name}.png');
  // Leave the toast cleared for the next case.
  await a.waitTextGone(snack, timeoutSecs: 8);
  await ensureContactsShell(a);
  print('[pair] $label: snackbarShown=$shown');
  return shown;
}

// ===========================================================================
// case — personal_card_send_c2c
// ===========================================================================
/// `message_attachment_personal_card_button` is the ONE live member of the
/// desktop attachment-toolbar key family — batch #2 established that
/// `message_attachment_{image,photo,video,search}_button` are dead under
/// toxee's attachment config. The key is attached by the fork's DESKTOP input
/// builder, keyed off `Icons.qr_code_2`
/// (tencent_cloud_chat_message_input_desktop.dart:654-663), and toxee only adds
/// that option for C2C (`if (userID != null)`, lib/ui/home_page.dart:1000-1003).
///
/// FORM FACTOR — LIVE PROBE, not a platform name. The desktop toolbar and the
/// mobile "+" attachment overlay are different widgets; this case detects which
/// composer is actually mounted (`message_attachment_file_button` /
/// `message_attachment_personal_card_button` vs
/// `message_attachment_options_button`) and SKIPs on the mobile composer, which
/// has no personal-card entry at all. A narrowed desktop window keeps the
/// desktop builder, so a width heuristic would be wrong here.
///
/// WHAT IS ASSERTED. `onPressed` renders a self QR card image and sends it as a
/// FILE when the friend is online, or — when offline — posts a two-line failure
/// TEXT into the same conversation (lib/ui/home_page.dart:1004-1050). Both
/// product branches add exactly one message to A's C2C history, and the online
/// branch additionally raises the `'Personal Card sent'` snackbar. The case
/// gates on "the conversation grew, or the snackbar appeared" — a real
/// side effect either way — and never on the tap alone. Nothing is deleted, so
/// the friendship and the row survive.
Future<bool?> _kg3PersonalCardSendC2c(Inst a, String toxB) async {
  const label = 'personal_card_send_c2c';
  const cardKey = 'message_attachment_personal_card_button';
  const sentSnack = 'Personal Card sent';
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] $label: A could not open the C2C chat');
    return false;
  }
  // Probe BOTH composer surfaces in one interleaved poll instead of waiting out
  // the desktop key first and then giving the mobile key a 3 s afterthought.
  // On a device the chat route can bind its state (what `_ensureChatOpen`
  // gates on) a few seconds before the composer's AnimatedSwitcher settles, and
  // the old sequencing turned that into a spurious "neither composer surface
  // resolved" FAIL on the very run whose screenshot showed the mobile composer
  // on screen (live 2026-08-16, iPad).
  var onDesktopComposer = false;
  var onMobileComposer = false;
  final probeDeadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(probeDeadline)) {
    if (await a.keyCenter(cardKey) != null) {
      onDesktopComposer = true;
      break;
    }
    if (await a.keyCenter('message_attachment_options_button') != null) {
      onMobileComposer = true;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (!onDesktopComposer) {
    final mobileComposer =
        onMobileComposer ||
        await a.waitKey('message_attachment_options_button', timeoutSecs: 2);
    if (mobileComposer) {
      print(
        '[pair] $label: SKIP — the MOBILE composer is mounted '
        '(message_attachment_options_button). The personal-card entry is '
        'attached only in the fork DESKTOP input builder '
        '(tencent_cloud_chat_message_input_desktop.dart:663); the mobile '
        'attachment overlay is data-driven from '
        'additionalAttachmentOptionsForMobile and offers File + Camera only.',
      );
      return null;
    }
    await a.shot('/tmp/ui_kg3_card_absent_${a.name}.png');
    print(
      '[pair] $label: neither composer surface resolved — the desktop toolbar '
      'should expose $cardKey in a C2C chat',
    );
    return false;
  }

  final before = (await _c2cMessages(a, toxB)).length;
  await a.waitTextGone(sentSnack, timeoutSecs: 4);
  if (!await a.tapKeyCenter(cardKey, timeoutSecs: 8)) {
    print('[pair] $label: the personal-card button was not tappable');
    return false;
  }
  var grew = false;
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline) && !grew) {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    grew = (await _c2cMessages(a, toxB)).length > before;
  }
  final snack = grew || await a.waitText(sentSnack, timeoutSecs: 4);
  final after = (await _c2cMessages(a, toxB)).length;
  await a.shot('/tmp/ui_kg3_card_${a.name}.png');
  print(
    '[pair] $label: before=$before after=$after grew=$grew '
    'snackbarOrGrew=$snack',
  );
  return grew || snack;
}
