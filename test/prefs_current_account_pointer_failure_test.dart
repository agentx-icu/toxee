// A refused current-account pointer write must reach the caller.
//
// `Prefs.setCurrentAccountToxId` used to log the `false` that `setString` /
// `remove` returns and carry on. Login, activation and account switch then ran
// on a LIVE account while the durable pointer still named the previous one (or
// none) — and the next cold start restored that other account, with the
// running session's history, drafts and queue attributed to it. The write now
// throws [CurrentAccountPointerFailure] so the caller rolls back.
//
// Platform-independent (shared prefs code), so this covers mobile too.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:toxee/util/prefs.dart';

const _pointerKey = 'flutter.current_account_tox_id';
const _toxIdA =
    'A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1'
    'A1A1A1A1A1A1';
const _toxIdB =
    'B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2'
    'B2B2B2B2B2B2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _WriteRefusingPrefsStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'current_account_tox_id': _toxIdA});
    store = _WriteRefusingPrefsStore(SharedPreferencesStorePlatform.instance);
    SharedPreferencesStorePlatform.instance = store;
    await Prefs.initialize(await SharedPreferences.getInstance());
    expect(await Prefs.getCurrentAccountToxId(), _toxIdA);
  });

  tearDown(() {
    SharedPreferencesStorePlatform.instance = store.inner;
  });

  /// What the next cold start would restore: the value that actually reached
  /// the store, not the one `SharedPreferences` cached optimistically.
  Future<String?> durablePointer() async {
    await (await SharedPreferences.getInstance()).reload();
    return Prefs.getCurrentAccountToxId();
  }

  test('a refused pointer write throws instead of returning', () async {
    store.refuse = true;
    await expectLater(
      Prefs.setCurrentAccountToxId(_toxIdB),
      throwsA(isA<CurrentAccountPointerFailure>()),
    );
    // The pointer still names A — which is exactly why the caller has to roll
    // back instead of running as B.
    expect(await durablePointer(), _toxIdA);
  });

  test('a refused clear throws too', () async {
    store.refuse = true;
    await expectLater(
      Prefs.setCurrentAccountToxId(null),
      throwsA(isA<CurrentAccountPointerFailure>()),
    );
    expect(await durablePointer(), _toxIdA);
  });

  test('an accepted write still updates the pointer and the cache', () async {
    await Prefs.setCurrentAccountToxId(_toxIdB);
    expect(await Prefs.getCurrentAccountToxId(), _toxIdB);
  });
}

/// A store that can drop writes to the current-account pointer, which is what
/// a full disk / a locked keystore / a revoked profile looks like to
/// `SharedPreferences`: the platform call returns false and the in-process
/// cache has already been updated.
class _WriteRefusingPrefsStore extends SharedPreferencesStorePlatform {
  _WriteRefusingPrefsStore(this.inner);

  final SharedPreferencesStorePlatform inner;
  bool refuse = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (refuse && key == _pointerKey) return false;
    return inner.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (refuse && key == _pointerKey) return false;
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
