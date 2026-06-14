// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

/// Recover the real-UI automation from non-Home startup pages that block the
/// register/login flow — primarily the `sc_load_account_fail.png` "Startup
/// Failed: Profile not found for account" page. A stale saved account whose
/// on-disk profile was wiped (common in the multi-instance harness, where the
/// per-instance profile dir is cleared but the account_list pref persists)
/// triggers a FAILED auto-restore on boot, so the app parks on that error page
/// with Retry / "Go to Login" buttons instead of the register/login UI that
/// [ensureHome] expects. Without this, ensureHome fails opaquely with
/// `tapText "Register new account" failed after 6 tries`.
///
/// Strategy: if the Startup-Failed page is showing, tap "Go to Login" to route
/// to the saved-accounts/register page; re-evaluate until we reach a
/// register-capable page (or sessionReady). Returns best-effort after
/// [maxRounds] so the caller still surfaces a clear downstream error.
Future<void> recoverStartupExceptions(Inst inst, {int maxRounds = 4}) async {
  for (var round = 0; round < maxRounds; round++) {
    await inst.foreground();
    final st = await inst.dumpState();
    if (st['sessionReady'] == true) return;
    // sc_load_account_fail: "Startup Failed" / "Exception: Profile not found".
    if (await inst.waitText('Startup Failed', timeoutSecs: 2)) {
      print(
        '[${inst.name}] sc_load_account_fail detected '
        '(stale account, profile missing) -> tapping "Go to Login"',
      );
      await inst.tapText('Go to Login');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      continue; // re-evaluate the page we landed on
    }
    // Register-capable page reached (blank register OR saved-accounts list,
    // both expose the "Register new account" affordance).
    if (await inst.waitText('Register new account', timeoutSecs: 2)) return;
    // Unknown transient page (route still settling); let frames pump and retry.
    await Future<void>.delayed(const Duration(milliseconds: 1000));
  }
  print(
    '[${inst.name}] WARN: startup recovery exhausted after $maxRounds '
    'rounds; proceeding best-effort',
  );
}

