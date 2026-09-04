// Unit tests for AccountReconciliation.reconcileOrphanedProfiles().
//
// Strategy: synthesize a "p_<first16>/tox_profile.tox" directory on disk
// with no matching account_list entry, run the reconciliation, and assert
// the account_list now contains an entry whose toxId prefix matches.
//
// The reconciliation depends on the tim2tox FFI to extract the toxId from
// a profile blob — to avoid a hard FFI dependency in unit tests, we use a
// real tox profile fixture (built via ToxProfileFixture) when the FFI is
// available, and skip the FFI-bound assertion otherwise.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/account_reconciliation.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';
import 'account_export/tox_profile_factory.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('AccountReconciliation.reconcileOrphanedProfiles', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
    });

    tearDown(() async {
      await env.dispose();
    });

    test('no profile root → returns 0', () async {
      // Remove the profiles dir entirely.
      await Directory(env.profiles).delete(recursive: true);
      expect(await AccountReconciliation.reconcileOrphanedProfiles(), 0);
    });

    test('empty profile root → returns 0', () async {
      expect(await AccountReconciliation.reconcileOrphanedProfiles(), 0);
      expect(await Prefs.getAccountList(), isEmpty);
    });

    test('recovers orphaned profile with no account_list entry',
        () async {
      final fixture = ToxProfileFixture.create();
      expect(fixture, isNotNull,
          reason: 'Tox profile fixture must be available with FFI');

      // extractToxIdFromProfile returns the 64-char public key form, which is
      // what gets stored in account_list. The first-16-char prefix matches
      // both the 64-char and 76-char forms (they share the public-key
      // prefix).
      final extractedToxId = fixture!.publicKeyHex;
      final prefix = extractedToxId.substring(0, 16);
      // Synthesize an orphan: p_<first16>/tox_profile.tox with no Prefs entry.
      final orphanDir = Directory(p.join(env.profiles, 'p_$prefix'));
      await orphanDir.create(recursive: true);
      await File(p.join(orphanDir.path, 'tox_profile.tox'))
          .writeAsBytes(fixture.savedata);

      // Sanity: no account_list entry yet.
      expect(await Prefs.getAccountList(), isEmpty);

      final recovered = await AccountReconciliation.reconcileOrphanedProfiles();
      expect(recovered, 1);

      final accounts = await Prefs.getAccountList();
      expect(accounts, hasLength(1));
      expect(accounts.first['toxId'], extractedToxId);
      expect(accounts.first['nickname'],
          'Recovered ${extractedToxId.substring(0, 8)}');
      // autoLogin should be disabled on recovered accounts so we don't
      // surprise-login to a half-recovered account on next launch.
      expect(accounts.first['autoLogin'], 'false');
      // A recovered account gets the same bundled default avatar that
      // register() installs, so it does not render as a per-surface fallback
      // (stock photo in the sidebar, initial in the profile page, …).
      final avatarPath = accounts.first['avatarPath'] ?? '';
      expect(avatarPath, isNotEmpty);
      expect(p.basename(avatarPath), 'avatar_${extractedToxId}_default.png');
      expect(await File(avatarPath).exists(), isTrue);
    }, skip: skipReason);

    test('idempotent: running twice does not duplicate the account',
        () async {
      final fixture = ToxProfileFixture.create();
      expect(fixture, isNotNull);

      final extractedToxId = fixture!.publicKeyHex;
      final prefix = extractedToxId.substring(0, 16);
      final orphanDir = Directory(p.join(env.profiles, 'p_$prefix'));
      await orphanDir.create(recursive: true);
      await File(p.join(orphanDir.path, 'tox_profile.tox'))
          .writeAsBytes(fixture.savedata);

      final first = await AccountReconciliation.reconcileOrphanedProfiles();
      final second = await AccountReconciliation.reconcileOrphanedProfiles();
      expect(first, 1);
      expect(second, 0,
          reason: 'second pass should be a no-op because account_list now matches');
      final accounts = await Prefs.getAccountList();
      expect(accounts, hasLength(1));
    }, skip: skipReason);

    test('skips profile already known in account_list', () async {
      final fixture = ToxProfileFixture.create();
      expect(fixture, isNotNull);

      final extractedToxId = fixture!.publicKeyHex;
      // Pre-register the account so the profile is NOT orphaned.
      await Prefs.addAccount(toxId: extractedToxId, nickname: 'Already known');

      final prefix = extractedToxId.substring(0, 16);
      final orphanDir = Directory(p.join(env.profiles, 'p_$prefix'));
      await orphanDir.create(recursive: true);
      await File(p.join(orphanDir.path, 'tox_profile.tox'))
          .writeAsBytes(fixture.savedata);

      final recovered = await AccountReconciliation.reconcileOrphanedProfiles();
      expect(recovered, 0);
      final accounts = await Prefs.getAccountList();
      expect(accounts, hasLength(1));
      // Original nickname should be preserved.
      expect(accounts.first['nickname'], 'Already known');
    }, skip: skipReason);

    test('skips p_* dir with no tox_profile.tox', () async {
      final emptyDir = Directory(p.join(env.profiles, 'p_0123456789abcdef'));
      await emptyDir.create(recursive: true);
      // No tox_profile.tox written.

      final recovered = await AccountReconciliation.reconcileOrphanedProfiles();
      expect(recovered, 0);
      expect(await Prefs.getAccountList(), isEmpty);
    });

    test('skips non-p_ directories', () async {
      final unrelated = Directory(p.join(env.profiles, 'other_thing'));
      await unrelated.create(recursive: true);
      // Even if it contains a tox_profile.tox, the dir name doesn't match
      // and should be ignored.
      await File(p.join(unrelated.path, 'tox_profile.tox'))
          .writeAsBytes([0, 1, 2, 3]);

      final recovered = await AccountReconciliation.reconcileOrphanedProfiles();
      expect(recovered, 0);
      expect(await Prefs.getAccountList(), isEmpty);
    });
  });
}
