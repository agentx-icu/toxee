import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/account_export/restore_transaction.dart';
import 'package:toxee/ui/settings/settings_page.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

import '../../account_export/test_support.dart';
import 'settings_account_test_support.dart';

const _importedToxId =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _laterFailureToxId =
    '2222222222222222222222222222222222222222222222222222222222222222';

Future<void> _pumpSettings(
  WidgetTester tester, {
  required SettingsPickImportFileFn pickImportFileFn,
  required SettingsImportAccountDataFn importAccountDataFn,
  EncryptProfileFileFn? encryptProfileFileFn,
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
        encryptProfileFileFn: encryptProfileFileFn,
        addImportedAccountFn: addImportedAccountFn,
        setImportedAccountPasswordFn: setImportedAccountPasswordFn,
      ),
    ),
  );
  await settleSettings(tester);
}

Finder _importButton() => find.widgetWithText(OutlinedButton, 'Import Account');

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxIterations = 100,
}) async {
  for (var i = 0; i < maxIterations && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

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

Future<void> _dismissImportFailure(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => find.widgetWithText(TextButton, 'OK').evaluate().isNotEmpty,
  );
  expect(find.widgetWithText(TextButton, 'OK'), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, 'OK'));
  await _pumpUntil(
    tester,
    () =>
        find.widgetWithText(TextButton, 'OK').evaluate().isEmpty &&
        tester.widget<OutlinedButton>(_importButton()).onPressed != null,
  );
}

Future<void> _seedRollbackResidue(String toxId) async {
  await Prefs.setAutoLogin(false, toxId);
  final dataRoot = Directory(await AppPaths.getAccountDataRoot(toxId));
  await dataRoot.create(recursive: true);
  await File('${dataRoot.path}/partial-import.json').writeAsString('partial');
}

Future<void> _expectNoImportResidue(String toxId) async {
  final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
  expect(
    await Directory(profileDir).exists(),
    isFalse,
    reason: 'failed import must remove its profile directory',
  );
  expect(
    await Directory(await AppPaths.getAccountDataRoot(toxId)).exists(),
    isFalse,
    reason: 'failed import must remove its account data directory',
  );
  expect(
    await Prefs.getAccountByToxId(toxId),
    isNull,
    reason: 'failed import must not remain in the account registry',
  );
  expect(
    await Prefs.exportScopedPrefsForAccount(toxId),
    isEmpty,
    reason: 'failed import must clear account-scoped preferences',
  );
  expect(
    await Prefs.hasAccountPassword(toxId),
    isFalse,
    reason: 'failed import must clear password hash and salt',
  );
}

