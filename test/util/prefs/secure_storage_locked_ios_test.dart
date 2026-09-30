// B9 (doc/reference/MOBILE_DEVICE_FEATURES.md): on a locked iPhone,
// flutter_secure_storage 9.2.4 reports an existing but unreadable Keychain
// item as "no value" (it retries the read with kSecAttrSynchronizable=true
// and returns that "not found"). The auto-login gate must not read that as
// "this account has no password": absence counts only when the Keychain
// itself says the item does not exist.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/prefs/password_verifier.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  FlutterSecureStorageFacade facade(
    String? probeAnswer, {
    bool isIOS = true,
    List<String>? probed,
    bool probeThrows = false,
  }) => FlutterSecureStorageFacade(
    const FlutterSecureStorage(),
    isIOS: isIOS,
    existenceProbe: (key) async {
      probed?.add(key);
      if (probeThrows) throw StateError('no channel');
      return probeAnswer;
    },
  );

  test('locked iPhone: an existing item that reads as empty is unavailable', () async {
    final outcome = await facade('found').readOutcome('pwd_ACCOUNT');
    expect(outcome.unavailable, isTrue);
  });

  test('only a Keychain "missing" is absence', () async {
    final outcome = await facade('missing').readOutcome('pwd_ACCOUNT');
    expect(outcome.unavailable, isFalse);
    expect(outcome.hasValue, isFalse);
  });

  test('a Keychain error or no probe answer is unavailable', () async {
    expect((await facade('error:-25308').readOutcome('k')).unavailable, isTrue);
    expect((await facade(null).readOutcome('k')).unavailable, isTrue);
    expect(
      (await facade('missing', probeThrows: true).readOutcome('k')).unavailable,
      isTrue,
    );
  });

  test('a value, or any other platform, needs no probe', () async {
    final probed = <String>[];
    FlutterSecureStorage.setMockInitialValues({'k': 'v'});
    expect((await facade('found', probed: probed).readOutcome('k')).value, 'v');
    FlutterSecureStorage.setMockInitialValues({});
    final android = await facade('found', isIOS: false, probed: probed)
        .readOutcome('k');
    expect(android.unavailable, isFalse);
    expect(probed, isEmpty);
  });

  test('a verifier still under the 64-char alias also fails closed', () async {
    final address = 'A' * 76;
    final alias = 'A' * 64;
    final locked = PasswordVerifier(
      secureStorage: FlutterSecureStorageFacade(
        const FlutterSecureStorage(),
        isIOS: true,
        // Only the alias item exists (unreadable while locked).
        existenceProbe: (key) async =>
            key == PasswordVerifier.secureHashKey(alias) ? 'found' : 'missing',
      ),
      legacyStore: _NoLegacy(),
    );
    expect(
      await locked.protectionState(address),
      AccountProtectionState.unknown,
    );
  });

  test('the password gate fails closed on a locked iPhone', () async {
    final locked = PasswordVerifier(
      secureStorage: facade('found'),
      legacyStore: _NoLegacy(),
    );
    expect(
      await locked.protectionState('ACCOUNT'),
      isNot(AccountProtectionState.none),
      reason: 'auto-login must not open a protected account while locked',
    );
    expect(await locked.hasPassword('ACCOUNT'), isTrue);

    final unprotected = PasswordVerifier(
      secureStorage: facade('missing'),
      legacyStore: _NoLegacy(),
    );
    expect(
      await unprotected.protectionState('ACCOUNT'),
      AccountProtectionState.none,
      reason: 'an account without a password still auto-logs-in while locked',
    );
  });
}
