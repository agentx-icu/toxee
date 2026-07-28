// Unit tests for [LoginPageController].
//
// We exercise the early-exit branches of the restore/import flows that do
// NOT require FFI:
//   - `restoreFromToxFile` with a non-.tox `filePathOverride` returns
//     [RestoreFailureKind.notAToxProfile] before any AccountExportService /
//     FFI call (line 271 in login_page_controller.dart).
//   - `restoreFromToxFile` against a path that doesn't exist falls into the
//     catch-all "non-password errors at this point mean the file is not a
//     valid Tox profile" branch and returns [RestoreFailureKind.notAToxProfile]
//     with a non-null detail.
//   - `restoreFromToxFile` with a cancelled password prompt for an encrypted
//     file returns [RestoreFailureKind.cancelled] without writing anything to
//     disk or Prefs.
//
// The happy path requires real Tox profile bytes (FFI extract) and is covered
// by integration-style account_export tests; see test/account_export/.
//
// Note: `restoreFromToxFile` only has `filePathOverride` as a @visibleForTesting
// seam. `importAccount` does not, so we can only assert that constructing the
// controller is safe and that the public sealed-result types are reachable
// (which is implicitly verified above).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/auth/login_use_case.dart';
import 'package:toxee/ui/login/login_page_controller.dart';
import 'package:toxee/util/account_export_service.dart'
    show InvalidBackupPasswordException, PasswordRequiredException;
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

import '../../account_export/test_support.dart';

final class _PrivacySentinelFailure implements Exception {
  const _PrivacySentinelFailure();

  @override
  String toString() =>
      '/private/accounts/alice/account_backup.tox '
      'FULL_TOX_ID_0123456789 PAYLOAD_SECRET STACK_SECRET';
}

final class _FailingLoginUseCase extends LoginUseCase {
  @override
  Future<LoginSuccess> execute(LoginParams params) async {
    throw const _PrivacySentinelFailure();
  }
}

Future<void> _initEmptyPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

final class _ExistingAccountArtifacts {
  const _ExistingAccountArtifacts({
    required this.profileFile,
    required this.dataFile,
    required this.scopedPrefs,
  });

  final File profileFile;
  final File dataFile;
  final Map<String, dynamic> scopedPrefs;
}

Future<_ExistingAccountArtifacts> _seedExistingAccountArtifacts(
  String toxId,
) async {
  await Prefs.addAccount(
    toxId: toxId,
    nickname: 'Existing Account',
    statusMessage: 'Existing status',
    autoLogin: true,
  );
  await Prefs.setAutoLogin(false, toxId);

  final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
  final profileFile = File(AppPaths.profileFileInDirectory(profileDir));
  await profileFile.parent.create(recursive: true);
  await profileFile.writeAsBytes(<int>[91, 92, 93]);

  final dataRoot = Directory(await AppPaths.getAccountDataRoot(toxId));
  await dataRoot.create(recursive: true);
  final dataFile = File('${dataRoot.path}/existing-data.txt');
  await dataFile.writeAsString('existing account data');

  return _ExistingAccountArtifacts(
    profileFile: profileFile,
    dataFile: dataFile,
    scopedPrefs: await Prefs.exportScopedPrefsForAccount(toxId),
  );
}

Future<void> _expectExistingAccountArtifactsPreserved(
  String toxId,
  _ExistingAccountArtifacts artifacts,
) async {
  final account = await Prefs.getAccountByToxId(toxId);
  expect(account, isNotNull);
  expect(account!['nickname'], 'Existing Account');
  expect(await artifacts.profileFile.readAsBytes(), <int>[91, 92, 93]);
  expect(await artifacts.dataFile.readAsString(), 'existing account data');
  expect(await Prefs.exportScopedPrefsForAccount(toxId), artifacts.scopedPrefs);
}

