import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tim2tox_dart/sdk/tim2tox_sdk_platform.dart';
import 'package:toxee/sdk_fake/fake_provider.dart';

void main() {
  group('Group conversation refresh regression', () {
    test('mergeExternalConversationUpdate keeps new unread and newer orderkey',
        () {
      final existing = V2TimConversation(conversationID: 'group_tox_conf_1')
        ..unreadCount = 0
        ..orderkey = 1000
        ..faceUrl = 'existing-face';

      final refreshed = V2TimConversation(conversationID: 'group_tox_conf_1')
        ..unreadCount = 2
        ..orderkey = 2000;

      final merged = mergeExternalConversationUpdate(
        existing: existing,
        refreshed: refreshed,
      );

      expect(merged.unreadCount, 2);
      expect(merged.orderkey, 2000);
      expect(merged.faceUrl, 'existing-face');
    });

    test('sparse merge preserves existing draft text and timestamp', () {
      final existing = V2TimConversation(conversationID: 'group_tox_conf_1')
        ..draftText = 'unfinished'
        ..draftTimestamp = 123;
      final refreshed = V2TimConversation(conversationID: 'group_tox_conf_1');

      final merged = mergeExternalConversationUpdate(
        existing: existing,
        refreshed: refreshed,
      );

      expect(merged.draftText, 'unfinished');
      expect(merged.draftTimestamp, 123);
    });

    test('sparse merge keeps an explicit empty draft clear', () {
      final existing = V2TimConversation(conversationID: 'group_tox_conf_1')
        ..draftText = 'unfinished'
        ..draftTimestamp = 123;
      final refreshed = V2TimConversation(conversationID: 'group_tox_conf_1')
        ..draftText = ''
        ..draftTimestamp = 456;

      final merged = mergeExternalConversationUpdate(
        existing: existing,
        refreshed: refreshed,
      );

      expect(merged.draftText, '');
      expect(merged.draftTimestamp, 456);
    });

    test(
        'resolveGroupIdForUnread falls back to v2 groupID for conference messages',
        () {
      expect(
        Tim2ToxSdkPlatform.resolveGroupIdForUnread(
          chatMessageGroupId: null,
          v2GroupId: 'tox_conf_1',
        ),
        'tox_conf_1',
      );

      expect(
        Tim2ToxSdkPlatform.resolveGroupIdForUnread(
          chatMessageGroupId: 'tox_group_1',
          v2GroupId: 'tox_conf_1',
        ),
        'tox_group_1',
      );
    });

    test(
        'selectDispatchListeners falls back to global listeners for instanceId 0',
        () {
      final selected = Tim2ToxSdkPlatform.selectDispatchListeners<String>(
        instanceId: 0,
        instanceListeners: const [],
        globalListeners: const ['global-listener'],
      );

      expect(selected, const ['global-listener']);
    });
  });
}
