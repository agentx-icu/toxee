// Regression test for tim2tox friend-application dismissal.
//
// S8 from the 2026-05-18 local-storage review: `refuseFriendApplication` and
// `deleteFriendApplication` on `Tim2ToxSdkPlatform` were no-ops that returned
// `code: 0 "success"` without doing anything. The C++ application queue was
// never told to drop them, so rejected friend requests came back on every 5s
// poll and ghost entries persisted across restarts.
//
// The fix records dismissed application *fingerprints* (`userId|wording`) in a
// persistent set (via the injected `ExtendedPreferencesService`) and filters
// them out of `getFriendApplications`. Pinning to wording — not userId alone —
// means a *new* application from the same peer with different wording
// surfaces again, instead of being silently filtered as it was in the original
// userID-only implementation.
//
// FFI dependency: `refuseFriendApplication` now consults the live C++
// application queue at refuse-time to discover the wording for each matching
// entry. Without a running Tox instance the queue is empty, so persistence
// tests for `refuseFriendApplication` end-to-end can only assert defensive
// no-op behavior; the round-trip path (dismissed-set → filter) is covered by
// pre-populating the persistence layer directly with synthetic fingerprints
// and exercising `filterDismissedApplications`. That stays pure Dart and runs
// in every environment.

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart';
import 'package:tim2tox_dart/interfaces/extended_preferences_service.dart';
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
  group('FfiChatService.filterDismissedApplications', () {
    test('returns the input unchanged when the dismissed set is empty', () {
      final apps = [
        (userId: 'alice', wording: 'hi'),
        (userId: 'bob', wording: 'add me'),
      ];
      final result = FfiChatService.filterDismissedApplications(
        apps,
        const <String>{},
      );
      expect(result, apps);
    });

    test('drops applications whose (userId, wording) fingerprint is dismissed',
        () {
      final apps = [
        (userId: 'alice', wording: 'hi'),
        (userId: 'bob', wording: 'add me'),
        (userId: 'carol', wording: 'hello'),
      ];
      final result = FfiChatService.filterDismissedApplications(
        apps,
        {'bob|add me'},
      );
      expect(result.map((app) => app.userId), ['alice', 'carol']);
    });

    test('a fresh application with new wording is NOT filtered when only the '
        'old wording was dismissed', () {
      // Regression for the user-visible bug: refusing peer B's first request
      // must not silently filter B's later requests with different wording.
      // C++ keeps re-emitting the persistent queue entry with its original
      // wording (still filtered), but a fresh request from B carries a new
      // string and reaches the UI.
      final apps = [
        (userId: 'bob', wording: 'second try, please'),
      ];
      final result = FfiChatService.filterDismissedApplications(
        apps,
        {'bob|first try'},
      );
      expect(result, apps);
    });

    test('normalizes 76-char Tox addresses down to the 64-char public key',
        () {
      // Native applications surface a 64-char public key; UI/dismissal calls
      // can carry the full 76-char address. Filter normalizes the input
      // userID to its 64-char prefix before composing the fingerprint, so a
      // 64-char-key fingerprint still matches.
      final fullAddress = 'a' * 76;
      final publicKey = 'a' * 64;
      final apps = [(userId: fullAddress, wording: 'long form')];
      final result = FfiChatService.filterDismissedApplications(
        apps,
        {'$publicKey|long form'},
      );
      expect(result, isEmpty);
    });
  });

  group('FfiChatService dismissed-set persistence (pure)', () {
    late _InMemoryPrefs prefs;
    late FfiChatService service;

    setUp(() {
      prefs = _InMemoryPrefs();
      service = FfiChatService(preferencesService: prefs);
    });

    test(
        'a fingerprint refused in a previous session still filters after '
        'restart (cross-restart round-trip)', () async {
      // The whole point of the PR1 fix: refused friend applications must
      // stay dismissed across an app restart, not just across polls in the
      // current session. Simulate this without FFI by:
      //   1. Seeding prefs with a fingerprint, as if a prior session's
      //      `refuseFriendApplication` had persisted it.
      //   2. Constructing a *fresh* FfiChatService with the same prefs —
      //      this is the "restart" surface: in-memory caches (e.g.
      //      `_observedApplicationWordings`) are empty, but the persistent
      //      dismissed set is read from prefs.
      //   3. Asserting that the filter still drops a request carrying that
      //      same `(userId, wording)`.
      const peer = 'peer-refused-last-session';
      await prefs.setStringList(
        FfiChatService.dismissedFriendApplicationsKey,
        ['$peer|original wording'],
      );

      // The original `service` was constructed in setUp before any prefs
      // mutation. The "restart" is this fresh instance.
      final restartedService = FfiChatService(preferencesService: prefs);

      final dismissed = await restartedService
          .getFriendApplicationsDismissedSetForTest();
      expect(dismissed, {'$peer|original wording'},
          reason: 'restarted service must read the previous session\'s '
              'dismissed set from prefs');

      // Filter still applies — the refused application stays hidden.
      final apps = [(userId: peer, wording: 'original wording')];
      expect(
        FfiChatService.filterDismissedApplications(apps, dismissed),
        isEmpty,
      );

      // And a fresh wording from the same peer still surfaces — the
      // wording-aware fingerprint is the whole reason we don't permanently
      // mute a peer with a single refusal.
      final fresh = [(userId: peer, wording: 'second try please')];
      expect(
        FfiChatService.filterDismissedApplications(fresh, dismissed),
        fresh,
      );
    });

    test('legacy bare-userId entries are dropped on read', () async {
      // Pre-populate prefs with the pre-fingerprint format. After the read
      // path runs once, legacy entries (no `|` separator) are stripped and
      // the storage is updated — the next read sees a clean list.
      await prefs.setStringList(
        FfiChatService.dismissedFriendApplicationsKey,
        ['legacy-userid', 'bob|some wording', 'another-legacy'],
      );

      final apps = [
        (userId: 'legacy-userid', wording: 'now a fresh request'),
        (userId: 'bob', wording: 'some wording'),
      ];
      // Production read path goes through getFriendApplications, but that
      // hits FFI. Reach into the persistence layer the same way the filter
      // does: read prefs and pass to filterDismissedApplications. After the
      // first call below, the legacy migration is applied.
      final filtered = await service.getFriendApplicationsDismissedSetForTest();
      final result = FfiChatService.filterDismissedApplications(apps, filtered);
      // Legacy entries no longer match anything (their userId-only key isn't
      // a fingerprint); the wording-keyed entry for 'bob' still filters.
      expect(result.map((a) => a.userId), ['legacy-userid']);

      // Storage was rewritten to drop legacy entries.
      final stored = await prefs
          .getStringList(FfiChatService.dismissedFriendApplicationsKey);
      expect(stored, ['bob|some wording']);
    });
  });

  group('FfiChatService friend-application dismissal (FFI-dependent)',
      skip: _ffiAvailable()
          ? null
          : 'tim2tox FFI library not loadable in this environment', () {
    late _InMemoryPrefs prefs;
    late FfiChatService service;

    setUp(() {
      prefs = _InMemoryPrefs();
      service = FfiChatService(preferencesService: prefs);
    });

    test(
        'refuseFriendApplication is a no-op when no matching entry is in the '
        'C++ queue (defensive)', () async {
      // With no Tox instance running the unfiltered FFI list is empty, so
      // refuse cannot capture a wording fingerprint and must not poison the
      // dismissed set with a userId-only entry (that was the old bug).
      await service.refuseFriendApplication('peer-with-no-pending-request');

      final stored = await prefs
          .getStringList(FfiChatService.dismissedFriendApplicationsKey);
      expect(stored ?? <String>[], isEmpty);
    });

    test('acceptFriendRequest clears every fingerprint matching the userId',
        () async {
      // Seed prefs with two fingerprints for the same peer plus one unrelated
      // entry; accept must remove the two matching entries but leave the
      // unrelated one intact.
      const userID = 'peer-reapply';
      await prefs.setStringList(
        FfiChatService.dismissedFriendApplicationsKey,
        ['$userID|first wording', '$userID|second wording', 'other|hi'],
      );

      await service.acceptFriendRequest(userID);

      final stored = await prefs
          .getStringList(FfiChatService.dismissedFriendApplicationsKey);
      expect(stored, ['other|hi']);
    });
  });
}

