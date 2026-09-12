part of 'package:toxee/util/prefs.dart';

// Account-registry read-modify-write bodies, split out of `prefs.dart`
// (complexity-gate pin).
//
// Each of these runs INSIDE the registry serialization gate
// (`Prefs._serializedRegistry`), which is why they call
// `Prefs._setAccountListUnguarded` rather than the public `Prefs.setAccountList`
// — the gate is not re-entrant, and taking it twice would deadlock. The thin
// public entry points that acquire it stay on `Prefs`.

/// Serializes every read-modify-write on `account_list`.
///
/// The registry is mutated by a read-then-write pair in half a dozen places
/// (add, touch, remove, set-avatar, the 64->76 backfill) and by concurrent
/// actors: the Settings page refreshes the last-login timestamp on a five
/// minute timer while an import or a deletion is rewriting the same key. Two
/// interleaved sequences both read the old list and the second write wins, so
/// the first one's change — a newly imported account, a removal — silently
/// disappears.
///
/// NOT re-entrant. Anything running inside the gate must use
/// [Prefs._setAccountListUnguarded], never the public [Prefs.setAccountList].
///
/// [AsyncGate] rather than a hand-rolled `_tail.then(body)` chain: chaining
/// onto the previous caller's future runs the body in THAT caller's zone, and
/// a mutation issued from inside a `testWidgets` body then never started
/// until the test was already over. See the class doc for the full trap.
final AsyncGate _accountRegistryGate = AsyncGate();

Future<T> _serializedRegistry<T>(Future<T> Function() body) {
  return _accountRegistryGate.run(body);
}

Future<void> addAccountUnguarded({
  required String toxId,
  String? nickname,
  String? statusMessage,
  String? avatarPath,
  bool? autoLogin,
  bool? autoAcceptFriends,
  bool? autoAcceptGroupInvites,
  bool? notificationSoundEnabled,
  bool updateLastLogin = true,
}) async {
  final accounts = await Prefs.getAccountList();
  final normalizedNickname = nickname?.trim();
  if (normalizedNickname != null && normalizedNickname.isNotEmpty) {
    // Use `compareToxIds` here too — after F12 backfill rewrites a row from
    // 64 to 76 chars, callers (`AccountSwitcher`, `LoginUseCase`) keep
    // passing the pre-backfill 64-char value. A raw `!=` check then treats
    // the same account as "another account" and rejects an otherwise valid
    // nickname update with `Nickname already used by another account`. The
    // fuzzy comparator matches the same equivalence the existing-row lookup
    // below uses, so the self-vs-other distinction stays consistent.
    final duplicate = accounts.any(
      (acc) =>
          !compareToxIds(acc['toxId'] ?? '', toxId) &&
          (acc['nickname'] ?? '').trim() == normalizedNickname,
    );
    if (duplicate) {
      throw StateError('Nickname already used by another account');
    }
  }
  // Find existing account by Tox ID (primary key). Use `compareToxIds`
  // so the lookup is robust to length differences — after the F12
  // backfill (`ShortToxIdBackfill`) rewrites an imported account's row
  // from 64 to 76 chars, callers like `AccountSwitcher` still pass the
  // pre-backfill 64-char value and an exact-match would silently create
  // a duplicate row. `compareToxIds` matches when one ID is a 16-char
  // prefix of the other, or when both normalize to the same 64-char
  // public-key form — which is exactly the equivalence we want.
  final existingIndex = accounts.indexWhere(
    (acc) => compareToxIds(acc['toxId'] ?? '', toxId),
  );
  Map<String, String> account;

  if (existingIndex >= 0) {
    // Update existing account
    account = accounts[existingIndex];
    if (updateLastLogin) {
      account['lastLoginTime'] = DateTime.now().toIso8601String();
    }
    // Update nickname if provided (allows nickname changes)
    if (nickname != null && nickname.isNotEmpty) {
      account['nickname'] = nickname;
    }
    if (statusMessage != null) {
      account['statusMessage'] = statusMessage;
    }
    if (avatarPath != null) {
      account['avatarPath'] = avatarPath;
    }
    if (autoLogin != null) {
      account['autoLogin'] = autoLogin.toString();
    }
    if (autoAcceptFriends != null) {
      account['autoAcceptFriends'] = autoAcceptFriends.toString();
    }
    if (autoAcceptGroupInvites != null) {
      account['autoAcceptGroupInvites'] = autoAcceptGroupInvites.toString();
    }
    if (notificationSoundEnabled != null) {
      account['notificationSoundEnabled'] = notificationSoundEnabled
          .toString();
    }
    accounts[existingIndex] = account;
  } else {
    // Add new account
    account = <String, String>{
      'toxId': toxId,
      'nickname': nickname ?? '',
      'statusMessage': statusMessage ?? '',
      if (updateLastLogin) 'lastLoginTime': DateTime.now().toIso8601String(),
    };
    if (avatarPath != null && avatarPath.isNotEmpty) {
      account['avatarPath'] = avatarPath;
    }
    if (autoLogin != null) {
      account['autoLogin'] = autoLogin.toString();
    } else {
      account['autoLogin'] = 'true'; // Default to true
    }
    if (autoAcceptFriends != null) {
      account['autoAcceptFriends'] = autoAcceptFriends.toString();
    } else {
      account['autoAcceptFriends'] = 'false'; // Default to false
    }
    if (autoAcceptGroupInvites != null) {
      account['autoAcceptGroupInvites'] = autoAcceptGroupInvites.toString();
    } else {
      account['autoAcceptGroupInvites'] = 'false'; // Default to false
    }
    if (notificationSoundEnabled != null) {
      account['notificationSoundEnabled'] = notificationSoundEnabled
          .toString();
    } else {
      account['notificationSoundEnabled'] = 'true'; // Default to true
    }
    accounts.add(account);
  }
  await Prefs._setAccountListUnguarded(accounts);
}

