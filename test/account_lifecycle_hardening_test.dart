import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/auth/login_use_case.dart';
import 'package:toxee/runtime/session_runtime_coordinator.dart';
import 'package:toxee/startup/startup_outcome.dart';
import 'package:toxee/startup/startup_session_use_case.dart';
import 'package:toxee/util/account_deletion.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/logger.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/prefs/draft_prefs.dart';
import 'package:toxee/util/session_password_store.dart';

import 'account_export/test_support.dart';

const _toxId =
    'ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD12345678ABCD';
const _otherToxId =
    '1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF12345678ABCD';
const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  late AccountExportTestEnv env;
  late _SecureStorageHarness secureStorage;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    SessionPasswordStore.clear();
    AppLogger.resetForTesting();
    AccountDeletionTestHooks.reset();
    AccountTeardownTestHooks.reset();
    SessionRuntimeCoordinator.debugReset();
    secureStorage = _SecureStorageHarness();
    _installSecureStorageHarness(secureStorage);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
    AccountDeletionTestHooks.reset();
    AccountTeardownTestHooks.reset();
    SessionRuntimeCoordinator.debugReset();
    SessionPasswordStore.clear();
    AppLogger.resetForTesting();
    await env.dispose();
  });

  group('durable account-deletion tombstones', () {
    test(
      'secure-storage delete failure leaves a tombstone and retries on restart',
      () async {
        await _seedDeletableAccount(
          _toxId,
          nickname: 'Deleting',
          current: true,
        );
        await _seedDeletableAccount(_otherToxId, nickname: 'Other');
        secureStorage.deleteSucceeds = false;

        final first = await AccountDeletionCoordinator.deleteAccount(
          toxId: _toxId,
        );

        expect(first.isPending, isTrue);
        expect(first.failure?.stage, AccountDeletionStage.securePassword);
        expect(await AccountDeletionJournalStore.read(_toxId), isNotNull);
        expect(await Prefs.getAccountByToxId(_toxId), isNotNull);
        expect(await Prefs.getCurrentAccountToxId(), _toxId);
        expect(await _profileExists(_toxId), isTrue);
        expect(await _accountDataExists(_toxId), isTrue);

        secureStorage.deleteSucceeds = true;
        final retry =
            await AccountDeletionCoordinator.recoverPendingDeletions();

        expect(retry, hasLength(1));
        expect(retry.single.completed, isTrue);
        expect(await AccountDeletionJournalStore.read(_toxId), isNull);
        expect(await Prefs.getAccountByToxId(_toxId), isNull);
        expect(await Prefs.getAccountByToxId(_otherToxId), isNotNull);
        expect(await Prefs.getCurrentAccountToxId(), isNull);
        expect(await _profileExists(_toxId), isFalse);
        expect(await _accountDataExists(_toxId), isFalse);
        expect(await _profileExists(_otherToxId), isTrue);
        expect(await _accountDataExists(_otherToxId), isTrue);
      },
    );

    test(
      'deleting one full-ID account preserves same-prefix v2 drafts',
      () async {
        const sharedPrefix = 'ABCDEF0123456789';
        final accountA = '$sharedPrefix${List<String>.filled(60, 'A').join()}';
        final accountB = '$sharedPrefix${List<String>.filled(60, 'B').join()}';
        const accountAConversation = 'c2c:delete-a';
        const accountBConversation = 'c2c:keep-b:$sharedPrefix';
        await _seedDeletableAccount(
          accountA,
          nickname: 'Deleting',
          current: true,
        );
        await _seedDeletableAccount(accountB, nickname: 'Same Prefix');
        final prefs = await SharedPreferences.getInstance();
        final drafts = DraftPrefs(
          prefs,
          activeAccountToxId: () async => accountA,
        );
        await drafts.saveDraft(
          accountToxId: accountA,
          conversationID: accountAConversation,
          text: 'delete account A draft',
        );
        await drafts.saveDraft(
          accountToxId: accountB,
          conversationID: accountBConversation,
          text: 'keep account B draft',
        );

        final result = await AccountDeletionCoordinator.deleteAccount(
          toxId: accountA,
        );

        expect(result.completed, isTrue);
        expect(await Prefs.getAccountByToxId(accountA), isNull);
        expect(await Prefs.getAccountByToxId(accountB), isNotNull);
        expect(
          prefs.getString('draft_v2:$accountA:$accountAConversation'),
          isNull,
        );
        expect(
          prefs.getString('draft_v2:$accountB:$accountBConversation'),
          isNotNull,
        );
        expect(
          (await drafts.loadDraft(
            accountToxId: accountB,
            conversationID: accountBConversation,
          ))?.text,
          'keep account B draft',
        );
      },
    );

    for (final failingStage in <AccountDeletionStage>[
      AccountDeletionStage.profileDirectory,
      AccountDeletionStage.accountDataDirectory,
    ]) {
      test(
        '${failingStage.name} failure keeps registry visible and is retryable',
        () async {
          await _seedDeletableAccount(
            _toxId,
            nickname: 'Directory Fail',
            current: true,
          );
          AccountDeletionTestHooks.deleteDirectory = (path, stage) async {
            if (stage == failingStage) {
              throw FileSystemException('delete denied', path);
            }
            final dir = Directory(path);
            if (await dir.exists()) {
              await dir.delete(recursive: true);
            }
          };

          final first = await AccountDeletionCoordinator.deleteAccount(
            toxId: _toxId,
          );

          expect(first.isPending, isTrue);
          expect(first.failure?.stage, failingStage);
          expect(await AccountDeletionJournalStore.read(_toxId), isNotNull);
          expect(await Prefs.getAccountByToxId(_toxId), isNotNull);
          expect(await Prefs.getCurrentAccountToxId(), _toxId);
          if (failingStage == AccountDeletionStage.profileDirectory) {
            expect(await _profileExists(_toxId), isTrue);
          } else {
            expect(await _profileExists(_toxId), isFalse);
            expect(await _accountDataExists(_toxId), isTrue);
          }

          AccountDeletionTestHooks.reset();
          final retry =
              await AccountDeletionCoordinator.recoverPendingDeletions();

          expect(retry.single.completed, isTrue);
          expect(await AccountDeletionJournalStore.read(_toxId), isNull);
          expect(await Prefs.getAccountByToxId(_toxId), isNull);
          expect(await _profileExists(_toxId), isFalse);
          expect(await _accountDataExists(_toxId), isFalse);
        },
      );
    }

    test(
      'cold retry skips completed stages when their dependencies are unavailable',
      () async {
        await _seedDeletableAccount(
          _toxId,
          nickname: 'Resume Delete',
          current: true,
        );
        var serviceCleanupCalls = 0;
        var passwordRemovalCalls = 0;
        var prefsCleanupCalls = 0;
        var accountDataDeleteCalls = 0;
        AccountDeletionTestHooks.removePassword = (toxId) async {
          passwordRemovalCalls++;
          return true;
        };
        AccountDeletionTestHooks.clearPrefsData = (toxId) async {
          prefsCleanupCalls++;
        };
        AccountDeletionTestHooks.deleteDirectory = (path, stage) async {
          if (stage == AccountDeletionStage.accountDataDirectory) {
            accountDataDeleteCalls++;
            throw FileSystemException('delete denied', path);
          }
          final dir = Directory(path);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        };

        final first = await AccountDeletionCoordinator.deleteAccount(
          toxId: _toxId,
          serviceCleanup: () async {
            serviceCleanupCalls++;
          },
        );

        expect(first.failure?.stage, AccountDeletionStage.accountDataDirectory);
        final tombstone = await AccountDeletionJournalStore.read(_toxId);
        expect(tombstone?.state, AccountDeletionState.profileDirectoryDeleted);
        expect(
          tombstone?.failureStage,
          AccountDeletionStage.accountDataDirectory,
        );

        AccountDeletionTestHooks.removePassword = (toxId) async {
          throw StateError('secure storage is unavailable');
        };
        AccountDeletionTestHooks.clearPrefsData = (toxId) async {
          throw StateError('preferences are unavailable');
        };
        AccountDeletionTestHooks.deleteDirectory = (path, stage) async {
          if (stage == AccountDeletionStage.profileDirectory) {
            throw StateError('profile storage is unavailable');
          }
          accountDataDeleteCalls++;
          final dir = Directory(path);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        };

        final retry =
            await AccountDeletionCoordinator.recoverPendingDeletions();

        expect(retry.single.completed, isTrue);
        expect(serviceCleanupCalls, 1);
        expect(passwordRemovalCalls, 1);
        expect(prefsCleanupCalls, 1);
        // First attempt fails on the legacy prefix data root. The retry then
        // removes both that root and the separate full-ID scratch root.
        expect(accountDataDeleteCalls, 3);
        expect(await AccountDeletionJournalStore.read(_toxId), isNull);
        expect(await Prefs.getAccountByToxId(_toxId), isNull);
      },
    );

    test(
      'current-account failure keeps the account registry visible until retry',
      () async {
        await _seedDeletableAccount(
          _toxId,
          nickname: 'Registry Last',
          current: true,
        );
        AccountDeletionTestHooks.setCurrentAccountToxId = (toxId) async {
          throw StateError('current-account preferences are unavailable');
        };

        final first = await AccountDeletionCoordinator.deleteAccount(
          toxId: _toxId,
        );

        expect(first.failure?.stage, AccountDeletionStage.currentAccount);
        expect(await Prefs.getAccountByToxId(_toxId), isNotNull);
        expect(await Prefs.getCurrentAccountToxId(), _toxId);
        final tombstone = await AccountDeletionJournalStore.read(_toxId);
        expect(
          tombstone?.state,
          AccountDeletionState.accountDataDirectoryDeleted,
        );
        expect(tombstone?.failureStage, AccountDeletionStage.currentAccount);

        AccountDeletionTestHooks.reset();
        final retry =
            await AccountDeletionCoordinator.recoverPendingDeletions();

        expect(retry.single.completed, isTrue);
        expect(await Prefs.getCurrentAccountToxId(), isNull);
        expect(await Prefs.getAccountByToxId(_toxId), isNull);
      },
    );

    test(
      'prefs failure is surfaced before profile or data directories move',
      () async {
        await _seedDeletableAccount(
          _toxId,
          nickname: 'Prefs Fail',
          current: true,
        );
        AccountDeletionTestHooks.clearPrefsData = (toxId) async {
          throw StateError('shared preferences refused remove');
        };

        final result = await AccountDeletionCoordinator.deleteAccount(
          toxId: _toxId,
        );

        expect(result.isPending, isTrue);
        expect(result.failure?.stage, AccountDeletionStage.prefsData);
        expect(await AccountDeletionJournalStore.read(_toxId), isNotNull);
        expect(await Prefs.getAccountByToxId(_toxId), isNotNull);
        expect(await _profileExists(_toxId), isTrue);
        expect(await _accountDataExists(_toxId), isTrue);
      },
    );

    test(
      'live service cleanup failure is recorded and later cold retry finishes',
      () async {
        await _seedDeletableAccount(
          _toxId,
          nickname: 'Service Fail',
          current: true,
        );

        final result = await AccountDeletionCoordinator.deleteAccount(
          toxId: _toxId,
          serviceCleanup: () async {
            throw StateError('service database locked');
          },
        );

        expect(result.isPending, isTrue);
        expect(result.failure?.stage, AccountDeletionStage.serviceData);
        expect(await AccountDeletionJournalStore.read(_toxId), isNotNull);
        expect(await Prefs.getAccountByToxId(_toxId), isNotNull);

        final retry =
            await AccountDeletionCoordinator.recoverPendingDeletions();

        expect(retry.single.completed, isTrue);
        expect(await AccountDeletionJournalStore.read(_toxId), isNull);
        expect(await Prefs.getAccountByToxId(_toxId), isNull);
      },
    );

    test(
      'privacy cleanup failure keeps registry visible and cold retry purges residues',
      () async {
        await _seedDeletableAccount(
          _toxId,
          nickname: 'Deleting',
          current: true,
        );
        await _seedDeletableAccount(_otherToxId, nickname: 'Other');
        await _seedPrivacyResidue(_toxId);
        final prefs = await SharedPreferences.getInstance();
        final otherAutoLoginKey = 'acct_auto_login_${_prefix16(_otherToxId)}';
        await prefs.setBool(otherAutoLoginKey, false);

        var serviceCleanupCalls = 0;
        AccountDeletionTestHooks.cleanupPrivacyResidue = (toxId) async {
          throw StateError('log directory locked');
        };

        final first = await AccountDeletionCoordinator.deleteAccount(
          toxId: _toxId,
          serviceCleanup: () async {
            serviceCleanupCalls++;
          },
        );

        expect(first.isPending, isTrue);
        expect(first.failure?.stage, AccountDeletionStage.privacyResidue);
        expect(await AccountDeletionJournalStore.read(_toxId), isNotNull);
        expect(await Prefs.getAccountByToxId(_toxId), isNotNull);
        expect(prefs.getString(_failedMessageKey(_toxId)), isNotNull);
        expect(prefs.getString(_legacyFailedMessageKey(_toxId)), isNotNull);
        expect(prefs.getString('self_nickname'), 'Deleting');
        expect(prefs.getString('self_status_msg'), 'status-$_toxId');
        expect(prefs.getString('self_avatar_path'), 'avatar-$_toxId.png');
        expect(await _logResidueContains(_toxId), isTrue);

        AccountDeletionTestHooks.removePassword = (toxId) async {
          throw StateError('secure storage should be skipped');
        };
        AccountDeletionTestHooks.clearPrefsData = (toxId) async {
          throw StateError('prefs cleanup should be skipped');
        };
        AccountDeletionTestHooks.deleteDirectory = (path, stage) async {
          throw StateError('${stage.name} should be skipped');
        };
        AccountDeletionTestHooks.setCurrentAccountToxId = (toxId) async {
          throw StateError('current-account cleanup should be skipped');
        };
        AccountDeletionTestHooks.cleanupPrivacyResidue = null;

        final retry =
            await AccountDeletionCoordinator.recoverPendingDeletions();
        AppLogger.info('post-delete logging works');

        expect(retry.single.completed, isTrue);
        expect(serviceCleanupCalls, 1);
        expect(await AccountDeletionJournalStore.read(_toxId), isNull);
        expect(await Prefs.getAccountByToxId(_toxId), isNull);
        expect(await Prefs.getAccountByToxId(_otherToxId), isNotNull);
        expect(prefs.getString(_failedMessageKey(_toxId)), isNull);
        expect(prefs.getString(_legacyFailedMessageKey(_toxId)), isNull);
        expect(prefs.getString('self_nickname'), isNull);
        expect(prefs.getString('self_status_msg'), isNull);
        expect(prefs.getString('self_avatar_path'), isNull);
        expect(prefs.getString('theme_mode'), 'dark');
        expect(prefs.getString('language_code'), 'zh');
        expect(prefs.getString('downloads_directory'), env.downloads);
        expect(prefs.getBool(otherAutoLoginKey), isFalse);
        expect(await _logResidueContains(_toxId), isFalse);
        final cleanLogPath = AppLogger.getLogPath();
        expect(cleanLogPath, isNotNull);
        expect(
          await File(cleanLogPath!).readAsString(),
          contains('post-delete logging works'),
        );
        expect(
          await File(p.join(env.appSupport, 'flutter_client.log')).exists(),
          isFalse,
        );
      },
    );

    test(
      'uncreatable fresh log sink keeps privacy cleanup retryable',
      () async {
        await _seedDeletableAccount(
          _toxId,
          nickname: 'Strict Log Reopen',
          current: true,
        );
        final blockingFile = File(p.join(env.extras, 'not_a_directory'));
        await blockingFile.writeAsString(
          'blocks child log creation',
          flush: true,
        );
        final invalidLogPath = p.join(blockingFile.path, 'app.log');
        AppLogger.setFileLoggingEnabled(false);
        AccountDeletionTestHooks.cleanupPrivacyResidue = (_) async {
          await AppLogger.openFreshLogSink(invalidLogPath);
        };

        final first = await AccountDeletionCoordinator.deleteAccount(
          toxId: _toxId,
        );

        expect(first.isPending, isTrue);
        expect(first.failure?.stage, AccountDeletionStage.privacyResidue);
        expect(first.failure?.cause, isA<FileSystemException>());
        final tombstone = await AccountDeletionJournalStore.read(_toxId);
        expect(tombstone?.state, AccountDeletionState.currentAccountCleared);
        expect(tombstone?.failureStage, AccountDeletionStage.privacyResidue);
        expect(await Prefs.getAccountByToxId(_toxId), isNotNull);

        AccountDeletionTestHooks.cleanupPrivacyResidue = null;
        final retry =
            await AccountDeletionCoordinator.recoverPendingDeletions();
        AppLogger.info('strict reopen post-purge logging works');

        expect(retry.single.completed, isTrue);
        expect(await AccountDeletionJournalStore.read(_toxId), isNull);
        expect(await Prefs.getAccountByToxId(_toxId), isNull);
        final cleanLogPath = AppLogger.getLogPath();
        expect(cleanLogPath, isNotNull);
        expect(
          await File(cleanLogPath!).readAsString(),
          contains('strict reopen post-purge logging works'),
        );
      },
    );

    test(
      'privacy cleanup preserves globals that belong to another current account',
      () async {
        await _seedDeletableAccount(_toxId, nickname: 'Deleting');
        await _seedDeletableAccount(
          _otherToxId,
          nickname: 'Other',
          current: true,
        );
        final prefs = await SharedPreferences.getInstance();
        await _seedPrivacyResidue(_toxId);
        await prefs.setString('self_nickname', 'Other');
        await prefs.setString('self_status_msg', 'other status');
        await prefs.setString('self_avatar_path', 'other-avatar.png');

        final result = await AccountDeletionCoordinator.deleteAccount(
          toxId: _toxId,
        );
        AppLogger.info('non-current delete logging works');

        expect(result.completed, isTrue);
        expect(await Prefs.getAccountByToxId(_toxId), isNull);
        expect(await Prefs.getAccountByToxId(_otherToxId), isNotNull);
        expect(await Prefs.getCurrentAccountToxId(), _otherToxId);
        expect(prefs.getString('self_nickname'), 'Other');
        expect(prefs.getString('self_status_msg'), 'other status');
        expect(prefs.getString('self_avatar_path'), 'other-avatar.png');
        expect(prefs.getString(_failedMessageKey(_toxId)), isNull);
        expect(prefs.getString(_legacyFailedMessageKey(_toxId)), isNull);
        expect(await _logResidueContains(_toxId), isFalse);
        expect(
          await File(AppLogger.getLogPath()!).readAsString(),
          contains('non-current delete logging works'),
        );
      },
    );
  });

  group('pending deletion guards', () {
    test('manual login for a deleting account fails before FFI init', () async {
      await _seedDeletableAccount(_toxId, nickname: 'Deleting');
      await AccountDeletionJournalStore.write(
        AccountDeletionTombstone.initial(toxId: _toxId),
      );

      await expectLater(
        () => LoginUseCase().execute(
          const LoginParams(nickname: 'Deleting', statusMessage: ''),
        ),
        throwsA(
          isA<AccountDeletionInProgressException>().having(
            (error) => error.toxId,
            'toxId',
            _toxId,
          ),
        ),
      );

      await _seedDeletableAccount(_otherToxId, nickname: 'Other');
      await expectLater(
        AccountService.throwIfAccountDeleting(_otherToxId),
        completes,
      );
    });

    test(
      'cold startup retries pending deletion but still honors unrelated account state',
      () async {
        await _seedDeletableAccount(_toxId, nickname: 'Deleting');
        await _seedDeletableAccount(
          _otherToxId,
          nickname: 'Other',
          current: true,
        );
        await Prefs.setNickname('Other');
        await Prefs.setAutoLogin(false, _otherToxId);
        await AccountDeletionJournalStore.write(
          AccountDeletionTombstone.initial(toxId: _toxId),
        );
        secureStorage.deleteSucceeds = false;

        final outcome = await StartupSessionUseCase().execute(
          onStepChanged: (_) {},
          loadFriends: (_) async {},
        );

        expect(outcome, isA<StartupShowLogin>());
        expect(secureStorage.deleteAttempts, greaterThan(0));
        expect(await AccountDeletionJournalStore.read(_toxId), isNotNull);
        expect(await Prefs.getAccountByToxId(_otherToxId), isNotNull);
        expect(await Prefs.getCurrentAccountToxId(), _otherToxId);
      },
    );
  });

  group('fail-closed session teardown', () {
    test(
      'runtime failure does not skip later teardown and surfaces first typed failure',
      () async {
        await _seedDeletableAccount(
          _toxId,
          nickname: 'Complete teardown',
          current: true,
        );
        const sessionPassword = 'recovery-material';
        SessionPasswordStore.set(_toxId, sessionPassword);
        final runtimeFailure = StateError('runtime teardown failed');
        final steps = <String>[];
        SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {
          steps.add('runtime');
          throw runtimeFailure;
        };
        AccountTeardownTestHooks.shutdownIrcSession = (_) async {
          steps.add('irc');
          throw StateError('irc shutdown failed');
        };
        AccountTeardownTestHooks.disposeService = (_) async {
          steps.add('service');
        };
        AccountTeardownTestHooks.encryptProfileFile = (_, password) async {
          steps.add('encrypt');
          expect(password, sessionPassword);
        };

        await expectLater(
          () => AccountService.teardownCurrentSession(
            service: _FakeFfiChatService(_toxId),
          ),
          throwsA(
            isA<AccountTeardownFailure>()
                .having(
                  (failure) => failure.stage.name,
                  'stage',
                  'runtimeDisposal',
                )
                .having((failure) => failure.cause, 'cause', runtimeFailure),
          ),
        );

        expect(steps, ['runtime', 'irc', 'service', 'encrypt']);
        expect(SessionPasswordStore.get(_toxId), isNull);
      },
    );

    test('service dispose failure is surfaced after profile cleanup', () async {
      await _seedDeletableAccount(
        _toxId,
        nickname: 'Dispose failure',
        current: true,
      );
      const sessionPassword = 'recovery-material';
      SessionPasswordStore.set(_toxId, sessionPassword);
      final disposeFailure = StateError('service dispose failed');
      var profileEncrypted = false;
      SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {};
      AccountTeardownTestHooks.shutdownIrcSession = (_) async {};
      AccountTeardownTestHooks.disposeService = (_) async {
        throw disposeFailure;
      };
      AccountTeardownTestHooks.encryptProfileFile = (_, _) async {
        profileEncrypted = true;
      };

      await expectLater(
        () => AccountService.teardownCurrentSession(
          service: _FakeFfiChatService(_toxId),
        ),
        throwsA(
          isA<AccountTeardownFailure>()
              .having(
                (failure) => failure.stage.name,
                'stage',
                'serviceDisposal',
              )
              .having((failure) => failure.cause, 'cause', disposeFailure),
        ),
      );

      expect(profileEncrypted, isTrue);
      expect(SessionPasswordStore.get(_toxId), isNull);
    });

    test(
      're-encryption failure is surfaced and preserves recovery password',
      () async {
        await _seedDeletableAccount(
          _toxId,
          nickname: 'Passworded',
          current: true,
        );
        const sessionPassword = 'recovery-material';
        SessionPasswordStore.set(_toxId, sessionPassword);
        final encryptionFailure = StateError(
          'disk full during profile encrypt',
        );
        AccountTeardownTestHooks.shutdownIrcSession = (_) async {};
        AccountTeardownTestHooks.disposeService = (_) async {};
        AccountTeardownTestHooks.encryptProfileFile = (_, _) async {
          throw encryptionFailure;
        };

        await expectLater(
          () => AccountService.teardownCurrentSession(
            service: _FakeFfiChatService(_toxId),
            reEncryptProfile: true,
          ),
          throwsA(
            isA<AccountTeardownFailure>()
                .having(
                  (failure) => failure.stage,
                  'stage',
                  AccountTeardownStage.profileReEncryption,
                )
                .having((failure) => failure.cause, 'cause', encryptionFailure),
          ),
        );

        expect(SessionPasswordStore.get(_toxId), sessionPassword);
      },
    );
  });
}

