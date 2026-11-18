import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:toxee/util/prefs.dart';

const _registryKey = 'flutter.account_list';
const _backupKey = 'flutter.account_list_corrupt_backup';
const _firstId =
    'A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1';
const _secondId =
    'B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_RefusingRegistryStore> setUpPrefs(String rawRegistry) async {
    final original = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);
    SharedPreferences.setMockInitialValues({});
    final store = _RefusingRegistryStore({_registryKey: rawRegistry});
    SharedPreferencesStorePlatform.instance = store;
    await Prefs.initialize(await SharedPreferences.getInstance());
    return store;
  }

  test(
    'a refused registry mutation leaves reads at the durable state',
    () async {
      final store = await setUpPrefs(
        jsonEncode([
          {'toxId': _firstId},
        ]),
      );
      store.refusedKey = _registryKey;

      await expectLater(
        Prefs.addAccount(toxId: _secondId, nickname: 'Second'),
        throwsA(isA<AccountRegistryWriteException>()),
      );
      expect(await Prefs.getAccountByToxId(_secondId), isNull);
      await expectLater(Prefs.removeAccount(_firstId), throwsException);
      expect(await Prefs.getAccountByToxId(_firstId), isNotNull);

      store.refusedKey = null;
      await Prefs.addAccount(toxId: _secondId, nickname: 'Second');
      expect(await Prefs.getAccountByToxId(_secondId), isNotNull);
    },
  );

  test(
    'refusing the backup prevents rewriting a partially parsed registry',
    () async {
      final rawRegistry = jsonEncode([
        {'toxId': _firstId},
        {'toxId': _secondId, 'nickname': 10},
      ]);
      final store = await setUpPrefs(rawRegistry);
      store.refusedKey = _backupKey;

      await expectLater(
        Prefs.addAccount(toxId: _firstId, nickname: 'Renamed'),
        throwsA(isA<AccountRegistryUnreadableException>()),
      );
      expect((await store.getAll())[_registryKey], rawRegistry);
      expect((await store.getAll())[_backupKey], isNull);
    },
  );

  test(
    'a pending backup is not durable proof for a concurrent rewrite',
    () async {
      final rawRegistry = jsonEncode([
        {'toxId': _firstId},
        {'toxId': _secondId, 'nickname': 10},
      ]);
      final store = await setUpPrefs(rawRegistry);
      store.refusedKey = _backupKey;
      final backupStarted = Completer<void>();
      final finishBackup = Completer<void>();
      store.beforeBackup = () async {
        if (!backupStarted.isCompleted) backupStarted.complete();
        await finishBackup.future;
      };

      final read = Prefs.getAccountList();
      await backupStarted.future;
      final rewrite = expectLater(
        Prefs.addAccount(toxId: _firstId, nickname: 'Renamed'),
        throwsA(isA<AccountRegistryUnreadableException>()),
      );
      await Future<void>.delayed(Duration.zero);
      finishBackup.complete();

      await read;
      await rewrite;
      expect((await store.getAll())[_registryKey], rawRegistry);
    },
  );

  test('a late registry reload cannot erase a successful mutation', () async {
    final store = await setUpPrefs(
      jsonEncode([
        {'toxId': _firstId},
      ]),
    );
    store.refusedKey = _registryKey;
    await expectLater(
      Prefs.addAccount(toxId: _secondId, nickname: 'Second'),
      throwsA(isA<AccountRegistryWriteException>()),
    );
    store.refusedKey = null;

    final captured = Completer<void>();
    final release = Completer<void>();
    store.afterSnapshot = () async {
      store.afterSnapshot = null;
      captured.complete();
      await release.future;
    };
    final oldRead = Prefs.getAccountList();
    await captured.future;
    final write = Prefs.addAccount(toxId: _secondId, nickname: 'Second');
    await Future<void>.delayed(Duration.zero);
    release.complete();

    await oldRead;
    await write;
    expect(await Prefs.getAccountByToxId(_secondId), isNotNull);
  });
}

class _RefusingRegistryStore extends InMemorySharedPreferencesStore {
  _RefusingRegistryStore(super.data) : super.withData();

  String? refusedKey;
  Future<void> Function()? beforeBackup;
  Future<void> Function()? afterSnapshot;

  @override
  Future<Map<String, Object>> getAll() async {
    final snapshot = await super.getAll();
    await afterSnapshot?.call();
    return snapshot;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == _backupKey) await beforeBackup?.call();
    if (key == refusedKey) return false;
    return super.setValue(valueType, key, value);
  }
}
