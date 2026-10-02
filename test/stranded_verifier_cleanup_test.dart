// A failed registration whose verifier delete secure storage refuses must not
// strand that verifier forever: the rollback records the Tox ID and the
// startup retry (StrandedVerifierCleanup.retryPending) removes it once the
// store cooperates. Same in-memory flutter_secure_storage mock as
// test/account_password_change_concurrency_test.dart, plus a switch that makes
// deletes fail the way a refusing Keychain / Keystore does (PlatformException,
// which the facade reports as `false`).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/account_registration_rollback.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/session_password_store.dart';
import 'package:toxee/util/stranded_verifier_cleanup.dart';

const _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789'
    '0123456789AB';
const _otherToxId =
    '1111111111111111111111111111111111111111111111111111111111111111'
    '22222222BBBB';

AccountRegistrationRollbackPlan _planWithVerifier(String toxId) =>
    AccountRegistrationRollbackPlan(
      service: null,
      toxId: toxId,
      tempDir: null,
      finalDir: null,
      ownsFinalDir: false,
      ownedDataRoots: const [],
      accountVisible: false,
      verifierWritten: true,
      previousAccount: null,
      previousNickname: null,
      previousStatusMessage: null,
      previousAvatarPath: null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};
  var failSecureDeletes = false;
  // Key-selective refusals: a journal-only refused delete, or a refused
  // salt write that leaves a partial verifier pair behind.
  bool Function(String key) failDeleteFor = (_) => false;
  bool Function(String key) failWriteFor = (_) => false;

  setUp(() async {
    secureStore.clear();
    failSecureDeletes = false;
    failDeleteFor = (_) => false;
    failWriteFor = (_) => false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (MethodCall call) async {
      final args =
          (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      switch (call.method) {
        case 'write':
          if (failWriteFor(args['key'] as String)) {
            throw PlatformException(code: 'secure-write-failed');
          }
          secureStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args['key'] as String];
        case 'delete':
          if (failSecureDeletes || failDeleteFor(args['key'] as String)) {
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
  });

  tearDown(() {
    SessionPasswordStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  test('a refused verifier delete is recorded by the rollback and removed by '
      'the startup retry once the store cooperates', () async {
    expect(await Prefs.setAccountPassword(_toxId, 'pw'), isTrue);
    expect(await Prefs.hasAccountPassword(_toxId), isTrue);

    failSecureDeletes = true;
    await rollbackFailedRegistration(_planWithVerifier(_toxId));
    expect(await Prefs.hasAccountPassword(_toxId), isTrue,
        reason: 'the store refused: the verifier is still there');
    expect(await StrandedVerifierCleanup.pending(), {_toxId},
        reason: 'the rollback recorded the stranded identity');

    failSecureDeletes = false;
    expect(await StrandedVerifierCleanup.retryPending(), 1);
    expect(await Prefs.hasAccountPassword(_toxId), isFalse,
        reason: 'the retry removed the verifier');
    expect(await StrandedVerifierCleanup.pending(), isEmpty,
        reason: 'the record is cleared on success');
    expect((await SharedPreferences.getInstance())
        .containsKey(StrandedVerifierCleanup.prefsKey), isFalse);
  });

  test('a successful rollback delete records nothing', () async {
    expect(await Prefs.setAccountPassword(_toxId, 'pw'), isTrue);
    await rollbackFailedRegistration(_planWithVerifier(_toxId));
    expect(await Prefs.hasAccountPassword(_toxId), isFalse);
    expect(await StrandedVerifierCleanup.pending(), isEmpty);
  });

  test('the retry keeps the record while secure storage still refuses',
      () async {
    expect(await Prefs.setAccountPassword(_toxId, 'pw'), isTrue);
    failSecureDeletes = true;
    await rollbackFailedRegistration(_planWithVerifier(_toxId));
    expect(await StrandedVerifierCleanup.pending(), {_toxId});

    expect(await StrandedVerifierCleanup.retryPending(), 0);
    expect(await StrandedVerifierCleanup.pending(), {_toxId},
        reason: 'still owed: retried on the next start');
    expect(await Prefs.hasAccountPassword(_toxId), isTrue);
  });

  test('record is idempotent and ignores an empty id', () async {
    await StrandedVerifierCleanup.record(_toxId);
    await StrandedVerifierCleanup.record(' $_toxId ');
    await StrandedVerifierCleanup.record('');
    await StrandedVerifierCleanup.record(_otherToxId);
    expect(await StrandedVerifierCleanup.pending(), {_toxId, _otherToxId});
  });

  test('the retry never revokes the verifier of a published account',
      () async {
    // Defensive: a recorded id that is in account_list is a live identity,
    // whatever the record says. Its verifier stays; the record is dropped.
    expect(await Prefs.setAccountPassword(_toxId, 'pw'), isTrue);
    await Prefs.addAccount(toxId: _toxId, nickname: 'Live');
    await StrandedVerifierCleanup.record(_toxId);
    // A genuinely stranded one in the same pass is still cleaned up.
    expect(await Prefs.setAccountPassword(_otherToxId, 'pw2'), isTrue);
    await StrandedVerifierCleanup.record(_otherToxId);

    expect(await StrandedVerifierCleanup.retryPending(), 1);
    expect(await Prefs.hasAccountPassword(_toxId), isTrue,
        reason: 'the published account keeps its password gate');
    expect(await Prefs.hasAccountPassword(_otherToxId), isFalse);
    expect(await StrandedVerifierCleanup.pending(), isEmpty);
  });

  test('a journal-only refused delete is recorded and retried too', () async {
    expect(await Prefs.setAccountPassword(_toxId, 'pw'), isTrue);
    // A registration-time journal record under this identity, as an
    // interrupted password transaction would leave.
    secureStore['pwd_txn_$_toxId'] = '{"kind":"set"}';
    failDeleteFor = (key) => key.startsWith('pwd_txn_');
    await rollbackFailedRegistration(_planWithVerifier(_toxId));
    expect(secureStore.containsKey('pwd_$_toxId'), isFalse,
        reason: 'the verifier delete itself went through');
    expect(secureStore.containsKey('pwd_txn_$_toxId'), isTrue);
    expect(await Prefs.hasAccountPassword(_toxId), isTrue,
        reason: 'fail-closed: a journal record alone keeps the gate up, '
            'which is exactly why the residue must be retried');
    expect(await StrandedVerifierCleanup.pending(), {_toxId});

    failDeleteFor = (_) => false;
    expect(await StrandedVerifierCleanup.retryPending(), 1);
    expect(secureStore.containsKey('pwd_txn_$_toxId'), isFalse);
    expect(await Prefs.hasAccountPassword(_toxId), isFalse);
    expect(await StrandedVerifierCleanup.pending(), isEmpty);
  });

  test('a partial verifier write (hash persisted, salt + compensating delete '
      'refused) is residue the rollback removes', () async {
    // Mirrors registerNewAccount: verifierWritten is flagged BEFORE the
    // attempt, so a false return from setAccountPassword still reaches the
    // rollback's removal.
    failWriteFor = (key) => key.startsWith('pwd_salt_');
    failSecureDeletes = true;
    expect(await Prefs.setAccountPassword(_toxId, 'pw'), isFalse);
    expect(secureStore.containsKey('pwd_$_toxId'), isTrue,
        reason: 'precondition: the hash half is stranded');

    await rollbackFailedRegistration(_planWithVerifier(_toxId));
    expect(await StrandedVerifierCleanup.pending(), {_toxId},
        reason: 'deletes still refused: recorded for the startup retry');

    failSecureDeletes = false;
    expect(await StrandedVerifierCleanup.retryPending(), 1);
    expect(secureStore.keys.where((k) => k.contains(_toxId)), isEmpty,
        reason: 'no half of the pair survives');
  });

  test('the retry survives a Prefs re-initialisation (durable record)',
      () async {
    await StrandedVerifierCleanup.record(_toxId);
    // A later start re-reads SharedPreferences; the record must come back.
    await Prefs.initialize(await SharedPreferences.getInstance());
    expect(await StrandedVerifierCleanup.pending(), {_toxId});
  });

  group('registry presence is never decided from a lossy decode', () {
    test('a row the decoder drops still counts as published', () async {
      expect(await Prefs.setAccountPassword(_toxId, 'pw'), isTrue);
      await StrandedVerifierCleanup.record(_toxId);
      // Valid toxId, non-string metadata: `_readAccountList` drops this row,
      // so a typed lookup would wrongly report the account absent.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'account_list', '[{"toxId":"$_toxId","nickname":5}]');
      expect(await Prefs.getAccountByToxId(_toxId), isNull,
          reason: 'precondition: the typed lookup cannot see the row');
      expect(await Prefs.accountRegistryPresence(_toxId),
          AccountRegistryPresence.present);

      expect(await StrandedVerifierCleanup.retryPending(), 0);
      expect(await Prefs.hasAccountPassword(_toxId), isTrue,
          reason: 'the published account keeps its password gate');
      expect(await StrandedVerifierCleanup.pending(), isEmpty,
          reason: 'a published identity is not a stranded registration');
    });

    test('an identity stored with JSON escapes or in a legacy short form '
        'still counts as published', () async {
      final prefs = await SharedPreferences.getInstance();
      // `\u0041` decodes to `A`: a raw-substring probe would miss it.
      final escaped = _toxId.replaceAll('A', r'\u0041');
      await prefs.setString(
          'account_list', '[{"toxId":"$escaped","nickname":"x"}]');
      expect(await Prefs.accountRegistryPresence(_toxId),
          AccountRegistryPresence.present);
      // 16-char legacy registry id (the on-disk `p_<first16>` form).
      await prefs.setString('account_list',
          '[{"toxId":"${_toxId.substring(0, 16)}","nickname":"x"}]');
      expect(await Prefs.accountRegistryPresence(_toxId),
          AccountRegistryPresence.present);
      // 64-char public key for a 76-char query and vice versa.
      await prefs.setString('account_list',
          '[{"toxId":"${_toxId.substring(0, 64).toLowerCase()}"}]');
      expect(await Prefs.accountRegistryPresence(_toxId),
          AccountRegistryPresence.present);
      await prefs.setString('account_list', '[{"toxId":"$_toxId"}]');
      expect(await Prefs.accountRegistryPresence(_toxId.substring(0, 64)),
          AccountRegistryPresence.present);
    });

    test('a changed nospam / checksum suffix is the same identity, and an '
        'alias-only verifier survives the retry', () async {
      // The 64-char public key is the identity; the 76-char address can change
      // its nospam + checksum suffix. The verifier alias is keyed by public key
      // and can be the ONLY verifier after an interrupted backfill, so a stale
      // record under the old address must not reach removeAccountPassword.
      final newAddress = '${_toxId.substring(0, 64)}FFFFFFFF0000';
      expect(newAddress, isNot(_toxId));
      await Prefs.addAccount(toxId: newAddress, nickname: 'Renospammed');
      expect(await Prefs.accountRegistryPresence(_toxId),
          AccountRegistryPresence.present);
      // Alias-only credentials under the public key.
      secureStore['pwd_${_toxId.substring(0, 64)}'] = 'hash';
      secureStore['pwd_salt_${_toxId.substring(0, 64)}'] = 'salt';
      await StrandedVerifierCleanup.record(_toxId);

      expect(await StrandedVerifierCleanup.retryPending(), 0);
      expect(secureStore.containsKey('pwd_${_toxId.substring(0, 64)}'), isTrue,
          reason: 'the shared alias is the live account\'s only verifier');
      expect(await StrandedVerifierCleanup.pending(), isEmpty,
          reason: 'a published identity is not a stranded registration');
    });

    test('a row whose identity cannot be read defers the removal', () async {
      expect(await Prefs.setAccountPassword(_toxId, 'pw'), isTrue);
      await StrandedVerifierCleanup.record(_toxId);
      final prefs = await SharedPreferences.getInstance();
      for (final payload in [
        '[{"toxId":12345,"nickname":"x"}]',
        '["not a row", {"toxId":"$_otherToxId"}]',
        '{"toxId":"$_otherToxId"}',
      ]) {
        await prefs.setString('account_list', payload);
        expect(await Prefs.accountRegistryPresence(_toxId),
            AccountRegistryPresence.unknown,
            reason: payload);
        expect(await StrandedVerifierCleanup.retryPending(), 0,
            reason: payload);
        expect(await Prefs.hasAccountPassword(_toxId), isTrue,
            reason: payload);
        expect(await StrandedVerifierCleanup.pending(), {_toxId},
            reason: payload);
      }
    });

    test('an undecodable registry defers the removal', () async {
      expect(await Prefs.setAccountPassword(_toxId, 'pw'), isTrue);
      await StrandedVerifierCleanup.record(_toxId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account_list', '{not json');
      expect(await Prefs.accountRegistryPresence(_toxId),
          AccountRegistryPresence.unknown);

      expect(await StrandedVerifierCleanup.retryPending(), 0);
      expect(await Prefs.hasAccountPassword(_toxId), isTrue);
      expect(await StrandedVerifierCleanup.pending(), {_toxId},
          reason: 'absence was not proven: kept for a later start');
    });

    test('an empty or clean registry proves absence', () async {
      expect(await Prefs.accountRegistryPresence(_toxId),
          AccountRegistryPresence.absent);
      await Prefs.addAccount(toxId: _otherToxId, nickname: 'Other');
      expect(await Prefs.accountRegistryPresence(_toxId),
          AccountRegistryPresence.absent);
      expect(await Prefs.accountRegistryPresence(_otherToxId.toLowerCase()),
          AccountRegistryPresence.present,
          reason: 'matched by public key, case-insensitively');
      expect(await Prefs.accountRegistryPresence(''),
          AccountRegistryPresence.unknown);
    });
  });

}