Future<void> ensureHome(
  Inst inst,
  String nickname, {
  bool requireHomeMenu = true,
}) async {
  await inst.foreground();
  final st = await inst.dumpState();
  if (st['sessionReady'] == true) {
    // A booted session has navigated past login/register; just make sure the
    // window is foregrounded so any in-flight frame settles.
    print('[${inst.name}] already logged in (${st['nickname']})');
    if (!requireHomeMenu ||
        await _chatsHomeReady(inst, timeoutSecs: 2) ||
        await inst.waitKey('new_entry_menu_button', timeoutSecs: 2)) {
      return;
    }
    if (!await inst.waitKey('new_entry_menu_button', timeoutSecs: 6)) {
      // A previous scenario may have left us on Contacts/Profile/Chat detail.
      // Normalize back to the Chats home before continuing.
      if (await inst.waitText('Back', timeoutSecs: 2)) {
        await inst.tapText('Back');
        await Future<void>.delayed(const Duration(milliseconds: 800));
      } else if (!await _selectChatsTab(inst)) {
        try {
          await inst.osaEscape();
        } on DriveError {
          // Best effort only: avoid tapping the top-left self-avatar hotspot.
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await _selectChatsTab(inst);
      }
      if (!await inst.waitKey('new_entry_menu_button', timeoutSecs: 8)) {
        if (await _recoverBlankHomeRoot(inst) &&
            await inst.waitKey('new_entry_menu_button', timeoutSecs: 8)) {
          return;
        }
        throw DriveError('[${inst.name}] did not recover to HomePage');
      }
    }
    return;
  }
  // Handle the sc_load_account_fail.png "Startup Failed" page (and similar
  // non-Home startup exceptions) before assuming the register page is showing.
  await recoverStartupExceptions(inst);
  print('[${inst.name}] registering "$nickname" via real UI...');
  await inst.tapText('Register new account');
  await Future<void>.delayed(const Duration(seconds: 2)); // route transition
  await inst.focusType('register_page_nickname_field', nickname);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await inst.tapKey('register_page_register_button');
  // Boot can take several seconds; keep foreground so frames pump.
  await inst.foreground();
  await inst.waitState(
    (s) => s['sessionReady'] == true,
    timeoutSecs: 60,
    label: 'sessionReady',
  );
  // First-run backup wizard blocks navigation; dismiss it.
  await inst.foreground();
  if (await inst.waitText('Save your account file', timeoutSecs: 20)) {
    await inst.tapText("I'll do it later");
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!await _tryTapText(inst, 'I understand, continue')) {
      await inst.tapAt(894, 520);
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
  }
  if (!requireHomeMenu) {
    return;
  }
  if (!await inst.waitKey('new_entry_menu_button', timeoutSecs: 25)) {
    throw DriveError('[${inst.name}] did not reach HomePage after register');
  }
  print('[${inst.name}] on HomePage ($nickname)');
}

Future<void> returnToChatsHome(Inst inst, {int rounds = 4}) async {
  for (var round = 0; round < rounds; round++) {
    await inst.foreground();
    if (await _chatsHomeReady(inst, timeoutSecs: 2)) {
      return;
    }
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'chats',
      label: 'returnToChatsHome',
      ready: () => _chatsHomeReady(inst, timeoutSecs: 2),
    )) {
      return;
    }
    if (await _recoverActiveConversation(inst)) {
      continue;
    }
    if (await _recoverFriendProfileToContacts(inst)) {
      continue;
    }
    if (await _dismissProfileQrOverlay(inst)) {
      continue;
    }
    if (await inst.waitText('Back', timeoutSecs: 1)) {
      await inst.tapText('Back');
    } else if (!await _selectChatsTab(inst)) {
      if (await _recoverBlankHomeRoot(inst)) {
        continue;
      }
      if (await _forceHomeRootAndWait(
        inst,
        tab: 'chats',
        label: 'returnToChatsHome fallback',
        ready: () => _chatsHomeReady(inst, timeoutSecs: 2),
      )) {
        return;
      }
      try {
        await inst.osaEscape();
      } on DriveError {
        // Best effort only: some shells ignore ESC, but it is safer than
        // tapping the top-left avatar area which opens the self-profile modal.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
  final st = await inst.dumpState();
  final shotPath = '/tmp/recover_chats_${inst.name}.png';
  final hasBack = await inst.waitText('Back', timeoutSecs: 1);
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: 1,
  );
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: 1,
  );
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: 1,
  );
  final hasNoConversation = await inst.waitText(
    'No Conversation',
    timeoutSecs: 1,
  );
  await inst.shot(shotPath);
  print(
    '[${inst.name}] recover-chats snapshot: '
    'sessionReady=${st['sessionReady']} '
    'friendCount=${st['friendCount']} '
    'friendApplicationCount=${st['friendApplicationCount']} '
    'currentConversation=${st['currentConversation']} '
    'profileContext=${st['homeShellInContactProfileContext']} '
    'hasBack=$hasBack hasNewEntry=$hasNewEntry '
    'hasChatsSidebar=$hasChatsSidebar hasContactsSidebar=$hasContactsSidebar '
    'hasNoConversation=$hasNoConversation '
    'shot=$shotPath',
  );
  throw DriveError('[${inst.name}] failed to recover to Chats home');
}

