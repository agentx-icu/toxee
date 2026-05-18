// Tests for the PR6 cross-platform polish changes to Prefs:
//
//   - C9: getAccountByToxId uses firstWhereOrNull, preserves the documented
//     fallback ordering (exact → case-insensitive → 64-char prefix →
//     compareToxIds), and returns null when nothing matches without
//     throwing.
//   - C10: importScopedPrefsForAccount skips malformed entries and
//     continues with the rest, instead of failing the whole import.
//
// These are pure-Dart tests; no FFI / path_provider / native channels.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
  });

  group('getAccountByToxId fallback ordering (C9)', () {
    // A 64-hex-character toxId; the only constraint we exercise here is
    // length >= 64 (so the prefix-match branch can fire).
    const String longId =
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

    test('returns null when account list is empty', () async {
      final found = await Prefs.getAccountByToxId(longId);
      expect(found, isNull);
    });

    test('exact match (case-sensitive) wins over case-insensitive', () async {
      // Seed two accounts: one matches case-insensitively, one matches
      // exactly. The exact match must be returned.
      final lowered = longId.toLowerCase();
      await Prefs.setAccountList(<Map<String, String>>[
        <String, String>{'toxId': lowered, 'nickname': 'lower'},
        <String, String>{'toxId': longId, 'nickname': 'exact'},
      ]);
      final found = await Prefs.getAccountByToxId(longId);
      expect(found, isNotNull);
      expect(found!['nickname'], 'exact');
    });

    test('falls back to case-insensitive when no exact match', () async {
      final lowered = longId.toLowerCase();
      await Prefs.setAccountList(<Map<String, String>>[
        <String, String>{'toxId': lowered, 'nickname': 'lower-only'},
      ]);
      final found = await Prefs.getAccountByToxId(longId);
      expect(found, isNotNull);
      expect(found!['nickname'], 'lower-only');
    });

    test('returns null cleanly (no StateError) when nothing matches',
        () async {
      await Prefs.setAccountList(<Map<String, String>>[
        <String, String>{'toxId': 'ZZZZ', 'nickname': 'unrelated'},
      ]);
      final found = await Prefs.getAccountByToxId(longId);
      expect(found, isNull);
    });
  });

  group('importScopedPrefsForAccount partial-restore (C10)', () {
    const String toxId =
        'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
    const String prefix16 = 'BBBBBBBBBBBBBBBB';

    test('skips a malformed List entry and continues with the rest',
        () async {
      // Construct a payload where one entry is a List<dynamic> whose
      // elements are NOT all strings. The old implementation would crash
      // the entire import via .cast<String>() → SharedPreferences setter.
      // The new implementation logs + skips that one and proceeds.
      final payload = <String, dynamic>{
        'good_string': 'hello',
        'bad_list': <Object>[1, 2, 3], // ints, not strings
        'good_int': 42,
      };

      await Prefs.importScopedPrefsForAccount(toxId, payload);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('good_string_$prefix16'), 'hello');
      expect(prefs.getInt('good_int_$prefix16'), 42);
      // The bad list key was skipped — no entry should exist.
      expect(prefs.getStringList('bad_list_$prefix16'), isNull);
    });

    test('empty toxId is a no-op', () async {
      await Prefs.importScopedPrefsForAccount('', <String, dynamic>{
        'foo': 'bar',
      });
      final prefs = await SharedPreferences.getInstance();
      // No scoped key should have been written.
      expect(prefs.getKeys().where((k) => k.startsWith('foo_')), isEmpty);
    });
  });
}
