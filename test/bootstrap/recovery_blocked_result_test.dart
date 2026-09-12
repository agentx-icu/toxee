// Regression guard for F1: a journal that cannot be recovered used to throw out
// of `AppBootstrap.initialize()`, which `main()` awaits BEFORE `runApp` — so the
// user got a black window with no message and no way in.
//
// Fail-closed is about not EXPOSING a half-restored account. It is not about
// refusing to render. These tests pin both halves: the recovery gate still stops
// account reconciliation (that invariant lives in
// app_bootstrap_recovery_order_test.dart), and the failure now surfaces as an
// `AppBootstrapRecoveryBlocked` result the app can render.

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/bootstrap/app_bootstrap.dart';
import 'package:toxee/bootstrap/app_bootstrap_result.dart';
import 'package:toxee/util/account_deletion_journal.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/safe_diagnostics.dart';

import '../account_export/test_support.dart';

import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  late AccountExportTestEnv env;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
  });

  tearDown(() async {
    AccountDeletionJournalStore.resetQuarantineState();
    await env.dispose();
  });

  group('AppBootstrapRecoveryBlocked', () {
    test('carries a sanitized detail, never a path or Tox ID', () {
      // The detail reaches both the screen and flutter_client.log. Journal paths
      // embed the account's public-key prefix and the absolute
      // application-support layout, which is why the producer runs the error
      // through SafeDiagnostics rather than interpolating it.
      const result = AppBootstrapRecoveryBlocked(detail: 'FormatException');
      expect(result, isA<AppBootstrapResult>());
      expect(result.detail, 'FormatException');
    });

    test('SafeDiagnostics.describeError keeps the type without the payload', () {
      final described = SafeDiagnostics.describeError(
        const FormatException('/Users/someone/Library/p_ABCDEF0123456789'),
      );
      expect(described, contains('FormatException'));
      expect(described, isNot(contains('p_ABCDEF0123456789')),
          reason: 'the account prefix must not reach the log or the screen');
      expect(described, isNot(contains('/Users/')),
          reason: 'nor the absolute local layout');
    });
  });

  group('deletion tombstones: unreadable files are quarantined, not fatal', () {
    Future<Directory> tombstoneDir() async {
      final root = await AppPaths.applicationSupportPath;
      final dir = Directory(p.join(root, 'account_deletion_tombstones'));
      await dir.create(recursive: true);
      return dir;
    }

    test('a corrupt tombstone does not abort the scan', () async {
      final dir = await tombstoneDir();
      final good = AccountDeletionTombstone.initial(toxId: 'A' * 76);
      await AccountDeletionJournalStore.write(good);
      await File(p.join(dir.path, 'garbage.json')).writeAsString('{ not json');

      // Before: this threw, and it sits on three hot paths — cold-start
      // recovery, `throwIfDeleting` (EVERY login and account switch), and
      // `clear`. One stray file blocked all of them.
      final tombstones = await AccountDeletionJournalStore.readAll();

      expect(tombstones.map((t) => t.toxId), contains('A' * 76),
          reason: 'the readable tombstone must still be returned');
    });

    test('the corrupt file is preserved, renamed rather than deleted', () async {
      final dir = await tombstoneDir();
      await File(p.join(dir.path, 'garbage.json')).writeAsString('{ not json');

      await AccountDeletionJournalStore.readAll();

      expect(await File(p.join(dir.path, 'garbage.json.corrupt')).exists(),
          isTrue,
          reason: 'it is the only record that a deletion was in progress, so it '
              'is quarantined rather than destroyed');
      expect(await File(p.join(dir.path, 'garbage.json')).exists(), isFalse,
          reason: 'and moved aside so it is not re-scanned forever');
    });

    test(
        'a corrupt tombstone whose NAME identifies the account keeps gating it',
        () async {
      // The gate is what stops a half-deleted account being opened — e.g. one
      // whose deletion stopped after the password was removed but before the
      // profile was. Renaming the file aside without replacing the gate made
      // that account readable again from this startup onward. The filename is
      // `<toxId>.json`, so the account is still identifiable.
      final dir = await tombstoneDir();
      final toxId = 'D' * 76;
      await File(p.join(dir.path, '$toxId.json')).writeAsString('{ truncated');

      expect(await AccountDeletionJournalStore.hasPendingForToxId(toxId), isTrue,
          reason: 'a minimal tombstone is rebuilt from the filename, so the '
              'account stays blocked and recovery re-runs the idempotent stages');
      expect(await File(p.join(dir.path, '$toxId.json.corrupt')).exists(),
          isTrue,
          reason: 'and the original bytes are still preserved');
      expect(AccountDeletionJournalStore.unattributableQuarantine, isEmpty,
          reason: 'this case IS attributable, so startup need not refuse');
    });

    test(
        'a corrupt tombstone that cannot be attributed makes startup refuse',
        () async {
      final dir = await tombstoneDir();
      await File(p.join(dir.path, 'garbage.json')).writeAsString('{ not json');

      await AccountDeletionJournalStore.readAll();

      // No account can be derived, so no gate can be rebuilt. Carrying on would
      // leave some account half-deleted with nothing blocking it, so startup
      // refuses to expose any account instead of guessing.
      expect(AccountDeletionJournalStore.unattributableQuarantine,
          contains('garbage.json'));
      await expectLater(
        AppBootstrap.recoverPendingRestoreBeforeAccountExposure(
          recoverPendingRestore: () async {},
          recoverPendingDeletions: () async {},
          reconcileAccounts: () async =>
              fail('reconciliation must not run with an unattributable record'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('an unattributable record does not gate an unrelated account',
        () async {
      final dir = await tombstoneDir();
      await File(p.join(dir.path, 'garbage.json')).writeAsString('{ not json');

      // It cannot name an account, so it must not block a specific one — the
      // process-wide refusal above is the correct instrument, not a per-account
      // block that would hit the wrong account.
      await expectLater(
        AccountDeletionJournalStore.hasPendingForToxId('B' * 76),
        completion(isFalse),
      );
    });

    test('clear() survives a corrupt sibling', () async {
      final dir = await tombstoneDir();
      final target = AccountDeletionTombstone.initial(toxId: 'C' * 76);
      await AccountDeletionJournalStore.write(target);
      await File(p.join(dir.path, 'garbage.json')).writeAsString('nope');

      // A corrupt sibling used to abort the sweep, which kept a COMPLETED
      // deletion's tombstone alive and re-ran its stages on every cold start.
      await AccountDeletionJournalStore.clear('C' * 76);

      expect(await AccountDeletionJournalStore.read('C' * 76), isNull);
    });
  });
}
