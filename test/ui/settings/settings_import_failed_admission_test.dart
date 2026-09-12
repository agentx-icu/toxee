// Regression gate for the FAILED (as opposed to refused) journal write on the
// `.tox` import path — Settings entry point
// (`lib/ui/settings/settings_page_import.dart`) plus a source-shape gate over
// the two login entry points that share the defect.
//
// THE FAILURE THIS PREVENTS — an existing account's only surviving credentials
// deleted by an import that wrote nothing.
//
// `markToxImportStage(... profileWritten ...)` is the FIRST durable step of a
// `.tox` import: until it returns, the import has created no profile, no
// registry row and no verifier. It can fail two ways. A REFUSED admission
// (`ToxImportInFlightException`, another import still on record) is recognised
// by the failure handler and skips the rollback. An ORDINARY I/O FAILURE of
// that same write — the journal file unwritable, its directory gone, the disk
// full — is not: it lands in the generic `catch`, and with the rollback flags
// armed one line too early it ran `ImportedAccountRollback.run` for an import
// that had created nothing. That rollback unconditionally clears the target Tox
// ID's password verifier and sweeps its `_<first16>`-scoped preferences, which
// belong to whatever is ALREADY stored under that id. A transient write error
// therefore locked the user out of an untouched account — permanently, because
// the PBKDF2 hash and salt it deleted exist in no other copy.
//
// Why the pre-existing account below carries no registry row: the row is
// exactly what the import's collision guard keys on (`Prefs.getAccountByToxId`
// → "account already exists" → return before the journal write), so the only
// states in which the flow can reach the journal write at all are those where
// the row is missing — a lost or never-republished registry row, the case
// `LegacyAccountDataClaim` / `AccountReconciliation` exist to repair. That makes
// the verifier and the scoped preferences the LAST surviving evidence of the
// account, which is precisely what the unguarded rollback deleted.
//
// How the write is made to fail: a DIRECTORY is created at the journal's exact
// path (`<applicationSupport>/account_tox_import_journal.json`). `File.exists()`
// is false for a directory, so the journal's admission checks all pass and it
// proceeds to `writeBytesAtomically`, whose publishing rename onto that path
// fails with `EISDIR`. That is an ordinary `FileSystemException`, not
// `ToxImportInFlightException` — i.e. exactly the branch this gate is about.
//
// Mobile parity: `SettingsPage`, `LoginPageController` and the restore flow are
// shared Dart with no platform fork, so this gate covers iOS/Android too.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/util/account_export/tox_import_journal.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

import '../../account_export/test_support.dart';
import 'settings_account_test_support.dart';

/// The account that is already on disk under the id the import targets. Shares
/// no 16-char prefix with [kSettingsToxId] (the signed-in account), so the
/// `_<first16>` sweeps of the two cannot be confused.
const _existingToxId =
    'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';

const _existingPassword = 'existing-account-password';

/// The wording the generic failure branch surfaces
/// (`l10n.failedToImportAccount`), as opposed to the refusal wording.
const _failureText = 'Failed to import account';

/// The journal file the import writes first, per `ToxImportJournal._fileName`.
const _journalFileName = 'account_tox_import_journal.json';

