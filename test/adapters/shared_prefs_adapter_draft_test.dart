import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tim2tox_dart/interfaces/draft_preferences_service.dart';
import 'package:toxee/adapters/shared_prefs_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adapter implements durable draft save, load, and removal', () async {
    final accountToxId = List<String>.filled(76, 'A').join();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'current_account_tox_id': accountToxId,
    });
    final prefs = await SharedPreferences.getInstance();
    final DraftPreferencesService service = SharedPreferencesAdapter(
      prefs,
      instanceId: 0,
      accountPrefix: accountToxId.substring(0, 16),
    );
    const draft = ConversationDraft(
      conversationID: 'group_ProjectX',
      text: 'unfinished',
      timestamp: 123,
    );

    await service.saveConversationDraft(
      accountToxId: accountToxId,
      draft: draft,
    );
    final reloaded = await service.loadConversationDraft(
      accountToxId: accountToxId,
      conversationID: draft.conversationID,
    );

    expect(reloaded?.conversationID, draft.conversationID);
    expect(reloaded?.text, draft.text);
    expect(reloaded?.timestamp, draft.timestamp);
    expect(
      prefs.getString('draft_v2:$accountToxId:${draft.conversationID}'),
      isNotNull,
    );

    await service.removeConversationDraft(
      accountToxId: accountToxId,
      conversationID: draft.conversationID,
    );
    expect(
      await service.loadConversationDraft(
        accountToxId: accountToxId,
        conversationID: draft.conversationID,
      ),
      isNull,
    );
  });

  test(
    'adapter clear removes exact v2 draft without suffix-trap leakage',
    () async {
      const sharedPrefix = 'ABCDEF0123456789';
      final accountA = '$sharedPrefix${List<String>.filled(60, 'A').join()}';
      final accountB = '$sharedPrefix${List<String>.filled(60, 'B').join()}';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'current_account_tox_id': accountA,
        'draft_v2:$accountA:c2c_friend': '{"text":"delete A","updatedAt":1}',
        'draft_v2:$accountB:c2c_friend_$sharedPrefix':
            '{"text":"keep B","updatedAt":2}',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SharedPreferencesAdapter(
        prefs,
        instanceId: 0,
        accountPrefix: accountA.substring(0, 16),
      );

      await service.clear();

      expect(prefs.getString('draft_v2:$accountA:c2c_friend'), isNull);
      expect(
        prefs.getString('draft_v2:$accountB:c2c_friend_$sharedPrefix'),
        isNotNull,
      );
    },
  );
}
