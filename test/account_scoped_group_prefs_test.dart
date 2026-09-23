// Tim2Tox-owned preference keys (pending group invites, kick-retained groups,
// invites queued for offline friends) are passed verbatim to getString /
// getStringSet, so the adapter must scope them per account explicitly or one
// account's data is read by the next.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/interfaces/group_identity_preferences_service.dart';
import 'package:toxee/adapters/shared_prefs_adapter.dart';

void main() {
  test('accountScopedKey separates accounts and round-trips values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final a = SharedPreferencesAdapter(prefs, accountPrefix: 'AAAA');
    final b = SharedPreferencesAdapter(prefs, accountPrefix: 'BBBB');
    expect(a, isA<AccountScopedPreferencesService>());

    const key = 'pending_group_invites_v1';
    expect(a.accountScopedKey(key), isNot(b.accountScopedKey(key)));
    await a.setString(a.accountScopedKey(key), 'from-a');
    expect(await b.getString(b.accountScopedKey(key)), isNull);
    expect(await a.getString(a.accountScopedKey(key)), 'from-a');
  });

  test('group type and identity removal', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final a = SharedPreferencesAdapter(prefs, accountPrefix: 'AAAA');
    await a.setGroupType('tox_1', 'conference');
    await a.setGroupChatId('tox_1', 'c' * 64);
    expect(await a.getGroupType('tox_1'), 'conference');
    await a.removeGroupIdentity('tox_1');
    expect(await a.getGroupType('tox_1'), isNull);
    expect(await a.getGroupChatId('tox_1'), isNull);
  });
}