Future<void> _addImportedAccountAndData({
  required String toxId,
  required String nickname,
  required String statusMessage,
  required bool autoLogin,
  required bool autoAcceptFriends,
  required bool notificationSoundEnabled,
}) async {
  await Prefs.addAccount(
    toxId: toxId,
    nickname: nickname,
    statusMessage: statusMessage,
    autoLogin: autoLogin,
    autoAcceptFriends: autoAcceptFriends,
    notificationSoundEnabled: notificationSoundEnabled,
  );
  await Prefs.setAutoLogin(false, toxId);
  final dataRoot = Directory(await AppPaths.getAccountDataRoot(toxId));
  await dataRoot.create(recursive: true);
  await File('${dataRoot.path}/partial-import.txt').writeAsString('partial');
}

Future<void> _expectImportRolledBack(String toxId) async {
  expect(await Prefs.getAccountByToxId(toxId), isNull);
  final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
  expect(await Directory(profileDir).exists(), isFalse);
  expect(
    await Directory(await AppPaths.getAccountDataRoot(toxId)).exists(),
    isFalse,
  );
  expect(await Prefs.exportScopedPrefsForAccount(toxId), isEmpty);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LoginPageController.restoreFromToxFile', () {
    test(
      'rejects non-.tox file with notAToxProfile (no FFI, no disk I/O)',
      () async {
        await _initEmptyPrefs();
        final controller = LoginPageController();
        // .txt extension trips the early file-type guard before any
        // AccountExportService.importAccountData call is made.
        final result = await controller.restoreFromToxFile(
          requestPassword: () async {
            fail(
              'Password should not be requested for an obvious non-.tox file',
            );
          },
          importedAccountDefaultName: 'imported',
          filePathOverride: '/tmp/not_a_tox_file.txt',
        );
        expect(result, isA<RestoreFailure>());
        final failure = result as RestoreFailure;
        expect(
          failure.kind,
          RestoreFailureKind.notAToxProfile,
          reason: 'Extension guard returns notAToxProfile before touching FFI',
        );
        expect(
          failure.detail,
          isNull,
          reason: 'Early-exit path does not have an underlying error string',
        );
      },
    );

    test('missing .tox file surfaces notAToxProfile failure', () async {
      await _initEmptyPrefs();
      // Use a path that definitely does not exist; the .tox extension passes
      // the first guard but the file read fails inside importAccountData and
      // the controller maps the unexpected error to notAToxProfile per its
      // own comment ("non-password errors at this point mean the file is
      // not a valid Tox profile").
      final controller = LoginPageController();
      final result = await controller.restoreFromToxFile(
        requestPassword: () async {
          fail('Password should not be requested when the file is missing');
        },
        importedAccountDefaultName: 'imported',
        filePathOverride:
            '/tmp/definitely_does_not_exist_${DateTime.now().microsecondsSinceEpoch}.tox',
      );
      expect(result, isA<RestoreFailure>());
      final failure = result as RestoreFailure;
      expect(failure.kind, RestoreFailureKind.notAToxProfile);
      expect(
        failure.detail,
        isNotNull,
        reason: 'A real underlying I/O error is captured for diagnostics',
      );
      expect(failure.detail, startsWith('error_type='));
      expect(failure.detail, isNot(contains('definitely_does_not_exist')));
    });

    test(
      'returns cancelled when an encrypted file asks for password and the '
      'user cancels the prompt',
      () async {
        await _initEmptyPrefs();
        // Build a fake "encrypted .tox" by writing the qTox/Tox-pass header
        // ("toxEsave") + arbitrary cipher bytes. importAccountData() detects
        // encryption via that prefix and throws PasswordRequiredException when
        // no password is provided; restoreFromToxFile then calls requestPassword
        // which returns null in this test.
        final tmpFile = File(
          '${Directory.systemTemp.path}/restoreFromToxFile_cancel_${DateTime.now().microsecondsSinceEpoch}.tox',
        );
        // The actual encryption magic is `toxEsave` (8 bytes) at offset 0, then
        // 24-byte salt, 24-byte nonce, mac, ciphertext. We only need the prefix
        // to trip the isDataEncrypted() check and the body large enough to clear
        // the toxPassEncryptionExtraLength threshold (≈ 8+32+24+16 bytes).
        final magic = [
          0x74,
          0x6F,
          0x78,
          0x45,
          0x73,
          0x61,
          0x76,
          0x65,
        ]; // toxEsave
        final filler = List<int>.filled(200, 0);
        await tmpFile.writeAsBytes([...magic, ...filler]);
        addTearDown(() async {
          if (await tmpFile.exists()) await tmpFile.delete();
        });

        final controller = LoginPageController();
        var passwordPromptCalls = 0;
        final result = await controller.restoreFromToxFile(
          requestPassword: () async {
            passwordPromptCalls++;
            return null; // user cancelled
          },
          importedAccountDefaultName: 'imported',
          filePathOverride: tmpFile.path,
        );
        expect(
          passwordPromptCalls,
          1,
          reason: 'Encrypted file should trigger exactly one password prompt',
        );
        expect(result, isA<RestoreFailure>());
        final failure = result as RestoreFailure;
        expect(
          failure.kind,
          RestoreFailureKind.cancelled,
          reason:
              'Cancelled password prompt must surface as cancelled, never as '
              'invalidPassword or generalError',
        );
      },
      // restoreFromToxFile → importAccountData → tox_file_io.isDataEncrypted
      // calls Tim2ToxFfi.open() to check the encryption magic. CI runners
      // that didn't build libtim2tox_ffi (analyze.yml's flutter test pass)
      // would dlopen-fail here. The two preceding tests avoid FFI: the
      // non-.tox test never reaches importAccountData, and the missing-file
      // test short-circuits on file.exists(). A proper fix would inject
      // AccountExportService as a constructor seam on LoginPageController
      // so this branch can be unit-tested without FFI; until then, skip
      // unless the env opts in.
      skip: Platform.environment['TOXEE_TESTS_NEED_NATIVE'] == '1'
          ? false
          : 'requires libtim2tox_ffi (set TOXEE_TESTS_NEED_NATIVE=1 to run)',
    );

    test(
      'rolls back written profile when restore fails after artifacts were created',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async =>
                  <String, dynamic>{
                    'toxId': toxId,
                    'toxProfile': Uint8List.fromList(<int>[1, 2, 3, 4]),
                    'nickname': 'Recovered',
                  },
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                throw Exception('boom after profile write');
              },
          encryptProfileFileFn: (String profilePath, String password) async {
            fail('plain restore must not encrypt the staged profile');
          },
        );

        final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final profileFilePath = AppPaths.profileFileInDirectory(profileDir);

        final result = await controller.restoreFromToxFile(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/fake_restore_success.tox',
        );

        expect(result, isA<RestoreFailure>());
        expect(
          (result as RestoreFailure).kind,
          RestoreFailureKind.generalError,
        );
        expect(
          await File(profileFilePath).exists(),
          isFalse,
          reason: 'restore rollback must remove the profile written earlier',
        );
        expect(
          await Prefs.getAccountByToxId(toxId),
          isNull,
          reason: 'restore rollback must not leave a visible account row',
        );
      },
    );

    test(
      'restore rolls back when account password persistence is refused',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '1010101010101010101010101010101010101010101010101010101010101010';
        var importCalls = 0;
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async {
                importCalls++;
                if (password == null) {
                  throw const PasswordRequiredException('password required');
                }
                return <String, dynamic>{
                  'toxId': toxId,
                  'toxProfile': Uint8List.fromList(<int>[1, 3, 5, 7]),
                  'nickname': 'Recovered',
                };
              },
          addAccountFn: _addImportedAccountAndData,
          encryptProfileFileFn: (String profilePath, String password) async =>
              true,
          setAccountPasswordFn: (String toxId, String password) async => false,
        );

        final result = await controller.restoreFromToxFile(
          requestPassword: () async => 'restore-password',
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/password_failure_restore.tox',
        );

        expect(importCalls, 2);
        expect(result, isA<RestoreFailure>());
        final failure = result as RestoreFailure;
        expect(failure.kind, RestoreFailureKind.generalError);
        expect(failure.detail, 'error_type=StateError');
        await _expectImportRolledBack(toxId);
      },
    );

    test(
      'restore encrypts the staged profile before account and password writes',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '1110101010101010101010101010101010101010101010101010101010101010';
        const password = 'restore-password';
        final events = <String>[];
        final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final expectedProfilePath = AppPaths.profileFileInDirectory(profileDir);
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async {
                if (password == null) {
                  throw const PasswordRequiredException('password required');
                }
                return <String, dynamic>{
                  'toxId': toxId,
                  'toxProfile': Uint8List.fromList(<int>[1, 3, 5, 7]),
                  'nickname': 'Recovered',
                };
              },
          encryptProfileFileFn: (String profilePath, String supplied) async {
            events.add('encrypt');
            expect(profilePath, expectedProfilePath);
            expect(supplied, password);
            expect(await File(profilePath).readAsBytes(), <int>[1, 3, 5, 7]);
            await File(profilePath).writeAsBytes(<int>[9, 8, 7]);
            return true;
          },
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                events.add('addAccount');
                expect(await File(expectedProfilePath).readAsBytes(), <int>[
                  9,
                  8,
                  7,
                ]);
              },
          setAccountPasswordFn: (String toxId, String supplied) async {
            events.add('savePassword');
            expect(supplied, password);
            return true;
          },
        );

        final result = await controller.restoreFromToxFile(
          requestPassword: () async => password,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/encrypted_restore.tox',
        );

        expect(result, isA<RestoreSuccess>());
        expect(events, <String>['encrypt', 'addAccount', 'savePassword']);
      },
    );

    test(
      'restore encryption refusal rolls back and never writes account password',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '1210101010101010101010101010101010101010101010101010101010101010';
        var addAccountCalls = 0;
        var passwordWriteCalls = 0;
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async {
                if (password == null) {
                  throw const PasswordRequiredException('password required');
                }
                return <String, dynamic>{
                  'toxId': toxId,
                  'toxProfile': Uint8List.fromList(<int>[2, 4, 6, 8]),
                  'nickname': 'Recovered',
                };
              },
          encryptProfileFileFn: (String profilePath, String password) async {
            expect(await File(profilePath).readAsBytes(), <int>[2, 4, 6, 8]);
            return false;
          },
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                addAccountCalls++;
              },
          setAccountPasswordFn: (String toxId, String password) async {
            passwordWriteCalls++;
            return true;
          },
        );

        final result = await controller.restoreFromToxFile(
          requestPassword: () async => 'restore-password',
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/encryption_refusal_restore.tox',
        );

        expect(result, isA<RestoreFailure>());
        expect(
          (result as RestoreFailure).kind,
          RestoreFailureKind.generalError,
        );
        expect(addAccountCalls, 0);
        expect(passwordWriteCalls, 0);
        await _expectImportRolledBack(toxId);
      },
    );

    test(
      'restore duplicate collision preserves existing account profile and data',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '2020202020202020202020202020202020202020202020202020202020202020';
        final artifacts = await _seedExistingAccountArtifacts(toxId);
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async =>
                  <String, dynamic>{
                    'toxId': toxId,
                    'toxProfile': Uint8List.fromList(<int>[2, 4, 6, 8]),
                    'nickname': 'Incoming',
                  },
        );

        final result = await controller.restoreFromToxFile(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/duplicate_restore.tox',
        );

        expect(result, isA<RestoreFailure>());
        expect(
          (result as RestoreFailure).kind,
          RestoreFailureKind.accountAlreadyExists,
        );
        await _expectExistingAccountArtifactsPreserved(toxId, artifacts);
      },
    );

    test(
      'restore validation error before its first write preserves existing artifacts',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '3030303030303030303030303030303030303030303030303030303030303030';
        final artifacts = await _seedExistingAccountArtifacts(toxId);
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async =>
                  <String, dynamic>{
                    'toxId': toxId,
                    'toxProfile': 'invalid profile bytes',
                    'nickname': 'Incoming',
                  },
        );

        final result = await controller.restoreFromToxFile(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/invalid_restore.tox',
        );

        expect(result, isA<RestoreFailure>());
        expect(
          (result as RestoreFailure).kind,
          RestoreFailureKind.generalError,
        );
        await _expectExistingAccountArtifactsPreserved(toxId, artifacts);
      },
    );

    test(
      'contains restore rollback failure and returns sanitized restore failure',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '3131313131313131313131313131313131313131313131313131313131313131';
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async =>
                  <String, dynamic>{
                    'toxId': toxId,
                    'toxProfile': Uint8List.fromList(<int>[3, 1, 3, 1]),
                    'nickname': 'Incoming',
                  },
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                throw Exception('private restore registry detail');
              },
          rollbackImportedAccountFn:
              ({required String toxId, required String logContext}) async {
                throw StateError('private restore rollback path');
              },
        );

        final result = await controller.restoreFromToxFile(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/restore_rollback_failure.tox',
        );

        expect(result, isA<RestoreFailure>());
        final failure = result as RestoreFailure;
        expect(failure.kind, RestoreFailureKind.generalError);
        expect(failure.detail, 'error_type=_Exception');
        expect(failure.detail, isNot(contains('private')));
      },
    );

    test(
      'generic tox import wrong password is invalid before writes or rollback',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const foreignToxId =
            '7070707070707070707070707070707070707070707070707070707070707070';
        final foreignArtifacts = await _seedExistingAccountArtifacts(
          foreignToxId,
        );
        final suppliedPasswords = <String?>[];
        var passwordPromptCalls = 0;
        var addAccountCalls = 0;
        var passwordWriteCalls = 0;
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async {
                suppliedPasswords.add(password);
                if (password == null) {
                  throw const PasswordRequiredException('password required');
                }
                throw Exception('Failed to decrypt Tox profile');
              },
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                addAccountCalls++;
              },
          setAccountPasswordFn: (String toxId, String password) async {
            passwordWriteCalls++;
            return true;
          },
        );

        final result = await controller.importAccount(
          requestPassword: () async {
            passwordPromptCalls++;
            return 'wrong password';
          },
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/encrypted_import.tox',
        );

        expect(suppliedPasswords, <String?>[null, 'wrong password']);
        expect(passwordPromptCalls, 1);
        expect(result, isA<ImportFailure>());
        final failure = result as ImportFailure;
        expect(failure.kind, ImportFailureKind.invalidPassword);
        expect(failure.kind, isNot(ImportFailureKind.generalError));
        expect(addAccountCalls, 0);
        expect(passwordWriteCalls, 0);
        await _expectExistingAccountArtifactsPreserved(
          foreignToxId,
          foreignArtifacts,
        );
      },
    );

    test('missing full-backup password performs no restore writes', () async {
      final env = await setUpAccountExportTestEnv();
      addTearDown(env.dispose);
      const toxId =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      var importCalls = 0;
      var addAccountCalls = 0;
      final controller = LoginPageController(
        readFullBackupMetadataFn: (String filePath, {String? password}) async {
          throw const PasswordRequiredException(
            'Password required for encrypted full backup',
          );
        },
        importFullBackupFn:
            ({required String filePath, String? password}) async {
              importCalls++;
              fail('Import must not run without a full-backup password');
            },
        addAccountFn:
            ({
              required String toxId,
              required String nickname,
              required String statusMessage,
              required bool autoLogin,
              required bool autoAcceptFriends,
              required bool notificationSoundEnabled,
            }) async {
              addAccountCalls++;
            },
      );

      final result = await controller.importAccount(
        requestPassword: () async => null,
        importedAccountDefaultName: 'Imported',
        filePathOverride: '/tmp/encrypted_backup.zip',
      );

      expect(result, isA<ImportFailure>());
      expect((result as ImportFailure).kind, ImportFailureKind.cancelled);
      expect(importCalls, 0);
      expect(addAccountCalls, 0);
      expect(
        await Directory(await AppPaths.getAccountDataRoot(toxId)).exists(),
        isFalse,
        reason: 'cancelling the password prompt must not restore any data',
      );
      expect(
        await Prefs.getAccountByToxId(toxId),
        isNull,
        reason: 'cancelling the password prompt must not add an account',
      );
    });

    test(
      'wrong full-backup password is invalid and performs no restore writes',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
        var metadataCalls = 0;
        var importCalls = 0;
        var addAccountCalls = 0;
        final controller = LoginPageController(
          readFullBackupMetadataFn:
              (String filePath, {String? password}) async {
                metadataCalls++;
                if (password == null) {
                  throw const PasswordRequiredException(
                    'Password required for encrypted full backup',
                  );
                }
                throw const InvalidBackupPasswordException();
              },
          importFullBackupFn:
              ({required String filePath, String? password}) async {
                importCalls++;
                fail('Import must not run after metadata authentication fails');
              },
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                addAccountCalls++;
              },
        );

        final result = await controller.importAccount(
          requestPassword: () async => 'wrong password',
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/encrypted_backup.zip',
        );

        expect(result, isA<ImportFailure>());
        expect(
          (result as ImportFailure).kind,
          ImportFailureKind.invalidPassword,
        );
        expect(metadataCalls, 2);
        expect(importCalls, 0);
        expect(addAccountCalls, 0);
        expect(
          await Directory(await AppPaths.getAccountDataRoot(toxId)).exists(),
          isFalse,
          reason: 'wrong-password authentication must precede restore writes',
        );
        expect(
          await Prefs.getAccountByToxId(toxId),
          isNull,
          reason: 'wrong password must not add an account',
        );
      },
    );

    test(
      'does not persist a full-backup password as the account password',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
        const backupPassword = 'backup decrypt password';
        var metadataCalls = 0;
        var promptCalls = 0;
        String? importPassword;
        String? persistedPassword;

        final controller = LoginPageController(
          readFullBackupMetadataFn:
              (String filePath, {String? password}) async {
                metadataCalls++;
                if (password == null) {
                  throw const PasswordRequiredException(
                    'Password required for encrypted full backup',
                  );
                }
                expect(password, backupPassword);
                return <String, dynamic>{'toxId': toxId, 'nickname': 'Zip'};
              },
          importFullBackupFn:
              ({required String filePath, String? password}) async {
                importPassword = password;
                return <String, dynamic>{
                  'toxId': toxId,
                  'nickname': 'Zip',
                  'toxProfile': Uint8List.fromList(<int>[7, 8, 9]),
                };
              },
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {},
          setAccountPasswordFn: (String toxId, String password) async {
            persistedPassword = password;
            return true;
          },
          encryptProfileFileFn: (String profilePath, String password) async {
            fail('full-backup archive passwords must not encrypt the profile');
          },
        );

        final result = await controller.importAccount(
          requestPassword: () async {
            promptCalls++;
            return backupPassword;
          },
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/encrypted_full_backup.zip',
        );

        expect(result, isA<ImportSuccess>());
        expect(metadataCalls, 2);
        expect(promptCalls, 1);
        expect(importPassword, backupPassword);
        expect(
          persistedPassword,
          isNull,
          reason: 'backup decryption password is not an account password',
        );
      },
    );

    test(
      'finalizes full-backup restore only after addAccount succeeds',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
        final events = <String>[];
        final controller = LoginPageController(
          readFullBackupMetadataFn:
              (String filePath, {String? password}) async => <String, dynamic>{
                'toxId': toxId,
                'nickname': 'Zip',
              },
          importFullBackupFn:
              ({required String filePath, String? password}) async =>
                  <String, dynamic>{'toxId': toxId, 'nickname': 'Zip'},
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                events.add('addAccount');
              },
          finalizeFullBackupImportFn: ({required String toxId}) async {
            events.add('finalize');
          },
          rollbackFullBackupImportFn: ({String? toxId}) async {
            fail('successful addAccount must finalize, not rollback');
          },
        );

        final result = await controller.importAccount(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/plain_full_backup.zip',
        );

        expect(result, isA<ImportSuccess>());
        expect(events, <String>['addAccount', 'finalize']);
      },
    );

    test(
      'rolls back pending full-backup restore when addAccount fails',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
        final events = <String>[];
        String? rollbackToxId;
        final controller = LoginPageController(
          readFullBackupMetadataFn:
              (String filePath, {String? password}) async => <String, dynamic>{
                'toxId': toxId,
                'nickname': 'Zip',
              },
          importFullBackupFn:
              ({required String filePath, String? password}) async =>
                  <String, dynamic>{'toxId': toxId, 'nickname': 'Zip'},
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                events.add('addAccount');
                throw Exception('registry write failed');
              },
          finalizeFullBackupImportFn: ({required String toxId}) async {
            fail('failed addAccount must not finalize the restore journal');
          },
          rollbackFullBackupImportFn: ({String? toxId}) async {
            events.add('rollback');
            rollbackToxId = toxId;
          },
        );

        final result = await controller.importAccount(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/plain_full_backup.zip',
        );

        expect(result, isA<ImportFailure>());
        expect((result as ImportFailure).kind, ImportFailureKind.generalError);
        expect(events, <String>['addAccount', 'rollback']);
        expect(rollbackToxId, toxId);
      },
    );

    test(
      'contains full-backup rollback failure and returns sanitized import failure',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            'abababababababababababababababababababababababababababababababab';
        final controller = LoginPageController(
          readFullBackupMetadataFn:
              (String filePath, {String? password}) async => <String, dynamic>{
                'toxId': toxId,
                'nickname': 'Zip',
              },
          importFullBackupFn:
              ({required String filePath, String? password}) async =>
                  <String, dynamic>{'toxId': toxId, 'nickname': 'Zip'},
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                throw Exception('private registry detail');
              },
          rollbackFullBackupImportFn: ({String? toxId}) async {
            throw StateError('private rollback path');
          },
        );

        final result = await controller.importAccount(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/rollback_failure.zip',
        );

        expect(result, isA<ImportFailure>());
        final failure = result as ImportFailure;
        expect(failure.kind, ImportFailureKind.generalError);
        expect(failure.detail, 'error_type=_Exception');
        expect(failure.detail, isNot(contains('private')));
      },
    );

    test(
      'import rolls back when account password persistence is refused',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '4040404040404040404040404040404040404040404040404040404040404040';
        var importCalls = 0;
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async {
                importCalls++;
                if (password == null) {
                  throw const PasswordRequiredException('password required');
                }
                return <String, dynamic>{
                  'toxId': toxId,
                  'toxProfile': Uint8List.fromList(<int>[8, 6, 4, 2]),
                  'nickname': 'Imported',
                };
              },
          addAccountFn: _addImportedAccountAndData,
          encryptProfileFileFn: (String profilePath, String password) async =>
              true,
          setAccountPasswordFn: (String toxId, String password) async => false,
        );

        final result = await controller.importAccount(
          requestPassword: () async => 'import-password',
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/password_failure_import.tox',
        );

        expect(importCalls, 2);
        expect(result, isA<ImportFailure>());
        final failure = result as ImportFailure;
        expect(failure.kind, ImportFailureKind.generalError);
        expect(failure.detail, 'error_type=StateError');
        await _expectImportRolledBack(toxId);
      },
    );

    test(
      'import encrypts the staged profile before account and password writes',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '4140404040404040404040404040404040404040404040404040404040404040';
        const password = 'import-password';
        final events = <String>[];
        final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
        final expectedProfilePath = AppPaths.profileFileInDirectory(profileDir);
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async {
                if (password == null) {
                  throw const PasswordRequiredException('password required');
                }
                return <String, dynamic>{
                  'toxId': toxId,
                  'toxProfile': Uint8List.fromList(<int>[8, 6, 4, 2]),
                  'nickname': 'Imported',
                };
              },
          encryptProfileFileFn: (String profilePath, String supplied) async {
            events.add('encrypt');
            expect(profilePath, expectedProfilePath);
            expect(supplied, password);
            expect(await File(profilePath).readAsBytes(), <int>[8, 6, 4, 2]);
            await File(profilePath).writeAsBytes(<int>[7, 7, 7]);
            return true;
          },
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                events.add('addAccount');
                expect(await File(expectedProfilePath).readAsBytes(), <int>[
                  7,
                  7,
                  7,
                ]);
              },
          setAccountPasswordFn: (String toxId, String supplied) async {
            events.add('savePassword');
            expect(supplied, password);
            return true;
          },
        );

        final result = await controller.importAccount(
          requestPassword: () async => password,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/encrypted_import.tox',
        );

        expect(result, isA<ImportSuccess>());
        expect(events, <String>['encrypt', 'addAccount', 'savePassword']);
      },
    );

    test(
      'import encryption error rolls back and never writes account password',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '4240404040404040404040404040404040404040404040404040404040404040';
        var addAccountCalls = 0;
        var passwordWriteCalls = 0;
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async {
                if (password == null) {
                  throw const PasswordRequiredException('password required');
                }
                return <String, dynamic>{
                  'toxId': toxId,
                  'toxProfile': Uint8List.fromList(<int>[5, 5, 5, 5]),
                  'nickname': 'Imported',
                };
              },
          encryptProfileFileFn: (String profilePath, String password) async {
            expect(await File(profilePath).readAsBytes(), <int>[5, 5, 5, 5]);
            throw StateError('injected encryption failure');
          },
          addAccountFn:
              ({
                required String toxId,
                required String nickname,
                required String statusMessage,
                required bool autoLogin,
                required bool autoAcceptFriends,
                required bool notificationSoundEnabled,
              }) async {
                addAccountCalls++;
              },
          setAccountPasswordFn: (String toxId, String password) async {
            passwordWriteCalls++;
            return true;
          },
        );

        final result = await controller.importAccount(
          requestPassword: () async => 'import-password',
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/encryption_error_import.tox',
        );

        expect(result, isA<ImportFailure>());
        expect((result as ImportFailure).kind, ImportFailureKind.generalError);
        expect(addAccountCalls, 0);
        expect(passwordWriteCalls, 0);
        await _expectImportRolledBack(toxId);
      },
    );

    test(
      'import duplicate collision preserves existing account profile and data',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '5050505050505050505050505050505050505050505050505050505050505050';
        final artifacts = await _seedExistingAccountArtifacts(toxId);
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async =>
                  <String, dynamic>{
                    'toxId': toxId,
                    'toxProfile': Uint8List.fromList(<int>[1, 2, 1, 2]),
                    'nickname': 'Incoming',
                  },
        );

        final result = await controller.importAccount(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/duplicate_import.tox',
        );

        expect(result, isA<ImportFailure>());
        expect(
          (result as ImportFailure).kind,
          ImportFailureKind.accountAlreadyExists,
        );
        await _expectExistingAccountArtifactsPreserved(toxId, artifacts);
      },
    );

    test(
      'import validation error before its first write preserves existing artifacts',
      () async {
        final env = await setUpAccountExportTestEnv();
        addTearDown(env.dispose);
        const toxId =
            '6060606060606060606060606060606060606060606060606060606060606060';
        final artifacts = await _seedExistingAccountArtifacts(toxId);
        final controller = LoginPageController(
          importAccountDataFn:
              ({required String filePath, String? password}) async =>
                  <String, dynamic>{
                    'toxId': toxId,
                    'toxProfile': 'invalid profile bytes',
                    'nickname': 'Incoming',
                  },
        );

        final result = await controller.importAccount(
          requestPassword: () async => null,
          importedAccountDefaultName: 'Imported',
          filePathOverride: '/tmp/invalid_import.tox',
        );

        expect(result, isA<ImportFailure>());
        expect((result as ImportFailure).kind, ImportFailureKind.generalError);
        await _expectExistingAccountArtifactsPreserved(toxId, artifacts);
      },
    );
  });

  test('login failure result exposes only the runtime error type', () async {
    final controller = LoginPageController(
      loginUseCase: _FailingLoginUseCase(),
    );

    final result = await controller.login(nickname: 'Alice', statusMessage: '');

    expect(result, isA<LoginControllerFailure>());
    expect(
      (result as LoginControllerFailure).message,
      'error_type=_PrivacySentinelFailure',
    );
    expect(result.message, isNot(contains('/private/accounts')));
    expect(result.message, isNot(contains('FULL_TOX_ID')));
    expect(result.message, isNot(contains('PAYLOAD_SECRET')));
    expect(result.message, isNot(contains('STACK_SECRET')));
  });

  group('LoginPageController construction', () {
    test('default constructor builds a non-null instance', () {
      final controller = LoginPageController();
      expect(controller, isNotNull);
    });
  });
}