Future<void> ensureContactsShell(Inst inst, {int rounds = 4}) async {
  for (var round = 0; round < rounds; round++) {
    await inst.foreground();
    if (await _contactsHomeReady(inst, timeoutSecs: 2)) {
      return;
    }
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'contacts',
      label: 'ensureContactsShell',
      ready: () => _contactsHomeReady(inst, timeoutSecs: 2),
    )) {
      return;
    }
    if (await _recoverActiveConversation(inst)) {
      continue;
    }
    if (await _recoverFriendProfileToContacts(inst)) {
      continue;
    }
    if (await _dismissProfileQrOverlay(inst)) {
      continue;
    }
    if (await _selectContactsTab(inst)) {
      continue;
    }
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'contacts',
      label: 'ensureContactsShell fallback',
      ready: () => _contactsHomeReady(inst, timeoutSecs: 2),
    )) {
      return;
    }
    if (await _tryTapText(inst, 'Back')) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      continue;
    }
    if (await _recoverBlankHomeRoot(inst)) {
      continue;
    }
    try {
      await inst.osaEscape();
    } on DriveError {
      // Best effort only.
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
  final st = await inst.dumpState();
  final shotPath = '/tmp/recover_contacts_${inst.name}.png';
  final hasBack = await inst.waitText('Back', timeoutSecs: 1);
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: 1,
  );
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: 1,
  );
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: 1,
  );
  await inst.shot(shotPath);
  print(
    '[${inst.name}] recover-contacts snapshot: '
    'sessionReady=${st['sessionReady']} '
    'friendCount=${st['friendCount']} '
    'friendApplicationCount=${st['friendApplicationCount']} '
    'currentConversation=${st['currentConversation']} '
    'hasBack=$hasBack hasNewEntry=$hasNewEntry '
    'hasChatsSidebar=$hasChatsSidebar hasContactsSidebar=$hasContactsSidebar '
    'shot=$shotPath',
  );
  throw DriveError('[${inst.name}] failed to recover to Contacts shell');
}

Future<void> ensureNewEntryShell(Inst inst, {int rounds = 4}) async {
  for (var round = 0; round < rounds; round++) {
    await inst.foreground();
    if (await _newEntryShellReady(inst, timeoutSecs: 2)) {
      return;
    }
    if (await _recoverActiveConversation(inst)) {
      continue;
    }
    if (await _recoverFriendProfileToContacts(inst)) {
      continue;
    }
    if (await _dismissProfileQrOverlay(inst)) {
      continue;
    }
    if (await _selectContactsTab(inst)) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      continue;
    }
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'contacts',
      label: 'ensureNewEntryShell',
      ready: () => _newEntryShellReady(inst, timeoutSecs: 2),
    )) {
      return;
    }
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'contacts',
      label: 'ensureNewEntryShell fallback',
      ready: () => _newEntryShellReady(inst, timeoutSecs: 2),
    )) {
      return;
    }
    if (await _tryTapText(inst, 'Back')) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      continue;
    }
    if (await _selectChatsTab(inst)) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      continue;
    }
    if (await _recoverBlankHomeRoot(inst)) {
      continue;
    }
    try {
      await inst.osaEscape();
    } on DriveError {
      // Best effort only.
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
  final st = await inst.dumpState();
  final shotPath = '/tmp/recover_new_entry_${inst.name}.png';
  final hasBack = await inst.waitText('Back', timeoutSecs: 1);
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: 1,
  );
  final hasContactAppBarMenu = await inst.waitKey(
    'contact_app_bar_menu_button',
    timeoutSecs: 1,
  );
  final hasContactAppBarTrailing = await inst.waitKey(
    'contact_app_bar_trailing_override',
    timeoutSecs: 1,
  );
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: 1,
  );
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: 1,
  );
  final hasContactsLanding =
      await inst.waitKey('contact_new_contacts_tab', timeoutSecs: 1) ||
      await inst.waitText('New Contacts', timeoutSecs: 1);
  final hasNoConversation = await inst.waitText(
    'No Conversation',
    timeoutSecs: 1,
  );
  await inst.shot(shotPath);
  print(
    '[${inst.name}] recover-new-entry snapshot: '
    'sessionReady=${st['sessionReady']} '
    'friendCount=${st['friendCount']} '
    'friendApplicationCount=${st['friendApplicationCount']} '
    'currentConversation=${st['currentConversation']} '
    'homeShellTab=${st['homeShellTab']} '
    'homeShellCurrentConversationId=${st['homeShellCurrentConversationId']} '
    'profileContext=${st['homeShellInContactProfileContext']} '
    'hasBack=$hasBack hasNewEntry=$hasNewEntry '
    'hasContactAppBarMenu=$hasContactAppBarMenu '
    'hasContactAppBarTrailing=$hasContactAppBarTrailing '
    'hasChatsSidebar=$hasChatsSidebar '
    'hasContactsSidebar=$hasContactsSidebar '
    'hasContactsLanding=$hasContactsLanding '
    'hasNoConversation=$hasNoConversation '
    'shot=$shotPath',
  );
  throw DriveError('[${inst.name}] failed to recover to new-entry shell');
}