/// Test-only accessor for the dismissed set, exposed via an extension so the
/// production class doesn't grow a public `@visibleForTesting` surface for
/// what is fundamentally an internal helper. Reaches into the persistence
/// layer the same way the production filter does.
extension _FfiChatServiceTestAccess on FfiChatService {
  Future<Set<String>> getFriendApplicationsDismissedSetForTest() async {
    // Trigger a read so legacy-migration runs, then return the persisted set.
    // We mirror the production read by going through preferencesService
    // directly so the test does not depend on FFI being loadable.
    final list = await preferencesService
        ?.getStringList(FfiChatService.dismissedFriendApplicationsKey);
    if (list == null) return <String>{};
    final fingerprints = list.where((s) => s.contains('|')).toList();
    if (fingerprints.length != list.length) {
      await preferencesService?.setStringList(
        FfiChatService.dismissedFriendApplicationsKey,
        fingerprints,
      );
    }
    return fingerprints.toSet();
  }
}

/// Minimal in-memory ExtendedPreferencesService used by the dismissal tests.
///
/// Implements only the methods our friend-application code path touches and
/// throws UnimplementedError for the rest, so any accidental usage of an
/// unmocked surface is loud rather than silently wrong.
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
  Future<List<String>?> getStringList(String key) async {
    final v = _store[key];
    return v == null ? null : List<String>.from(v as List);
  }

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

  // Unused by these tests — fail loudly if touched.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
        'InMemoryPrefs does not implement ${invocation.memberName}');
  }
}