Future<void> touchAccountLoginTimeUnguarded(String toxId) async {
  final normalized = toxId.trim();
  if (normalized.isEmpty) return;
  final accounts = await Prefs.getAccountList();
  // Fuzzy match — mirrors [getAccountByToxId] so callers can pass any of
  // the formats that flow through the system (76-char service.selfId,
  // 64-char toxIdForLogin, 16-char prefix) and still hit the same row.
  int index = accounts.indexWhere(
    (acc) => (acc['toxId']?.trim() ?? '') == normalized,
  );
  if (index < 0) {
    final lowered = normalized.toLowerCase();
    index = accounts.indexWhere(
      (acc) => (acc['toxId']?.trim() ?? '').toLowerCase() == lowered,
    );
  }
  if (index < 0 && normalized.length >= 64) {
    final prefix = normalized.substring(0, 64);
    index = accounts.indexWhere((acc) {
      final accToxId = acc['toxId']?.trim() ?? '';
      return accToxId.length >= 64 && accToxId.substring(0, 64) == prefix;
    });
  }
  if (index < 0) {
    index = accounts.indexWhere(
      (acc) => compareToxIds(acc['toxId']?.trim() ?? '', normalized),
    );
  }
  if (index < 0) return;
  accounts[index]['lastLoginTime'] = DateTime.now().toIso8601String();
  await Prefs._setAccountListUnguarded(accounts);
}

Future<void> removeAccountUnguarded(String toxId) async {
  final accounts = await Prefs.getAccountList();
  accounts.removeWhere((acc) => compareToxIds(acc['toxId'] ?? '', toxId));
  await Prefs._setAccountListUnguarded(accounts);
  // Revoke any L3 seed-account marker so a deleted account can't leave the
  // debug mutating-tool grant behind for a reused/recreated identity.
  await Prefs.removeL3SeedToxId(toxId);
}

Future<void> setAccountAvatarPathUnguarded(
  String toxId,
  String? path,
) async {
  final accounts = await Prefs.getAccountList();
  final index = accounts.indexWhere(
    (acc) => compareToxIds(acc['toxId'] ?? '', toxId),
  );
  if (index < 0) return;
  if (path == null || path.isEmpty) {
    accounts[index].remove('avatarPath');
  } else {
    accounts[index]['avatarPath'] = path;
  }
  await Prefs._setAccountListUnguarded(accounts);
}
