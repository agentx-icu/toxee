// X3 — Single migration registry test.
//
// Verifies that the previously-inline lazy migrations (autoAcceptFriends,
// autoAcceptGroupInvites, autoLogin, notificationSoundEnabled) are now
// owned by PrefsUpgrader.runAccountMigrations at the v1→v2 step. The four
// getters in Prefs must NOT contain a fallback into `account_list` JSON
// anymore — that path is exercised here exclusively through the upgrader.
//
// Also covers the GLOBAL v2→v3 step: the one-shot sweep of the un-attributable
// per-peer mute keys (`c2c_recv_opt_<id>`, `group_recv_opt_<id>`,
// `do_not_disturb_<id>`) that older builds minted whenever no account was
// available to scope by. Those entries are read by nobody (the getters now
// require a scope) and deleted by nobody (every teardown path sweeps the
// `_<first16>` suffix), so only a migration can collect them.
//
// Mobile parity: pure Dart over SharedPreferences, no platform branch.

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

  group('run() v2→v3 — unscoped per-peer mute orphan sweep', () {
    // A second account, so "keep the other account's scoped keys" is a real
    // assertion and not a tautology against a single prefix.
    const String toxIdB =
        'BBBBBBBBBBBBBBBB0123456789abcdef0123456789abcdef0123456789abcdef';
    const String prefixB = 'BBBBBBBBBBBBBBBB';

    const String peer = 'CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCD'
        'CDCDCDCDCDCDCDCDCDCDCDCD';
    const String gid = 'group-42';

    String accountListJson(List<String> toxIds) =>
        jsonEncode(toxIds.map((id) => <String, String>{'toxId': id}).toList());

    Set<String> muteKeys(SharedPreferences p) => p
        .getKeys()
        .where((k) =>
            k.startsWith('c2c_recv_opt_') ||
            k.startsWith('group_recv_opt_') ||
            k.startsWith('do_not_disturb_'))
        .toSet();

    test(
      'removes the unscoped entries and keeps every known account scoped one',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'account_list': accountListJson(<String>[toxId, toxIdB]),
          // Orphans: written before an account was known.
          'c2c_recv_opt_$peer': 2,
          'group_recv_opt_$gid': 2,
          'do_not_disturb_$peer': true,
          // Legitimate, scoped state for both accounts.
          'c2c_recv_opt_${peer}_$prefix16': 2,
          'group_recv_opt_${gid}_$prefix16': 2,
          'do_not_disturb_${peer}_$prefix16': true,
          'c2c_recv_opt_${peer}_$prefixB': 1,
        });
        final prefs = await SharedPreferences.getInstance();

        await PrefsUpgrader.run(prefs);

        expect(muteKeys(prefs), <String>{
          'c2c_recv_opt_${peer}_$prefix16',
          'group_recv_opt_${gid}_$prefix16',
          'do_not_disturb_${peer}_$prefix16',
          'c2c_recv_opt_${peer}_$prefixB',
        });
        // Values survive intact — this is a key sweep, not a reset.
        expect(prefs.getInt('c2c_recv_opt_${peer}_$prefix16'), 2);
        expect(prefs.getInt('c2c_recv_opt_${peer}_$prefixB'), 1);
        expect(prefs.getBool('do_not_disturb_${peer}_$prefix16'), true);
        expect(prefs.getInt('prefs_schema_version'), currentGlobalPrefsVersion);
      },
    );

    test('claims nothing for the current account', () async {
      // The deliberate semantic choice: an unscoped entry is un-attributable,
      // so it is DELETED rather than adopted. Adopting would silently mute a
      // peer for an account that never muted them (invisible missed
      // notifications); deleting costs at most one re-mute.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[toxId]),
        'current_account_tox_id': toxId,
        'c2c_recv_opt_$peer': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(muteKeys(prefs), isEmpty);
      expect(prefs.getInt('c2c_recv_opt_${peer}_$prefix16'), isNull);
    });

    test('keeps keys scoped to the current-account pointer alone', () async {
      // account_list can lag the pointer (mid-registration, or a rewrite that
      // failed). The pointer alone must be enough to protect that account.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'current_account_tox_id': toxId,
        'c2c_recv_opt_${peer}_$prefix16': 2,
        'c2c_recv_opt_$peer': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(muteKeys(prefs), <String>{'c2c_recv_opt_${peer}_$prefix16'});
    });

    test('keeps keys scoped to an account_prefs_version stamp alone', () async {
      // An account that was activated on this install but is absent from
      // account_list (e.g. a half-finished deletion) still owns its keys —
      // finishing that deletion is clearAccountData's job, not this sweep's.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_prefs_version_$prefixB': currentAccountPrefsVersion,
        'group_recv_opt_${gid}_$prefixB': 2,
        'group_recv_opt_$gid': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(muteKeys(prefs), <String>{'group_recv_opt_${gid}_$prefixB'});
    });

    test('matches the account scope case-insensitively', () async {
      // Tox IDs are hex, so two spellings are the same account. Folding case
      // can only widen the KEEP set — it must never widen the delete set.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[toxId.toLowerCase()]),
        'c2c_recv_opt_${peer}_$prefix16': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(muteKeys(prefs), <String>{'c2c_recv_opt_${peer}_$prefix16'});
    });

    test('deletes nothing when account_list is unparseable', () async {
      // Without a readable registry we cannot tell scoped from unscoped. Doing
      // nothing leaves the pre-migration state, which is safe; guessing could
      // wipe a live account's mutes.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': '{not valid json',
        'c2c_recv_opt_$peer': 2,
        'c2c_recv_opt_${peer}_$prefix16': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(muteKeys(prefs), <String>{
        'c2c_recv_opt_$peer',
        'c2c_recv_opt_${peer}_$prefix16',
      });
      // The stamp still advances: this is best-effort cleanup, not a gate.
      expect(prefs.getInt('prefs_schema_version'), currentGlobalPrefsVersion);
    });

    test('removes everything when the install knows no account at all',
        () async {
      // No account_list, no pointer, no version stamp — there is no owner any
      // of these entries could belong to.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'c2c_recv_opt_$peer': 2,
        'c2c_recv_opt_${peer}_$prefix16': 2,
        'do_not_disturb_$peer': true,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(muteKeys(prefs), isEmpty);
    });

    test('leaves unrelated preferences untouched', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[toxId]),
        'c2c_recv_opt_$peer': 2,
        'theme_mode': 'dark',
        'pinned_peers_$prefix16': <String>['p1'],
        'muted_peers': <String>['legacy'],
        'black_list_$toxId': <String>['b1'],
        'friend_remark_${peer}_$prefix16': 'Bob',
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(prefs.getString('theme_mode'), 'dark');
      expect(prefs.getStringList('pinned_peers_$prefix16'), <String>['p1']);
      expect(prefs.getStringList('muted_peers'), <String>['legacy']);
      expect(prefs.getStringList('black_list_$toxId'), <String>['b1']);
      expect(prefs.getString('friend_remark_${peer}_$prefix16'), 'Bob');
      expect(muteKeys(prefs), isEmpty);
    });

    test('is idempotent — a re-run collects nothing new', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[toxId]),
        'c2c_recv_opt_$peer': 2,
        'c2c_recv_opt_${peer}_$prefix16': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);
      final afterFirst = muteKeys(prefs);
      expect(afterFirst, <String>{'c2c_recv_opt_${peer}_$prefix16'});

      // Force the step to run a second time (the version stamp would normally
      // short-circuit it) so idempotency is a property of the SWEEP, not just
      // of the schema guard. Pinned to 2 — the version the v2→v3 sweep runs
      // FROM — rather than `currentGlobalPrefsVersion - 1`, which silently
      // stops exercising this step the moment a v4 is added.
      await prefs.setInt('prefs_schema_version', 2);
      await PrefsUpgrader.run(prefs);

      expect(muteKeys(prefs), afterFirst);
      expect(prefs.getInt('c2c_recv_opt_${peer}_$prefix16'), 2);
    });

    test('does not run again once the schema stamp is current', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'prefs_schema_version': currentGlobalPrefsVersion,
        'account_list': accountListJson(<String>[toxId]),
        'c2c_recv_opt_$peer': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(
        muteKeys(prefs),
        <String>{'c2c_recv_opt_$peer'},
        reason:
            'an already-migrated store must not be re-swept; a later build '
            'that legitimately reintroduces an unscoped key would be eaten',
      );
    });
  });

  group('run() v3→v4 — placeholder-scoped account state', () {
    // Older builds handed `FfiChatService.selfId` — the V2TIM login ALIAS,
    // which toxee always sets to 'FlutterUIKitClient' — to
    // ExtendedPreferencesService as the account scope. Everything the user
    // muted or blocked therefore landed in one placeholder slot shared by
    // every local account. tim2tox now passes the real Tox ID, so without this
    // step the user's mutes and entire blocked list vanish on upgrade.
    const String toxIdB =
        'BBBBBBBBBBBBBBBB0123456789abcdef0123456789abcdef0123456789abcdef';
    const String prefixB = 'BBBBBBBBBBBBBBBB';
    const String placeholder = 'FlutterUIKitClient';
    const String placeholderPrefix = 'FlutterUIKitClie';

    const String peer = 'CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCD'
        'CDCDCDCDCDCDCDCDCDCDCDCD';
    const String gid = 'group-42';

    String accountListJson(List<String> toxIds) =>
        jsonEncode(toxIds.map((id) => <String, String>{'toxId': id}).toList());

    Set<String> placeholderKeys(SharedPreferences p) => p
        .getKeys()
        .where((k) =>
            k.endsWith('_$placeholderPrefix') || k.endsWith('_$placeholder'))
        .toSet();

    test('claims mutes for the only account on the install', () async {
      // Exactly one account => the placeholder slot cannot have been written by
      // anyone else, so this is not a guess.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[toxId]),
        'current_account_tox_id': toxId,
        'c2c_recv_opt_${peer}_$placeholderPrefix': 2,
        'group_recv_opt_${gid}_$placeholderPrefix': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(prefs.getInt('c2c_recv_opt_${peer}_$prefix16'), 2);
      expect(prefs.getInt('group_recv_opt_${gid}_$prefix16'), 2);
      expect(placeholderKeys(prefs), isEmpty);
      expect(prefs.getInt('prefs_schema_version'), currentGlobalPrefsVersion);
    });

    test('deletes mutes rather than guessing when two accounts exist',
        () async {
      // Un-attributable: either account could have written it. Claiming would
      // SILENTLY suppress notifications for an account that never muted this
      // peer; deleting costs one visible re-mute. Same verdict as v2→v3.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[toxId, toxIdB]),
        'current_account_tox_id': toxId,
        'c2c_recv_opt_${peer}_$placeholderPrefix': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(placeholderKeys(prefs), isEmpty);
      expect(prefs.getInt('c2c_recv_opt_${peer}_$prefix16'), isNull);
      expect(prefs.getInt('c2c_recv_opt_${peer}_$prefixB'), isNull);
    });

    test('merges the blacklist into EVERY account rather than dropping it',
        () async {
      // Opposite verdict from mutes, on purpose: dropping a blacklist entry
      // silently lets a blocked peer back through (a safety control failing
      // open), while over-blocking is visible in the Blocked Users list and
      // one click to undo.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[toxId, toxIdB]),
        'black_list_$placeholder': <String>['blockedA', 'blockedB'],
        'black_list_$toxIdB': <String>['alreadyBlocked'],
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(prefs.getStringList('black_list_$toxId'),
          <String>['blockedA', 'blockedB']);
      expect(
        prefs.getStringList('black_list_$toxIdB'),
        <String>['alreadyBlocked', 'blockedA', 'blockedB'],
        reason: 'union, not replace — an account\'s own blocks must survive',
      );
      expect(prefs.containsKey('black_list_$placeholder'), isFalse);
    });

    test('drops everything when the install knows no account at all', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'c2c_recv_opt_${peer}_$placeholderPrefix': 2,
        'black_list_$placeholder': <String>['blockedA'],
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(placeholderKeys(prefs), isEmpty);
      expect(
        prefs.getKeys().where((k) => k.startsWith('black_list_')),
        isEmpty,
        reason: 'there is no account these could be re-homed to',
      );
    });

    test('defers to PlaceholderAccountMigration when the ACCOUNT is the '
        'placeholder', () async {
      // A different, older defect: the placeholder was stored as the account's
      // own id. `PlaceholderAccountMigration` discovers the real Tox ID at
      // login (AFTER this upgrader has run) and relocates these keys itself.
      // Acting here would see "zero real accounts" and delete exactly what it
      // is about to rescue.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[placeholder]),
        'current_account_tox_id': placeholder,
        'c2c_recv_opt_${peer}_$placeholderPrefix': 2,
        'black_list_$placeholder': <String>['blockedA'],
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(prefs.getInt('c2c_recv_opt_${peer}_$placeholderPrefix'), 2);
      expect(
          prefs.getStringList('black_list_$placeholder'), <String>['blockedA']);
    });

    test('never clobbers a value already written under the real scope',
        () async {
      // A post-fix write is authoritative; the stranded placeholder value is
      // older by construction.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[toxId]),
        'c2c_recv_opt_${peer}_$placeholderPrefix': 2,
        'c2c_recv_opt_${peer}_$prefix16': 0,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(prefs.getInt('c2c_recv_opt_${peer}_$prefix16'), 0);
      expect(placeholderKeys(prefs), isEmpty);
    });

    test('changes nothing when the account registry is unreadable', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': '{not valid json',
        'c2c_recv_opt_${peer}_$placeholderPrefix': 2,
        'black_list_$placeholder': <String>['blockedA'],
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(prefs.getInt('c2c_recv_opt_${peer}_$placeholderPrefix'), 2);
      expect(
          prefs.getStringList('black_list_$placeholder'), <String>['blockedA']);
      // Best-effort cleanup, not a gate: the stamp still advances.
      expect(prefs.getInt('prefs_schema_version'), currentGlobalPrefsVersion);
    });

    test('survives the single 2→4 upgrade hop', () async {
      // THE cross-step hazard. The v2→v3 sweep classifies "not suffixed by a
      // known account prefix" as an orphan; `_FlutterUIKitClie` is exactly
      // that, so without an explicit carve-out it would delete these keys
      // moments before v3→v4 could rehome them.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'prefs_schema_version': 2,
        'account_list': accountListJson(<String>[toxId]),
        'c2c_recv_opt_${peer}_$placeholderPrefix': 2,
        // A genuinely unscoped orphan, which v2→v3 must still collect.
        'c2c_recv_opt_$peer': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(prefs.getInt('c2c_recv_opt_${peer}_$prefix16'), 2,
          reason: 'the placeholder-scoped mute must reach v3→v4 alive');
      expect(prefs.containsKey('c2c_recv_opt_$peer'), isFalse);
      expect(placeholderKeys(prefs), isEmpty);
    });

    test('is idempotent — a forced re-run changes nothing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[toxId]),
        'c2c_recv_opt_${peer}_$placeholderPrefix': 2,
        'black_list_$placeholder': <String>['blockedA'],
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);
      final afterFirst = <String, Object?>{
        for (final k in prefs.getKeys()) k: prefs.get(k),
      };

      await prefs.setInt('prefs_schema_version', 3);
      await PrefsUpgrader.run(prefs);

      final afterSecond = <String, Object?>{
        for (final k in prefs.getKeys()) k: prefs.get(k),
      };
      expect(afterSecond.keys.toSet(), afterFirst.keys.toSet());
      expect(prefs.getInt('c2c_recv_opt_${peer}_$prefix16'), 2);
      expect(prefs.getStringList('black_list_$toxId'), <String>['blockedA']);
    });

    test('leaves correctly scoped state alone', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'account_list': accountListJson(<String>[toxId, toxIdB]),
        'c2c_recv_opt_${peer}_$prefix16': 2,
        'group_recv_opt_${gid}_$prefixB': 2,
        'black_list_$toxId': <String>['b1'],
        'theme_mode': 'dark',
        // The trigger, so the step actually runs rather than returning early.
        'c2c_recv_opt_${gid}_$placeholderPrefix': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.run(prefs);

      expect(prefs.getInt('c2c_recv_opt_${peer}_$prefix16'), 2);
      expect(prefs.getInt('group_recv_opt_${gid}_$prefixB'), 2);
      expect(prefs.getStringList('black_list_$toxId'), <String>['b1']);
      expect(prefs.getString('theme_mode'), 'dark');
    });
  });

  group('migrateBlackListScope', () {
    // Extracted from `PlaceholderAccountMigration` (Step 3c) so the key surgery
    // is provable on its own — that migration needs a live FfiChatService and
    // therefore cannot run under `flutter test`. `black_list_<toxId>` is scoped
    // by the FULL id, so the `endsWith('_<first16>')` scan that relocates every
    // other account-scoped key never sees it.
    const String toxIdB =
        'BBBBBBBBBBBBBBBB0123456789abcdef0123456789abcdef0123456789abcdef';
    const String placeholder = 'FlutterUIKitClient';

    test('moves the list and removes the source', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'black_list_$placeholder': <String>['peerA', 'peerB'],
      });
      final prefs = await SharedPreferences.getInstance();

      final move = await PrefsUpgrader.migrateBlackListScope(
        prefs,
        fromToxId: placeholder,
        toToxId: toxId,
      );

      expect(move, isNotNull);
      expect(move!.moved, isTrue);
      expect(prefs.getStringList('black_list_$toxId'),
          <String>['peerA', 'peerB']);
      expect(prefs.containsKey('black_list_$placeholder'), isFalse);
    });

    test('unions with the destination instead of replacing it', () async {
      // Replacing would silently UNBLOCK whoever the destination account had
      // blocked — a safety control failing open.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'black_list_$placeholder': <String>['peerA', 'shared'],
        'black_list_$toxId': <String>['own', 'shared'],
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.migrateBlackListScope(
        prefs,
        fromToxId: placeholder,
        toToxId: toxId,
      );

      expect(prefs.getStringList('black_list_$toxId'),
          <String>['own', 'shared', 'peerA']);
    });

    test('is a no-op when there is nothing under the source scope', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'black_list_$toxId': <String>['own'],
      });
      final prefs = await SharedPreferences.getInstance();

      final move = await PrefsUpgrader.migrateBlackListScope(
        prefs,
        fromToxId: placeholder,
        toToxId: toxId,
      );

      expect(move, isNotNull);
      expect(move!.moved, isFalse,
          reason: 'a no-op must not register a rollback step');
      expect(prefs.getStringList('black_list_$toxId'), <String>['own']);
    });

    test('is a no-op when source and destination are the same account',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'black_list_$toxId': <String>['own'],
      });
      final prefs = await SharedPreferences.getInstance();

      final move = await PrefsUpgrader.migrateBlackListScope(
        prefs,
        fromToxId: toxId,
        toToxId: toxId,
      );

      expect(move!.moved, isFalse);
      expect(prefs.getStringList('black_list_$toxId'), <String>['own']);
    });

    test('is idempotent', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'black_list_$placeholder': <String>['peerA'],
      });
      final prefs = await SharedPreferences.getInstance();

      await PrefsUpgrader.migrateBlackListScope(prefs,
          fromToxId: placeholder, toToxId: toxId);
      await PrefsUpgrader.migrateBlackListScope(prefs,
          fromToxId: placeholder, toToxId: toxId);

      expect(prefs.getStringList('black_list_$toxId'), <String>['peerA']);
    });

    test('rollback restores an absent destination by REMOVING it', () async {
      // Writing an empty list instead would be wrong: an empty blacklist is a
      // meaningful "blocked nobody", not "never had one".
      SharedPreferences.setMockInitialValues(<String, Object>{
        'black_list_$placeholder': <String>['peerA'],
      });
      final prefs = await SharedPreferences.getInstance();

      final move = await PrefsUpgrader.migrateBlackListScope(prefs,
          fromToxId: placeholder, toToxId: toxIdB);
      expect(await PrefsUpgrader.rollbackBlackListScope(prefs, move!), isTrue);

      expect(prefs.containsKey('black_list_$toxIdB'), isFalse);
      expect(prefs.getStringList('black_list_$placeholder'), <String>['peerA']);
    });

    test('rollback restores a pre-existing destination exactly', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'black_list_$placeholder': <String>['peerA'],
        'black_list_$toxIdB': <String>['own'],
      });
      final prefs = await SharedPreferences.getInstance();

      final move = await PrefsUpgrader.migrateBlackListScope(prefs,
          fromToxId: placeholder, toToxId: toxIdB);
      expect(prefs.getStringList('black_list_$toxIdB'),
          <String>['own', 'peerA']);

      expect(await PrefsUpgrader.rollbackBlackListScope(prefs, move!), isTrue);

      expect(prefs.getStringList('black_list_$toxIdB'), <String>['own']);
      expect(prefs.getStringList('black_list_$placeholder'), <String>['peerA']);
    });

    test('rolling back a no-op changes nothing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'black_list_$toxId': <String>['own'],
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        await PrefsUpgrader.rollbackBlackListScope(
            prefs, const BlackListScopeMigration.noop()),
        isTrue,
      );
      expect(prefs.getStringList('black_list_$toxId'), <String>['own']);
    });
  });
}