Future<void> _seedDeletableAccount(
  String toxId, {
  required String nickname,
  bool current = false,
}) async {
  await Prefs.addAccount(toxId: toxId, nickname: nickname, statusMessage: '');
  if (current) {
    await Prefs.setCurrentAccountToxId(toxId);
    await Prefs.setNickname(nickname);
    await Prefs.setStatusMessage('');
  }
  final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
  await Directory(profileDir).create(recursive: true);
  await File(
    AppPaths.profileFileInDirectory(profileDir),
  ).writeAsString('profile-$toxId', flush: true);
  final accountDataRoot = await AppPaths.getAccountDataRoot(toxId);
  await Directory(
    p.join(accountDataRoot, 'chat_history'),
  ).create(recursive: true);
  await File(
    p.join(accountDataRoot, 'chat_history', 'conversation.json'),
  ).writeAsString('{"message":"sensitive"}', flush: true);
}

Future<bool> _profileExists(String toxId) async {
  final profileDir = await AppPaths.getProfileDirectoryForToxId(toxId);
  return File(AppPaths.profileFileInDirectory(profileDir)).exists();
}

Future<bool> _accountDataExists(String toxId) async {
  return Directory(await AppPaths.getAccountDataRoot(toxId)).exists();
}

String _prefix16(String toxId) {
  return toxId.length >= 16 ? toxId.substring(0, 16) : toxId;
}

