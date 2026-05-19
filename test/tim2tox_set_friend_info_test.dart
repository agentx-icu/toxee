// Regression test for tim2tox `Tim2ToxSdkPlatform.setFriendInfo`.
//
// S9 from the 2026-05-18 local-storage review: `setFriendInfo` returned
// `code: 0 "success"` without persisting anything. The UIKit profile-page
// "set friend remark" silently failed.
//
// The fix routes `friendRemark` through the typed
// `ExtendedPreferencesService.setFriendRemark` so the host adapter applies
// its per-account scoping (toxee scopes by current Tox-ID prefix); the same
// scope is read back in `fakeUserToV2TimFriendInfo` so the alias becomes
// visible across the contact list, search, and chat headers — not just the
// editing UI's ephemeral state.
//
// `friendCustomInfo` has no place to land in the current
// `ExtendedPreferencesService` interface and is intentionally a TODO; this
// test confirms the remark side now persists.
//
// FFI dependency: `Tim2ToxSdkPlatform`'s constructor requires a real
// `FfiChatService`, which opens the tim2tox FFI library. Skipped when the
// library is not loadable in this environment.

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/interfaces/extended_preferences_service.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

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
  final skipReason = ffiAvailable
      ? null
      : 'tim2tox FFI library not loadable in this environment';

  group('Tim2ToxSdkPlatform.setFriendInfo', skip: skipReason, () {
    late _InMemoryPrefs prefs;
    late FfiChatService ffi;
    late Tim2ToxSdkPlatform platform;

    setUp(() {
      prefs = _InMemoryPrefs();
      ffi = FfiChatService(preferencesService: prefs);
      platform = Tim2ToxSdkPlatform(
        ffiService: ffi,
        preferencesService: prefs,
      );
    });

    test('persists friendRemark via the typed setFriendRemark API', () async {
      const userID = 'peer-alice';
      const remark = 'Alice (from work)';

      final cb = await platform.setFriendInfo(
        userID: userID,
        friendRemark: remark,
      );
      expect(cb.code, 0);

      // Read back via the same typed API the converter uses, so this test
      // does not depend on the host adapter's internal key shape. What
      // matters is that the round-trip (setFriendInfo → getFriendRemark)
      // returns the value — that's what makes the alias visible to the
      // contact list and chat headers via the converter.
      final stored = await prefs.getFriendRemark(userID);
      expect(stored, remark);
    });

    test('returns success when friendRemark is null (no-op write)', () async {
      const userID = 'peer-bob';
      final cb = await platform.setFriendInfo(userID: userID);
      expect(cb.code, 0);
      expect(await prefs.getFriendRemark(userID), isNull);
    });

    test(
        'friendCustomInfo without friendRemark returns failure — caller-supplied '
        'data was dropped', () async {
      // Previously this returned code:0 "success" while silently discarding
      // the customInfo map. The fix surfaces the silent-drop as a real
      // failure when no other piece of input succeeded, so integrators
      // notice when their data is going nowhere.
      const userID = 'peer-carol';
      final cb = await platform.setFriendInfo(
        userID: userID,
        friendCustomInfo: const {'department': 'eng'},
      );
      expect(cb.code, isNot(0),
          reason: 'caller asked for customInfo to be persisted, but we '
              'have nowhere to put it — must not pretend it succeeded');
      expect(cb.desc.toLowerCase(), contains('friendcustominfo'));
    });

    test(
        'friendCustomInfo with friendRemark succeeds (remark persisted, '
        'customInfo dropped with warning)', () async {
      // The remark side is the implemented path. customInfo is still
      // dropped on the floor (TODO), but because remark persisted, the
      // overall call counts as success — the alias is the user-visible
      // half of the operation.
      const userID = 'peer-dave';
      const remark = 'Dave (sales)';
      final cb = await platform.setFriendInfo(
        userID: userID,
        friendRemark: remark,
        friendCustomInfo: const {'team': 'sales'},
      );
      expect(cb.code, 0);
      expect(await prefs.getFriendRemark(userID), remark);
    });

    test('empty-string friendRemark clears the stored remark', () async {
      // The _InMemoryPrefs adapter treats "" as a clear (matching the
      // production toxee adapter's behavior). Pin that round-trip via the
      // platform call so a future change to the prefs adapter that breaks
      // it shows up here.
      const userID = 'peer-erin';
      await prefs.setFriendRemark(userID, 'old alias');
      expect(await prefs.getFriendRemark(userID), 'old alias');

      final cb = await platform.setFriendInfo(userID: userID, friendRemark: '');
      expect(cb.code, 0);
      expect(await prefs.getFriendRemark(userID), isNull,
          reason: 'empty string should clear, not store an empty alias');
    });

    test('returns failure when the preferences adapter throws', () async {
      // If the host's setFriendRemark throws (e.g. disk full, scope
      // resolution failure), the platform must surface that as a non-zero
      // code with the error description — not silently swallow.
      final faulty = _ThrowingPrefs();
      final faultyFfi = FfiChatService(preferencesService: faulty);
      final faultyPlatform = Tim2ToxSdkPlatform(
        ffiService: faultyFfi,
        preferencesService: faulty,
      );

      final cb = await faultyPlatform.setFriendInfo(
        userID: 'peer-frank',
        friendRemark: 'will explode',
      );
      expect(cb.code, isNot(0));
      expect(cb.desc, contains('setFriendInfo failed'));
    });
  });

  group(
    'Tim2ToxSdkPlatform.setFriendInfo with no preferences service',
    skip: skipReason,
    () {
      test(
          'returns failure (not 0) when friendRemark is requested but no '
          'preferences service is wired up', () async {
        // Latent footgun: a misconfigured integration that forgot to
        // inject ExtendedPreferencesService would previously get
        // code:0 "success" back while nothing was persisted. The fix
        // returns -1 so the misconfiguration is loud.
        final ffi = FfiChatService();
        final platform = Tim2ToxSdkPlatform(ffiService: ffi);

        final cb = await platform.setFriendInfo(
          userID: 'peer-gwen',
          friendRemark: 'will be lost',
        );
        expect(cb.code, isNot(0),
            reason: 'no prefs available — must not silently drop the remark');
        expect(cb.desc.toLowerCase(), contains('preferences'));
      });
    },
  );
}

