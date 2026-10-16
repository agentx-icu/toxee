// Lifecycle paths that DISCARD an FfiChatService on failure must record an
// instance that was not proven stopped in NativeQuarantine, or a deletion in
// the same process removes the directory a late savedata write still lands
// in. The two paths below used to dispose and only log a throw (retro codex
// review of #126): the failed-login catch of initializeServiceForAccount and
// createAccountScopedService during registration (whose caller had already
// dropped its reference, so the rollback deleted the account) — and the
// placeholder-identity discovery session, whose caller then migrated the
// profile directory and deleted the decrypted copy under it.
//
// Needs the real libtim2tox_ffi (native init/login), skip-guarded like
// test/account_registration_password_failure_test.dart.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/account_export/account_export_service.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/native_dispose.dart';
import 'package:toxee/util/native_quarantine.dart';
import 'package:toxee/util/placeholder_account_migration.dart';
import 'package:toxee/util/placeholder_identity_discovery.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/profile_open_failure.dart';
import 'package:toxee/util/session_password_store.dart';

import 'account_export/test_support.dart';
import 'account_export/tox_profile_factory.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late AccountExportTestEnv env;
  final secureStore = <String, String>{};
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    SessionPasswordStore.clear();
    AccountRegistrationTestHooks.reset();
    NativeDisposeTestHooks.reset();
    NativeQuarantine.reset();
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
    AccountRegistrationTestHooks.reset();
    NativeDisposeTestHooks.reset();
    NativeQuarantine.reset();
    SessionPasswordStore.clear();
    await env.dispose();
  });

  group('a failed login', () {
    Future<String?> stageEncryptedAccount() async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) return null;
      final dir = await AppPaths.getProfileDirectoryForToxId(fixture.toxId);
      await Directory(dir).create(recursive: true);
      final path = AppPaths.profileFileInDirectory(dir);
      await File(path).writeAsBytes(fixture.savedata, flush: true);
      await AccountExportService.encryptProfileFile(
        path,
        SecretPassword.fromString('right-pw'),
      );
      await Prefs.addAccount(toxId: fixture.toxId, nickname: 'Enc');
      return fixture.toxId;
    }

    Future<Object?> loginWithWrongPassword(String toxId) async {
      try {
        final service = await AccountService.initializeServiceForAccount(
          toxId: toxId,
          password: SecretPassword.fromString('wrong-pw'),
          startPolling: false,
        );
        await service.dispose();
        return null;
      } catch (e) {
        return e;
      }
    }

    test(
      'records an instance that was not proven stopped and rethrows the '
      'login error',
      () async {
        final toxId = await stageEncryptedAccount();
        if (toxId == null) return markTestSkipped('no profile fixture');
        NativeDisposeTestHooks.nativeStoppedOverride = (_) => false;

        final error = await loginWithWrongPassword(toxId);

        expect(
          error,
          isA<ProfileUnopenableWithPasswordException>(),
          reason: 'the login error itself is rethrown, not a cleanup one',
        );
        expect(NativeQuarantine.contains(toxId), isTrue);
      },
      skip: skipReason,
    );

    test(
      'a pointer restore that throws does not replace the login error',
      () async {
        final toxId = await stageEncryptedAccount();
        if (toxId == null) return markTestSkipped('no profile fixture');
        final store = _PointerThrowingStore(
          SharedPreferencesStorePlatform.instance,
        );
        SharedPreferencesStorePlatform.instance = store..armed = true;
        try {
          final error = await loginWithWrongPassword(toxId);
          expect(error, isA<ProfileUnopenableWithPasswordException>());
          expect(store.pointerWrites, greaterThan(0),
              reason: 'the failing restore must actually have been reached');
        } finally {
          SharedPreferencesStorePlatform.instance = store.inner;
        }
      },
      skip: skipReason,
    );

    test('control: a provably stopped instance records nothing', () async {
      final toxId = await stageEncryptedAccount();
      if (toxId == null) return markTestSkipped('no profile fixture');

      expect(await loginWithWrongPassword(toxId), isNotNull);
      expect(NativeQuarantine.contains(toxId), isFalse);
    }, skip: skipReason);
  });

  for (final protected in [false, true]) {
    group('registration (${protected ? 'password' : 'no password'}) whose '
        'scoped reopen fails inside the factory', () {
      Future<String?> registerFailingInFactory() async {
        String? toxId;
        // The bootstrap instance stops cleanly (hook = the test's statement);
        // only the factory's own cleanup is under test.
        AccountRegistrationTestHooks.disposeService = (s) => s.dispose();
        AccountRegistrationTestHooks.duringScopedOpen = (svc) async {
          toxId = svc.getSelfToxId();
          throw StateError('injected scoped-open failure');
        };
        RegisterResult? unexpected;
        Object? error;
        try {
          unexpected = await AccountService.registerNewAccount(
            nickname: 'Reopen ${protected ? 'P' : 'N'}',
            password: protected
                ? SecretPassword.fromString('registration-pw')
                : null,
          );
        } catch (e) {
          error = e;
        } finally {
          await unexpected?.service.dispose();
        }
        expect(unexpected, isNull);
        expect(error.toString(), contains('injected scoped-open failure'));
        expect(toxId, isNotNull, reason: 'the factory hook must have run');
        return toxId;
      }

      test(
        'keeps the account, its verifier and its directory when the scoped '
        'instance was not proven stopped',
        () async {
          NativeDisposeTestHooks.nativeStoppedOverride = (_) => false;
          final toxId = await registerFailingInFactory();

          expect(NativeQuarantine.contains(toxId!), isTrue);
          expect(await Prefs.getAccountByToxId(toxId), isNotNull);
          expect(
            await Directory(
              await AppPaths.getProfileDirectoryForToxId(toxId),
            ).exists(),
            isTrue,
          );
          if (protected) {
            expect(await Prefs.hasAccountPassword(toxId), isTrue);
          }
        },
        skip: skipReason,
      );

      test('control: a provably stopped instance is rolled back', () async {
        final toxId = await registerFailingInFactory();

        expect(NativeQuarantine.contains(toxId!), isFalse);
        expect(await Prefs.getAccountByToxId(toxId), isNull);
        expect(
          await Directory(
            await AppPaths.getProfileDirectoryForToxId(toxId),
          ).exists(),
          isFalse,
        );
      }, skip: skipReason);
    });
  }

  group('placeholder identity discovery', () {
    const placeholder = PlaceholderAccountMigration.placeholderToxId;

    /// A real profile for the placeholder account; returns its address.
    Future<String?> stagePlaceholder({SecretPassword? encryptWith}) async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) return null;
      final dir = await AppPaths.getProfileDirectoryForToxId(placeholder);
      await Directory(dir).create(recursive: true);
      final path = AppPaths.profileFileInDirectory(dir);
      await File(path).writeAsBytes(fixture.savedata, flush: true);
      if (encryptWith != null) {
        await AccountExportService.encryptProfileFile(path, encryptWith);
      }
      return fixture.toxId;
    }

    List<Directory> scratchCopies() => Directory(env.appSupport)
        .listSync()
        .whereType<Directory>()
        .where(
          (d) => p
              .basename(d.path)
              .startsWith('.placeholder_discovery_scratch_'),
        )
        .toList();

    test('control: a provably stopped session reports the real id', () async {
      final toxId = await stagePlaceholder();
      if (toxId == null) return markTestSkipped('no profile fixture');
      final found = await discoverPlaceholderRealToxId();
      expect(found, isNotNull);
      expect(found!.substring(0, 64), toxId.substring(0, 64));
      expect(NativeQuarantine.contains(toxId), isFalse);
    }, skip: skipReason);

    test(
      'an unproven stop defers the migration and records both ids',
      () async {
        final toxId = await stagePlaceholder();
        if (toxId == null) return markTestSkipped('no profile fixture');
        NativeDisposeTestHooks.nativeStoppedOverride = (_) => false;

        expect(await discoverPlaceholderRealToxId(), isNull);
        expect(NativeQuarantine.contains(toxId), isTrue);
        expect(NativeQuarantine.contains(placeholder), isTrue);
      },
      skip: skipReason,
    );

    test(
      'a later clean discovery in the same process still defers: the '
      'earlier instance may be saving into the directory',
      () async {
        final toxId = await stagePlaceholder();
        if (toxId == null) return markTestSkipped('no profile fixture');
        NativeDisposeTestHooks.nativeStoppedOverride = (_) => false;
        expect(await discoverPlaceholderRealToxId(), isNull);

        NativeDisposeTestHooks.reset(); // the retry stops cleanly
        expect(await discoverPlaceholderRealToxId(), isNull);
        expect(NativeQuarantine.contains(placeholder), isTrue);
      },
      skip: skipReason,
    );

    test(
      'an unproven stop leaves the decrypted copy for the next start '
      'instead of deleting it under a late write',
      () async {
        final password = SecretPassword.fromString('placeholder-pw');
        final toxId = await stagePlaceholder(encryptWith: password);
        if (toxId == null) return markTestSkipped('no profile fixture');
        NativeDisposeTestHooks.nativeStoppedOverride = (_) => false;

        expect(await discoverPlaceholderRealToxId(password), isNull);
        expect(scratchCopies(), hasLength(1));
        // An in-process sweep must not take it either.
        await sweepPlaceholderDiscoveryScratch();
        expect(scratchCopies(), hasLength(1));

        // Control in the same shape: a proven stop removes the copy (the
        // registry is reset: a fresh process).
        NativeDisposeTestHooks.reset();
        NativeQuarantine.reset();
        for (final d in scratchCopies()) {
          d.deleteSync(recursive: true);
        }
        expect(await discoverPlaceholderRealToxId(password), isNotNull);
        expect(scratchCopies(), isEmpty);
      },
      skip: skipReason,
    );
  });
}

const _pointerKey = 'flutter.current_account_tox_id';

/// Throws (a storage failure, not a refusal) on every current-account
/// pointer write while [armed].
class _PointerThrowingStore extends SharedPreferencesStorePlatform {
  _PointerThrowingStore(this.inner);

  final SharedPreferencesStorePlatform inner;
  bool armed = false;
  int pointerWrites = 0;

  void _maybeThrow(String key) {
    if (!armed || key != _pointerKey) return;
    pointerWrites++;
    throw PlatformException(code: 'prefs-io', message: 'injected');
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _maybeThrow(key);
    return inner.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    _maybeThrow(key);
    return inner.remove(key);
  }

  @override
  Future<bool> clear() => inner.clear();

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      inner.clearWithParameters(parameters);

  @override
  Future<Map<String, Object>> getAll() => inner.getAll();

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => inner.getAllWithParameters(parameters);
}
