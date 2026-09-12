// L1 regression/coverage test for toxee's auto-login startup DECISION
// (UI_AUTOMATION / roadmap item 6: "Auto-login persistence across cold
// restart").
//
// StartupSessionUseCase.execute() (lib/startup/startup_session_use_case.dart)
// computes the cold-start outcome purely from persisted Prefs. This file locks
// the early-return-to-login decision paths — the ones that land on the login
// page BEFORE any FFI/init/boot runs:
//
//   * nickname null / empty                  → StartupShowLogin (lines 38-40)
//   * nickname set + autoLogin == false      → StartupShowLogin (lines 41-43)
//   * ambiguous (duplicate) nickname         → StartupShowLogin (lines 75-78,
//                                               via getUniqueAccountByNickname's
//                                               StateError)
//
// Layer note — NO _ffiAvailable() skip-guard is needed (unlike its sibling
// test/account_password_lifecycle_test.dart), but the FFI-free guarantee is
// NOT uniform across the three paths:
//
//   * nickname null/empty and autoLogin==false return at lines 38-43, which
//     run BEFORE StartupStep.initializingService (line 45) and therefore
//     unconditionally before the first FFI touch. These two are hard
//     FFI-free guarantees regardless of any other persisted state.
//
//   * the ambiguous-nickname path returns LATER, at lines 76-78. It runs
//     AFTER PlaceholderAccountMigration.migrateIfNeeded() (line 71).
//     migrateIfNeeded() CAN spin up a short-lived discovery FfiChatService
//     and call init()/login() (placeholder_account_migration.dart
//     discoverPlaceholderRealToxId) — but ONLY when there is a
//     placeholder-keyed account ('FlutterUIKitClient') to migrate. When no
//     such account exists it returns null in microseconds without opening
//     FFI (migrateIfNeeded early-return at lines 58-60). In the ambiguous
//     test below the two seeded accounts are keyed by 'A'*76 / 'B'*76 and
//     no current-account pointer is set, so migrateIfNeeded() no-ops and
//     the path stays FFI-free — but that is a property of THIS test's seeded
//     state, not a structural guarantee of the code path. Do not seed a
//     'FlutterUIKitClient' account into this test without also building the
//     native lib / adding a skip-guard.
//
// The unit-under-test for these decisions is otherwise pure Prefs + the use
// case, so no libtim2tox_ffi dylib is required for the state these tests set up.
//
// We deliberately do NOT cover the auto-login-SUCCESS path (autoLogin == true
// with a valid staged account). That path proceeds past init into
// AppBootstrapCoordinator.boot → service.startPolling() (real DHT/network) and
// touches the xyz.luan/audioplayers platform channel — flaky/unsafe/hangs in a
// unit test. See account_password_lifecycle_test.dart Bug 3 control test for
// the rationale.

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/startup/startup_outcome.dart';
import 'package:toxee/startup/startup_session_use_case.dart';
import 'package:toxee/util/prefs.dart';

import 'account_export/test_support.dart';