Future<void> _ensureRestoredHome(Inst inst, _RestoredAccount restored) async {
  await inst.foreground();
  final st = await inst.dumpState();
  if (st['sessionReady'] == true) {
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'chats',
      label: 'restored session preflight',
      ready: () => _chatsHomeReady(inst, timeoutSecs: 3),
    )) {
      return;
    }
    await returnToChatsHome(inst, rounds: 8);
    return;
  }
  print(
    '[${inst.name}] booting restored account '
    '${_shortId(restored.toxId)} via l3_boot_existing_account...',
  );
  await inst.bootExistingAccount(restored.toxId, restored.nickname);
  await inst.foreground();
  await inst.waitState(
    (s) => s['sessionReady'] == true,
    timeoutSecs: 60,
    label: 'restored sessionReady',
  );
  if (await _forceHomeRootAndWait(
    inst,
    tab: 'chats',
    label: 'restored boot',
    ready: () => _chatsHomeReady(inst, timeoutSecs: 3),
  )) {
    return;
  }
  await returnToChatsHome(inst, rounds: 8);
}

class _RestoredAccount {
  _RestoredAccount({required this.toxId, required this.nickname});

  final String toxId;
  final String nickname;
}

class _RestoredPair {
  _RestoredPair({required this.a, required this.b});

  final _RestoredAccount a;
  final _RestoredAccount b;

