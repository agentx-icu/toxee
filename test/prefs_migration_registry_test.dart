// X3 — Single migration registry test.
//
// Verifies that the previously-inline lazy migrations (autoAcceptFriends,
// autoAcceptGroupInvites, autoLogin, notificationSoundEnabled) are now
// owned by PrefsUpgrader.runAccountMigrations at the v1→v2 step. The four
// getters in Prefs must NOT contain a fallback into `account_list` JSON
// anymore — that path is exercised here exclusively through the upgrader.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/prefs_upgrader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A toxId where the first 16 chars match `prefix16` (the value used by
  // Prefs._scopedKey). Keeping these aligned matters: the upgrader writes
  // scoped keys under `<base>_<prefix16>` and the getters read the same.
  const String toxId =
      'AAAAAAAAAAAAAAAA0123456789abcdef0123456789abcdef0123456789abcdef';
  const String prefix16 = 'AAAAAAAAAAAAAAAA';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<SharedPreferences> seedAccountList(
      Map<String, String> accountFields) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'account_list': jsonEncode(<Map<String, String>>[
        <String, String>{'toxId': toxId, ...accountFields},
      ]),
    });
    return SharedPreferences.getInstance();
  }

  group('runAccountMigrations v1→v2 — eager bool settings', () {
    test('copies all four bool keys when account_list has them', () async {
      final prefs = await seedAccountList(<String, String>{
        'autoAcceptFriends': 'true',
        'autoAcceptGroupInvites': 'false',
        'autoLogin': 'false',
        'notificationSoundEnabled': 'true',
      });

      await PrefsUpgrader.runAccountMigrations(prefs, prefix16);

      expect(prefs.getBool('acct_auto_accept_friends_$prefix16'), true);
      expect(
          prefs.getBool('acct_auto_accept_group_invites_$prefix16'), false);
      expect(prefs.getBool('acct_auto_login_$prefix16'), false);
      expect(prefs.getBool('acct_notification_sound_$prefix16'), true);
      // Version stamp advanced.
      expect(prefs.getInt('account_prefs_version_$prefix16'),
          currentAccountPrefsVersion);
    });

    test('skips keys missing from the account_list entry', () async {
      // Only one of the four fields present.
      final prefs = await seedAccountList(<String, String>{
        'autoAcceptFriends': 'true',
      });

      await PrefsUpgrader.runAccountMigrations(prefs, prefix16);

      expect(prefs.getBool('acct_auto_accept_friends_$prefix16'), true);
      expect(
          prefs.getBool('acct_auto_accept_group_invites_$prefix16'), isNull);
      expect(prefs.getBool('acct_auto_login_$prefix16'), isNull);
      expect(prefs.getBool('acct_notification_sound_$prefix16'), isNull);
    });

    test('does not overwrite an already-set scoped key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': jsonEncode(<Map<String, String>>[
          <String, String>{'toxId': toxId, 'autoLogin': 'false'},
        ]),
        // User already set autoLogin=true under the new scoped key. The
        // migration must NOT clobber that.
        'acct_auto_login_$prefix16': true,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.runAccountMigrations(prefs, prefix16);

      expect(prefs.getBool('acct_auto_login_$prefix16'), true);
    });

    test('no-op when account_list is missing', () async {
      final prefs = await SharedPreferences.getInstance();
      await PrefsUpgrader.runAccountMigrations(prefs, prefix16);
      // Nothing written for the bool keys.
      expect(prefs.getBool('acct_auto_accept_friends_$prefix16'), isNull);
      expect(prefs.getBool('acct_auto_login_$prefix16'), isNull);
    });

    test('idempotent — second call is a no-op', () async {
      final prefs = await seedAccountList(<String, String>{
        'autoAcceptFriends': 'true',
      });

      await PrefsUpgrader.runAccountMigrations(prefs, prefix16);
      // Manually clear the scoped key to detect a re-run.
      await prefs.remove('acct_auto_accept_friends_$prefix16');
      await PrefsUpgrader.runAccountMigrations(prefs, prefix16);
      // Version is already at currentAccountPrefsVersion; v1→v2 must not
      // run again, so the cleared key stays cleared.
      expect(prefs.getBool('acct_auto_accept_friends_$prefix16'), isNull);
    });

    test('still applies v0→v1 groups migration before v1→v2', () async {
      // Old install: had groups_list (unscoped) and account_list bools.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'groups_list': <String>['g1', 'g2'],
        'quit_groups_list': <String>['g3'],
        'account_list': jsonEncode(<Map<String, String>>[
          <String, String>{'toxId': toxId, 'autoLogin': 'false'},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.runAccountMigrations(prefs, prefix16);

      // v0→v1 happened.
      expect(prefs.getStringList('groups_list_$prefix16'),
          containsAll(<String>['g1', 'g2']));
      expect(prefs.getStringList('quit_groups_list_$prefix16'),
          containsAll(<String>['g3']));
      // v1→v2 happened.
      expect(prefs.getBool('acct_auto_login_$prefix16'), false);
    });
  });

  group('Prefs getters read scoped keys without lazy migration', () {
    test('getAutoLogin returns scoped value when migrated', () async {
      final prefs = await seedAccountList(<String, String>{
        'autoLogin': 'false',
      });
      await PrefsUpgrader.runAccountMigrations(prefs, prefix16);
      await Prefs.initialize(prefs);
      await Prefs.setCurrentAccountToxId(toxId);

      final result = await Prefs.getAutoLogin();
      expect(result, false);
    });

    test('getAutoLogin returns true default for new account when '
        'no scoped key and no account_list entry', () async {
      final prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);
      await Prefs.setCurrentAccountToxId(toxId);

      // Default for new accounts (preserved from the prior behaviour).
      final result = await Prefs.getAutoLogin();
      expect(result, true);
    });

    test(
        'getAutoAcceptFriends returns false default when no scoped key '
        'and no account_list entry', () async {
      final prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);
      await Prefs.setCurrentAccountToxId(toxId);

      final result = await Prefs.getAutoAcceptFriends();
      expect(result, false);
    });
  });
}
