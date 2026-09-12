// Regression tests for the cross-account legacy-data bleed (A5) and the
// account-registry corruption policy (A10).
//
// A5: `AppPaths.migrateAccountDataFromLegacy` copied the single global
// pre-multi-account dataset (`chat_history/`, `offline_message_queue.json`,
// `avatars/`) into WHATEVER account it was handed, on every login and every
// registration, and never retired the source. On an upgraded install the first
// account absorbed the legacy history — and so did every account created
// afterwards. Deleting the recipient did not help; the source stayed put.
//
// Ownership must be PROVEN. First-claim-wins was rejected: on an upgrade with
// account A's ENCRYPTED legacy profile, registering account B before ever
// logging into A would have handed A's history to B. These tests run without the
// FFI, so the Tox ID cannot be extracted from the legacy blob and the proof
// exercised here is byte identity between the legacy profile and the account's
// own profile — which is precisely the evidence available in that encrypted
// case.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/legacy_account_data_claim.dart';
import 'package:toxee/util/prefs.dart';

import '../account_export/test_support.dart';

void main() {
  late AccountExportTestEnv env;

  final accountA = 'A' * 76;
  final accountB = 'B' * 76;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
  });

  tearDown(() async {
    await env.dispose();
  });

  /// Seed the pre-multi-account global dataset.
  Future<void> seedLegacyGlobalData() async {
    final historyDir = Directory(await AppPaths.chatHistoryPath);
    await historyDir.create(recursive: true);
    await File(
      p.join(historyDir.path, 'c2c_PEER.json'),
    ).writeAsString('["legacy message"]');
    await File(
      await AppPaths.offlineMessageQueueFilePath,
    ).writeAsString('["queued for peer"]');
  }

  /// Write the legacy single-account profile blob.
  Future<void> seedLegacyProfile(List<int> bytes) async {
    final legacyDir = await AppPaths.toxProfileDir;
    await legacyDir.create(recursive: true);
    await File(
      AppPaths.profileFileInDirectory(legacyDir.path),
    ).writeAsBytes(bytes);
  }

  /// Give [toxId] its own profile, so ownership can be proven by byte identity.
  Future<void> seedOwnProfile(String toxId, List<int> bytes) async {
    final dir = await AppPaths.getProfileDirectoryForToxId(toxId);
    await Directory(dir).create(recursive: true);
    await File(AppPaths.profileFileInDirectory(dir)).writeAsBytes(bytes);
  }

  Future<bool> accountHasLegacyHistory(String toxId) async {
    final dir = await AppPaths.getAccountChatHistoryPath(toxId);
    return File(p.join(dir, 'c2c_PEER.json')).exists();
  }

  group('legacy global data goes only to a PROVEN owner', () {
    // These tests run without the FFI, so the Tox ID cannot be extracted from
    // the legacy blob. The proof that remains is byte identity between the
    // legacy profile and the account's own profile — which is exactly what
    // identifies the legacy account when its profile is ENCRYPTED, the case
    // that makes "first to ask" unsafe.
    const legacyBlob = <int>[0xDE, 0xAD, 0xBE, 0xEF, 0x01];

    test('an account whose own profile IS the legacy blob absorbs it',
        () async {
      await seedLegacyGlobalData();
      await seedLegacyProfile(legacyBlob);
      await seedOwnProfile(accountA, legacyBlob);

      await AppPaths.migrateAccountDataFromLegacy(accountA);

      expect(await accountHasLegacyHistory(accountA), isTrue);
      expect(
        await File(
          p.join(await AppPaths.getAccountDataRoot(accountA),
              'offline_message_queue.json'),
        ).exists(),
        isTrue,
      );
    });

    test(
        'an account that CANNOT prove ownership gets nothing, even when it is '
        'the only one and asks first', () async {
      // The counterexample that killed first-claim-wins: upgrade with account
      // A's ENCRYPTED legacy profile, then register B before ever logging into
      // A. B asks first and is the only registered account — and must still be
      // refused, because neither fact is evidence that the data is B's.
      await seedLegacyGlobalData();
      await seedLegacyProfile(legacyBlob);
      await seedOwnProfile(accountB, const <int>[0x99, 0x99]); // a DIFFERENT id

      await AppPaths.migrateAccountDataFromLegacy(accountB);

      expect(await accountHasLegacyHistory(accountB), isFalse,
          reason: 'one identity\'s messages must never be copied into a '
              'different local account');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LegacyAccountDataClaim.claimedByKey), isNull,
          reason: 'and no claim may be recorded, so the rightful owner can '
              'still claim when it eventually logs in');
    });

    test('with no legacy profile at all, nobody may take the data', () async {
      await seedLegacyGlobalData();
      // Global history present but no legacy profile to attribute it to.

      await AppPaths.migrateAccountDataFromLegacy(accountA);

      expect(await accountHasLegacyHistory(accountA), isFalse);
    });

    test('a SECOND account gets nothing once the owner has claimed', () async {
      await seedLegacyGlobalData();
      await seedLegacyProfile(legacyBlob);
      await seedOwnProfile(accountA, legacyBlob);
      await AppPaths.migrateAccountDataFromLegacy(accountA);

      // Even if B could somehow prove ownership of the same blob, the recorded
      // claim is exclusive.
      await seedOwnProfile(accountB, legacyBlob);
      await AppPaths.migrateAccountDataFromLegacy(accountB);

      expect(await accountHasLegacyHistory(accountB), isFalse);
    });

    test('the claim is a durable record, not in-memory state', () async {
      await seedLegacyGlobalData();
      await seedLegacyProfile(legacyBlob);
      await seedOwnProfile(accountA, legacyBlob);
      await AppPaths.migrateAccountDataFromLegacy(accountA);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LegacyAccountDataClaim.claimedByKey), accountA,
          reason: 'recorded so a later process — not just a later call — '
              'refuses a second claimant');
    });

    test('the owner re-claiming keeps passing (every login calls this)',
        () async {
      await seedLegacyGlobalData();
      await seedLegacyProfile(legacyBlob);
      await seedOwnProfile(accountA, legacyBlob);
      await AppPaths.migrateAccountDataFromLegacy(accountA);

      expect(await LegacyAccountDataClaim.claim(accountA), isTrue);
    });

    test('concurrent claimants cannot both win', () async {
      await seedLegacyGlobalData();
      await seedLegacyProfile(legacyBlob);
      // Both accounts can prove ownership of the same blob; the gate must still
      // grant exactly one.
      await seedOwnProfile(accountA, legacyBlob);
      await seedOwnProfile(accountB, legacyBlob);

      final results = await Future.wait([
        LegacyAccountDataClaim.claim(accountA),
        LegacyAccountDataClaim.claim(accountB),
      ]);

      expect(results.where((granted) => granted).length, 1,
          reason: 'the read-then-write must be serialized');
    });
  });

  group('account registry corruption (A10)', () {
    test('a malformed ROW is dropped, the rest survive', () async {
      final prefs = await SharedPreferences.getInstance();
      // One good row, one row whose values are not all strings.
      await prefs.setString(
        'account_list',
        '[{"toxId":"$accountA","nickname":"Good"},'
        '{"toxId":"$accountB","nickname":{"nested":"bad"}}]',
      );

      final rows = await Prefs.getAccountList();

      expect(rows.length, 1, reason: 'the parseable row must survive');
      expect(rows.single['toxId'], accountA);
      expect(prefs.getString('account_list_corrupt_backup'), isNotNull,
          reason: 'the raw payload is preserved so the dropped row is not lost '
              'for good');
    });

    test(
        'an UNPARSEABLE registry throws instead of looking empty, and blocks '
        'the overwrite that would destroy it', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_list', 'not json at all');

      // The old behaviour returned [] here, which every caller reads as "no
      // accounts registered" — so the picker emptied and the next write
      // published a single-row list over the original.
      await expectLater(
        Prefs.getAccountList(),
        throwsA(isA<AccountRegistryUnreadableException>()),
      );
      await expectLater(
        Prefs.setAccountList([
          {'toxId': accountB, 'nickname': 'Reconstructed'},
        ]),
        throwsA(isA<AccountRegistryUnreadableException>()),
        reason: 'refusing the write is what keeps the original bytes around',
      );
      expect(prefs.getString('account_list'), 'not json at all',
          reason: 'the original payload must be untouched');
      expect(prefs.getString('account_list_corrupt_backup'), 'not json at all',
          reason: 'and preserved in the backup slot');
    });

    test('addAccount cannot launder an unreadable registry into an overwrite',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_list', '{"not":"an array"}');

      await expectLater(
        Prefs.addAccount(toxId: accountA, nickname: 'New'),
        throwsA(isA<AccountRegistryUnreadableException>()),
      );
      expect(prefs.getString('account_list'), '{"not":"an array"}');
    });
  });
}
