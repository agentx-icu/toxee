// Regression + characterization tests for the account-password lifecycle
// (S40 / roadmap L2-3). Three bugs were surfaced by the S40 MCP playbook
// (test/mcp/S40_set_password.md). As of 2026-05-29 only ONE has a landed fix:
//
//   Bug 1 — SessionPasswordStore drift after F12 backfill  [FIX LANDED]
//     initializeServiceForAccount keyed the in-memory session password under
//     the raw (possibly 64-char) input toxId, but teardownCurrentSession looks
//     it up under the canonical 76-char address (from service.getSelfToxId()).
//     The mismatch made the lookup miss → re-encrypt-on-logout was silently
//     skipped → the on-disk profile was left PLAINTEXT after logout. The fix
//     (account_service.dart:275) keys the store under the post-backfill
//     `activeToxId`. This group locks that fix.
//
//   Bug 2 — post-remove re-encrypt  [FIX NOT LANDED — S40d gap]
//   Bug 3 — autoLogin + encrypted profile  [FIX NOT LANDED]
//     Encoded below as `skip`-marked desired-behavior tests so the intent is
//     recorded and they flip to active the moment the fix lands. They are NOT
//     green today because the fixes do not exist; a green test would be a lie.
//
// Layer: like test/account_switch_resets_global_prefs_test.dart this needs the
// real libtim2tox_ffi dylib (Tox encryption + profile load) but pumps no
// MaterialApp, so it lives in test/ with an _ffiAvailable() skip-guard. The
// password VERIFIER (PBKDF2 / flutter_secure_storage) is intentionally NOT
// exercised here — Bug 1 is reproduced by encrypting the profile directly via
// AccountExportService and passing the password to init, so no secure-storage
// channel mock is needed. Verifier behaviour is covered by
// test/util/prefs/password_verifier_test.dart.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:toxee/startup/startup_outcome.dart';
import 'package:toxee/startup/startup_session_use_case.dart';
import 'package:toxee/util/account_export/account_export_service.dart';
import 'package:toxee/util/account_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';
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

Future<String> _stageProfile(ToxProfileFixture fixture) async {
  final dir = await AppPaths.getProfileDirectoryForToxId(fixture.toxId);
  await Directory(dir).create(recursive: true);
  final path = AppPaths.profileFileInDirectory(dir);
  await File(path).writeAsBytes(fixture.savedata, flush: true);
  return path;
}

