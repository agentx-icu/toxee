import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tim2tox_dart/models/chat_message.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/sdk_fake/fake_event_bus.dart';
import 'package:toxee/sdk_fake/fake_im.dart';
import 'package:toxee/sdk_fake/fake_managers.dart';
import 'package:toxee/sdk_fake/fake_models.dart';
import 'package:toxee/sdk_fake/fake_provider.dart';
import 'package:toxee/sdk_fake/fake_uikit_core.dart';
import 'package:toxee/sdk_fake/uikit_data_facade.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const groupId = 'tox_conf_av_1';
  const conversationId = 'group_$groupId';
  FakeChatDataProvider? provider;

  setUp(() async {
    FakeUIKit.instance.dispose();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
    await Prefs.setCurrentAccountToxId('group_type_test_account');
  });

  tearDown(() {
    provider?.dispose();
    provider = null;
    FakeUIKit.instance.dispose();
  });

  test(
    'latest-name refresh keeps av_conference in mapped conversation',
    () async {
      await Prefs.setGroupName(groupId, 'Renamed AV conference');
      final dataProvider = FakeChatDataProvider();
      provider = dataProvider;
      final refreshedFuture = dataProvider.conversationStream.firstWhere(
        (conversations) => conversations.any(
          (conversation) => conversation.conversationID == conversationId,
        ),
      );

      FakeUIKit.instance.eventBusInstance.emit(
        FakeIM.topicConversation,
        FakeConversation(
          conversationID: conversationId,
          title: 'Old name',
          faceUrl: null,
          unreadCount: 0,
          isGroup: true,
          groupType: 'av_conference',
        ),
      );

      final refreshed = (await refreshedFuture).singleWhere(
        (conversation) => conversation.conversationID == conversationId,
      );
      expect(refreshed.showName, 'Renamed AV conference');
      expect(refreshed.groupType, 'av_conference');
    },
  );

  test('pin emit resolves av_conference from UIKit group data', () async {
    UikitDataFacade.buildGroupList(<V2TimGroupInfo>[
      V2TimGroupInfo(groupID: groupId, groupType: 'av_conference'),
    ], 'fake_conversation_group_type_test');
    final bus = FakeEventBus();
    final manager = FakeConversationManager(bus, _GroupTypeTestFfi());
    await manager.start();
    final emittedFuture = bus
        .on<FakeConversation>(FakeIM.topicConversation)
        .firstWhere(
          (conversation) => conversation.conversationID == conversationId,
        );

    await manager.setPinned(conversationId, true);

    final emitted = await emittedFuture;
    expect(emitted.isPinned, isTrue);
    expect(emitted.groupType, 'av_conference');
    manager.dispose();
    bus.dispose();
  });

  test('conversation mapping preserves supported SDK group types', () async {
    const expectedByGroupId = <String, String>{
      'tox_public_1': GroupType.Public,
      'tox_meeting_1': GroupType.Meeting,
      'tox_avchatroom_1': GroupType.AVChatRoom,
      'tox_community_1': GroupType.Community,
      'tox_work_1': GroupType.Work,
      'tox_group_1': GroupType.Work,
      'tox_conference_1': GroupType.AVChatRoom,
      'tox_av_conference_1': 'av_conference',
    };

    final dataProvider = FakeChatDataProvider();
    provider = dataProvider;
    final mappedFuture = dataProvider.conversationStream.firstWhere(
      (conversations) =>
          conversations
                  .where(
                    (conversation) =>
                        expectedByGroupId.containsKey(conversation.groupID),
                  )
                  .length ==
              expectedByGroupId.length &&
          conversations
              .where(
                (conversation) =>
                    expectedByGroupId.containsKey(conversation.groupID),
              )
              .every(
                (conversation) =>
                    expectedByGroupId[conversation.groupID] ==
                    conversation.groupType,
              ),
    );

    UikitDataFacade.buildGroupList([
      for (final entry in expectedByGroupId.entries)
        V2TimGroupInfo(
          groupID: entry.key,
          groupType: switch (entry.key) {
            'tox_public_1' => GroupType.Public,
            'tox_meeting_1' => GroupType.Meeting,
            'tox_avchatroom_1' => GroupType.AVChatRoom,
            'tox_community_1' => GroupType.Community,
            'tox_work_1' => GroupType.Work,
            'tox_group_1' => 'group',
            'tox_conference_1' => 'conference',
            'tox_av_conference_1' => 'av_conference',
            _ => '',
          },
        ),
    ], 'fake_conversation_group_type_test_supported_types');

    for (final entry in expectedByGroupId.entries) {
      FakeUIKit.instance.eventBusInstance.emit(
        FakeIM.topicConversation,
        FakeConversation(
          conversationID: 'group_${entry.key}',
          title: 'Supported type',
          faceUrl: null,
          unreadCount: 0,
          isGroup: true,
          groupType: switch (entry.key) {
            'tox_public_1' => GroupType.Public,
            'tox_meeting_1' => GroupType.Meeting,
            'tox_avchatroom_1' => GroupType.AVChatRoom,
            'tox_community_1' => GroupType.Community,
            'tox_work_1' => GroupType.Work,
            'tox_group_1' => 'group',
            'tox_conference_1' => 'conference',
            'tox_av_conference_1' => 'av_conference',
            _ => '',
          },
        ),
      );
    }

    final mapped = await mappedFuture;
    final actualByGroupId = {
      for (final conversation in mapped.where(
        (conversation) => expectedByGroupId.containsKey(conversation.groupID),
      ))
        conversation.groupID!: conversation.groupType,
    };

    expect(actualByGroupId, expectedByGroupId);
  });

  test(
    'conversation mapping is case-insensitive for supported SDK group types',
    () async {
      const expectedByGroupId = <String, String>{
        'tox_public_2': GroupType.Public,
        'tox_meeting_2': GroupType.Meeting,
        'tox_avchatroom_2': GroupType.AVChatRoom,
        'tox_community_2': GroupType.Community,
        'tox_work_2': GroupType.Work,
        'tox_group_2': GroupType.Work,
        'tox_conference_2': GroupType.AVChatRoom,
        'tox_av_conference_2': 'av_conference',
      };

      final dataProvider = FakeChatDataProvider();
      provider = dataProvider;
      final mappedFuture = dataProvider.conversationStream.firstWhere(
        (conversations) =>
            conversations
                    .where(
                      (conversation) =>
                          expectedByGroupId.containsKey(conversation.groupID),
                    )
                    .length ==
                expectedByGroupId.length &&
            conversations
                .where(
                  (conversation) =>
                      expectedByGroupId.containsKey(conversation.groupID),
                )
                .every(
                  (conversation) =>
                      expectedByGroupId[conversation.groupID] ==
                      conversation.groupType,
                ),
      );

      UikitDataFacade.buildGroupList([
        for (final entry in expectedByGroupId.entries)
          V2TimGroupInfo(
            groupID: entry.key,
            groupType: switch (entry.key) {
              'tox_public_2' => GroupType.Public.toLowerCase(),
              'tox_meeting_2' => GroupType.Meeting.toLowerCase(),
              'tox_avchatroom_2' => GroupType.AVChatRoom.toLowerCase(),
              'tox_community_2' => GroupType.Community.toLowerCase(),
              'tox_work_2' => GroupType.Work.toLowerCase(),
              'tox_group_2' => 'group',
              'tox_conference_2' => 'conference',
              'tox_av_conference_2' => 'av_conference',
              _ => '',
            },
          ),
      ], 'fake_conversation_group_type_test_case_insensitive_types');

      for (final entry in expectedByGroupId.entries) {
        FakeUIKit.instance.eventBusInstance.emit(
          FakeIM.topicConversation,
          FakeConversation(
            conversationID: 'group_${entry.key}',
            title: 'Supported type',
            faceUrl: null,
            unreadCount: 0,
            isGroup: true,
            groupType: switch (entry.key) {
              'tox_public_2' => GroupType.Public.toLowerCase(),
              'tox_meeting_2' => GroupType.Meeting.toLowerCase(),
              'tox_avchatroom_2' => GroupType.AVChatRoom.toLowerCase(),
              'tox_community_2' => GroupType.Community.toLowerCase(),
              'tox_work_2' => GroupType.Work.toLowerCase(),
              'tox_group_2' => 'group',
              'tox_conference_2' => 'conference',
              'tox_av_conference_2' => 'av_conference',
              _ => '',
            },
          ),
        );
      }

      final mapped = await mappedFuture;
      final actualByGroupId = {
        for (final conversation in mapped.where(
          (conversation) => expectedByGroupId.containsKey(conversation.groupID),
        ))
          conversation.groupID!: conversation.groupType,
      };

      expect(actualByGroupId, expectedByGroupId);
    },
  );
}

class _GroupTypeTestFfi implements FfiChatService {
  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
  getFriendList() async => const [];

  @override
  int getUnreadOf(String peerId) => 0;

  @override
  Set<String> get knownGroups => const <String>{};

  @override
  Map<String, ChatMessage> get lastMessages => const <String, ChatMessage>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
