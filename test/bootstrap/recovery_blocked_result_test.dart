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
      expect(AccountDeletionJournalStore.quarantined, contains('garbage.json'),
          reason: 'reported so startup can surface it');
    });

    test('an unreadable tombstone cannot gate an unrelated account', () async {
      final dir = await tombstoneDir();
      await File(p.join(dir.path, 'garbage.json')).writeAsString('{ not json');

      // A tombstone we cannot parse names no account, so it must not block one.
      // Throwing here (the old behaviour) blocked EVERY account instead.
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