Future<String> _createEncryptedFullBackup(
  AccountExportTestEnv env, {
  required String password,
  required String fileName,
}) async {
  final profileDir = await AppPaths.getProfileDirectoryForToxId(_importedToxId);
  final profileFile = File(AppPaths.profileFileInDirectory(profileDir));
  await profileFile.parent.create(recursive: true);
  await profileFile.writeAsBytes(<int>[31, 32, 33, 34]);
  await Prefs.addAccount(
    toxId: _importedToxId,
    nickname: 'ZIP Account',
    autoLogin: false,
  );
  final backupPath = await AccountExportService.exportFullBackup(
    toxId: _importedToxId,
    password: password,
    filePath: '${env.extras}/$fileName',
  );
  await Prefs.clearAccountData(_importedToxId);
  await Prefs.removeAccount(_importedToxId);
  if (await profileFile.parent.exists()) {
    await profileFile.parent.delete(recursive: true);
  }
  final dataRoot = Directory(await AppPaths.getAccountDataRoot(_importedToxId));
  if (await dataRoot.exists()) {
    await dataRoot.delete(recursive: true);
  }
  return backupPath;
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
    await env.dispose();
  });

  testWidgets('only one picker runs while file selection is pending', (
    tester,
  ) async {
    final firstPick = Completer<String?>();
    var pickerCalls = 0;
    await _pumpSettings(
      tester,
      pickImportFileFn: () {
        pickerCalls++;
        return pickerCalls == 1
            ? firstPick.future
            : Future<String?>.value(null);
      },
      importAccountDataFn:
          ({required String filePath, String? password}) async {
            fail('cancelled file selection must not import');
          },
    );

    await tester.tap(_importButton());
    await tester.pump();
    await tester.tap(_importButton());
    await tester.pump();

    expect(pickerCalls, 1);
    expect(tester.widget<OutlinedButton>(_importButton()).onPressed, isNull);

    firstPick.complete(null);
    await _pumpUntil(
      tester,
      () => tester.widget<OutlinedButton>(_importButton()).onPressed != null,
    );
    await tester.tap(_importButton());
    await tester.pump();

    expect(
      pickerCalls,
      2,
      reason: 'a completed import attempt must release the single-flight gate',
    );
  });

  testWidgets(
    'only one import runs while pending and an error can be retried',
    (tester) async {
      final firstImport = Completer<Map<String, dynamic>>();
      var pickerCalls = 0;
      var importCalls = 0;
      await _pumpSettings(
        tester,
        pickImportFileFn: () async {
          pickerCalls++;
          return '/tmp/settings_pending_import.tox';
        },
        importAccountDataFn:
            ({required String filePath, String? password}) async {
              importCalls++;
              if (importCalls == 1) return firstImport.future;
              throw StateError('retry reached import');
            },
      );

      await tester.runAsync(() async {
        await tester.tap(_importButton());
        await _pumpRealUntil(tester, () => importCalls == 1);
        await tester.tap(_importButton());
        await tester.pump();

        expect(pickerCalls, 1);
        expect(importCalls, 1);
        expect(
          tester.widget<OutlinedButton>(_importButton()).onPressed,
          isNull,
        );

        firstImport.completeError(StateError('injected import failure'));
        await _dismissImportFailure(tester);
        await tester.tap(_importButton());
        await _pumpRealUntil(tester, () => importCalls == 2);
      });

      expect(pickerCalls, 2);
      expect(importCalls, 2);
    },
  );

  testWidgets('wrong tox password remains a localized typed failure', (
    tester,
  ) async {
    const privateDetail =
        '/private/accounts/alice/encrypted_profile.tox PAYLOAD_SECRET';
    var importCalls = 0;
    await _pumpSettings(
      tester,
      pickImportFileFn: () async => '/tmp/settings_wrong_password.tox',
      importAccountDataFn:
          ({required String filePath, String? password}) async {
            importCalls++;
            if (password == null) {
              throw const PasswordRequiredException('password required');
            }
            throw Exception(privateDetail);
          },
    );

    await tester.runAsync(() async {
      await tester.tap(_importButton());
      final passwordField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await _pumpRealUntil(tester, () => passwordField.evaluate().length == 1);
      await tester.enterText(passwordField, 'wrong-password');
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await _pumpRealUntil(
        tester,
        () => find.text('Invalid password').evaluate().isNotEmpty,
      );
    });

    expect(importCalls, 2);
    expect(find.text('Invalid password'), findsOneWidget);
    expect(find.textContaining(privateDetail), findsNothing);
    expect(find.textContaining('Failed to import account'), findsNothing);
  });

  testWidgets('addAccount failure rolls back profile data prefs and registry', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      pickImportFileFn: () async => '/tmp/settings_add_failure.tox',
      importAccountDataFn:
          ({required String filePath, String? password}) async =>
              <String, dynamic>{
                'toxId': _importedToxId,
                'toxProfile': Uint8List.fromList(<int>[1, 2, 3, 4]),
                'nickname': 'Partial Account',
              },
      encryptProfileFileFn: (String profilePath, String password) async {
        fail('plain .tox imports must not encrypt the staged profile');
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
            await Prefs.addAccount(
              toxId: toxId,
              nickname: nickname,
              statusMessage: statusMessage,
              autoLogin: autoLogin,
              autoAcceptFriends: autoAcceptFriends,
              notificationSoundEnabled: notificationSoundEnabled,
            );
            await _seedRollbackResidue(toxId);
            throw StateError('injected addAccount persistence failure');
          },
    );

    await tester.runAsync(() async {
      await tester.tap(_importButton());
      await _pumpUntil(
        tester,
        () => find.widgetWithText(TextButton, 'OK').evaluate().isNotEmpty,
      );
      await _expectNoImportResidue(_importedToxId);
    });

    expect(await Prefs.getAccountByToxId(kSettingsToxId), isNotNull);
  });

  testWidgets('password persistence failure fully rolls back the import', (
    tester,
  ) async {
    var importCalls = 0;
    await _pumpSettings(
      tester,
      pickImportFileFn: () async => '/tmp/settings_password_failure.tox',
      importAccountDataFn:
          ({required String filePath, String? password}) async {
            importCalls++;
            if (password == null) {
              throw const PasswordRequiredException('password required');
            }
            return <String, dynamic>{
              'toxId': _laterFailureToxId,
              'toxProfile': Uint8List.fromList(<int>[5, 6, 7, 8]),
              'nickname': 'Encrypted Account',
            };
          },
      encryptProfileFileFn: (String profilePath, String password) async => true,
      setImportedAccountPasswordFn: (String toxId, String password) async {
        final persisted = await Prefs.setAccountPassword(toxId, password);
        expect(persisted, isTrue);
        await _seedRollbackResidue(toxId);
        return false;
      },
    );

    await tester.runAsync(() async {
      await tester.tap(_importButton());
      final passwordField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await _pumpRealUntil(tester, () => passwordField.evaluate().length == 1);
      await tester.enterText(passwordField, 'import-password');
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await _pumpRealUntil(
        tester,
        () =>
            importCalls == 2 &&
            find.textContaining('error_type=StateError').evaluate().isNotEmpty,
      );
      await _expectNoImportResidue(_laterFailureToxId);
    });

    expect(
      secureStore.keys.where((key) => key.contains(_laterFailureToxId)),
      isEmpty,
      reason: 'rollback must delete both secure password entries',
    );
    expect(await Prefs.getAccountByToxId(kSettingsToxId), isNotNull);
    expect(
      find.textContaining('Failed to persist imported account password'),
      findsNothing,
    );
  });

  testWidgets(
    'encrypted tox is protected before account and password persistence',
    (tester) async {
      const password = 'import-password';
      final events = <String>[];
      var importCalls = 0;
      String? encryptedPath;
      String? encryptionPassword;
      List<int>? bytesAtEncryption;
      List<int>? bytesAtAddAccount;
      String? persistedPassword;
      final profileDir = await AppPaths.getProfileDirectoryForToxId(
        _importedToxId,
      );
      final expectedProfilePath = AppPaths.profileFileInDirectory(profileDir);
      await _pumpSettings(
        tester,
        pickImportFileFn: () async => '/tmp/settings_encrypted_import.tox',
        importAccountDataFn:
            ({required String filePath, String? password}) async {
              importCalls++;
              if (password == null) {
                throw const PasswordRequiredException('password required');
              }
              return <String, dynamic>{
                'toxId': _importedToxId,
                'toxProfile': Uint8List.fromList(<int>[1, 2, 3, 4]),
                'nickname': 'Encrypted Account',
              };
            },
        encryptProfileFileFn: (String profilePath, String supplied) async {
          events.add('encrypt');
          encryptedPath = profilePath;
          encryptionPassword = supplied;
          bytesAtEncryption = await File(profilePath).readAsBytes();
          await File(profilePath).writeAsBytes(<int>[9, 9, 9]);
          return true;
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
              events.add('addAccount');
              bytesAtAddAccount = await File(expectedProfilePath).readAsBytes();
            },
        setImportedAccountPasswordFn: (String toxId, String supplied) async {
          events.add('savePassword');
          persistedPassword = supplied;
          return true;
        },
      );

      await tester.runAsync(() async {
        await tester.tap(_importButton());
        final passwordField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await _pumpRealUntil(
          tester,
          () => passwordField.evaluate().length == 1,
        );
        await tester.enterText(passwordField, password);
        await tester.tap(find.widgetWithText(TextButton, 'OK'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      expect(importCalls, 2);
      expect(events, <String>['encrypt', 'addAccount', 'savePassword']);
      expect(encryptedPath, expectedProfilePath);
      expect(encryptionPassword, password);
      expect(bytesAtEncryption, <int>[1, 2, 3, 4]);
      expect(bytesAtAddAccount, <int>[9, 9, 9]);
      expect(persistedPassword, password);
    },
  );

  testWidgets(
    'encryption refusal rolls back and never writes account or password',
    (tester) async {
      var importCalls = 0;
      var addAccountCalls = 0;
      var passwordWriteCalls = 0;
      await _pumpSettings(
        tester,
        pickImportFileFn: () async => '/tmp/settings_encryption_refusal.tox',
        importAccountDataFn:
            ({required String filePath, String? password}) async {
              importCalls++;
              if (password == null) {
                throw const PasswordRequiredException('password required');
              }
              return <String, dynamic>{
                'toxId': _laterFailureToxId,
                'toxProfile': Uint8List.fromList(<int>[5, 6, 7, 8]),
                'nickname': 'Encrypted Account',
              };
            },
        encryptProfileFileFn: (String profilePath, String password) async {
          expect(await File(profilePath).readAsBytes(), <int>[5, 6, 7, 8]);
          return false;
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
              addAccountCalls++;
            },
        setImportedAccountPasswordFn: (String toxId, String password) async {
          passwordWriteCalls++;
          return true;
        },
      );

      await tester.runAsync(() async {
        await tester.tap(_importButton());
        final passwordField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await _pumpRealUntil(
          tester,
          () => passwordField.evaluate().length == 1,
        );
        await tester.enterText(passwordField, 'import-password');
        await tester.tap(find.widgetWithText(TextButton, 'OK'));
        await _pumpRealUntil(
          tester,
          () => find
              .textContaining('error_type=StateError')
              .evaluate()
              .isNotEmpty,
        );
        await _expectNoImportResidue(_laterFailureToxId);
      });

      expect(importCalls, 2);
      expect(addAccountCalls, 0);
      expect(passwordWriteCalls, 0);
    },
  );

  testWidgets(
    'encryption error rolls back and never writes account or password',
    (tester) async {
      var importCalls = 0;
      var addAccountCalls = 0;
      var passwordWriteCalls = 0;
      await _pumpSettings(
        tester,
        pickImportFileFn: () async => '/tmp/settings_encryption_error.tox',
        importAccountDataFn:
            ({required String filePath, String? password}) async {
              importCalls++;
              if (password == null) {
                throw const PasswordRequiredException('password required');
              }
              return <String, dynamic>{
                'toxId': _laterFailureToxId,
                'toxProfile': Uint8List.fromList(<int>[8, 7, 6, 5]),
                'nickname': 'Encrypted Account',
              };
            },
        encryptProfileFileFn: (String profilePath, String password) async {
          expect(await File(profilePath).readAsBytes(), <int>[8, 7, 6, 5]);
          throw StateError('private encryption implementation detail');
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
              addAccountCalls++;
            },
        setImportedAccountPasswordFn: (String toxId, String password) async {
          passwordWriteCalls++;
          return true;
        },
      );

      await tester.runAsync(() async {
        await tester.tap(_importButton());
        final passwordField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await _pumpRealUntil(
          tester,
          () => passwordField.evaluate().length == 1,
        );
        await tester.enterText(passwordField, 'import-password');
        await tester.tap(find.widgetWithText(TextButton, 'OK'));
        await _pumpRealUntil(
          tester,
          () => find
              .textContaining('error_type=StateError')
              .evaluate()
              .isNotEmpty,
        );
        await _expectNoImportResidue(_laterFailureToxId);
      });

      expect(importCalls, 2);
      expect(addAccountCalls, 0);
      expect(passwordWriteCalls, 0);
      expect(
        find.textContaining('private encryption implementation detail'),
        findsNothing,
      );
    },
  );

  test(
    'mobile and desktop controls share the import transaction handler',
    () async {
      final mobileSource = await File(
        'lib/ui/settings/settings_page.dart',
      ).readAsString();
      final desktopSource = await File(
        'lib/ui/settings/settings_page_build.dart',
      ).readAsString();
      final sharedHandler = RegExp(
        r'onPressed: _importInProgress \? null : _importAccount',
      );

      expect(sharedHandler.allMatches(mobileSource), hasLength(1));
      expect(sharedHandler.allMatches(desktopSource), hasLength(1));
    },
  );

  testWidgets(
    'zip password stays archive-only and never encrypts the restored profile',
    (tester) async {
      const archivePassword = 'archive-only-password';
      final zipPath = (await tester.runAsync<String>(
        () => _createEncryptedFullBackup(
          env,
          password: archivePassword,
          fileName: 'settings_archive_password.zip',
        ),
      ))!;
      FullBackupRestoreTestHooks.profileIdentityExtractor =
          (Uint8List profileBytes) => _importedToxId;
      addTearDown(FullBackupRestoreTestHooks.reset);
      var encryptionCalls = 0;
      var passwordWriteCalls = 0;
      await _pumpSettings(
        tester,
        pickImportFileFn: () async => zipPath,
        importAccountDataFn:
            ({required String filePath, String? password}) async {
              fail('the .zip branch must not invoke .tox decoding');
            },
        encryptProfileFileFn: (String profilePath, String password) async {
          encryptionCalls++;
          return true;
        },
        setImportedAccountPasswordFn: (String toxId, String password) async {
          passwordWriteCalls++;
          return true;
        },
      );

      await tester.runAsync(() async {
        await tester.tap(_importButton());
        final passwordField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await _pumpRealUntil(
          tester,
          () => passwordField.evaluate().length == 1,
        );
        await tester.enterText(passwordField, archivePassword);
        await tester.tap(find.widgetWithText(TextButton, 'OK'));
        await _pumpRealUntil(
          tester,
          () =>
              find.text('Account imported successfully').evaluate().isNotEmpty,
        );
        expect(await Prefs.getAccountByToxId(_importedToxId), isNotNull);
        expect(await Prefs.hasAccountPassword(_importedToxId), isFalse);
      });

      expect(encryptionCalls, 0);
      expect(passwordWriteCalls, 0);
    },
  );

  testWidgets('zip duplicate guard runs before restore writes', (tester) async {
    const archivePassword = 'duplicate-archive-password';
    final zipPath = (await tester.runAsync<String>(
      () => _createEncryptedFullBackup(
        env,
        password: archivePassword,
        fileName: 'settings_duplicate.zip',
      ),
    ))!;
    await tester.runAsync(() async {
      await Prefs.addAccount(
        toxId: _importedToxId,
        nickname: 'Existing ZIP Account',
      );
    });
    var encryptionCalls = 0;
    var passwordWriteCalls = 0;
    await _pumpSettings(
      tester,
      pickImportFileFn: () async => zipPath,
      importAccountDataFn:
          ({required String filePath, String? password}) async {
            fail('the .zip branch must not invoke .tox decoding');
          },
      encryptProfileFileFn: (String profilePath, String password) async {
        encryptionCalls++;
        return true;
      },
      setImportedAccountPasswordFn: (String toxId, String password) async {
        passwordWriteCalls++;
        return true;
      },
    );

    await tester.runAsync(() async {
      await tester.tap(_importButton());
      final passwordField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await _pumpRealUntil(tester, () => passwordField.evaluate().length == 1);
      await tester.enterText(passwordField, archivePassword);
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await _pumpRealUntil(
        tester,
        () => find.text('Account already exists').evaluate().isNotEmpty,
      );
      final account = await Prefs.getAccountByToxId(_importedToxId);
      expect(account?['nickname'], 'Existing ZIP Account');
      final profileDir = await AppPaths.getProfileDirectoryForToxId(
        _importedToxId,
      );
      expect(await Directory(profileDir).exists(), isFalse);
    });

    expect(encryptionCalls, 0);
    expect(passwordWriteCalls, 0);
  });
}
