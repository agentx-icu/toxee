// Regression tests for A4: the single-file `.tox` import had no journal.
//
// It writes three pieces of durable state in order — the profile file, the
// account row, the password verifier — and its only recovery was an in-process
// `catch`. A kill does not run that, and mobile kills backgrounded apps as a
// matter of course, so each gap left a shape the user could not get out of:
//
//   * killed after the profile write, before encryption: an UNPROTECTED profile
//     that `AccountReconciliation` would register as a usable account, even
//     though the user supplied a password;
//   * killed after encryption, before the row: an invisible encrypted orphan —
//     reconciliation skips profiles whose identity it cannot extract, and
//     re-import was refused because the file already existed;
//   * killed after the row, before the verifier: ciphertext in the picker,
//     reported unprotected, impossible to open.
//
// Recovery rolls back rather than completing, because finishing needs the user's
// password and startup does not have it. A rolled-back import is one the user
// can simply retry.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/util/account_export/tox_import_journal.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/imported_account_rollback.dart';
import 'package:toxee/util/prefs.dart';

import 'test_support.dart';

void main() {
  late AccountExportTestEnv env;

  final toxId = 'A' * 76;

  final secureStore = <String, String>{};
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      final args =
          (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      switch (call.method) {
        case 'write':
          secureStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args['key'] as String];
        case 'delete':
          secureStore.remove(args['key'] as String);
          return null;
        case 'containsKey':
          return secureStore.containsKey(args['key'] as String);
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'deleteAll':
          secureStore.clear();
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    await ToxImportJournal.clear(toxId: toxId);
    ToxImportJournal.resetUnresolved();
    await env.dispose();
  });

  /// Stage the on-disk state an import would have created, and journal it as if
  /// the process died at [stage].
  Future<String> stageInterruptedImport(ToxImportStage stage) async {
    final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
    final ownership = await ImportedAccountRollback.captureOwnership(toxId);
    await Directory(profileDir).create(recursive: true);
    final profilePath = AppPaths.profileFileInDirectory(profileDir);
    await File(profilePath).writeAsBytes(<int>[1, 2, 3, 4]);
    await markToxImportStage(
      toxId: toxId,
      stage: stage,
      expectsPassword: true,
      ownership: ownership,
    );
    return profilePath;
  }

  test('an import killed before encryption is rolled back, not registered',
      () async {
    final profilePath = await stageInterruptedImport(
      ToxImportStage.profileWritten,
    );

    await ToxImportJournal.recoverPendingImport();

    expect(await File(profilePath).exists(), isFalse,
        reason: 'an unprotected profile must not survive for reconciliation to '
            'pick up as a usable account');
    expect(await ToxImportJournal.read(), isNull,
        reason: 'and the journal is cleared so it is not replayed');
  });

  test('an encrypted orphan is removed so the file can be imported again',
      () async {
    final profilePath = await stageInterruptedImport(
      ToxImportStage.profileProtected,
    );

    await ToxImportJournal.recoverPendingImport();

    // This is the shape that was previously unrecoverable: no registry row to
    // find it by, reconciliation unable to read its identity, and re-import
    // refused because the profile file existed.
    expect(await File(profilePath).exists(), isFalse);
  });

  test('a published row and its verifier are both undone', () async {
    await stageInterruptedImport(ToxImportStage.accountPublished);
    await Prefs.addAccount(toxId: toxId, nickname: 'Half imported');
    expect(await Prefs.setAccountPassword(toxId, 'pw'), isTrue);

    await ToxImportJournal.recoverPendingImport();

    expect(await Prefs.getAccountByToxId(toxId), isNull,
        reason: 'the row must go with the profile');
    expect(await Prefs.accountProtectionState(toxId),
        AccountProtectionState.none,
        reason: 'and so must the verifier — otherwise a later import of the '
            'same file demands a password for an account that no longer exists');
  });

  test('a clean start with no journal does nothing', () async {
    await ToxImportJournal.recoverPendingImport();
    expect(await ToxImportJournal.read(), isNull);
  });

  test('the journal only claims the account it names', () async {
    await stageInterruptedImport(ToxImportStage.profileWritten);

    expect(await ToxImportJournal.isPendingFor(toxId), isTrue);
    expect(await ToxImportJournal.isPendingFor('B' * 76), isFalse,
        reason: 'an in-flight import must not shadow an unrelated account');
  });

  test(
      'an unreadable journal is KEPT, so the warning survives a restart',
      () async {
    final root = await AppPaths.applicationSupportPath;
    final journal = File(p.join(root, 'account_tox_import_journal.json'));
    await journal.writeAsString('{ truncated');

    expect(await ToxImportJournal.read(), isNull,
        reason: 'it yields no entry — the account cannot be identified');
    expect(await journal.exists(), isTrue,
        reason: 'but the FILE stays: it is the durable marker. Renaming it aside '
            'left only an in-memory flag, so the next cold start forgot the '
            'problem and reconciliation proceeded over the half-import');
    expect(ToxImportJournal.hasUnreadableJournal, isTrue,
        reason: 'reported separately from `unresolved`, because an unidentifiable '
            'import must not block the whole app — only orphan adoption');
    expect(ToxImportJournal.unresolved, isEmpty);
  });

  group('the singleton record belongs to exactly one import', () {
    final other = 'B' * 76;

    test('a second import refuses rather than overwriting the first record',
        () async {
      await stageInterruptedImport(ToxImportStage.profileWritten);

      // Three entry points (Settings import, login import, login restore) guard
      // themselves with three independent per-widget booleans, so overlap is
      // possible. Overwriting here would erase the only pointer to the first
      // import's leftovers, which reconciliation would then adopt WITHOUT the
      // password the user gave it.
      await expectLater(
        markToxImportStage(
          toxId: other,
          stage: ToxImportStage.profileWritten,
          expectsPassword: false,
          ownership: const ImportedAccountOwnership.none(),
        ),
        throwsA(isA<ToxImportInFlightException>()),
      );
      final surviving = await ToxImportJournal.read();
      expect(surviving?.toxId, toxId);
    });

    test('advancing the SAME import through its stages is not a conflict',
        () async {
      await stageInterruptedImport(ToxImportStage.profileWritten);
      await markToxImportStage(
        toxId: toxId,
        stage: ToxImportStage.accountPublished,
        expectsPassword: true,
        ownership: const ImportedAccountOwnership.none(),
      );
      expect((await ToxImportJournal.read())?.stage,
          ToxImportStage.accountPublished);
    });

    test('an unreadable record blocks a new import instead of being replaced',
        () async {
      final root = await AppPaths.applicationSupportPath;
      await File(p.join(root, 'account_tox_import_journal.json'))
          .writeAsString('{ truncated');

      await expectLater(
        markToxImportStage(
          toxId: toxId,
          stage: ToxImportStage.profileWritten,
          expectsPassword: false,
          ownership: const ImportedAccountOwnership.none(),
        ),
        throwsA(isA<ToxImportInFlightException>()),
      );
    });

    test('two imports racing admission cannot both publish', () async {
      // The ownership check and the write are a read-modify-write. Checking
      // "is there a record?" and then writing one is not enough on its own:
      // two imports that interleave inside that window both see nothing and
      // both publish, and the first one's recovery record is gone. Starting
      // them without awaiting the first is what puts them in that window.
      final first = markToxImportStage(
        toxId: toxId,
        stage: ToxImportStage.profileWritten,
        expectsPassword: false,
        ownership: const ImportedAccountOwnership.none(),
      ).then((_) => 'admitted').catchError((Object _) => 'refused');
      final second = markToxImportStage(
        toxId: other,
        stage: ToxImportStage.profileWritten,
        expectsPassword: false,
        ownership: const ImportedAccountOwnership.none(),
      ).then((_) => 'admitted').catchError((Object _) => 'refused');

      final outcomes = await Future.wait<String>(<Future<String>>[
        first,
        second,
      ]);

      expect(outcomes.where((o) => o == 'admitted'), hasLength(1),
          reason: 'exactly one of two concurrent imports may be admitted');
      final record = await ToxImportJournal.read();
      expect(record, isNotNull);
      expect(<String>[toxId, other], contains(record!.toxId),
          reason: 'and the surviving record must be a real one, not a blend');
    });

    test('a retry of the SAME account is refused until recovery has run',
        () async {
      await stageInterruptedImport(ToxImportStage.profileWritten);

      // The retry looks like the same account, so an ownership check on the Tox
      // ID alone waves it through - and then its success clears the earlier
      // attempt's record, discarding the only pointer to what that attempt left
      // behind. A half-written verifier (hash stored, salt not) then survives
      // under an account the user can never open again.
      await expectLater(
        markToxImportStage(
          toxId: toxId,
          stage: ToxImportStage.profileWritten,
          expectsPassword: true,
          ownership: const ImportedAccountOwnership.none(),
        ),
        throwsA(isA<ToxImportInFlightException>()),
      );
      expect((await ToxImportJournal.read())?.stage,
          ToxImportStage.profileWritten,
          reason: 'the original record survives for the next cold start');
    });

    test('clear does not delete a record that belongs to another import',
        () async {
      await stageInterruptedImport(ToxImportStage.profileWritten);

      await ToxImportJournal.clear(toxId: other);

      expect(await ToxImportJournal.read(), isNotNull,
          reason: 'the second import finishing must not wipe the first one out '
              'of recovery');
    });
  });

  group('the journal is cleared only when the rollback is verified', () {
    test('a surviving profile keeps the journal for the next attempt', () async {
      final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
      await Directory(profileDir).create(recursive: true);
      final profile = File(AppPaths.profileFileInDirectory(profileDir));
      await profile.writeAsBytes(<int>[9, 9]);
      await markToxImportStage(
        toxId: toxId,
        stage: ToxImportStage.profileWritten,
        expectsPassword: false,
        ownership: const ImportedAccountOwnership.none(),
      );

      // `ownership.none()` means the rollback may delete nothing, so the profile
      // survives. Dropping the journal here would hand that leftover to the
      // reconciliation pass that runs right afterwards.
      final cleared = await ToxImportJournal.clearIfRolledBack(toxId: toxId);

      expect(cleared, isFalse);
      expect(await ToxImportJournal.read(), isNotNull,
          reason: 'the record must survive so the next start retries');
    });

    test('a surviving verifier also keeps the journal', () async {
      await markToxImportStage(
        toxId: toxId,
        stage: ToxImportStage.accountPublished,
        expectsPassword: true,
        ownership: const ImportedAccountOwnership.none(),
      );
      // The verifier is read back from the durable store rather than taken from
      // the caller. It used to be a `verifierRemoved` parameter defaulting to
      // true that every production handler omitted, so a secure-store cleanup
      // that quietly failed still cleared the journal - and the next import of
      // the same file inherited a verifier nobody could satisfy.
      expect(await Prefs.setAccountPassword(toxId, 'pw'), isTrue);

      expect(
        await ToxImportJournal.clearIfRolledBack(toxId: toxId),
        isFalse,
        reason: 'ciphertext with a stale verifier is exactly the state the '
            'rollback exists to remove',
      );
      expect(await ToxImportJournal.read(), isNotNull);
    });

    test('a fully undone import clears', () async {
      await markToxImportStage(
        toxId: toxId,
        stage: ToxImportStage.profileWritten,
        expectsPassword: false,
        ownership: const ImportedAccountOwnership.none(),
      );
      // No profile on disk and no row: nothing survives.
      expect(await ToxImportJournal.clearIfRolledBack(toxId: toxId), isTrue);
      expect(await ToxImportJournal.read(), isNull);
    });
  });
}
