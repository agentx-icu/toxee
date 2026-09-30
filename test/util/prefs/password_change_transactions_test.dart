// The journaled password change: what the gate reports, what verifies, and
// how an interrupted change is finished or abandoned at the next login.

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/prefs/password_change_transactions.dart';
import 'package:toxee/util/prefs/password_verifier.dart';

class _MemorySecureStorage extends SecureStorageFacade {
  final Map<String, String> entries = {};
  bool unavailable = false;
  final Set<String> undeletable = {};

  @override
  Future<String?> read(String key) async => entries[key];

  @override
  Future<SecureStorageReadOutcome> readOutcome(String key) async =>
      unavailable
          ? const SecureStorageReadOutcome.unavailable()
          : SecureStorageReadOutcome.answered(entries[key]);

  @override
  Future<bool> write(String key, String value) async {
    entries[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    if (undeletable.contains(key)) return false;
    entries.remove(key);
    return true;
  }
}

class _NoLegacy implements LegacyPasswordStore {
  @override
  Future<String?> readLegacyHash(String toxId) async => null;
  @override
  Future<String?> readLegacySalt(String toxId) async => null;
  @override
  Future<void> removeLegacyHash(String toxId) async {}
  @override
  Future<void> removeLegacySalt(String toxId) async {}
}

void main() {
  final toxId = 'A' * 76;
  late _MemorySecureStorage storage;
  late PasswordVerifier verifier;
  late PasswordChangeTransactions tx;

  setUp(() {
    storage = _MemorySecureStorage();
    verifier = PasswordVerifier(secureStorage: storage, legacyStore: _NoLegacy());
    tx = PasswordChangeTransactions(
      verifier: verifier,
      journal: PasswordChangeJournal(storage),
    );
  });

  group('set / change', () {
    test('a staged set keeps the gate closed and accepts the new password',
        () async {
      await verifier.setPassword(toxId, 'old');
      expect(await tx.beginSet(toxId, 'new'), isTrue);
      expect(await tx.protectionState(toxId), AccountProtectionState.protected);
      expect(await tx.verifyPassword(toxId, 'old'), isTrue);
      expect(await tx.verifyPassword(toxId, 'new'), isTrue,
          reason: 'the file may already carry the recorded password');
      expect(await tx.verifyPassword(toxId, 'other'), isFalse);
    });

    test('promote needs proof: refused while staged, accepted once rekeyed',
        () async {
      await verifier.setPassword(toxId, 'old');
      await tx.beginSet(toxId, 'new');
      expect(await tx.promoteSet(toxId), isFalse);
      expect(await verifier.verifyPassword(toxId, 'old'), isTrue);
      expect(await tx.markRekeyed(toxId), isTrue);
      expect(await tx.promoteSet(toxId), isTrue);
      expect((await tx.pending(toxId)).record, isNull);
      expect(await verifier.verifyPassword(toxId, 'new'), isTrue);
      expect(await verifier.verifyPassword(toxId, 'old'), isFalse);
    });

    test('login with the OLD password after a staged set abandons the record',
        () async {
      await verifier.setPassword(toxId, 'old');
      await tx.beginSet(toxId, 'new');
      final result = await tx.reconcileAfterLogin(
        toxId,
        'old',
        rekeyLive: (_) async => fail('no re-key for an abandoned set'),
      );
      expect(result, PasswordChangeReconcile.abandoned);
      expect((await tx.pending(toxId)).record, isNull);
      expect(await verifier.verifyPassword(toxId, 'old'), isTrue);
    });

    test('login with the NEW password promotes it whatever the phase says',
        () async {
      await verifier.setPassword(toxId, 'old');
      await tx.beginSet(toxId, 'new'); // killed before the phase write
      final result = await tx.reconcileAfterLogin(
        toxId,
        'new',
        rekeyLive: (_) async => fail('no re-key needed'),
      );
      expect(result, PasswordChangeReconcile.promoted);
      expect(await verifier.verifyPassword(toxId, 'new'), isTrue);
      expect(await verifier.verifyPassword(toxId, 'old'), isFalse);
      expect((await tx.pending(toxId)).record, isNull);
    });

    test('a first-time set with no primary verifier still gates', () async {
      await tx.beginSet(toxId, 'first');
      expect(await tx.protectionState(toxId), AccountProtectionState.protected);
      expect(await tx.verifyPassword(toxId, 'first'), isTrue);
    });
  });

  group('remove', () {
    test('staged removal stays protected; rekeyed is closed until reconciled',
        () async {
      await verifier.setPassword(toxId, 'pw');
      await tx.beginRemove(toxId);
      expect(await tx.protectionState(toxId), AccountProtectionState.protected);
      await tx.markRekeyed(toxId);
      expect(await tx.protectionState(toxId), AccountProtectionState.unknown);
      await tx.reconcileForGate(toxId);
      expect(await tx.protectionState(toxId), AccountProtectionState.none);
      expect((await tx.pending(toxId)).record, isNull);
    });

    test('a verifier source that cannot be deleted keeps the gate closed',
        () async {
      await verifier.setPassword(toxId, 'pw');
      await tx.beginRemove(toxId);
      await tx.markRekeyed(toxId);
      storage.undeletable.add(PasswordVerifier.secureSaltKey(toxId));
      await tx.reconcileForGate(toxId);
      expect(await tx.protectionState(toxId), AccountProtectionState.unknown);
      expect((await tx.pending(toxId)).record?.kind, PasswordChangeKind.remove);
      storage.undeletable.clear();
      await tx.reconcileForGate(toxId);
      expect(await tx.protectionState(toxId), AccountProtectionState.none);
    });

    test('login after a staged removal completes it through the live re-key',
        () async {
      await verifier.setPassword(toxId, 'pw');
      await tx.beginRemove(toxId);
      final rekeys = <String?>[];
      final result = await tx.reconcileAfterLogin(
        toxId,
        'pw',
        rekeyLive: (p) async {
          rekeys.add(p);
          return true;
        },
      );
      expect(result, PasswordChangeReconcile.removalCompleted);
      expect(rekeys, [null]);
      expect(await tx.protectionState(toxId), AccountProtectionState.none);
    });
  });

  group('fail closed', () {
    test('an unreadable journal reports unknown', () async {
      await verifier.setPassword(toxId, 'pw');
      storage.unavailable = true;
      expect(await tx.protectionState(toxId), AccountProtectionState.unknown);
    });

    test('a record this build cannot parse reports unknown', () async {
      storage.entries[PasswordChangeJournal.key(toxId)] = '{"kind":"???"}';
      expect(await tx.protectionState(toxId), AccountProtectionState.unknown);
      expect((await tx.pending(toxId)).unavailable, isTrue);
    });

    test('removePassword is strict: a swallowed alias delete is a failure',
        () async {
      final alias = 'A' * 64;
      await verifier.setPassword(toxId, 'pw');
      storage.entries[PasswordVerifier.secureHashKey(alias)] = 'stale';
      storage.undeletable.add(PasswordVerifier.secureHashKey(alias));
      expect(await verifier.removePassword(toxId), isFalse);
      storage.undeletable.clear();
      expect(await verifier.removePassword(toxId), isTrue);
      expect(storage.entries.containsKey(PasswordVerifier.secureHashKey(alias)),
          isFalse);
    });
  });
}
