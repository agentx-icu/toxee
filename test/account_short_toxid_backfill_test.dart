// Regression test for finding F12 (roadmap L1-F12): ShortToxIdBackfill must
// rewrite a persisted 64-char public-key toxId up to the canonical 76-char
// address (public key + nospam + checksum) once login resolves it, so the
// account_list row, the current-account pointer, and the displayed "User ID"
// all carry the full address — without re-keying the 16-char-prefix-scoped
// Prefs (64 and 76 share the same first-16 prefix).
//
// Layer: the only service call backfillIfNeeded makes is getSelfToxId(), so a
// one-method stub suffices. FfiChatService's constructor opens the FFI dylib
// (Tim2ToxFfi.open), so the stub needs the lib loadable → _ffiAvailable()
// skip-guard, same as the sibling FFI-backed tests. No real init/login/network
// A secure-storage mock IS required even though no password keys are seeded:
// `migrateAccountPasswordKeys` now ABORTS when the credential store cannot be
// read, because treating "unreadable" as "no password" let an identity rename
// strand the verifier under the old toxId and subsequently bypass the
// auto-login password gate. An unmocked keychain channel reports exactly that
// unavailability, so without the mock the backfill correctly refuses to run.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/short_tox_id_backfill.dart';

import 'account_export/test_support.dart';

bool _ffiAvailable() {
  try {
    Tim2ToxFfi.open();
    return true;
  } catch (_) {
    return false;
  }
}

class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService(this._selfToxId) : super();
  final String? _selfToxId;

  @override
  String? getSelfToxId() => _selfToxId;
}

void main() {
  final skipReason = _ffiAvailable()
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  late AccountExportTestEnv env;

  // Empty but AVAILABLE secure storage: reads answer "no such key" rather than
  // throwing MissingPluginException, which is what lets the password-key
  // migration conclude "nothing to migrate" instead of "cannot tell".
  final secureStore = <String, String>{};
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  // Installs (or re-installs) the in-memory keychain. Re-installable so a test
  // can simulate an outage and then its recovery; `secureStore` survives the
  // gap, which is what a real keychain does.
  void restoreSecureStorageMock() {
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
  }

  setUp(() async {
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

  test(
      'backfill rewrites short toxId → canonical 76-char, is idempotent, and '
      'preserves prefix-scoped keys', () async {
    // A 76-char address is publicKey(64) + nospam(8) + checksum(4); an
    // imported (F12) account persisted only the 64-char public key.
    final canonical = 'A' * 76;
    final shortToxId = canonical.substring(0, 64); // 'A' * 64, shared prefix.
    final service = _StubFfiChatService(canonical);
    addTearDown(() async {
      try {
        await service.dispose();
      } catch (_) {}
    });

    // Seed an account row + current pointer under the SHORT id, plus a
    // prefix-scoped key with a NON-default value (auto-login defaults to true,
    // so seeding false makes a successful post-backfill read prove the scoped
    // key survived rather than falling back to the global default).
    await Prefs.addAccount(toxId: shortToxId, nickname: 'BackfillAcct');
    await Prefs.setCurrentAccountToxId(shortToxId);
    await Prefs.setAutoLogin(false, shortToxId);

    expect((await Prefs.getAccountByToxId(shortToxId))?['toxId'], shortToxId,
        reason: 'precondition: row keyed under the 64-char id');

    final result = await ShortToxIdBackfill.backfillIfNeeded(
      service: service,
      persistedToxId: shortToxId,
    );

    // Rewrite assertions. getAccountByToxId has a 64-prefix fuzzy fallback, so
    // assert the row's stored toxId is the full 76-char form (proves the
    // rewrite happened, not just a fuzzy match).
    expect(result, canonical, reason: 'returns the canonical 76-char id');
    expect((await Prefs.getAccountByToxId(canonical))?['toxId'], canonical,
        reason: 'account_list row rewritten to the 76-char address');
    expect(await Prefs.getCurrentAccountToxId(), canonical,
        reason: 'current-account pointer advanced to the 76-char address');
    expect(await Prefs.getAutoLogin(canonical), isFalse,
        reason: 'the prefix-scoped acct_auto_login key (shared 16-char prefix) '
            'must survive unchanged, not be re-keyed or lost');

    // The row must be REWRITTEN IN PLACE — not a new canonical row appended
    // alongside a lingering 64-char row (which the canonical-only assertions
    // above would not catch).
    final accountsAfter = await Prefs.getAccountList();
    expect(accountsAfter.length, 1,
        reason: 'rewrite in place — exactly one row, no duplicate');
    expect(accountsAfter.any((a) => a['toxId'] == shortToxId), isFalse,
        reason: 'the 64-char row must be gone, not left behind');

    // Idempotent: the next login reads the now-canonical id from account_list
    // and calls backfill again — must be a no-op (no duplicate rows, stable
    // pointer).
    final result2 = await ShortToxIdBackfill.backfillIfNeeded(
      service: service,
      persistedToxId: canonical,
    );
    expect(result2, canonical);
    final accounts = await Prefs.getAccountList();
    expect(accounts.where((a) => a['toxId'] == canonical).length, 1,
        reason: 'no duplicate account_list rows after a repeated backfill');
    expect(await Prefs.getCurrentAccountToxId(), canonical);
  }, skip: skipReason);

  // SECURITY REGRESSION GUARD — the crash/outage window in the 64 -> 76 rewrite.
  //
  // The rewrite touches two stores that cannot be updated atomically: the
  // `account_list` row and the credential keys. Whichever survives alone, the
  // account must stay verifiable.
  //
  // Moving the credentials FIRST was unsafe: it left the verifier at the 76-char
  // id while the row still said 64, and 76 cannot be derived from 64 (nospam and
  // checksum are gone), so the next login looked up an empty namespace and the
  // account read as UNPROTECTED. The row now moves first, leaving the derivable
  // mismatch, and `PasswordVerifier` resolves the 64-char public-key alias.
  test(
      'a credential-store outage during the rewrite leaves the account still '
      'protected and still verifiable (via the public-key alias)', () async {
    final canonical = 'B' * 76;
    final shortToxId = canonical.substring(0, 64);
    final service = _StubFfiChatService(canonical);
    addTearDown(() async {
      try {
        await service.dispose();
      } catch (_) {}
    });

    await Prefs.addAccount(toxId: shortToxId, nickname: 'Imported');
    await Prefs.setCurrentAccountToxId(shortToxId);
    expect(await Prefs.setAccountPassword(shortToxId, 'pw'), isTrue,
        reason: 'precondition: a verifier exists under the short id');

    // The keychain goes away mid-rewrite (a locked store, a lost entitlement).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);

    final result = await ShortToxIdBackfill.backfillIfNeeded(
      service: service,
      persistedToxId: shortToxId,
    );

    // The row advanced; the credentials did not. That is the SAFE direction.
    expect(result, canonical);
    final accounts = await Prefs.getAccountList();
    expect(accounts.single['toxId'], canonical);

    // The outage passes. The account must resolve again — without this the user
    // would be locked out of a password they still know.
    restoreSecureStorageMock();

    expect(await Prefs.accountProtectionState(canonical),
        AccountProtectionState.protected,
        reason: 'the verifier is found under the 64-char public-key alias, so '
            'the auto-login gate still demands a password');
    expect(await Prefs.verifyAccountPassword(canonical, 'pw'), isTrue,
        reason: 'and the password the user knows still verifies end to end');
    expect(await Prefs.verifyAccountPassword(canonical, 'wrong'), isFalse,
        reason: 'the alias path must not weaken verification');
  }, skip: skipReason);
}
