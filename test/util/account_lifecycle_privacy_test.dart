import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/runtime/session_runtime_coordinator.dart';
import 'package:toxee/util/account_deletion.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/imported_account_rollback.dart';
import 'package:toxee/util/logger.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/session_password_store.dart';

import '../account_export/test_support.dart';

const _accountIdSecret =
    'ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD12345678ABCD';
const _messageSecret = 'MESSAGE_SECRET_9cf34a';
const _pathSecret = 'PATH_SECRET_61e980';
const _filenameSecret = 'account_backup_743bd2.tox';
const _payloadSecret = 'PAYLOAD_SECRET_b56f08';
const _stackSecret = 'STACK_SECRET_2d69b1';

final class _SentinelFailure implements Exception {
  const _SentinelFailure();

  @override
  String toString() {
    return '$_messageSecret $_pathSecret $_filenameSecret '
        '$_accountIdSecret $_payloadSecret $_stackSecret';
  }
}

void _expectNoSentinelData(String value) {
  for (final secret in <String>[
    _accountIdSecret,
    _messageSecret,
    _pathSecret,
    _filenameSecret,
    _payloadSecret,
    _stackSecret,
  ]) {
    expect(value, isNot(contains(secret)), reason: 'leaked sentinel: $secret');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccountExportTestEnv env;
  late File logFile;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    logFile = File(p.join(env.extras, 'account_lifecycle_privacy.log'));
    AppLogger.resetForTesting();
    AppLogger.setConsoleLoggingEnabled(false);
    AppLogger.setLogPath(logFile.path);
    await AppLogger.initialize();
    AccountTeardownTestHooks.reset();
    SessionRuntimeCoordinator.debugReset();
    SessionPasswordStore.clear();
  });

  tearDown(() async {
    AccountTeardownTestHooks.reset();
    SessionRuntimeCoordinator.debugReset();
    SessionPasswordStore.clear();
    AppLogger.resetForTesting();
    await env.dispose();
  });

  test('lifecycle exception strings redact identifiers and typed causes', () {
    const cause = _SentinelFailure();
    final stackTrace = StackTrace.fromString(_stackSecret);
    final teardownFailure = AccountTeardownFailure(
      toxId: _accountIdSecret,
      stage: AccountTeardownStage.profileReEncryption,
      cause: cause,
      stackTrace: stackTrace,
    );
    final deletionFailure = AccountDeletionFailure(
      toxId: _accountIdSecret,
      stage: AccountDeletionStage.profileDirectory,
      cause: cause,
      stackTrace: stackTrace,
    );
    final pendingResult = AccountDeletionResult.pending(
      toxId: _accountIdSecret,
      failure: deletionFailure,
    );
    const completedResult = AccountDeletionResult.completed(_accountIdSecret);
    const inProgress = AccountDeletionInProgressException(_accountIdSecret);

    expect(teardownFailure.toxId, _accountIdSecret);
    expect(teardownFailure.cause, same(cause));
    expect(teardownFailure.stackTrace, same(stackTrace));
    expect(deletionFailure.toxId, _accountIdSecret);
    expect(deletionFailure.cause, same(cause));
    expect(deletionFailure.stackTrace, same(stackTrace));
    expect(pendingResult.toxId, _accountIdSecret);
    expect(pendingResult.failure, same(deletionFailure));
    expect(completedResult.toxId, _accountIdSecret);
    expect(inProgress.toxId, _accountIdSecret);

    for (final rendered in <String>[
      teardownFailure.toString(),
      deletionFailure.toString(),
      pendingResult.toString(),
      completedResult.toString(),
      inProgress.toString(),
    ]) {
      _expectNoSentinelData(rendered);
    }
  });

  test(
    'persisted deletion failure retains recovery state but not cause data',
    () async {
      const cause = _SentinelFailure();
      final stackTrace = StackTrace.fromString(_stackSecret);
      final resumable = AccountDeletionTombstone.initial(
        toxId: _accountIdSecret,
        deletedCurrentAccount: true,
      ).markCompleted(AccountDeletionState.profileDirectoryDeleted);
      final failed = resumable.markFailure(
        AccountDeletionFailure(
          toxId: _accountIdSecret,
          stage: AccountDeletionStage.accountDataDirectory,
          cause: cause,
          stackTrace: stackTrace,
        ),
      );

      await AccountDeletionJournalStore.write(failed);
      final persisted = await AccountDeletionJournalStore.read(
        _accountIdSecret,
      );

      expect(persisted, isNotNull);
      expect(persisted!.toxId, _accountIdSecret);
      expect(persisted.state, AccountDeletionState.profileDirectoryDeleted);
      expect(persisted.deletedCurrentAccount, isTrue);
      expect(persisted.failureStage, AccountDeletionStage.accountDataDirectory);
      expect(persisted.failureDescription, 'error_type=_SentinelFailure');
      _expectNoSentinelData(persisted.failureDescription!);
    },
  );

  test('teardown logs only context, stage, and runtime error type', () async {
    const cause = _SentinelFailure();
    final profileDirectory = await AppPaths.getProfileDirectoryForToxId(
      _accountIdSecret,
    );
    await Directory(profileDirectory).create(recursive: true);
    await File(
      AppPaths.profileFileInDirectory(profileDirectory),
    ).writeAsString('profile');
    SessionPasswordStore.set(_accountIdSecret, 'recovery-password');
    SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {};
    AccountTeardownTestHooks.shutdownIrcSession = (_) async {};
    AccountTeardownTestHooks.disposeService = (_) async {
      Error.throwWithStackTrace(cause, StackTrace.fromString(_stackSecret));
    };
    AccountTeardownTestHooks.encryptProfileFile = (_, _) async {};

    await expectLater(
      () => AccountService.teardownCurrentSession(
        service: _FakeFfiChatService(_accountIdSecret),
      ),
      throwsA(
        isA<AccountTeardownFailure>()
            .having(
              (failure) => failure.stage,
              'stage',
              AccountTeardownStage.serviceDisposal,
            )
            .having((failure) => failure.cause, 'cause', same(cause)),
      ),
    );

    final logged = await logFile.readAsString();
    expect(logged, contains('stage=serviceDisposal'));
    expect(logged, contains('error_type=_SentinelFailure'));
    _expectNoSentinelData(logged);
  });

  test(
    'import rollback logs omit account ID and raw filesystem failure',
    () async {
      final poisonedRoot =
          '${env.root.path}${Platform.pathSeparator}'
          '$_messageSecret-$_pathSecret-$_filenameSecret-'
          '$_payloadSecret-$_stackSecret';
      await Prefs.setProfileStorageRoot(poisonedRoot);
      final profileDirectory = await AppPaths.getProfileDirectoryForToxId(
        _accountIdSecret,
      );
      await Directory(profileDirectory).create(recursive: true);
      final partialImport = File(p.join(profileDirectory, 'partial-import'));
      await partialImport.writeAsString('partial');
      RandomAccessFile? lockedFile;
      if (Platform.isWindows) {
        lockedFile = await partialImport.open(mode: FileMode.append);
      } else {
        final lockResult = await Process.run('chmod', <String>[
          '0555',
          poisonedRoot,
        ]);
        expect(lockResult.exitCode, 0);
      }

      try {
        await ImportedAccountRollback.run(
          toxId: _accountIdSecret,
          logContext: 'PrivacyTest',
        );
      } finally {
        await lockedFile?.close();
        if (!Platform.isWindows) {
          await Process.run('chmod', <String>['0755', poisonedRoot]);
        }
      }

      final logged = await logFile.readAsString();
      expect(logged, contains('[PrivacyTest]'));
      expect(logged, contains('import_rollback_failed'));
      expect(logged, contains('error_type='));
      _expectNoSentinelData(logged);
    },
  );
}

final class _FakeFfiChatService implements FfiChatService {
  _FakeFfiChatService(this._toxId);

  final String _toxId;

  @override
  String? getSelfToxId() => _toxId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
