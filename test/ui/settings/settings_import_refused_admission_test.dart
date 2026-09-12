// Regression gate for the `admissionRefused` branch of the Settings import
// failure path (`lib/ui/settings/settings_page_import.dart`).
//
// THE FAILURE THIS PREVENTS — an existing account's password destroyed by an
// import that never wrote anything.
//
// `ToxImportJournal.write` REFUSES admission (throws
// `ToxImportInFlightException`) while another account's import is still on
// record and unrecovered. That refusal is the FIRST durable step of a `.tox`
// import, so a refused import has created nothing: no profile, no registry row,
// no verifier. The rollback flags, however, are armed one line earlier — and
// the failure path used to run `ImportedAccountRollback.run` on them anyway.
// That rollback unconditionally clears the target Tox ID's password verifier
// and its `_<first16>`-scoped preferences, which belong to whatever is ALREADY
// stored under that id. So pressing "Import Account" at the wrong moment
// silently destroyed an existing account's password: the user was locked out of
// an account the import never touched, with nothing in the UI to say so, and no
// copy of the PBKDF2 hash left anywhere to restore it from.
//
// Why the pre-existing account below carries no registry row: the row is
// exactly what the import's collision guard keys on
// (`Prefs.getAccountByToxId` → "account already exists" → return), so the only
// states in which the flow can reach the journal write at all are those where
// the row is missing — a lost or never-republished registry row, the case
// `LegacyAccountDataClaim` / `AccountReconciliation` exist to repair. That makes
// the verifier and the scoped preferences the LAST surviving evidence of the
// account, which is precisely what the unguarded rollback deleted.
//
// Mobile parity: `SettingsPage` and its import handler are shared Dart with no
// platform fork, so this gate covers iOS/Android too.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/util/account_export/tox_import_journal.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/imported_account_rollback.dart';
import 'package:toxee/util/prefs.dart';

import '../../account_export/test_support.dart';
import 'settings_account_test_support.dart';

/// The account that is already on disk under the id the import targets. Shares
/// no 16-char prefix with [kSettingsToxId] (the signed-in account), so the
/// `_<first16>` sweeps of the two cannot be confused.
const _existingToxId =
    'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';

/// The unrecovered import already on record, which is what refuses admission.
const _foreignToxId =
    'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE';

const _existingPassword = 'existing-account-password';

/// The exact wording the refusal surfaces (`l10n.importBlockedByPendingImport`).
const _refusalText = 'Another account import was interrupted';

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
    await ToxImportJournal.clear(toxId: _foreignToxId);
    ToxImportJournal.resetUnresolved();
    await env.dispose();
  });

  testWidgets(
    'a refused import leaves the existing account password and prefs intact',
    (tester) async {
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

        // Another account's import is on record and has not been recovered, so
        // the journal refuses to admit this one.
        await markToxImportStage(
          toxId: _foreignToxId,
          stage: ToxImportStage.profileWritten,
          expectsPassword: false,
          ownership: const ImportedAccountOwnership.none(),
        );
      });

      var importCalls = 0;
      await _pumpSettings(
        tester,
        pickImportFileFn: () async => '/tmp/settings_refused_admission.tox',
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
              fail('a refused import must not publish an account row');
            },
        setImportedAccountPasswordFn: (String toxId, String password) async {
          fail('a refused import must not rewrite the account password');
        },
      );

      await tester.runAsync(() async {
        await tester.tap(_importButton());
        await _pumpRealUntil(
          tester,
          () => find.textContaining(_refusalText).evaluate().isNotEmpty,
        );
      });

      expect(importCalls, 1);
      expect(
        find.textContaining(_refusalText),
        findsOneWidget,
        reason: 'the refusal is reported as "restart to finish undoing it", '
            'not as a generic import failure',
      );

      await tester.runAsync(() async {
        expect(
          await Prefs.verifyAccountPassword(_existingToxId, _existingPassword),
          isTrue,
          reason: 'the refused import wrote nothing, so it must not clear the '
              'password verifier of the account already under this id',
        );
        expect(
          await Prefs.hasAccountPassword(_existingToxId),
          isTrue,
          reason: 'hash AND salt must both survive',
        );
        expect(
          secureStore.keys.where((key) => key.contains(_existingToxId)).length,
          2,
          reason: 'both secure-storage password entries must still be there',
        );
        expect(
          await Prefs.getAutoLogin(_existingToxId),
          isFalse,
          reason: 'the account-scoped preferences must survive a refused import',
        );
        expect(
          await Prefs.exportScopedPrefsForAccount(_existingToxId),
          isNotEmpty,
          reason: 'a refused import must not sweep the `_<first16>` scope',
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
          reason: 'admission was refused before any profile was staged',
        );

        // The refused import must not clear the OTHER import's record: that
        // record is the only pointer to leftovers the next cold start has to
        // roll back.
        final surviving = await ToxImportJournal.read();
        expect(surviving, isNotNull);
        expect(surviving!.toxId, _foreignToxId);
        expect(surviving.stage, ToxImportStage.profileWritten);
      });
    },
  );
}