String _failedMessageKey(String toxId) {
  return 'tencent_cloud_chat_failed_messages_$toxId';
}

String _legacyFailedMessageKey(String toxId) {
  return 'tencent_cloud_chat_failed_messages_${_prefix16(toxId)}';
}

Future<void> _seedPrivacyResidue(String toxId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_failedMessageKey(toxId), 'full failed $toxId');
  await prefs.setString(_legacyFailedMessageKey(toxId), 'legacy failed $toxId');
  await prefs.setString('self_nickname', 'Deleting');
  await prefs.setString('self_status_msg', 'status-$toxId');
  await prefs.setString('self_avatar_path', 'avatar-$toxId.png');
  await prefs.setString('theme_mode', 'dark');
  await prefs.setString('language_code', 'zh');

  final logsDir = await AppPaths.logsDir;
  await logsDir.create(recursive: true);
  await File(
    p.join(logsDir.path, 'app_old.log'),
  ).writeAsString('old diagnostic residue $toxId', flush: true);

  final activeLogPath = p.join(logsDir.path, 'app_active.log');
  AppLogger.setLogPath(activeLogPath);
  await AppLogger.initialize();
  AppLogger.info('active diagnostic residue $toxId');

  final appSupport = await AppPaths.applicationSupportPath;
  await File(
    p.join(appSupport, 'flutter_client.log'),
  ).writeAsString('deprecated diagnostic residue $toxId', flush: true);
}