Future<void> _pumpSettings(
  WidgetTester tester, {
  required SettingsPickImportFileFn pickImportFileFn,
  required SettingsImportAccountDataFn importAccountDataFn,
  SettingsAddImportedAccountFn? addImportedAccountFn,
  SettingsSetImportedAccountPasswordFn? setImportedAccountPasswordFn,
}) async {
  final service = SettingsHarnessService();
  addTearDown(service.disposeStub);
  await tester.binding.setSurfaceSize(const Size(1280, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    settingsApp(
      SettingsPage(
        service: service,
        connectionStatusStream: service.connectionStatusStream,
        autoAcceptFriends: false,
        onAutoAcceptFriendsChanged: (_) {},
        autoAcceptGroupInvites: false,
        onAutoAcceptGroupInvitesChanged: (_) {},
        pickImportFileFn: pickImportFileFn,
        importAccountDataFn: importAccountDataFn,
        addImportedAccountFn: addImportedAccountFn,
        setImportedAccountPasswordFn: setImportedAccountPasswordFn,
      ),
    ),
  );
  await settleSettings(tester);
}

Finder _importButton() => find.widgetWithText(OutlinedButton, 'Import Account');

Future<void> _pumpRealUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxIterations = 400,
}) async {
  for (var i = 0; i < maxIterations && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Asserts the ordering that keeps a failed journal write non-destructive:
/// ownership is snapshotted before anything is written, but the rollback is
/// armed only after the write has actually succeeded.
void _expectRollbackArmedAfterJournalWrite(String path, String armMarker) {
  final source = File(path).readAsStringSync();

  final capture = source.indexOf('ImportedAccountRollback.captureOwnership(');
  expect(capture, greaterThanOrEqualTo(0), reason: path);

  // Ownership must be captured BEFORE the first write: it records what was
  // already on disk, and capturing it afterwards would make the import claim —
  // and later delete — a pre-existing account's directories.
  final firstMark = source.indexOf('markToxImportStage(');
  expect(
    firstMark,
    greaterThan(capture),
    reason:
        '$path: ownership must be snapshotted before the first journal write, '
        'or the rollback set includes state this import did not create',
  );

  // ...and the rollback must be armed only AFTER that write returns. Arming it
  // first makes an ordinary I/O failure of the write run a rollback for an
  // import that created nothing, deleting the password verifier and scoped
  // preferences of the account already stored under this id.
  final mark = source.indexOf('markToxImportStage(', capture);
  final arm = source.indexOf(armMarker, capture);
  expect(mark, greaterThan(capture), reason: path);
  expect(arm, greaterThanOrEqualTo(0), reason: '$path: `$armMarker` not found');
  expect(
    arm,
    greaterThan(mark),
    reason:
        '$path: `$armMarker` must come AFTER the profileWritten journal write. '
        'Armed before it, a failed write takes the destructive rollback branch '
        'and wipes an existing account\'s credentials.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccountExportTestEnv env;
  final secureStore = <String, String>{};
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (
          MethodCall call,
        ) async {
          final args =
              (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
          final key = args['key'] as String?;
          switch (call.method) {
            case 'write':
              if (key != null) secureStore[key] = args['value'] as String;
              return null;
            case 'read':
              return key == null ? null : secureStore[key];
            case 'delete':
              if (key != null) secureStore.remove(key);
              return null;
            case 'containsKey':
              return key != null && secureStore.containsKey(key);
            case 'readAll':
              return Map<String, String>.from(secureStore);
            case 'deleteAll':
              secureStore.clear();
              return null;
            default:
              return null;
          }
        });
    await Prefs.setCurrentAccountToxId(kSettingsToxId);
    await Prefs.setNickname('Current Account');
    await Prefs.addAccount(toxId: kSettingsToxId, nickname: 'Current Account');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    ToxImportJournal.resetUnresolved();
    await env.dispose();
  });

  testWidgets(
    'an import whose journal write fails leaves the existing account password '
    'and prefs intact',
    (tester) async {
      // Hoisted: seeded inside the first `runAsync`, asserted in a later one.
      var seededSecureKeys = <String>{};
      await tester.runAsync(() async {
        // The account already stored under the id this import targets: a
        // password verifier plus one `_<first16>`-scoped preference. `autoLogin`
        // defaults to TRUE when its key is absent, so storing `false` here makes
        // a silent deletion observable rather than indistinguishable.
        expect(
          await Prefs.setAccountPassword(_existingToxId, _existingPassword),
          isTrue,
        );
        await Prefs.setAutoLogin(false, _existingToxId);
        expect(await Prefs.getAutoLogin(_existingToxId), isFalse);
        // Snapshot what the verifier actually occupies, so the assertion below
        // is "nothing was deleted" rather than a hard-coded entry count.
        seededSecureKeys = secureStore.keys
            .where((key) => key.contains(_existingToxId))
            .toSet();
        expect(seededSecureKeys, isNotEmpty);

        // Block the journal write with a directory at its exact path. The
        // admission checks read it as absent (`File.exists()` is false for a
        // directory), so the import reaches `writeBytesAtomically`, whose
        // publishing rename then fails with EISDIR — an ordinary I/O error, not
        // the refusal the failure handler special-cases.
        final journalPath = p.join(
          await AppPaths.applicationSupportPath,
          _journalFileName,
        );
        await Directory(journalPath).create(recursive: true);
      });

      var importCalls = 0;
      await _pumpSettings(
        tester,
        pickImportFileFn: () async => '/tmp/settings_failed_admission.tox',
        importAccountDataFn:
            ({required String filePath, String? password}) async {
              importCalls++;
              return <String, dynamic>{
                'toxId': _existingToxId,
                'toxProfile': Uint8List.fromList(<int>[1, 2, 3, 4]),
                'nickname': '',
              };
            },
        addImportedAccountFn:
            ({
              required String toxId,
              required String nickname,
              required String statusMessage,
              required bool autoLogin,
              required bool autoAcceptFriends,
              required bool notificationSoundEnabled,
            }) async {
              fail(
                'an import that never got past the journal write must not '
                'publish an account row',
              );
            },
        setImportedAccountPasswordFn: (String toxId, String password) async {
          fail(
            'an import that never got past the journal write must not rewrite '
            'the account password',
          );
        },
      );

      await tester.runAsync(() async {
        await tester.tap(_importButton());
        await _pumpRealUntil(
          tester,
          () => find.textContaining(_failureText).evaluate().isNotEmpty,
        );
      });

      expect(importCalls, 1);
      expect(
        find.textContaining(_failureText),
        findsOneWidget,
        reason:
            'a failed journal write is reported as a generic import failure, '
            'which is the branch that used to run the rollback',
      );

      await tester.runAsync(() async {
        expect(
          await Prefs.verifyAccountPassword(_existingToxId, _existingPassword),
          isTrue,
          reason:
              'the import wrote nothing, so it must not clear the password '
              'verifier of the account already under this id',
        );
        expect(
          await Prefs.hasAccountPassword(_existingToxId),
          isTrue,
          reason: 'hash AND salt must both survive',
        );
        // Not a count: the verifier is stored under several shapes (the atomic
        // record plus the legacy hash/salt pair that keeps a downgraded build
        // working), and pinning the number here would fail every time that set
        // changes for reasons this test does not care about. What it cares about
        // is that NOTHING was deleted.
        expect(
          secureStore.keys.where((key) => key.contains(_existingToxId)),
          containsAll(seededSecureKeys),
          reason: 'every secure-storage entry seeded for this account must '
              'still be there',
        );
        expect(
          await Prefs.getAutoLogin(_existingToxId),
          isFalse,
          reason:
              'the account-scoped preferences must survive an import that '
              'failed before its first durable write',
        );
        expect(
          await Prefs.exportScopedPrefsForAccount(_existingToxId),
          isNotEmpty,
          reason: 'a failed journal write must not sweep the `_<first16>` scope',
        );
        expect(
          await Prefs.getAccountByToxId(kSettingsToxId),
          isNotNull,
          reason: 'and it must not remove any registry row either',
        );
        expect(
          await Directory(
            await AppPaths.getProfileDirectoryForToxId(_existingToxId),
          ).exists(),
          isFalse,
          reason: 'the import failed before any profile was staged',
        );
      });
    },
  );

  // The same one-line ordering protects all three `.tox` entry points, but only
  // Settings is reachable from a widget test; the two login paths would
  // otherwise regress unobserved and destroy the same credentials.
  test(
    'every .tox entry point arms its rollback only after the journal write '
    'succeeds',
    () {
      // Settings gates its rollback on the boolean, not on `rollbackToxId`
      // (which the shared `.zip`/`.tox` prologue sets before the collision
      // guard), so the boolean is the line that must stay below the write.
      _expectRollbackArmedAfterJournalWrite(
        'lib/ui/settings/settings_page_import.dart',
        'rollbackImportedAccount = true',
      );
      _expectRollbackArmedAfterJournalWrite(
        'lib/ui/login/login_page_controller.dart',
        'rollbackToxId = toxId',
      );
      _expectRollbackArmedAfterJournalWrite(
        'lib/ui/login/login_restore_from_tox.dart',
        'rollbackToxId = toxId',
      );
    },
  );
}