void main() {
  final ffiAvailable = _ffiAvailable();
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late AccountExportTestEnv env;

  // In-memory flutter_secure_storage so the PasswordVerifier (PBKDF2) write in
  // Prefs.setAccountPassword actually succeeds — the real facade is a no-op in
  // tests (write→false). Needed only by the set-path group, but harmless to the
  // others (which never write a verifier).
  final secureStore = <String, String>{};
  bool failSecureDeletes = false;
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() async {
    env = await setUpAccountExportTestEnv();
    SessionPasswordStore.clear(); // static singleton — avoid cross-test bleed.
    secureStore.clear();
    failSecureDeletes = false;
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
          if (failSecureDeletes) {
            throw PlatformException(
              code: 'secure-delete-failed',
              message: 'Injected secure-storage delete failure',
            );
          }
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
    SessionPasswordStore.clear();
    await env.dispose();
  });

  group('Bug 1 — SessionPasswordStore keyed under canonical toxId', () {
    test(
        'init(short toxId, password) keys the session store under the '
        'post-backfill canonical id, so logout re-encrypts the profile',
        () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      const password = 'sekret-pw';
      // The 76-char address is publicKey(64) + nospam(8) + checksum(4); the
      // first 64 chars are the public key. An imported (F12) account persists
      // only that 64-char form, which the backfill later rewrites to 76.
      final canonicalToxId = fixture.toxId;
      final shortToxId = fixture.toxId.substring(0, 64);

      // Stage the profile (same p_<first16> dir for 64/76) then encrypt it on
      // disk, so init's decrypt-with-password path runs.
      final profilePath = await _stageProfile(fixture);
      await AccountExportService.encryptProfileFile(profilePath, password);
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isTrue,
          reason: 'precondition: the staged profile is encrypted on disk');

      await Prefs.addAccount(toxId: shortToxId, nickname: 'PwAcct');
      await Prefs.setCurrentAccountToxId(shortToxId);

      // Unit under test: init decrypts, loads, runs ShortToxIdBackfill, then
      // SessionPasswordStore.set(activeToxId, password) — must use the
      // canonical id, not the short input.
      final service = await AccountService.initializeServiceForAccount(
        toxId: shortToxId,
        password: password,
        startPolling: false,
      );
      // Safety-net cleanup for an early assertion failure before the explicit
      // teardownCurrentSession below. Guarded because teardownCurrentSession
      // (the unit under test) already disposes the service on the happy path —
      // a second dispose must not throw.
      addTearDown(() async {
        try {
          await service.dispose();
        } catch (_) {}
      });

      // Primary lock: the session password is retrievable under the canonical
      // id and NOT under the short input (proves the fix's keying). Pre-fix the
      // store was keyed under shortToxId → get(canonical) == null.
      expect(SessionPasswordStore.get(canonicalToxId), password,
          reason: 'session password must be keyed under the canonical toxId');
      expect(SessionPasswordStore.get(shortToxId), isNull,
          reason: 'session password must NOT be keyed under the short input');

      // Deeper lock: logout re-encrypts the profile using that session
      // password. Pre-fix the lookup missed and the file stayed PLAINTEXT.
      await AccountService.teardownCurrentSession(
          service: service, reEncryptProfile: true);
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isTrue,
          reason: 'logout must re-encrypt the profile (the drift bug left it '
              'plaintext)');
    }, skip: skipReason);
  });

  group('Bug 2 — password updates keep on-disk encryption in sync (FIX LANDED)',
      () {
    test(
        'removing a password leaves the profile plaintext and clears the '
        'session password (no re-encrypt on logout)', () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      const password = 'remove-me-pw';
      final toxId = fixture.toxId;

      // Encrypted-on-disk account; logging in with the password decrypts it on
      // disk and arms SessionPasswordStore for re-encrypt-on-logout.
      final profilePath = await _stageProfile(fixture);
      await AccountExportService.encryptProfileFile(profilePath, password);
      await Prefs.addAccount(toxId: toxId, nickname: 'RemoveAcct');
      await Prefs.setCurrentAccountToxId(toxId);

      final service = await AccountService.initializeServiceForAccount(
        toxId: toxId,
        password: password,
        startPolling: false,
      );
      addTearDown(() async {
        try {
          await service.dispose();
        } catch (_) {}
      });
      expect(SessionPasswordStore.get(toxId), password,
          reason: 'precondition: login armed the session password');

      // The fix under test.
      final ok = await AccountService.removeAccountPassword(service);
      expect(ok, isTrue,
          reason: 'the secure-storage delete completed durably');
      expect(SessionPasswordStore.get(toxId), isNull,
          reason: 'remove must clear the in-memory session password');

      // Logout must NOT re-encrypt — the profile stays plaintext (the user
      // unprotected it). Pre-fix, the stale session password re-encrypted it.
      await AccountService.teardownCurrentSession(
          service: service, reEncryptProfile: true);
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isFalse,
          reason: 'logout must not re-encrypt a password-removed profile');
    }, skip: skipReason);

    test(
        'failed durable password removal leaves the session password armed',
        () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      const password = 'retain-on-delete-failure';
      final toxId = fixture.toxId;

      final profilePath = await _stageProfile(fixture);
      await AccountExportService.encryptProfileFile(profilePath, password);
      await Prefs.addAccount(toxId: toxId, nickname: 'DeleteFailAcct');
      await Prefs.setCurrentAccountToxId(toxId);

      final service = await AccountService.initializeServiceForAccount(
        toxId: toxId,
        password: password,
        startPolling: false,
      );
      addTearDown(() async {
        try {
          await service.dispose();
        } catch (_) {}
      });
      expect(SessionPasswordStore.get(toxId), password,
          reason: 'precondition: login armed the session password');

      failSecureDeletes = true;
      final ok = await AccountService.removeAccountPassword(service);

      expect(ok, isFalse,
          reason: 'the secure-storage facade rejected durable deletion');
      expect(SessionPasswordStore.get(toxId), password,
          reason: 'a failed durable removal must retain the password so the '
              'still-protected account can be re-encrypted on logout');
    }, skip: skipReason);

    test(
        'setting a password mid-session arms logout to encrypt with the NEW '
        'password', () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      final toxId = fixture.toxId;

      // Account starts with NO password → plaintext on disk, empty session pw.
      final profilePath = await _stageProfile(fixture);
      await Prefs.addAccount(toxId: toxId, nickname: 'SetAcct');
      await Prefs.setCurrentAccountToxId(toxId);

      final service = await AccountService.initializeServiceForAccount(
        toxId: toxId,
        startPolling: false,
      );
      addTearDown(() async {
        try {
          await service.dispose();
        } catch (_) {}
      });
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isFalse,
          reason: 'precondition: no-password account is plaintext on disk');

      // The fix under test (set/change branch).
      const newPassword = 'fresh-pw';
      final ok = await AccountService.setAccountPassword(service, newPassword);
      expect(ok, isTrue,
          reason: 'verifier write must succeed (secure-storage mock)');
      expect(SessionPasswordStore.get(toxId), newPassword,
          reason: 'set must arm the session password for logout encryption');

      // Logout must now encrypt with the new password. Pre-fix the session
      // store was untouched → logout skipped encryption → on-disk plaintext
      // disagreed with the verifier.
      await AccountService.teardownCurrentSession(
          service: service, reEncryptProfile: true);
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isTrue,
          reason: 'logout must encrypt the profile with the newly-set password');
    }, skip: skipReason);
  });

  group('Bug 3 — autoLogin with an encrypted profile routes to login (FIX '
      'LANDED)', () {
    test(
        'encrypted profile + autoLogin → StartupShowLogin (never a silent '
        'StartupOpenHome, never a generic error)', () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      final toxId = fixture.toxId;

      // Stage an ENCRYPTED profile and a fully auto-login-eligible account:
      // global nickname set, autoLogin on, a unique account_list row, current
      // pointer set. On cold start there is no session password to decrypt it.
      final profilePath = await _stageProfile(fixture);
      await AccountExportService.encryptProfileFile(profilePath, 'cold-pw');
      await Prefs.addAccount(toxId: toxId, nickname: 'EncAcct');
      await Prefs.setCurrentAccountToxId(toxId);
      await Prefs.setNickname('EncAcct');
      await Prefs.setStatusMessage('');
      await Prefs.setAutoLogin(true, toxId);
      await Prefs.setAutoLogin(true); // global, in case getAutoLogin() reads it

      final outcome = await StartupSessionUseCase().execute(
        onStepChanged: (_) {},
        loadFriends: (_) async {},
      );

      // The fix routes to the login page (where _quickLogin prompts for the
      // password) instead of attempting a doomed password-less init that
      // throws → StartupShowError. The security invariant: NEVER OpenHome
      // (that would mean an encrypted profile was silently decrypted).
      expect(outcome, isA<StartupShowLogin>(),
          reason: 'encrypted + autoLogin must route to login for a password '
              'prompt, not a silent error or home-open');
      expect(outcome, isNot(isA<StartupOpenHome>()));
      // The profile must remain encrypted on disk (the failed-init cleanup
      // path is never taken; nothing decrypted it).
      expect(await AccountExportService.isProfileFileEncrypted(profilePath),
          isTrue,
          reason: 'the encrypted profile must be untouched on disk');
    }, skip: skipReason);

    test(
        'control: a non-encrypted account is not short-circuited to login by '
        'the probe (proves the ShowLogin reroute is encryption-gated)',
        () async {
      final fixture = ToxProfileFixture.create();
      if (fixture == null) {
        markTestSkipped('ToxProfileFixture.create() returned null');
        return;
      }
      final toxId = fixture.toxId;

      // Same auto-login-eligible setup (nickname, autoLogin, account row,
      // current pointer) but NO encrypted profile present, so the probe's
      // isProfileFileEncrypted hit never fires and execution falls through.
      //
      // Why no on-disk profile at all: any PRESENT profile (even a garbage
      // blob) loads as a fresh Tox at service.init(), so init SUCCEEDS and
      // execution proceeds into AppBootstrapCoordinator.boot — which starts
      // real polling and touches platform channels (audioplayers), unsafe in a
      // unit test. With no profile, resolveToxProfilePath() returns null, the
      // probe is skipped, and initializeServiceForAccount throws
      // 'Profile not found' BEFORE service.init/boot — so we get a clean
      // StartupShowError, never reaching polling. The assertion is the
      // negative: the outcome is NOT StartupShowLogin, i.e. an auto-login
      // account does not route to login unless the encrypted-profile probe
      // fires.
      await Prefs.addAccount(toxId: toxId, nickname: 'PlainAcct');
      await Prefs.setCurrentAccountToxId(toxId);
      await Prefs.setNickname('PlainAcct');
      await Prefs.setStatusMessage('');
      await Prefs.setAutoLogin(true, toxId);
      await Prefs.setAutoLogin(true);
      expect(await AppPaths.resolveToxProfilePath(toxId), isNull,
          reason: 'precondition: no profile on disk → probe is skipped');

      final outcome = await StartupSessionUseCase().execute(
        onStepChanged: (_) {},
        loadFriends: (_) async {},
      );

      expect(outcome, isNot(isA<StartupShowLogin>()),
          reason: 'a non-encrypted account must not be rerouted to login by '
              'the probe (it falls through; init then errors on the missing '
              'profile)');
    }, skip: skipReason);
  });
}