void main() {
  late AccountExportTestEnv env;

  // In-memory flutter_secure_storage. The real facade cannot reach a keychain
  // in a unit test, and an unmocked channel now reports "unavailable" rather
  // than "no password" — correct, but it makes every account look protected.
  // The auth-gate group needs all three protection states, so mock the channel
  // and let individual tests tear it down to simulate unavailability.
  // Mirrors test/account_password_lifecycle_test.dart.
  final secureStore = <String, String>{};
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    // Mocks path_provider + SharedPreferences and runs Prefs.initialize().
    env = await setUpAccountExportTestEnv();
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
    await env.dispose();
  });

  // execute() takes no-op step/loadFriends callbacks for every path here;
  // the decision is made before either is meaningfully exercised.
  Future<StartupOutcome> run() => StartupSessionUseCase().execute(
        onStepChanged: (_) {},
        loadFriends: (_) async {},
      );

  group('StartupSessionUseCase.execute — decisions that land on login', () {
    test(
        'nickname set + autoLogin=false → StartupShowLogin '
        '(toggle-off then cold restart)', () async {
      await Prefs.setNickname('Alice');
      // No current account toxId is set, so getAutoLogin() reads the GLOBAL
      // key (prefs.dart:721). Set it false explicitly to simulate the user
      // having toggled auto-login off before the cold restart.
      await Prefs.setAutoLogin(false);

      expect(await Prefs.getAutoLogin(), isFalse,
          reason: 'precondition: global auto-login must read back false');

      final outcome = await run();

      expect(outcome, isA<StartupShowLogin>(),
          reason: 'a nickname-set account with auto-login disabled must route '
              'to the login page, not auto-open home');
      expect(outcome, isNot(isA<StartupOpenHome>()),
          reason: 'auto-login disabled must never silently open home');
      expect(outcome, isNot(isA<StartupWaitForConnection>()),
          reason: 'execute() returns before any service is created, so it '
              'cannot return a wait-for-connection outcome');
      expect(outcome, isNot(isA<StartupShowError>()),
          reason: 'a disabled-auto-login decision is not an error path');
    });

    test('nickname null → StartupShowLogin (no registered user)', () async {
      // Fresh env: no nickname persisted. getNickname() returns null.
      expect(await Prefs.getNickname(), isNull,
          reason: 'precondition: a fresh install has no persisted nickname');

      final outcome = await run();

      expect(outcome, isA<StartupShowLogin>(),
          reason: 'a missing nickname means no registered user → login page');
      expect(outcome, isNot(isA<StartupOpenHome>()),
          reason: 'no registered user must never open home');
    });

    test('nickname empty/whitespace → StartupShowLogin', () async {
      await Prefs.setNickname('   ');
      // Even with auto-login on, the empty-nickname guard (lines 38-40) wins
      // because it is checked before the autoLogin guard.
      await Prefs.setAutoLogin(true);

      final outcome = await run();

      expect(outcome, isA<StartupShowLogin>(),
          reason: 'a whitespace-only nickname is treated as no nickname '
              '(nick.trim().isEmpty) → login page');
      expect(outcome, isNot(isA<StartupOpenHome>()),
          reason: 'an empty nickname must never open home');
    });

    test(
        'ambiguous (duplicate) nickname + autoLogin=true → StartupShowLogin '
        '(getUniqueAccountByNickname StateError is caught)', () async {
      // Seed two accounts sharing the SAME nickname directly via setAccountList
      // — addAccount() rejects duplicate nicknames, so we bypass its guard to
      // construct the ambiguous state the decision must handle. With no current
      // account pointer, getAutoLogin() reads the global key (default true), so
      // execution reaches getUniqueAccountByNickname (line 75), which throws a
      // StateError on the duplicate → caught at lines 76-78 → StartupShowLogin.
      await Prefs.setAccountList([
        {
          'toxId': 'A' * 76,
          'nickname': 'Twins',
          'statusMessage': '',
        },
        {
          'toxId': 'B' * 76,
          'nickname': 'Twins',
          'statusMessage': '',
        },
      ]);
      await Prefs.setNickname('Twins');
      await Prefs.setAutoLogin(true); // global; reaches the unique lookup

      // Precondition: the lookup is genuinely ambiguous.
      expect(
        () => Prefs.getUniqueAccountByNickname('Twins'),
        throwsA(isA<StateError>()),
        reason: 'precondition: two accounts share the nickname so the unique '
            'lookup throws StateError',
      );

      final outcome = await run();

      expect(outcome, isA<StartupShowLogin>(),
          reason: 'an ambiguous nickname cannot resolve a single account to '
              'auto-login → route to login page rather than guess');
      expect(outcome, isNot(isA<StartupShowError>()),
          reason: 'the StateError is caught and converted to a login redirect, '
              'not surfaced as a startup error');
    });
  });

  group('Auto-login authentication gate (password-protected accounts)', () {
    // REGRESSION GUARD for an authentication bypass.
    //
    // The gate used to be `isProfileFileEncrypted(profile)` alone. That is the
    // wrong authority: `initializeServiceForAccount` decrypts the profile in
    // place for the whole session and ONLY `teardownCurrentSession` re-encrypts
    // it, so any exit that skips teardown (crash, force-quit, or simply closing
    // the desktop window) leaves a protected account in plaintext. Auto-login
    // then saw an unencrypted file, concluded "not protected", and opened the
    // account with no password prompt at all. Setting a password in Settings and
    // closing the window was enough to reproduce.
    //
    // The gate is now the DURABLE verifier, which is true regardless of what the
    // file on disk currently looks like. These tests seed exactly that state —
    // a password-protected account whose profile is NOT encrypted — and require
    // the login page.
    // Seeds a single auto-login-eligible account and returns its toxId. No
    // profile file is written: the old gate probed the FILE, and the whole point
    // is that the decision must not depend on it.
    Future<String> seedAutoLoginAccount(String fill, String nickname) async {
      final toxId = fill * 76;
      await Prefs.setAccountList([
        {'toxId': toxId, 'nickname': nickname, 'statusMessage': ''},
      ]);
      await Prefs.setNickname(nickname);
      await Prefs.setCurrentAccountToxId(toxId);
      await Prefs.setAutoLogin(true);
      return toxId;
    }

    test(
        'protected account with NO profile ciphertext → StartupShowLogin '
        '(the durable verifier decides, not the file)', () async {
      final toxId = await seedAutoLoginAccount('C', 'Protected');
      expect(await Prefs.setAccountPassword(toxId, 'correct horse'), isTrue,
          reason: 'precondition: the durable verifier must persist');
      expect(await Prefs.accountProtectionState(toxId),
          AccountProtectionState.protected,
          reason: 'precondition: the account reads back as protected');

      final outcome = await run();

      expect(outcome, isA<StartupShowLogin>(),
          reason: 'a password-protected account must reach the login page so '
              'the password is actually demanded and verified');
      expect(outcome, isNot(isA<StartupOpenHome>()),
          reason: 'auto-opening home here IS the authentication bypass');
      expect(outcome, isNot(isA<StartupWaitForConnection>()),
          reason: 'the gate must return before any service is created');
    });

    test(
        'legacy plain-prefs verifier also gates (secure storage never consulted '
        'successfully)', () async {
      final toxId = await seedAutoLoginAccount('E', 'LegacyProtected');
      // Pre-S1 installs stored the hash in SharedPreferences. It still proves
      // the account is protected, so it must gate exactly like a modern one.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'account_password_$toxId',
        'deadbeef' * 8, // shape-only; the gate never verifies, only detects
      );

      expect(await Prefs.accountProtectionState(toxId),
          AccountProtectionState.protected);
      expect(await run(), isA<StartupShowLogin>());
    });

    test(
        'secure storage UNAVAILABLE → StartupShowLogin (fail closed, never '
        'fail open)', () async {
      await seedAutoLoginAccount('F', 'Unknown');
      // Kill the mock channel so every read throws MissingPluginException —
      // the real-world shape is a locked keychain or a missing entitlement.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureChannel, null);

      final outcome = await run();

      expect(outcome, isA<StartupShowLogin>(),
          reason: 'an unreadable secure store means "possibly protected"; '
              'treating it as "not protected" is the bypass');
      expect(outcome, isNot(isA<StartupOpenHome>()));
    });

    test(
        'CONTROL: unprotected account is not gated — it proceeds into init '
        '(and fails there for want of FFI, not at the gate)', () async {
      final toxId = await seedAutoLoginAccount('D', 'Open');
      expect(await Prefs.accountProtectionState(toxId),
          AccountProtectionState.none,
          reason: 'precondition: no verifier, and secure storage DID answer');

      // Without this control a gate that returned StartupShowLogin for every
      // account would pass all three tests above. An unprotected account must
      // get past the gate; it then dies in initializeServiceForAccount because
      // there is no profile and no libtim2tox_ffi in a unit test, which surfaces
      // as StartupShowError. That error is the proof the gate let it through.
      expect(await run(), isA<StartupShowError>(),
          reason: 'reaching init (and failing there) proves the protection gate '
              'did not short-circuit an unprotected account');
    });
  });

  group('Auto-login persistence across cold restart (roadmap item 6)', () {
    test(
        'setAutoLogin(false) persists, and a fresh execute() reads it back '
        '→ StartupShowLogin (simulated cold restart)', () async {
      await Prefs.setNickname('Persisted');

      // Persist the toggle-off, then prove it round-trips through Prefs as the
      // cold-restart reader would observe it.
      await Prefs.setAutoLogin(false);
      expect(await Prefs.getAutoLogin(), isFalse,
          reason: 'setAutoLogin(false) must persist so a later cold start reads '
              'the disabled state, not the default-true');

      // A fresh use case instance (no in-process state carried over) standing
      // in for the next cold start reading the persisted Prefs.
      final outcome = await StartupSessionUseCase().execute(
        onStepChanged: (_) {},
        loadFriends: (_) async {},
      );

      expect(outcome, isA<StartupShowLogin>(),
          reason: 'a cold restart that reads persisted autoLogin=false must '
              'land on login, proving the toggle survives the restart');
      expect(outcome, isNot(isA<StartupOpenHome>()),
          reason: 'persisted disabled auto-login must never auto-open home');
    });
  });
}
