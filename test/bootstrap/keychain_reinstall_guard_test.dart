// P3 (doc/reference/MOBILE_DEVICE_FEATURES.md): an iOS reinstall keeps the old
// installation's Keychain items. The guard wipes them on the first launch of a
// FRESH installation, never touches an installation that has accounts or
// profiles, and retries a refused wipe without ever deleting what a registered
// account or an on-disk profile owns.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/bootstrap/keychain_reinstall_guard.dart';

const _alice =
    'AB12CD34EF56AB12CD34EF56AB12CD34EF56AB12CD34EF56AB12CD34EF56AB12'
    '0123456789AB';
const _bob =
    '42602EDA5DBB10CEC132E5FE0D69DA5F59F9CCC434D6D26233FE3DEDD72F2127';

class _FakeKeychain implements KeychainMaintenance {
  _FakeKeychain(this.keys);

  final Set<String> keys;
  bool refuse = false;
  int wipes = 0;

  @override
  Future<bool> wipeAll() async {
    wipes++;
    if (refuse) return false;
    keys.clear();
    return true;
  }

  @override
  Future<List<String>> listKeys() async {
    if (refuse) throw StateError('locked');
    return keys.toList();
  }

  @override
  Future<bool> deleteKeys(List<String> toDelete) async {
    if (refuse) return false;
    keys.removeAll(toDelete);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  String registry(List<String> ids) =>
      '[${ids.map((id) => '{"toxId":"$id","nickname":"n"}').join(',')}]';

  Future<void> run(
    SharedPreferences prefs,
    _FakeKeychain keychain, {
    Set<String> profiles = const {},
    bool isIOS = true,
  }) => KeychainReinstallGuard.run(
    prefs,
    isIOS: isIOS,
    keychain: keychain,
    profilePrefixes: () async => profiles,
  );

  String? marker(SharedPreferences prefs) =>
      prefs.getString(KeychainReinstallGuard.markerKey);

  test('fresh installation: wipes everything, once', () async {
    final prefs = await prefsWith({});
    final keychain = _FakeKeychain({'pwd_$_bob', 'pwd_salt_$_bob', 'x'});
    await run(prefs, keychain);
    expect(keychain.keys, isEmpty);
    expect(marker(prefs), 'done');

    keychain.keys.add('pwd_new');
    await run(prefs, keychain);
    expect(keychain.wipes, 1);
    expect(keychain.keys, {'pwd_new'});
  });

  test('an empty registry list with no profiles is fresh', () async {
    final prefs = await prefsWith({'account_list': '[]'});
    final keychain = _FakeKeychain({'pwd_$_bob'});
    await run(prefs, keychain);
    expect(keychain.keys, isEmpty);
  });

  test('upgrade with accounts: sweeps only orphans, keeps owned + unknown',
      () async {
    // Install A with a password, uninstall, reinstall an OLDER build, create
    // B, upgrade to this build: A's verifier is an orphan and must go.
    final prefs = await prefsWith({'account_list': registry([_alice])});
    final keychain = _FakeKeychain({'pwd_$_alice', 'pwd_$_bob', 'other'});
    await run(prefs, keychain);
    expect(keychain.keys, {'pwd_$_alice', 'other'});
    expect(keychain.wipes, 0);
    expect(marker(prefs), 'done');
  });

  test('profiles on disk without registry rows: their items are kept',
      () async {
    // AccountReconciliation recovers such profiles later in startup; their
    // verifiers must still be there.
    final prefs = await prefsWith({});
    final keychain = _FakeKeychain({'pwd_$_bob'});
    await run(prefs, keychain, profiles: {'42602EDA5DBB10CE'});
    expect(keychain.keys, {'pwd_$_bob'});
    expect(marker(prefs), 'done');
  });

  test('a preserved corrupt registry: nothing deleted, stays pending',
      () async {
    final prefs = await prefsWith({'account_list_corrupt_backup': '{oops'});
    final keychain = _FakeKeychain({'pwd_$_bob'});
    await run(prefs, keychain);
    expect(keychain.keys, {'pwd_$_bob'});
    expect(marker(prefs), 'pending');
  });

  test('a refused wipe stays pending and retries while still fresh', () async {
    final prefs = await prefsWith({});
    final keychain = _FakeKeychain({'pwd_$_bob'})..refuse = true;
    await run(prefs, keychain);
    expect(marker(prefs), 'pending');
    expect(keychain.keys, {'pwd_$_bob'});

    keychain.refuse = false;
    await run(prefs, keychain);
    expect(keychain.keys, isEmpty);
    expect(marker(prefs), 'done');
  });

  test('pending retry after accounts appeared deletes only orphans', () async {
    final prefs = await prefsWith({});
    final keychain = _FakeKeychain({
      'pwd_$_bob',
      'pwd_salt_$_bob',
      'irc_channel_password_#toxee_42602EDA5DBB10CE',
      'unknown_key',
    })..refuse = true;
    await run(prefs, keychain);
    expect(marker(prefs), 'pending');

    // Meanwhile the user registered Alice (and set a password).
    await prefs.setString('account_list', registry([_alice]));
    keychain.keys.addAll({
      'pwd_$_alice',
      'pwd_salt_$_alice',
      'irc_channel_password_#chan_with_underscores_${_alice.substring(0, 16)}',
    });
    keychain.refuse = false;
    await run(prefs, keychain);

    expect(keychain.keys, {
      'pwd_$_alice',
      'pwd_salt_$_alice',
      'irc_channel_password_#chan_with_underscores_${_alice.substring(0, 16)}',
      'unknown_key',
    });
    expect(marker(prefs), 'done');
  });

  test('ownership: 64-char alias and profile-only owners count', () {
    final owners = {_alice.substring(0, 16).toUpperCase()};
    expect(
      KeychainReinstallGuard.isOrphanForTest(
        'pwd_${_alice.substring(0, 64).toLowerCase()}',
        owners,
      ),
      isFalse,
    );
    expect(KeychainReinstallGuard.isOrphanForTest('pwd_$_bob', owners), isTrue);
    expect(
      KeychainReinstallGuard.isOrphanForTest('irc_channel_password_x', owners),
      isFalse,
      reason: 'unscoped key: owner unknown, keep',
    );
  });

  test('not iOS: no-op', () async {
    final prefs = await prefsWith({});
    final keychain = _FakeKeychain({'pwd_$_bob'});
    await run(prefs, keychain, isIOS: false);
    expect(keychain.keys, {'pwd_$_bob'});
    expect(marker(prefs), isNull);
  });

  test('a current-account pointer without a registry row is not fresh',
      () async {
    // A crash between writing the pointer and the registry row.
    final prefs = await prefsWith({'current_account_tox_id': _bob});
    final keychain = _FakeKeychain({'pwd_$_bob'});
    await run(prefs, keychain);
    expect(keychain.keys, {'pwd_$_bob'});
    expect(marker(prefs), 'done');
  });
}
