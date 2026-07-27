import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/session_password_store.dart';

import 'account_export/test_support.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late AccountExportTestEnv env;
  String? passwordWriteToxId;
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    SessionPasswordStore.clear();
    passwordWriteToxId = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
          final args =
              (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
          switch (call.method) {
            case 'read':
              return null;
            case 'write':
              final key = args['key'] as String;
              if (key.startsWith('pwd_') && !key.startsWith('pwd_salt_')) {
                passwordWriteToxId = key.substring('pwd_'.length);
              }
              throw PlatformException(
                code: 'secure-write-failed',
                message: 'Injected secure-storage write failure',
              );
            case 'delete':
              return null;
            case 'containsKey':
              return false;
            case 'readAll':
              return <String, String>{};
            case 'deleteAll':
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    SessionPasswordStore.clear();
    await env.dispose();
  });

  test(
    'registration aborts and fully rolls back when password verifier write fails',
    () async {
      const previousToxId = '0123456789ABCDEF';
      await Prefs.addAccount(
        toxId: previousToxId,
        nickname: 'Dormant Account',
        statusMessage: 'Dormant status',
      );
      await Prefs.setCurrentAccountToxId(null);
      await Prefs.setNickname('Previous Account');
      await Prefs.setStatusMessage('Previous status');
      await Prefs.setAvatarPath('/previous/avatar.png');
      final previousRegistry = await Prefs.getAccountList();

      var encryptionCalls = 0;
      Object? registrationError;
      RegisterResult? unexpectedResult;
      try {
        unexpectedResult = await AccountService.registerNewAccount(
          nickname: 'Verifier Failure',
          statusMessage: 'Must roll back',
          password: 'registration-password',
          encryptProfileFileOverride: (_, __) async {
            encryptionCalls++;
          },
        );
      } catch (error) {
        registrationError = error;
      } finally {
        await unexpectedResult?.service.dispose();
      }

      expect(registrationError, isA<StateError>());
      expect(
        registrationError.toString(),
        contains('persist account password verifier'),
      );
      expect(unexpectedResult, isNull);
      expect(
        encryptionCalls,
        0,
        reason:
            'profile encryption must not start until the verifier is '
            'durably persisted',
      );

      final failedToxId = passwordWriteToxId;
      expect(
        failedToxId,
        isNotNull,
        reason: 'registration must reach the injected verifier write seam',
      );
      expect(
        SessionPasswordStore.get(failedToxId!),
        isNull,
        reason: 'a non-durable password must never arm session encryption',
      );

      final failedProfileDir = await AppPaths.getProfileDirectoryForToxId(
        failedToxId,
      );
      final failedAccountDataRoot = await AppPaths.getAccountDataRoot(
        failedToxId,
      );
      expect(
        await Directory(failedProfileDir).exists(),
        isFalse,
        reason: 'the generated profile must be removed during rollback',
      );
      expect(
        await Directory(failedAccountDataRoot).exists(),
        isFalse,
        reason: 'generated account files must be removed during rollback',
      );
      expect(
        await Prefs.exportScopedPrefsForAccount(failedToxId),
        isEmpty,
        reason: 'registration rollback must remove account-scoped prefs',
      );
      expect(
        await Prefs.getAccountByToxId(failedToxId),
        isNull,
        reason: 'the failed account must not remain in the registry',
      );
      expect(
        await Prefs.getAccountList(),
        previousRegistry,
        reason: 'the pre-registration account registry must be restored',
      );

      expect(await Prefs.getCurrentAccountToxId(), isNull);
      expect(await Prefs.getNickname(), 'Previous Account');
      expect(await Prefs.getStatusMessage(), 'Previous status');
      expect(await Prefs.getAvatarPath(), '/previous/avatar.png');
      expect(
        Tim2ToxFfi.open().isInstanceInitialized(0),
        0,
        reason: 'the failed registration service must be disposed',
      );

      expect(
        await Prefs.hasAccountPassword(failedToxId),
        isFalse,
        reason: 'no durable verifier may remain after the failed write',
      );
    },
    skip: skipReason,
  );
}
