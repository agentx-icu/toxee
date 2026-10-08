import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/runtime/session_runtime_coordinator.dart';
import 'package:toxee/util/account_deletion.dart';
import 'package:toxee/util/account_registration_rollback.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/account_session_cleanup.dart';
import 'package:toxee/util/account_teardown_failure.dart';
import 'package:toxee/util/native_quarantine.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/session_password_store.dart';

import 'account_export/test_support.dart';
import 'support/secret_password_text.dart';

const _toxId =
    'ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD12345678ABCD';
const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// `dispose()` returned normally but the native instance was NOT proven
/// stopped — what `FfiChatService` reports after quarantining an instance a
/// background task was still using. A late savedata write is then possible,
/// so nothing may delete or re-encrypt the profile directory.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccountExportTestEnv env;

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    SessionPasswordStore.clear();
    AccountTeardownTestHooks.reset();
    AccountDeletionTestHooks.reset();
    NativeQuarantine.reset();
    SessionRuntimeCoordinator.debugReset();
    SessionRuntimeCoordinator.debugTeardownBodyOverride = () async {};
    AccountTeardownTestHooks.shutdownIrcSession = (_) async {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (_) async => null);
    await Prefs.addAccount(toxId: _toxId, nickname: 'Quarantined', statusMessage: '');
    SessionPasswordStore.set(_toxId, SecretPassword.fromString('recovery'));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
    AccountTeardownTestHooks.reset();
    AccountDeletionTestHooks.reset();
    NativeQuarantine.reset();
    SessionRuntimeCoordinator.debugReset();
    SessionPasswordStore.clear();
    await env.dispose();
  });

  test('teardown reports whether native was proven stopped', () async {
    expect(
      await AccountService.teardownCurrentSession(
        service: _QuarantinedService(_toxId, stopped: false),
      ),
      isFalse,
    );
    expect(
      await AccountService.teardownCurrentSession(
        service: _QuarantinedService(_toxId, stopped: null),
      ),
      isFalse,
      reason: 'an older tim2tox that cannot tell is not proof',
    );
    expect(
      await AccountService.teardownCurrentSession(
        service: _QuarantinedService(_toxId, stopped: true),
      ),
      isTrue,
    );
    // A test hook standing in for dispose is the test's own statement.
    AccountTeardownTestHooks.disposeService = (_) async {};
    expect(
      await AccountService.teardownCurrentSession(
        service: _QuarantinedService(_toxId, stopped: false),
      ),
      isTrue,
    );
  });

  test(
    'deletion cleanup refuses to go on and keeps the session password',
    () async {
      await expectLater(
        clearAndTearDownForDeletion(
          service: _QuarantinedService(_toxId, stopped: false),
          toxId: _toxId,
          teardown: AccountService.teardownCurrentSession,
        ),
        throwsA(
          isA<NativeInstanceNotStoppedException>()
              .having((e) => e.toxId, 'toxId', _toxId)
              .having((e) => e.operation, 'operation', 'account_deletion'),
        ),
      );
      expect(secretText(SessionPasswordStore.get(_toxId)), 'recovery');

      await clearAndTearDownForDeletion(
        service: _QuarantinedService(_toxId, stopped: true),
        toxId: _toxId,
        teardown: AccountService.teardownCurrentSession,
      );
      expect(SessionPasswordStore.get(_toxId), isNull);
    },
  );

  test(
    'a quarantined instance leaves the account deletion pending for the '
    'cold-start retry instead of deleting the profile directory',
    () async {
      var directoryDeletes = 0;
      AccountDeletionTestHooks.deleteDirectory = (_, _) async {
        directoryDeletes++;
      };

      await expectLater(
        AccountService.deleteAccountCompletely(
          service: _QuarantinedService(_toxId, stopped: false),
          toxId: _toxId,
        ),
        throwsA(
          isA<AccountDeletionFailure>()
              .having((f) => f.stage, 'stage', AccountDeletionStage.serviceData)
              .having(
                (f) => f.cause,
                'cause',
                isA<NativeInstanceNotStoppedException>(),
              ),
        ),
      );
      final tombstone = await AccountDeletionJournalStore.read(_toxId);
      expect(tombstone, isNotNull);
      expect(tombstone?.failureStage, AccountDeletionStage.serviceData);
      expect(directoryDeletes, 0);
      expect(await Prefs.getAccountByToxId(_toxId), isNotNull);
      expect(NativeQuarantine.contains(_toxId), isTrue);

      // The Login page resuming the tombstone in the SAME process (no
      // service) must not delete the directory either: the zombie is
      // still here.
      _stubDeletionStages();
      await expectLater(
        AccountService.deleteAccountWithoutService(toxId: _toxId),
        throwsA(
          isA<AccountDeletionFailure>()
              .having((f) => f.stage, 'stage', AccountDeletionStage.profileDirectory)
              .having(
                (f) => f.cause,
                'cause',
                isA<NativeInstanceNotStoppedException>(),
              ),
        ),
      );
      expect(directoryDeletes, 0);
      expect(await AccountDeletionJournalStore.read(_toxId), isNotNull);

      // A fresh process has no zombie: the cold-start retry finishes.
      NativeQuarantine.reset();
      final retry = await AccountDeletionCoordinator.recoverPendingDeletions();
      expect(retry.single.completed, isTrue);
      expect(directoryDeletes, greaterThan(0));
      expect(await AccountDeletionJournalStore.read(_toxId), isNull);
    },
  );

  test('a dispose that throws is recorded as unproven too', () async {
    NativeQuarantine.reset();
    final throwing = _QuarantinedService(_toxId, stopped: true)
      ..disposeError = StateError('native refused to dispose');
    expect(
      await disposeRegistrationBootstrap(throwing, 'probe'),
      isFalse,
    );
    expect(NativeQuarantine.contains(_toxId), isTrue);
    NativeQuarantine.reset();
    expect(
      await disposeRegistrationBootstrap(
        _QuarantinedService(_toxId, stopped: false),
        'probe',
      ),
      isFalse,
    );
    expect(NativeQuarantine.contains(_toxId), isTrue);
    NativeQuarantine.reset();
    expect(
      await disposeRegistrationBootstrap(
        _QuarantinedService(_toxId, stopped: true),
        'probe',
      ),
      isTrue,
    );
    expect(NativeQuarantine.contains(_toxId), isFalse);
  });

  test(
    'registration rollback keeps the directories and the published account '
    'when the bootstrap instance was not proven stopped',
    () async {
      final root = await AppPaths.getProfileStorageRoot();
      final tempDir = Directory('$root/.tmp_register_quarantine')
        ..createSync(recursive: true);
      final finalDir = Directory('$root/p_quarantine')
        ..createSync(recursive: true);
      AccountRegistrationRollbackPlan plan(_QuarantinedService service) =>
          AccountRegistrationRollbackPlan(
            service: service,
            toxId: _toxId,
            tempDir: tempDir.path,
            finalDir: finalDir.path,
            ownsFinalDir: true,
            ownedDataRoots: const [],
            accountVisible: true,
            verifierWritten: true,
            previousAccount: null,
            previousNickname: 'Previous',
            previousStatusMessage: null,
            previousAvatarPath: null,
          );

      // A replacement service opened after an earlier quarantine: disposed
      // all the same, outcome combined with the historical flag.
      final late = _QuarantinedService(_toxId, stopped: true);
      await rollbackFailedRegistration(
        AccountRegistrationRollbackPlan(
          service: late,
          toxId: _toxId,
          tempDir: tempDir.path,
          finalDir: finalDir.path,
          ownsFinalDir: true,
          ownedDataRoots: const [],
          accountVisible: true,
          verifierWritten: true,
          bootstrapStopped: false,
          previousAccount: null,
          previousNickname: 'Previous',
          previousStatusMessage: null,
          previousAvatarPath: null,
        ),
      );
      expect(late.disposeCalls, 1);
      expect(tempDir.existsSync(), isTrue);
      expect(finalDir.existsSync(), isTrue);
      expect(
        await Prefs.getAccountByToxId(_toxId),
        isNotNull,
        reason: 'the published account stays registered with its verifier',
      );
      expect(await Prefs.getNickname(), 'Previous', reason: 'mirror restored');

      final quarantined = _QuarantinedService(_toxId, stopped: false);
      await rollbackFailedRegistration(plan(quarantined));
      expect(quarantined.disposeCalls, 1);
      expect(tempDir.existsSync(), isTrue);
      expect(finalDir.existsSync(), isTrue);
      expect(await Prefs.getAccountByToxId(_toxId), isNotNull);
      // Deleting the kept account from Login in the same process is refused
      // at the directory stage for the same reason.
      expect(NativeQuarantine.contains(_toxId), isTrue);
      var directoryDeletes = 0;
      AccountDeletionTestHooks.deleteDirectory = (_, _) async {
        directoryDeletes++;
      };
      _stubDeletionStages();
      await expectLater(
        AccountService.deleteAccountWithoutService(toxId: _toxId),
        throwsA(
          isA<AccountDeletionFailure>().having(
            (f) => f.stage,
            'stage',
            AccountDeletionStage.profileDirectory,
          ),
        ),
      );
      expect(directoryDeletes, 0);
      await AccountDeletionJournalStore.clear(_toxId);
      AccountDeletionTestHooks.reset();
      NativeQuarantine.reset();

      // A provably stopped instance cleans up as before.
      await rollbackFailedRegistration(
        plan(_QuarantinedService(_toxId, stopped: true)),
      );
      expect(tempDir.existsSync(), isFalse);
      expect(finalDir.existsSync(), isFalse);
      expect(await Prefs.getAccountByToxId(_toxId), isNull);
    },
  );
}

/// Every deletion stage after the service one succeeds trivially, so the
/// directory stages are the only thing that can stop the coordinator.
void _stubDeletionStages() {
  AccountDeletionTestHooks.removePassword = (_) async => true;
  AccountDeletionTestHooks.purgeSecureSecrets = (_) async => true;
  AccountDeletionTestHooks.clearPrefsData = (_) async {};
  AccountDeletionTestHooks.cleanupPrivacyResidue = (_) async {};
}

final class _QuarantinedService implements FfiChatService {
  _QuarantinedService(this._toxId, {required this.stopped});

  final String _toxId;
  final bool? stopped;
  int disposeCalls = 0;
  Object? disposeError;

  @override
  String? getSelfToxId() => _toxId;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    final error = disposeError;
    if (error != null) throw error;
  }

  @override
  bool? get nativeInstanceStopped => stopped;

  @override
  Future<void> clearAllAccountData() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
