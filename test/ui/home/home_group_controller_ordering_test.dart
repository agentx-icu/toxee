// Ordering invariant test for HomeGroupController.handleGroupChanged.
//
// Background: doc/architecture/MAINTAINER_ARCHITECTURE.md flags
// the critical ordering requirement:
//
//   clearMessageList → deleteGroupInfoFromJoinedGroupList
//       → unblockConversation → refreshConversations
//
// This test was written together with the controller extraction and pins the
// invariant so future edits can't silently reorder the four steps.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:toxee/ui/home/home_group_controller.dart';
import 'package:toxee/util/prefs.dart';

enum _Op {
  clearMessageList,
  deleteGroupInfoFromJoinedGroupList,
  unblockConversation,
  refreshConversations,
}

GroupSyncOps _recorderOps({
  required List<_Op> log,
  List<V2TimGroupInfo> groupListSnapshot = const <V2TimGroupInfo>[],
  List<V2TimGroupInfo> sdkGroupListResult = const <V2TimGroupInfo>[],
}) {
  return GroupSyncOps(
    clearMessageList: (_) => log.add(_Op.clearMessageList),
    getGroupListSnapshot: () => List<V2TimGroupInfo>.from(groupListSnapshot),
    deleteGroupInfoFromJoinedGroupList: (_) =>
        log.add(_Op.deleteGroupInfoFromJoinedGroupList),
    fetchSdkGroupListSnapshot: () async =>
        List<V2TimGroupInfo>.from(sdkGroupListResult),
    buildGroupList: (_, __) {},
    addGroupInfoToJoinedGroupList: (_) {},
    getKnownGroups: () => <String>{},
    unblockConversation: (_) => log.add(_Op.unblockConversation),
    refreshConversations: () async => log.add(_Op.refreshConversations),
    onUpdateTray: () async {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    // Scoped Prefs keys require an active account; set a stable test toxId.
    await Prefs.setCurrentAccountToxId('test_tox_id');
  });

  group('handleGroupChanged ordering', () {
    test('full order: clearMessageList → deleteGroupInfoFromJoinedGroupList '
        '→ unblockConversation → refreshConversations', () async {
      final log = <_Op>[];
      final controller = HomeGroupController(ops: _recorderOps(log: log));

      await controller.handleGroupChanged('tox_group_1');

      expect(
        log,
        equals([
          _Op.clearMessageList,
          _Op.deleteGroupInfoFromJoinedGroupList,
          _Op.unblockConversation,
          _Op.refreshConversations,
        ]),
      );
    });

    test(
      'clearMessageList runs before deleteGroupInfoFromJoinedGroupList',
      () async {
        final log = <_Op>[];
        final controller = HomeGroupController(ops: _recorderOps(log: log));

        await controller.handleGroupChanged('tox_group_1');

        final clearIdx = log.indexOf(_Op.clearMessageList);
        final deleteIdx = log.indexOf(_Op.deleteGroupInfoFromJoinedGroupList);
        expect(clearIdx, isNonNegative);
        expect(deleteIdx, isNonNegative);
        expect(clearIdx, lessThan(deleteIdx));
      },
    );

    test('unblockConversation runs before refreshConversations '
        '(counteracts quitGroup side-effect)', () async {
      final log = <_Op>[];
      final controller = HomeGroupController(ops: _recorderOps(log: log));

      await controller.handleGroupChanged('tox_group_1');

      final unblockIdx = log.indexOf(_Op.unblockConversation);
      final refreshIdx = log.indexOf(_Op.refreshConversations);
      expect(unblockIdx, isNonNegative);
      expect(refreshIdx, isNonNegative);
      expect(unblockIdx, lessThan(refreshIdx));
    });

    test('unblockConversation receives the `group_` prefix '
        '(FakeChatDataProvider stores it that way)', () async {
      final unblocked = <String>[];
      final ops = GroupSyncOps(
        clearMessageList: (_) {},
        getGroupListSnapshot: () => <V2TimGroupInfo>[],
        deleteGroupInfoFromJoinedGroupList: (_) {},
        fetchSdkGroupListSnapshot: () async => <V2TimGroupInfo>[],
        buildGroupList: (_, __) {},
        addGroupInfoToJoinedGroupList: (_) {},
        getKnownGroups: () => <String>{},
        unblockConversation: unblocked.add,
        refreshConversations: () async {},
        onUpdateTray: () async {},
      );
      final controller = HomeGroupController(ops: ops);

      await controller.handleGroupChanged('my_group');

      expect(unblocked, contains('group_my_group'));
    });

    test('each of the four critical ops is called exactly once', () async {
      final log = <_Op>[];
      final controller = HomeGroupController(ops: _recorderOps(log: log));

      await controller.handleGroupChanged('tox_group_1');

      for (final op in _Op.values) {
        expect(
          log.where((e) => e == op).length,
          equals(1),
          reason: '$op should be called exactly once',
        );
      }
    });

    test('non-empty displayName is persisted via Prefs', () async {
      final log = <_Op>[];
      final controller = HomeGroupController(ops: _recorderOps(log: log));

      await controller.handleGroupChanged(
        'tox_group_2',
        displayName: 'My Group',
      );

      expect(await Prefs.getGroupName('tox_group_2'), equals('My Group'));
    });

    test('null displayName does not write to Prefs', () async {
      final log = <_Op>[];
      final controller = HomeGroupController(ops: _recorderOps(log: log));

      await controller.handleGroupChanged('tox_group_3');

      expect(await Prefs.getGroupName('tox_group_3'), isNull);
    });

    test('latest-name rebuild preserves av_conference group type', () async {
      const groupId = 'tox_conf_av_1';
      final rebuiltGroups = <V2TimGroupInfo>[];
      final existing = V2TimGroupInfo(
        groupID: groupId,
        groupType: 'av_conference',
      );
      final ops = GroupSyncOps(
        clearMessageList: (_) {},
        getGroupListSnapshot: () => <V2TimGroupInfo>[existing],
        deleteGroupInfoFromJoinedGroupList: (_) {},
        fetchSdkGroupListSnapshot: () async => <V2TimGroupInfo>[],
        buildGroupList: (_, __) {},
        addGroupInfoToJoinedGroupList: rebuiltGroups.add,
        getKnownGroups: () => <String>{},
        unblockConversation: (_) {},
        refreshConversations: () async {},
        onUpdateTray: () async {},
      );

      await HomeGroupController(
        ops: ops,
      ).handleGroupChanged(groupId, displayName: 'Renamed AV conference');

      expect(rebuiltGroups.single.groupType, 'av_conference');
    });

    test(
      'unknown groups fall back to GroupType.Work and tox_conf_ to AVChatRoom',
      () async {
        final addedGroups = <V2TimGroupInfo>[];
        final ops = GroupSyncOps(
          clearMessageList: (_) {},
          getGroupListSnapshot: () => <V2TimGroupInfo>[],
          deleteGroupInfoFromJoinedGroupList: (_) {},
          fetchSdkGroupListSnapshot: () async => <V2TimGroupInfo>[],
          buildGroupList: (_, __) {},
          addGroupInfoToJoinedGroupList: addedGroups.add,
          getKnownGroups: () => <String>{},
          unblockConversation: (_) {},
          refreshConversations: () async {},
          onUpdateTray: () async {},
        );

        await HomeGroupController(
          ops: ops,
        ).handleGroupChanged('tox_group_unknown');
        await HomeGroupController(
          ops: ops,
        ).handleGroupChanged('tox_conf_legacy');

        expect(
          addedGroups
              .firstWhere((group) => group.groupID == 'tox_group_unknown')
              .groupType,
          GroupType.Work,
        );
        expect(
          addedGroups
              .firstWhere((group) => group.groupID == 'tox_conf_legacy')
              .groupType,
          GroupType.AVChatRoom,
        );
      },
    );
  });

  group('loadPersistedGroupsIntoUIKit', () {
    test('calls refreshConversations after a successful run', () async {
      var refreshCalled = false;
      final ops = GroupSyncOps(
        clearMessageList: (_) {},
        getGroupListSnapshot: () => <V2TimGroupInfo>[],
        deleteGroupInfoFromJoinedGroupList: (_) {},
        fetchSdkGroupListSnapshot: () async => <V2TimGroupInfo>[],
        buildGroupList: (_, __) {},
        addGroupInfoToJoinedGroupList: (_) {},
        getKnownGroups: () => <String>{},
        unblockConversation: (_) {},
        refreshConversations: () async {
          refreshCalled = true;
        },
        onUpdateTray: () async {},
      );
      final controller = HomeGroupController(ops: ops);

      await controller.loadPersistedGroupsIntoUIKit();

      expect(refreshCalled, isTrue);
    });

    test('does not throw with empty Prefs state (new account)', () async {
      final ops = GroupSyncOps(
        clearMessageList: (_) {},
        getGroupListSnapshot: () => <V2TimGroupInfo>[],
        deleteGroupInfoFromJoinedGroupList: (_) {},
        fetchSdkGroupListSnapshot: () async => <V2TimGroupInfo>[],
        buildGroupList: (_, __) {},
        addGroupInfoToJoinedGroupList: (_) {},
        getKnownGroups: () => <String>{},
        unblockConversation: (_) {},
        refreshConversations: () async {},
        onUpdateTray: () async {},
      );
      final controller = HomeGroupController(ops: ops);

      await expectLater(controller.loadPersistedGroupsIntoUIKit(), completes);
    });

    test('when allGroups is empty (new account / post-logout), '
        'stale snapshot groups are NOT merged into buildGroupList', () async {
      // Simulate a stale UIKit snapshot from the previous account session.
      // The guard in loadPersistedGroupsIntoUIKit at `if (allGroups.isNotEmpty)`
      // must prevent these from being merged when the new account has no
      // persisted groups — otherwise stale groups from account A leak into
      // account B's conversation list.
      final stalePreviousGroup = V2TimGroupInfo(
        groupID: 'stale_from_previous_account',
        groupType: 'work',
      );
      final builtLists = <List<V2TimGroupInfo>>[];
      final ops = GroupSyncOps(
        clearMessageList: (_) {},
        getGroupListSnapshot: () => <V2TimGroupInfo>[stalePreviousGroup],
        deleteGroupInfoFromJoinedGroupList: (_) {},
        fetchSdkGroupListSnapshot: () async => <V2TimGroupInfo>[],
        buildGroupList: (list, _) =>
            builtLists.add(List<V2TimGroupInfo>.from(list)),
        addGroupInfoToJoinedGroupList: (_) {},
        getKnownGroups: () => <String>{}, // new account → no known groups
        unblockConversation: (_) {},
        refreshConversations: () async {},
        onUpdateTray: () async {},
      );
      final controller = HomeGroupController(ops: ops);

      await controller.loadPersistedGroupsIntoUIKit();

      expect(
        builtLists,
        isNotEmpty,
        reason: 'buildGroupList must be called exactly once',
      );
      expect(
        builtLists.single,
        isEmpty,
        reason:
            'When allGroups is empty (new account / post-logout), the '
            'previous account snapshot must NOT be merged into the new '
            "account's UIKit group list. Removing the `allGroups.isNotEmpty` "
            'guard would cause stale group_<id> entries from the previous '
            "account to appear in the new account's conversation list.",
      );
    });

    test(
      'persisted group rebuild preserves av_conference group type',
      () async {
        const groupId = 'tox_conf_av_2';
        await Prefs.setGroups(<String>{groupId});
        final addedGroups = <V2TimGroupInfo>[];
        final existing = V2TimGroupInfo(
          groupID: groupId,
          groupType: 'av_conference',
        );
        final ops = GroupSyncOps(
          clearMessageList: (_) {},
          getGroupListSnapshot: () => <V2TimGroupInfo>[existing],
          deleteGroupInfoFromJoinedGroupList: (_) {},
          fetchSdkGroupListSnapshot: () async => <V2TimGroupInfo>[],
          buildGroupList: (_, __) {},
          addGroupInfoToJoinedGroupList: addedGroups.add,
          getKnownGroups: () => <String>{},
          unblockConversation: (_) {},
          refreshConversations: () async {},
          onUpdateTray: () async {},
        );

        await HomeGroupController(ops: ops).loadPersistedGroupsIntoUIKit();

        expect(addedGroups.single.groupType, 'av_conference');
      },
    );
  });
}