Future<bool> _logResidueContains(String value) async {
  final logsDir = await AppPaths.logsDir;
  if (await logsDir.exists()) {
    await for (final entry in logsDir.list(recursive: true)) {
      if (entry is! File) continue;
      if ((await entry.readAsString()).contains(value)) return true;
    }
  }
  final flatLog = File(
    p.join(await AppPaths.applicationSupportPath, 'flutter_client.log'),
  );
  return await flatLog.exists() &&
      (await flatLog.readAsString()).contains(value);
}

void _installSecureStorageHarness(_SecureStorageHarness harness) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureChannel, (MethodCall call) async {
        final args =
            (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
        switch (call.method) {
          case 'write':
            harness.entries[args['key'] as String] = args['value'] as String;
            return null;
          case 'read':
            return harness.entries[args['key'] as String];
          case 'delete':
            harness.deleteAttempts++;
            if (!harness.deleteSucceeds) {
              throw PlatformException(code: 'KEYSTORE_DELETE_FAILED');
            }
            harness.entries.remove(args['key'] as String);
            return null;
          case 'containsKey':
            return harness.entries.containsKey(args['key'] as String);
          case 'readAll':
            return Map<String, String>.from(harness.entries);
          case 'deleteAll':
            harness.entries.clear();
            return null;
          default:
            return null;
        }
      });
}

final class _SecureStorageHarness {
  final Map<String, String> entries = <String, String>{};
  bool deleteSucceeds = true;
  int deleteAttempts = 0;
}

final class _FakeFfiChatService implements FfiChatService {
  _FakeFfiChatService(this._toxId);

  final String _toxId;

  @override
  String? getSelfToxId() => _toxId;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
