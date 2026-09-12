// Regression tests for the authenticated continuation of the
// `FlutterUIKitClient` placeholder-account migration.
//
// Background, because the shape of these tests only makes sense with it:
// legacy builds persisted the V2TIM login alias (`FlutterUIKitClient`) as if it
// were the user's Tox ID, so account rows, `account_data/` directories, profile
// directories, scoped prefs and the blocked-peer list all ended up under a
// placeholder namespace. `PlaceholderAccountMigration` repairs that on startup,
// but it first has to learn the REAL 76-char Tox address, and the only way to
// learn it is to OPEN the account (`init()` + `login()` on a throwaway
// `FfiChatService`).
//
// That is the whole problem. The migration runs on every cold start, ahead of
// the auto-login authentication gate, so a password-protected account was
// unsealed here regardless of what the gate later decided — and on an ENCRYPTED
// profile it could not even succeed, so the session was opened precisely in the
// cases where it bought nothing. `discoverPlaceholderRealToxId` now refuses both
// shapes when it has not been handed a verified password, and `LoginUseCase`
// supplies that password after `verifyAccountPassword` succeeds so the refusal
// is a deferral rather than a permanent dead end (a protected placeholder
// account used to stay under `FlutterUIKitClient` forever: blocked-peer list
// read under an id nothing writes, session password cached under the
// placeholder while teardown looks under the real address, so even a clean
// logout stopped re-encrypting the profile).
//
// A bare `expect(result, isNull)` would not distinguish "refused" from "opened
// the account and then failed", and the second one is the regression that
// matters, so the tests below assert on a side effect instead. For the two
// refusal guards that is the account's chat-history / avatars directories,
// which are created only after both guards have passed. For the rejected
// password (which is refused further down, after those creates) it is the
// profile file staying byte-identical.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/logger.dart';
import 'package:toxee/util/placeholder_account_migration.dart';
import 'package:toxee/util/placeholder_identity_discovery.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

const _placeholder = PlaceholderAccountMigration.placeholderToxId;