/// ExtendedPreferencesService implementation whose `setFriendRemark` throws.
/// Used to test that platform-side error handling surfaces failures.
class _ThrowingPrefs implements ExtendedPreferencesService {
  @override
  Future<void> setFriendRemark(String friendId, String? remark) {
    throw StateError('simulated prefs failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
        '_ThrowingPrefs does not implement ${invocation.memberName}');
  }
}

class _InMemoryPrefs implements ExtendedPreferencesService {
  final Map<String, Object?> _store = {};

  @override
  Future<String?> getString(String key) async => _store[key] as String?;

  @override
  Future<void> setString(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<bool?> getBool(String key) async => _store[key] as bool?;

  @override
  Future<void> setBool(String key, bool value) async {
    _store[key] = value;
  }

  @override
  Future<int?> getInt(String key) async => _store[key] as int?;

  @override
  Future<void> setInt(String key, int value) async {
    _store[key] = value;
  }

  @override
  Future<List<String>?> getStringList(String key) async =>
      _store[key] == null ? null : List<String>.from(_store[key] as List);

  @override
  Future<void> setStringList(String key, List<String> value) async {
    _store[key] = List<String>.from(value);
  }

  @override
  Future<void> remove(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }

  // Friend remark: matches the host adapter's behavior except for scoping.
  // The production toxee adapter writes under `friend_remark_<id>_<scope>`;
  // the test only cares about round-trip, so we use the bare key.
  @override
  Future<String?> getFriendRemark(String friendId) async =>
      _store['friend_remark_$friendId'] as String?;

  @override
  Future<void> setFriendRemark(String friendId, String? remark) async {
    if (remark == null || remark.isEmpty) {
      _store.remove('friend_remark_$friendId');
    } else {
      _store['friend_remark_$friendId'] = remark;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
        'InMemoryPrefs does not implement ${invocation.memberName}');
  }
}