  static Future<_RestoredPair> load() async {
    final root =
        jsonDecode(
              await File(
                'tool/mcp_test/.multi_instance_runtime/pair.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final instances =
        ((((root['fixture_restore'] as Map?)?['restored'] as Map?)?['instances']
                    as Map?) ??
                const <String, dynamic>{})
            .cast<String, dynamic>();
    _RestoredAccount parse(String name) {
      final raw =
          (instances[name] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final toxId = raw['tox_id']?.toString() ?? '';
      final nickname = raw['nickname']?.toString() ?? '';
      if (toxId.isEmpty || nickname.isEmpty) {
        throw DriveError('restored pair metadata missing for $name: $raw');
      }
      return _RestoredAccount(toxId: toxId, nickname: nickname);
    }

    return _RestoredPair(a: parse('A'), b: parse('B'));
  }
}

Future<bool> _tryTapText(Inst inst, String text) async {
  for (var i = 0; i < 3; i++) {
    try {
      await inst.tapText(text, retries: 1);
      return true;
    } on DriveError {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  return false;
}

Future<bool> _isFriendProfileShell(Inst inst) async {
  return await inst.waitKey(
        'user_profile_delete_friend_button',
        timeoutSecs: 1,
      ) ||
      await inst.waitKey('user_profile_friend_name_text', timeoutSecs: 1) ||
      await inst.waitKey('friend_profile_send_message_tile', timeoutSecs: 1) ||
      await inst.waitKey(
        'friend_profile_send_message_button',
        timeoutSecs: 1,
      ) ||
      await inst.waitText('Add Friend', timeoutSecs: 1);
}

Future<bool> _recoverFriendProfileToContacts(Inst inst) async {
  if (!await _isFriendProfileShell(inst)) return false;
  if (await _selectContactsTab(inst) || await _tryTapText(inst, 'Back')) {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return true;
  }
  return false;
}

/// Pop the friend's CONTACT profile when it's pushed ON TOP of a chat (opened
/// from the chat header). A prior case can leave it covering the chat surface:
/// `_chatSurfaceReady` then passes on the OFFSTAGE chat tree behind it, but
/// the composer / message rows the case drives are not hittable (the
/// secondary-tap / send lands on the profile). Unlike
/// `_recoverFriendProfileToContacts` (which lands on the Contacts tab), this
/// pops BACK to the chat it was pushed from. Returns whether it ended OFF the
/// profile. No-op when no profile is showing.
Future<bool> _dismissFriendProfileToUnderlying(Inst inst) async {
  for (var i = 0; i < 3; i++) {
    if (!await _isFriendProfileShell(inst)) return true;
    if (!await _tryTapText(inst, 'Back')) {
      try {
        await inst.osaEscape();
      } on DriveError {
        // The "<" back affordance at the top-left of the profile app bar.
        await inst.tapAt(28, 72);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  return !await _isFriendProfileShell(inst);
}

Future<bool> _isProfileQrOverlay(Inst inst) async {
  return await inst.waitKey('profile_tox_id_copy_button', timeoutSecs: 1) ||
      await inst.waitKey('profile_qr_copy_button', timeoutSecs: 1) ||
      (await inst.waitText('Save Image', timeoutSecs: 1) &&
          await inst.waitText(
            'Scan QR code to add me as contact',
            timeoutSecs: 1,
          ));
}

Future<bool> _dismissProfileQrOverlay(Inst inst) async {
  if (!await _isProfileQrOverlay(inst)) return false;
  try {
    await inst.osaEscape();
  } on DriveError {
    // Fall back to the top-right close button if the overlay ignores ESC.
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
  if (!await _isProfileQrOverlay(inst)) return true;
  await inst.tapAt(1056, 174);
  await Future<void>.delayed(const Duration(milliseconds: 900));
  return true;
}

Future<bool> _recoverActiveConversation(Inst inst) async {
  final st = await inst.dumpState();
  if (st['currentConversation'] == null) return false;
  try {
    await inst.clearActiveConversation();
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
    print(
      '[${inst.name}] WARN clearActiveConversation unavailable on '
      'non-test account; falling back to UI recovery',
    );
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 900));
  return true;
}

Future<bool> _recoverBlankHomeRoot(Inst inst) async {
  final st = await inst.dumpState();
  if (st['sessionReady'] != true || st['currentConversation'] != null) {
    return false;
  }
  final hasBack = await inst.waitText('Back', timeoutSecs: 1);
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: 1,
  );
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: 1,
  );
  if (hasBack || hasChatsSidebar || hasContactsSidebar) {
    return false;
  }
  print(
    '[${inst.name}] blank shell detected '
    '(sessionReady=true, currentConversation=null, no Back/sidebar) '
    '-> forcing HomePage root',
  );
  try {
    await inst.forceHomeRoot(tab: 'chats');
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
    print(
      '[${inst.name}] WARN forceHomeRoot unavailable on non-test account '
      'during blank-shell recovery',
    );
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  return true;
}

Future<bool> _contactsHomeReady(Inst inst, {int timeoutSecs = 1}) async {
  final st = await inst.dumpState();
  final shellTab = st['homeShellTab']?.toString();
  if (shellTab != null && shellTab != 'contacts') {
    return false;
  }
  if (st['sessionReady'] != true ||
      st['homeShellInContactProfileContext'] == true) {
    return false;
  }
  if (await inst.waitText('Back', timeoutSecs: timeoutSecs)) {
    return false;
  }
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: timeoutSecs,
  );
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: timeoutSecs,
  );
  final hasContactsLanding =
      await inst.waitKey(
        'contact_new_contacts_tab',
        timeoutSecs: timeoutSecs,
      ) ||
      await inst.waitText('New Contacts', timeoutSecs: timeoutSecs);
  return hasContactsSidebar && (hasNewEntry || hasContactsLanding);
}

Future<bool> _newEntryShellReady(Inst inst, {int timeoutSecs = 1}) async {
  final st = await inst.dumpState();
  final keyTimeoutSecs = timeoutSecs <= 1 ? timeoutSecs : 1;
  final hasBack = await inst.waitText('Back', timeoutSecs: keyTimeoutSecs);
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: keyTimeoutSecs,
  );
  final hasContactAppBarMenu = await inst.waitKey(
    'contact_app_bar_menu_button',
    timeoutSecs: keyTimeoutSecs,
  );
  final hasContactAppBarTrailing = await inst.waitKey(
    'contact_app_bar_trailing_override',
    timeoutSecs: keyTimeoutSecs,
  );
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: keyTimeoutSecs,
  );
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: keyTimeoutSecs,
  );
  final hasContactsLanding =
      await inst.waitKey(
        'contact_new_contacts_tab',
        timeoutSecs: keyTimeoutSecs,
      ) ||
      await inst.waitText('New Contacts', timeoutSecs: keyTimeoutSecs);
  final hasNoConversation = await inst.waitText(
    'No Conversation',
    timeoutSecs: keyTimeoutSecs,
  );
  return _newEntryShellLandmarksAreUsable(
    state: st,
    hasBack: hasBack,
    hasNewEntry: hasNewEntry,
    hasContactAppBarMenu: hasContactAppBarMenu,
    hasContactAppBarTrailing: hasContactAppBarTrailing,
    hasChatsSidebar: hasChatsSidebar,
    hasContactsSidebar: hasContactsSidebar,
    hasContactsLanding: hasContactsLanding,
    hasNoConversation: hasNoConversation,
  );
}

bool _newEntryShellLandmarksAreUsable({
  required Map<String, dynamic> state,
  required bool hasBack,
  required bool hasNewEntry,
  required bool hasContactAppBarMenu,
  required bool hasContactAppBarTrailing,
  required bool hasChatsSidebar,
  required bool hasContactsSidebar,
  required bool hasContactsLanding,
  required bool hasNoConversation,
}) {
  if (state['sessionReady'] != true || hasBack) {
    return false;
  }
  final shellTab = state['homeShellTab']?.toString();
  if (shellTab != null && shellTab != 'contacts' && shellTab != 'chats') {
    return false;
  }
  final hasEntryAffordance =
      hasNewEntry || hasContactAppBarMenu || hasContactAppBarTrailing;
  if (!hasEntryAffordance) return false;
  final hasHomeLandmark =
      hasChatsSidebar ||
      hasContactsSidebar ||
      hasContactsLanding ||
      hasNoConversation;
  if (!hasHomeLandmark) return false;
  if (state['homeShellInContactProfileContext'] == true &&
      !_isStaleNoFriendHomeShell(
        state: state,
        hasContactsLanding: hasContactsLanding,
        hasNoConversation: hasNoConversation,
      )) {
    return false;
  }
  return true;
}

bool _isStaleNoFriendHomeShell({
  required Map<String, dynamic> state,
  required bool hasContactsLanding,
  required bool hasNoConversation,
}) {
  return _stateInt(state['friendCount']) == 0 &&
      (hasContactsLanding || hasNoConversation);
}

int? _stateInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

int _runShellRecoverySelfTest() {
  var failures = 0;

  Map<String, dynamic> state({
    required String? tab,
    bool sessionReady = true,
    bool profile = false,
    int? friendCount,
  }) => {
    'sessionReady': sessionReady,
    'homeShellTab': tab,
    'homeShellInContactProfileContext': profile,
    if (friendCount != null) 'friendCount': friendCount,
  };

  void expectUsable(
    String name,
    bool expected, {
    required Map<String, dynamic> state,
    bool hasBack = false,
    bool hasNewEntry = true,
    bool hasContactAppBarMenu = false,
    bool hasContactAppBarTrailing = false,
    bool hasChatsSidebar = false,
    bool hasContactsSidebar = false,
    bool hasContactsLanding = false,
    bool hasNoConversation = false,
  }) {
    final actual = _newEntryShellLandmarksAreUsable(
      state: state,
      hasBack: hasBack,
      hasNewEntry: hasNewEntry,
      hasContactAppBarMenu: hasContactAppBarMenu,
      hasContactAppBarTrailing: hasContactAppBarTrailing,
      hasChatsSidebar: hasChatsSidebar,
      hasContactsSidebar: hasContactsSidebar,
      hasContactsLanding: hasContactsLanding,
      hasNoConversation: hasNoConversation,
    );
    if (actual != expected) {
      failures++;
      print(
        '[self-test] FAIL $name: expected=$expected actual=$actual '
        'state=$state',
      );
    }
  }

  void expectChatsUsable(
    String name,
    bool expected, {
    required Map<String, dynamic> state,
    bool hasBack = false,
    bool hasChatsSidebar = true,
    bool hasNewEntry = true,
    bool hasNoConversation = false,
  }) {
    final actual = _chatsHomeLandmarksAreUsable(
      state: state,
      hasBack: hasBack,
      hasChatsSidebar: hasChatsSidebar,
      hasNewEntry: hasNewEntry,
      hasNoConversation: hasNoConversation,
    );
    if (actual != expected) {
      failures++;
      print(
        '[self-test] FAIL $name: expected=$expected actual=$actual '
        'state=$state',
      );
    }
  }

  expectUsable(
    'fresh chats no-friend shell with NewEntry',
    true,
    state: state(tab: 'chats'),
    hasChatsSidebar: true,
    hasNoConversation: true,
  );
  expectUsable(
    'fresh contacts shell with NewEntry',
    true,
    state: state(tab: 'contacts'),
    hasContactsSidebar: true,
    hasContactsLanding: true,
  );
  expectUsable(
    'stale profile flag on a no-friend home shell',
    true,
    state: state(tab: 'chats', profile: true, friendCount: 0),
    hasContactAppBarTrailing: true,
    hasChatsSidebar: true,
    hasContactsSidebar: true,
    hasContactsLanding: true,
    hasNoConversation: true,
  );
  expectUsable(
    'UIKit contacts app-bar fallback',
    true,
    state: state(tab: 'contacts'),
    hasNewEntry: false,
    hasContactAppBarMenu: true,
    hasContactsSidebar: true,
  );
  expectUsable(
    'profile route is not a reusable shell',
    false,
    state: state(tab: 'contacts', profile: true, friendCount: 1),
    hasContactsSidebar: true,
    hasContactsLanding: true,
  );
  expectUsable(
    'detail back route is not a reusable shell',
    false,
    state: state(tab: 'contacts'),
    hasBack: true,
    hasContactsSidebar: true,
    hasContactsLanding: true,
  );
  expectUsable(
    'settings tab is not an add-friend shell',
    false,
    state: state(tab: 'settings'),
    hasNewEntry: true,
    hasContactsSidebar: true,
  );
  expectUsable(
    'missing add-friend affordance is not reusable',
    false,
    state: state(tab: 'chats'),
    hasNewEntry: false,
    hasChatsSidebar: true,
    hasNoConversation: true,
  );
  expectChatsUsable(
    'stale no-friend conversation is reusable chats home',
    true,
    state: {
      ...state(tab: 'chats', profile: true, friendCount: 0),
      'currentConversation': {'conversationID': 'c2c_stale'},
    },
  );
  expectChatsUsable(
    'friend profile context is not chats home',
    false,
    state: {
      ...state(tab: 'chats', profile: true, friendCount: 1),
      'currentConversation': {'conversationID': 'c2c_friend'},
    },
  );

  if (failures != 0) return 1;
  print('[self-test] PASS shell recovery landmark matrix');
  return 0;
}

Future<bool> _chatsHomeReady(Inst inst, {int timeoutSecs = 1}) async {
  final st = await inst.dumpState();
  if (st['sessionReady'] != true) return false;
  // Robust early-accept: after a switch-back / account-delete boot (which mounts
  // a fresh HomePage), `new_entry_menu_button` and the other landmark keys can
  // lag the dump even though the home shell is fully up — the persistent SIDEBAR
  // AVATAR (and the dump homeShellTab) survive that boot. If the session is ready
  // AND the home shell is observable by either, the chats home IS usable. Without
  // this, the inter-sweep recovery throws "did not recover to HomePage" after a
  // destructive account flow and cascades every later sweep.
  if (st['homeShellTab'] != null ||
      await inst.waitKey('sidebar_user_avatar', timeoutSecs: timeoutSecs)) {
    return true;
  }
  final hasBack = await inst.waitText('Back', timeoutSecs: timeoutSecs);
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: timeoutSecs,
  );
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: timeoutSecs,
  );
  final hasNoConversation = await inst.waitText(
    'No Conversation',
    timeoutSecs: timeoutSecs,
  );
  return _chatsHomeLandmarksAreUsable(
    state: st,
    hasBack: hasBack,
    hasChatsSidebar: hasChatsSidebar,
    hasNewEntry: hasNewEntry,
    hasNoConversation: hasNoConversation,
  );
}

