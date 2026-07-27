import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/prefs/draft_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sharedPrefix = 'ABCDEF0123456789';
  final accountA = _fullToxId(sharedPrefix, 'A');
  final accountB = _fullToxId(sharedPrefix, 'B');
  String? activeAccount;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    activeAccount = accountA;
  });

  DraftPrefs createStore({
    DraftPrefsStringWriter? writer,
    DraftPrefsStringRemover? remover,
  }) {
    return DraftPrefs(
      prefs,
      activeAccountToxId: () async => activeAccount,
      clock: () => DateTime.fromMillisecondsSinceEpoch(123456000),
      stringWriter: writer,
      stringRemover: remover,
    );
  }

  test('same-prefix full account IDs use isolated v2 keys', () async {
    final store = createStore();

    await store.saveDraft(
      accountToxId: accountA,
      conversationID: 'c2c_friend',
      text: 'account A',
    );
    await store.saveDraft(
      accountToxId: accountB,
      conversationID: 'c2c_friend',
      text: 'account B',
    );

    expect(
      (await store.loadDraft(
        accountToxId: accountA,
        conversationID: 'c2c_friend',
      ))?.text,
      'account A',
    );
    expect(
      (await store.loadDraft(
        accountToxId: accountB,
        conversationID: 'c2c_friend',
      ))?.text,
      'account B',
    );
    expect(
      jsonDecode(prefs.getString('draft_v2:$accountA:c2c_friend')!),
      <String, Object>{'text': 'account A', 'updatedAt': 123456},
    );
    expect(prefs.getString('draft_v2:$sharedPrefix:c2c_friend'), isNull);
  });

  test(
    'migration prefers v2, then scoped legacy, then unscoped legacy',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'draft_v2:$accountA:c2c_v2': jsonEncode(<String, Object>{
          'text': 'v2 wins',
          'updatedAt': 42,
        }),
        'draft_c2c_v2_$sharedPrefix': 'scoped loses',
        'draft_c2c_scoped_$sharedPrefix': 'scoped wins',
        'draft_c2c_scoped': 'unscoped loses',
        'draft_c2c_unscoped': 'unscoped fallback',
        'draft_c2c_inactive': 'must remain unclaimed',
      });
      prefs = await SharedPreferences.getInstance();
      final store = createStore();

      expect(
        (await store.loadDraft(
          accountToxId: accountA,
          conversationID: 'c2c_v2',
        ))?.text,
        'v2 wins',
      );
      expect(prefs.getString('draft_c2c_v2_$sharedPrefix'), isNull);

      expect(
        (await store.loadDraft(
          accountToxId: accountA,
          conversationID: 'c2c_scoped',
        ))?.text,
        'scoped wins',
      );
      expect(prefs.getString('draft_c2c_scoped_$sharedPrefix'), isNull);
      expect(prefs.getString('draft_c2c_scoped'), isNull);

      expect(
        (await store.loadDraft(
          accountToxId: accountA,
          conversationID: 'c2c_unscoped',
        ))?.text,
        'unscoped fallback',
      );
      expect(prefs.getString('draft_c2c_unscoped'), isNull);

      expect(
        await store.loadDraft(
          accountToxId: accountB,
          conversationID: 'c2c_inactive',
        ),
        isNull,
      );
      expect(prefs.getString('draft_c2c_inactive'), 'must remain unclaimed');
    },
  );

  test('failed v2 migration write leaves the legacy draft intact', () async {
    await prefs.setString('draft_c2c_friend_$sharedPrefix', 'legacy survives');
    final store = createStore(
      writer: (String key, String value) async => false,
    );

    expect(
      (await store.loadDraft(
        accountToxId: accountA,
        conversationID: 'c2c_friend',
      ))?.text,
      'legacy survives',
    );
    expect(
      prefs.getString('draft_c2c_friend_$sharedPrefix'),
      'legacy survives',
    );
    expect(prefs.getString('draft_v2:$accountA:c2c_friend'), isNull);
  });

  test(
    'failed legacy removal leaves v2 intact and reports clear failure',
    () async {
      await prefs.setString('draft_c2c_friend_$sharedPrefix', 'stale legacy');
      final store = createStore(
        remover: (String key) async {
          if (key == 'draft_c2c_friend_$sharedPrefix') return false;
          return prefs.remove(key);
        },
      );
      await store.saveDraft(
        accountToxId: accountA,
        conversationID: 'c2c_friend',
        text: 'authoritative v2',
      );

      await expectLater(
        store.saveDraft(
          accountToxId: accountA,
          conversationID: 'c2c_friend',
          text: '',
        ),
        throwsStateError,
      );

      expect(prefs.getString('draft_v2:$accountA:c2c_friend'), isNotNull);
      expect(
        (await store.loadDraft(
          accountToxId: accountA,
          conversationID: 'c2c_friend',
        ))?.text,
        'authoritative v2',
      );
    },
  );

  test(
    'legacy prefix migration tolerates account hex casing differences',
    () async {
      activeAccount = accountA.toLowerCase();
      await prefs.setString(
        'draft_c2c_friend_$sharedPrefix',
        'uppercase legacy key',
      );
      final store = createStore();

      final migrated = await store.loadDraft(
        accountToxId: accountA,
        conversationID: 'c2c_friend',
      );

      expect(migrated?.text, 'uppercase legacy key');
      expect(prefs.getString('draft_c2c_friend_$sharedPrefix'), isNull);
      expect(prefs.getString('draft_v2:$accountA:c2c_friend'), isNotNull);
    },
  );

  test('empty text clears only the selected local account draft', () async {
    final store = createStore();
    await prefs.setString(
      'draft_c2c_friend_$sharedPrefix',
      'stale scoped draft',
    );
    await prefs.setString('draft_c2c_friend', 'stale unscoped draft');
    await store.saveDraft(
      accountToxId: accountA,
      conversationID: 'c2c_friend',
      text: 'clear me',
    );
    await store.saveDraft(
      accountToxId: accountB,
      conversationID: 'c2c_friend',
      text: 'keep me',
    );

    await store.saveDraft(
      accountToxId: accountA,
      conversationID: 'c2c_friend',
      text: '',
    );

    expect(
      await store.loadDraft(
        accountToxId: accountA,
        conversationID: 'c2c_friend',
      ),
      isNull,
    );
    expect(
      (await store.loadDraft(
        accountToxId: accountB,
        conversationID: 'c2c_friend',
      ))?.text,
      'keep me',
    );
    expect(prefs.getString('draft_c2c_friend_$sharedPrefix'), isNull);
    expect(prefs.getString('draft_c2c_friend'), isNull);
  });

  test('a new helper instance loads a previously saved draft', () async {
    await createStore().saveDraft(
      accountToxId: accountA,
      conversationID: 'c2c_friend',
      text: 'survives restart',
      updatedAt: 777,
    );

    final reloaded = await createStore().loadDraft(
      accountToxId: accountA,
      conversationID: 'c2c_friend',
    );

    expect(reloaded?.text, 'survives restart');
    expect(reloaded?.updatedAt, 777);
  });

  test('group conversation IDs remain case-sensitive', () async {
    final store = createStore();
    await store.saveDraft(
      accountToxId: accountA,
      conversationID: 'group_ProjectX',
      text: 'upper',
    );
    await store.saveDraft(
      accountToxId: accountA,
      conversationID: 'group_projectx',
      text: 'lower',
    );

    expect(
      (await store.loadDraft(
        accountToxId: accountA,
        conversationID: 'group_ProjectX',
      ))?.text,
      'upper',
    );
    expect(
      (await store.loadDraft(
        accountToxId: accountA,
        conversationID: 'group_projectx',
      ))?.text,
      'lower',
    );
  });

  test(
    '64-character account IDs resolve only through the active full ID',
    () async {
      final store = createStore();
      await store.saveDraft(
        accountToxId: accountA.substring(0, 64),
        conversationID: 'c2c_friend',
        text: 'resolved',
      );

      expect(prefs.getString('draft_v2:$accountA:c2c_friend'), isNotNull);
      expect(
        () => store.saveDraft(
          accountToxId: sharedPrefix,
          conversationID: 'c2c_friend',
          text: 'unsafe prefix',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'clearScopedKeysForAccount removes only exact full-ID v2 drafts',
    () async {
      final store = createStore();
      await store.saveDraft(
        accountToxId: accountA,
        conversationID: 'c2c_friend',
        text: 'delete account A',
      );
      await store.saveDraft(
        accountToxId: accountB,
        conversationID: 'c2c_friend_$sharedPrefix',
        text: 'keep account B',
      );

      await Prefs.clearScopedKeysForAccount(accountA);

      expect(prefs.getString('draft_v2:$accountA:c2c_friend'), isNull);
      expect(
        prefs.getString('draft_v2:$accountB:c2c_friend_$sharedPrefix'),
        isNotNull,
      );
      expect(
        (await store.loadDraft(
          accountToxId: accountB,
          conversationID: 'c2c_friend_$sharedPrefix',
        ))?.text,
        'keep account B',
      );
    },
  );

  test(
    'portable export strips account IDs and imports under target full ID',
    () async {
      const conversation = 'c2c:friend:with:colons';
      final store = createStore();
      await store.saveDraft(
        accountToxId: accountA,
        conversationID: conversation,
        text: 'portable account A',
        updatedAt: 777,
      );
      await store.saveDraft(
        accountToxId: accountB,
        conversationID: '${conversation}_$sharedPrefix',
        text: 'account B must stay out',
        updatedAt: 888,
      );

      final exported = await Prefs.exportScopedPrefsForAccount(accountA);

      final portableDrafts = exported[DraftPrefs.portableBackupSectionKey];
      expect(portableDrafts, isA<Map<String, dynamic>>());
      expect(
        (portableDrafts as Map<String, dynamic>).keys,
        unorderedEquals(<String>[conversation]),
      );
      expect(portableDrafts.toString(), isNot(contains(accountA)));
      expect(portableDrafts.toString(), isNot(contains(accountB)));
      expect(
        portableDrafts.toString(),
        isNot(contains('account B must stay out')),
      );
      expect(exported.toString(), isNot(contains(accountB)));
      expect(exported.toString(), isNot(contains('account B must stay out')));

      final accountC = _fullToxId('0011223344556677', 'C');
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);
      activeAccount = accountC;

      await Prefs.importScopedPrefsForAccount(accountC, exported);

      expect(prefs.getString('draft_v2:$accountA:$conversation'), isNull);
      expect(prefs.getString('draft_v2:$accountB:$conversation'), isNull);
      final imported = await createStore().loadDraft(
        accountToxId: accountC,
        conversationID: conversation,
      );
      expect(imported?.text, 'portable account A');
      expect(imported?.updatedAt, 777);
    },
  );

  test(
    'malformed portable draft entries do not poison other scoped prefs',
    () async {
      final accountC = _fullToxId('0011223344556677', 'C');
      await Prefs.importScopedPrefsForAccount(accountC, <String, dynamic>{
        DraftPrefs.portableBackupSectionKey: <String, dynamic>{
          'c2c:valid': jsonEncode(<String, Object>{
            'text': 'valid draft',
            'updatedAt': 900,
          }),
          'c2c:bad-json': '{',
          'c2c:bad-shape': jsonEncode(<String, Object>{'text': 12}),
          '': jsonEncode(<String, Object>{
            'text': 'empty conv',
            'updatedAt': 1,
          }),
        },
        'good_string': 'restored primitive',
      });

      activeAccount = accountC;
      final imported = await createStore().loadDraft(
        accountToxId: accountC,
        conversationID: 'c2c:valid',
      );

      expect(imported?.text, 'valid draft');
      expect(imported?.updatedAt, 900);
      expect(
        prefs.getString('good_string_${accountC.substring(0, 16)}'),
        'restored primitive',
      );
      expect(prefs.getString('draft_v2:$accountC:c2c:bad-json'), isNull);
      expect(prefs.getString('draft_v2:$accountC:c2c:bad-shape'), isNull);
    },
  );

  test('portable import reports SharedPreferences write failures', () async {
    final report = await DraftPrefs.importPortableDrafts(
      prefs: prefs,
      accountToxId: accountA,
      portableDrafts: <String, dynamic>{
        'c2c:friend': jsonEncode(<String, Object>{
          'text': 'not written',
          'updatedAt': 321,
        }),
      },
      stringWriter: (String key, String value) async => false,
    );

    expect(report.writeFailures, 1);
    expect(report.imported, 0);
    expect(prefs.getString('draft_v2:$accountA:c2c:friend'), isNull);
  });

  test(
    'scoped prefs restore fails when a portable draft write fails',
    () async {
      await expectLater(
        Prefs.importScopedPrefsForAccount(accountA, <String, dynamic>{
          DraftPrefs.portableBackupSectionKey: <String, dynamic>{
            'c2c:friend': jsonEncode(<String, Object>{
              'text': 'must not be lost',
              'updatedAt': 321,
            }),
          },
          'good_string': 'must not commit after draft failure',
        }, draftStringWriter: (String key, String value) async => false),
        throwsA(isA<StateError>()),
      );

      expect(prefs.getString('draft_v2:$accountA:c2c:friend'), isNull);
      expect(
        prefs.getString('good_string_${accountA.substring(0, 16)}'),
        isNull,
      );
    },
  );

  test(
    'portable import reports thrown SharedPreferences write failures',
    () async {
      final report = await DraftPrefs.importPortableDrafts(
        prefs: prefs,
        accountToxId: accountA,
        portableDrafts: <String, dynamic>{
          'c2c:friend': jsonEncode(<String, Object>{
            'text': 'not written',
            'updatedAt': 321,
          }),
        },
        stringWriter: (String key, String value) async {
          throw StateError('write failed');
        },
      );

      expect(report.writeFailures, 1);
      expect(report.imported, 0);
      expect(prefs.getString('draft_v2:$accountA:c2c:friend'), isNull);
    },
  );

  test(
    'portable draft values are canonicalized before export and import',
    () async {
      const conversation = 'c2c:extra-fields';
      final encodedWithExtras = jsonEncode(<String, Object>{
        'text': 'clean draft',
        'updatedAt': 456,
        'accountToxId': accountA,
        'conversationID': conversation,
      });
      await prefs.setString(
        'draft_v2:$accountA:$conversation',
        encodedWithExtras,
      );

      final exported = DraftPrefs.exportPortableDrafts(
        prefs: prefs,
        accountToxId: accountA,
      );

      expect(exported[conversation], contains('clean draft'));
      expect(exported[conversation], isNot(contains(accountA)));
      expect(exported[conversation], isNot(contains('conversationID')));

      final accountC = _fullToxId('0011223344556677', 'C');
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      await Prefs.initialize(prefs);
      await DraftPrefs.importPortableDrafts(
        prefs: prefs,
        accountToxId: accountC,
        portableDrafts: <String, dynamic>{conversation: encodedWithExtras},
      );

      final stored = prefs.getString('draft_v2:$accountC:$conversation');
      expect(stored, contains('clean draft'));
      expect(stored, isNot(contains(accountA)));
      expect(stored, isNot(contains('conversationID')));
    },
  );
}

String _fullToxId(String prefix, String suffixCharacter) {
  return '$prefix${List<String>.filled(60, suffixCharacter).join()}';
}