const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// The encrypt/decrypt helpers go through `libtim2tox_ffi` (tox_pass_encrypt /
/// tox_pass_decrypt), so the two tests that need a genuinely encrypted profile
/// blob are skipped where the library is not loadable — same gate the
/// `test/account_export/` suite uses. The protected-account test below needs no
/// FFI at all and always runs; it is the primary guard.
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
  final ffiSkip = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late AccountExportTestEnv env;
  final secureStore = <String, String>{};

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    AppLogger.resetForTesting();
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (MethodCall call) async {
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
        .setMockMethodCallHandler(_secureChannel, null);
    await env.dispose();
  });

  /// Writes a `tox_profile.tox` for the placeholder account. The bytes are
  /// deliberately not a valid tox save — every test here must return before
  /// anything tries to load them.
  Future<String> stagePlaceholderProfile() async {
    final profileDir = await AppPaths.getProfileDirectoryForToxId(_placeholder);
    await Directory(profileDir).create(recursive: true);
    final profilePath = AppPaths.profileFileInDirectory(profileDir);
    await File(profilePath).writeAsBytes(
      Uint8List.fromList(List<int>.generate(512, (i) => i % 251)),
    );
    return profilePath;
  }

  /// True when discovery got past its two refusal guards. Both guards return
  /// before the account's chat-history and avatars directories are created, and
  /// nothing else in a unit-test process creates them, so their absence proves
  /// control never reached the rest of the function.
  Future<bool> discoveryProceededPastTheGuards() async {
    final history = await AppPaths.getAccountChatHistoryPath(_placeholder);
    final avatars = await AppPaths.getAccountAvatarsPath(_placeholder);
    return await Directory(history).exists() || await Directory(avatars).exists();
  }

  group('discoverPlaceholderRealToxId refuses to authenticate itself', () {
    test('a password-protected account is not unsealed by an unauthenticated '
        'startup migration', () async {
      // Prevents: the startup migration opening a password-protected account
      // before the user has typed anything. Discovery is `init()` + `login()`,
      // it runs ahead of the auto-login gate, and it used to run
      // unconditionally — so the protection the user asked for was bypassed on
      // every cold start of an un-migrated legacy account.
      await stagePlaceholderProfile();
      expect(await Prefs.setAccountPassword(_placeholder, 'correct horse'),
          isTrue);
      expect(
        await Prefs.accountProtectionState(_placeholder),
        AccountProtectionState.protected,
        reason: 'test setup: the account must really look protected',
      );

      final result = await discoverPlaceholderRealToxId();

      expect(result, isNull,
          reason: 'no Tox ID may be discovered without authentication');
      expect(await discoveryProceededPastTheGuards(), isFalse,
          reason: 'the refusal must happen BEFORE the discovery session is '
              'built — returning null after opening the account would be the '
              'same leak with a tidier return value');
    });

    test('an unprotected-but-encrypted profile is also refused', () async {
      // Prevents: reintroducing the "open it anyway" behaviour for a profile
      // that is encrypted at rest. Without a passphrase this layer cannot
      // possibly load it, so opening the account here is pure cost — and the
      // session it mints is a real native Tox instance that later startup code
      // would adopt. Protection state and file encryption are independent (a
      // profile stays plaintext for a whole authenticated session), so this
      // needs its own guard and its own test.
      final profilePath = await stagePlaceholderProfile();
      await AccountExportService.encryptProfileFile(profilePath, 'pass phrase');
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isTrue,
          reason: 'test setup: the profile must really be encrypted');
      expect(
        await Prefs.accountProtectionState(_placeholder),
        AccountProtectionState.none,
        reason: 'test setup: this case must be reached by the ENCRYPTION '
            'guard, not the protection guard',
      );

      final result = await discoverPlaceholderRealToxId();

      expect(result, isNull);
      expect(await discoveryProceededPastTheGuards(), isFalse);
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isTrue,
          reason: 'a refusal must not have touched the file');
    }, skip: ffiSkip);

    test('a password that does not decrypt the profile leaves it untouched',
        () async {
      // Prevents two failures at once. First: a wrong or stale password must
      // not be allowed to proceed into the discovery session on a profile that
      // was never decrypted. Second — and this is the one that costs the user
      // their account — the failed-decrypt path must not leave
      // `tox_profile.tox` truncated, half-written or plaintext.
      //
      // Byte-identity is the assertion that carries both. The directory probe
      // used by the tests above deliberately cannot be used here: the two
      // `Directory.create` calls were moved AHEAD of the decrypt on purpose, so
      // that a create that throws (full disk, permissions) cannot happen in the
      // window between decryption and the `finally` that re-encrypts. So the
      // directories exist either way, and what distinguishes "rejected the
      // password" from "ran a session" is the file: a session would have been
      // preceded by a real decrypt and followed by the `finally` re-encrypting
      // under a freshly generated salt/nonce, which cannot reproduce the
      // original ciphertext.
      final profilePath = await stagePlaceholderProfile();
      await AccountExportService.encryptProfileFile(profilePath, 'the real one');
      final before = await File(profilePath).readAsBytes();

      final result = await discoverPlaceholderRealToxId('not the real one');

      expect(result, isNull);
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isTrue);
      expect(await File(profilePath).readAsBytes(), before,
          reason: 'a rejected password must be observable as "nothing '
              'happened" \u2014 no decrypt, no session, no re-encryption');
    }, skip: ffiSkip);

    test('a missing profile is reported, not treated as an open account',
        () async {
      // Prevents: a fresh install (or an already-migrated one) paying for a
      // native session on every cold start. There is nothing to discover
      // without a profile blob, and the early return is what keeps the
      // migration cheap enough to run unconditionally.
      expect(await discoverPlaceholderRealToxId(), isNull);
      expect(await discoveryProceededPastTheGuards(), isFalse);
    });
  });

  group('migrateIfNeeded is a no-op when there is nothing placeholder-keyed',
      () {
    test('an account list without the placeholder never reaches discovery',
        () async {
      // Prevents: the migration running discovery for users who never had the
      // bug. `migrateIfNeeded` must inspect the durable state FIRST and bail
      // before `discoverPlaceholderRealToxId` (which opens an account) is
      // reached at all.
      await stagePlaceholderProfile();
      await Prefs.addAccount(
        toxId: 'A' * 76,
        nickname: 'someone',
        statusMessage: '',
      );
      await Prefs.setCurrentAccountToxId('A' * 76);

      expect(await PlaceholderAccountMigration.migrateIfNeeded(), isNull);
      expect(await discoveryProceededPastTheGuards(), isFalse);
    });

    test('a protected placeholder account survives an unauthenticated pass '
        'unchanged', () async {
      // Prevents: a half-migration. When discovery refuses, `migrateIfNeeded`
      // must abandon the whole transaction — the account row and the
      // current-account pointer stay on the placeholder so the authenticated
      // login path can retry. Renaming directories or re-keying prefs against a
      // null/partial Tox ID is unrecoverable.
      await stagePlaceholderProfile();
      await Prefs.setAccountPassword(_placeholder, 'correct horse');
      await Prefs.addAccount(
        toxId: _placeholder,
        nickname: 'legacy',
        statusMessage: '',
      );
      await Prefs.setCurrentAccountToxId(_placeholder);

      expect(await PlaceholderAccountMigration.migrateIfNeeded(), isNull);

      expect(await discoveryProceededPastTheGuards(), isFalse);
      expect(await Prefs.getCurrentAccountToxId(), _placeholder,
          reason: 'the pointer must not move without a discovered Tox ID');
      final accounts = await Prefs.getAccountList();
      expect(accounts.map((a) => a['toxId']), contains(_placeholder),
          reason: 'the row must still be there for the authenticated retry');
    });
  });

  // Source-shape assertions. The orderings below cannot be exercised
  // hermetically — the authenticated branch ends in
  // `AccountService.initializeServiceForAccount`, which mints a real native Tox
  // instance — but getting them wrong is silent and expensive, so they are
  // pinned by reading the source. This idiom is already used in this suite (see
  // `test/android_real_ui_driver_source_test.dart`).
  group('call ordering in LoginUseCase (source shape)', () {
    late String source;

    setUp(() {
      source = File('lib/auth/login_use_case.dart').readAsStringSync();
    });

    test('the unauthenticated pre-lookup migration runs before the account '
        'lookup', () {
      // Prevents: the nickname lookup resolving against a stale,
      // placeholder-keyed row for the (unprotected) accounts the startup
      // migration CAN repair. If the lookup wins the race, login proceeds under
      // `FlutterUIKitClient` even though a migration was available.
      final preLookup =
          source.indexOf('await PlaceholderAccountMigration.migrateIfNeeded();');
      final lookup = source.indexOf('Prefs.getUniqueAccountByNickname');

      expect(preLookup, greaterThanOrEqualTo(0),
          reason: 'the unauthenticated pre-lookup migration call is gone');
      expect(lookup, greaterThan(preLookup));
    });

    test('the authenticated migration runs after verification and before the '
        'session is created', () {
      // Prevents the two ways this call can be misplaced, both of which are
      // silent:
      //
      //  * moved ABOVE `verifyAccountPassword` it becomes the very bypass the
      //    refusal in `discoverPlaceholderRealToxId` exists to close — an
      //    unverified string would unseal the account;
      //  * moved BELOW `initializeServiceForAccount` it runs under a LIVE
      //    session, and the migration renames the account's `account_data/` and
      //    profile DIRECTORIES out from under it. (This is exactly why it
      //    cannot ride along with `ShortToxIdBackfill`, which only rewrites ids
      //    whose 16-char directory prefix is unchanged.)
      final verify = source.indexOf('Prefs.verifyAccountPassword(');
      final authenticatedMigrate =
          source.indexOf('authenticatedPassword: params.password');
      final initService =
          source.indexOf('AccountService.initializeServiceForAccount(');

      expect(verify, greaterThanOrEqualTo(0),
          reason: 'password verification is gone from LoginUseCase');
      expect(authenticatedMigrate, greaterThanOrEqualTo(0),
          reason: 'the authenticated continuation is gone; a protected '
              'placeholder account would stay placeholder-keyed forever');
      expect(initService, greaterThanOrEqualTo(0));

      expect(authenticatedMigrate, greaterThan(verify),
          reason: 'migration must not run on an unverified password');
      expect(initService, greaterThan(authenticatedMigrate),
          reason: 'directory renames cannot happen under a live session');
    });

    test('the authenticated migration is gated on the placeholder id', () {
      // Prevents: paying for a discovery session (and handing the user's
      // password to it) on every single protected login. Only an account whose
      // stored id IS the placeholder has anything to migrate.
      final guard = source
          .indexOf('toxIdForLogin == PlaceholderAccountMigration.placeholderToxId');
      final authenticatedMigrate =
          source.indexOf('authenticatedPassword: params.password');

      expect(guard, greaterThanOrEqualTo(0));
      expect(authenticatedMigrate, greaterThan(guard));
    });
  });

  group('password plumbing and re-encryption (source shape)', () {
    test('migrateIfNeeded forwards its password to discovery', () {
      // Prevents: `migrateIfNeeded` accepting `authenticatedPassword` and
      // dropping it. Every runtime symptom would be identical to "no password
      // supplied" — discovery refuses, the account stays placeholder-keyed —
      // so nothing in the black-box tests above can tell the two apart.
      final source =
          File('lib/util/placeholder_account_migration.dart').readAsStringSync();
      expect(source, contains('discoverPlaceholderRealToxId(authenticatedPassword)'));
    });

    test('discovery never decrypts the profile the account actually uses', () {
      // Prevents: a decrypted `tox_profile.tox` left on disk. The first version
      // of this fix decrypted in place and re-encrypted in a `finally`, which
      // looks equivalent and is not - the re-encrypt itself can fail, and then
      // discovery returns normally with the private key in plaintext and no
      // session left that owns putting it back. (`initializeServiceForAccount`
      // only re-encrypts on teardown what IT decrypted, so nothing downstream
      // repairs it either.) Discovery only needs to read an id, so it works on
      // a throwaway copy and the real file is never modified at all.
      //
      // Not covered at runtime: reaching the session leg needs a real
      // `FfiChatService.init()` on the shared native singleton, which is not
      // hermetic in a unit test.
      final source = File('lib/util/placeholder_identity_discovery.dart')
          .readAsStringSync();

      expect(source, isNot(contains('encryptProfileFile(profileFile')),
          reason: 'the account\'s own profile must never be re-encrypted here, '
              'because it must never have been decrypted here');
      expect(source, contains('await File(profileFile).copy(copy)'));
      expect(source, contains('AccountExportService.decryptProfileFile(copy'),
          reason: 'the COPY is what gets decrypted');

      // The copy is a plaintext private key, so its removal must not depend on
      // discovery succeeding.
      final session = source.indexOf('_runDiscoverySession(');
      final finallyBlock = source.indexOf('} finally {', session);
      final cleanup = source.indexOf('_deleteScratch(scratch)', finallyBlock);
      expect(session, greaterThanOrEqualTo(0));
      expect(finallyBlock, greaterThan(session));
      expect(cleanup, greaterThan(finallyBlock));

      // And it lives beside the real profile, not in the system temp directory,
      // where it would not inherit the same protection.
      expect(source, contains('AppPaths.applicationSupportPath'));
      expect(source, isNot(contains('Directory.systemTemp')));
    });
  });
}