bool _chatsHomeLandmarksAreUsable({
  required Map<String, dynamic> state,
  required bool hasBack,
  required bool hasChatsSidebar,
  required bool hasNewEntry,
  required bool hasNoConversation,
}) {
  if (state['sessionReady'] != true || hasBack || !hasChatsSidebar) {
    return false;
  }
  final shellTab = state['homeShellTab']?.toString();
  if (shellTab != null && shellTab != 'chats') {
    return false;
  }
  final staleNoFriendShell =
      _stateInt(state['friendCount']) == 0 && hasNewEntry;
  if (state['homeShellInContactProfileContext'] == true &&
      !staleNoFriendShell) {
    return false;
  }
  return state['currentConversation'] == null ||
      hasNoConversation ||
      staleNoFriendShell;
}

Future<bool> _forceHomeRootAndWait(
  Inst inst, {
  required String tab,
  required String label,
  required Future<bool> Function() ready,
}) async {
  if (inst.navToolsUnavailable) {
    // l3_force_home_root is refused on a freshly-registered (non-test) account;
    // skip the known-dead call so it neither WARN-spams nor burns a recovery
    // round. The UI-landmark recovery below (sidebar taps, Back, escape) and the
    // relaxed no-friend readiness handle these accounts without it.
    return false;
  }
  final sw = Stopwatch()..start();
  try {
    await inst.forceHomeRoot(tab: tab);
  } on DriveError catch (e) {
    print(
      '[${inst.name}] WARN forceHomeRoot($tab) failed during $label: '
      '${e.message}',
    );
    return false;
  }
  final deadline = DateTime.now().add(const Duration(seconds: 6));
  var ok = false;
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) {
      ok = true;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  final shellTab = await _homeShellTab(inst);
  print(
    '[${inst.name}] forceHomeRoot($tab) during $label '
    '=> ready=$ok after ${sw.elapsedMilliseconds}ms '
    '(homeShellTab=${shellTab ?? 'unknown'})',
  );
  return ok;
}

