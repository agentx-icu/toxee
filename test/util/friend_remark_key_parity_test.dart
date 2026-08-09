// Tripwire for the friend-remark storage key, which TWO independent
// account-scoping implementations write:
//
//   * `Prefs.setFriendRemark`                    — lib/util/prefs.dart
//                                                  (`_friendRemarkKey` + `_scopedKey`)
//   * `SharedPreferencesAdapter.setFriendRemark` — lib/adapters/shared_prefs_adapter.dart
//                                                  (`_friendRemarkKey` + `_prefixKey`)
//
// The PRODUCT write path is the adapter: the friend-profile remark dialog calls
// `contactSDK.setFriendInfo` -> `Tim2ToxSdkPlatform.setFriendInfo` ->
// `ExtendedPreferencesService.setFriendRemark` (= the adapter). Several READERS
// go through `Prefs.getFriendRemark` instead — including `l3_dump_state`, which
// is what the S30/H5 gate asserts on. `scoped_key_test.dart` only locks the
// shared `scopedPrefsKey` FORMAT helper; nothing asserted that the two call
// sites feed it the same base key and the same prefix. They are today; this
// test makes a future divergence fail loudly instead of silently making
// remarks written by the product invisible to everything that reads via Prefs.
//
// Mobile parity: both implementations are plain Dart over SharedPreferences,
// shared by every platform — no platform-specific branch is involved.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/adapters/shared_prefs_adapter.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A realistic 76-char Tox ID; both writers scope by its first 16 chars.
  final accountToxId = '0123456789ABCDEF${List<String>.filled(60, 'A').join()}';
  final accountPrefix = accountToxId.substring(0, 16);
  final friendId = List<String>.filled(64, 'B').join();

  Set<String> remarkKeys(SharedPreferences p) =>
      p.getKeys().where((k) => k.startsWith('friend_remark_')).toSet();

  test('Prefs and SharedPreferencesAdapter agree on the friend-remark key',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.setCurrentAccountToxId(accountToxId);

    // --- UI-side implementation (Prefs._scopedKey) ---
    await Prefs.setFriendRemark(friendId, 'via-prefs');
    final viaPrefs = remarkKeys(prefs);
    expect(
      viaPrefs.length,
      1,
      reason: 'Prefs.setFriendRemark must write exactly one key',
    );
    final prefsKey = viaPrefs.single;
    expect(prefsKey, 'friend_remark_${friendId}_$accountPrefix');
    expect(prefs.getString(prefsKey), 'via-prefs');

    // Empty remark clears (the contract `l3_set_friend_remark` relies on).
    await Prefs.setFriendRemark(friendId, '');
    expect(remarkKeys(prefs), isEmpty);

    // --- Platform/adapter implementation (SharedPreferencesAdapter._prefixKey),
    // i.e. what Tim2ToxSdkPlatform.setFriendInfo actually writes through ---
    final adapter = SharedPreferencesAdapter(
      prefs,
      accountPrefix: accountPrefix,
    );
    await adapter.setFriendRemark(friendId, 'via-adapter');
    final viaAdapter = remarkKeys(prefs);
    expect(viaAdapter.length, 1);
    expect(
      viaAdapter.single,
      prefsKey,
      reason: 'the two implementations must land on the SAME key — otherwise a '
          'remark set through the product is invisible to Prefs readers '
          '(contact list, chat header, l3_dump_state.friends[].remark)',
    );

    // Cross-read: the product write is visible to BOTH readers.
    expect(await Prefs.getFriendRemark(friendId), 'via-adapter');
    expect(await adapter.getFriendRemark(friendId), 'via-adapter');

    // Adapter clear (null and empty both remove) is visible to Prefs too.
    await adapter.setFriendRemark(friendId, '');
    expect(remarkKeys(prefs), isEmpty);
    expect(await Prefs.getFriendRemark(friendId), isNull);
  });
}