Future<bool> _selectChatsTab(Inst inst) async {
  if (await inst.tryTapKey('sidebar_chats_tab', retries: 2)) {
    if (await _chatsHomeReady(inst, timeoutSecs: 2)) {
      return true;
    }
  }
  if (await _tryTapText(inst, 'Chats')) {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (await _chatsHomeReady(inst, timeoutSecs: 2)) {
      return true;
    }
  }
  final sidebarVisible =
      await inst.waitKey('sidebar_chats_tab', timeoutSecs: 1) ||
      await inst.waitKey('sidebar_contacts_tab', timeoutSecs: 1);
  if (!sidebarVisible) {
    return false;
  }
  await inst.tapAt(_sidebarTabX, _sidebarChatsY);
  await Future<void>.delayed(const Duration(milliseconds: 900));
  return _chatsHomeReady(inst, timeoutSecs: 2);
}

Future<bool> _selectContactsTab(Inst inst) async {
  if (await inst.tryTapKey('sidebar_contacts_tab', retries: 2)) {
    if (await _contactsHomeReady(inst, timeoutSecs: 2)) {
      return true;
    }
  }
  if (await _tryTapText(inst, 'Contacts')) {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (await _contactsHomeReady(inst, timeoutSecs: 2)) {
      return true;
    }
  }
  final sidebarVisible =
      await inst.waitKey('sidebar_contacts_tab', timeoutSecs: 1) ||
      await inst.waitKey('sidebar_chats_tab', timeoutSecs: 1);
  if (!sidebarVisible) {
    return false;
  }
  await inst.tapAt(_sidebarTabX, _sidebarContactsY);
  await Future<void>.delayed(const Duration(milliseconds: 900));
  return _contactsHomeReady(inst, timeoutSecs: 2);
}
