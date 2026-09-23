import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';

/// Whether the member list the UIKit cached for a group (carried on a
/// `membersChange` event) differs from the rows an open member page shows —
/// a join, a leave / kick, or a role / group-nickname change.
///
/// An empty [cached] list means "no cache", not "no members": the UIKit only
/// patches a cache that exists, so there is nothing to compare against.
/// Avatar / nickname enrichment is deliberately NOT part of the signature: the
/// page writes those onto the rows itself, and a refetch it triggered comes
/// back as a `membersChange` whose cache equals what it now shows — comparing
/// only identity + role + name card is what keeps that from looping.
bool memberListNeedsRefresh(
  List<V2TimGroupMemberFullInfo> shown,
  List<V2TimGroupMemberFullInfo?> cached,
) {
  final cachedRows = cached.whereType<V2TimGroupMemberFullInfo>().toList();
  if (cachedRows.isEmpty) return false;
  String signature(V2TimGroupMemberFullInfo m) =>
      '${m.userID}|${m.role}|${m.nameCard ?? ''}';
  final shownSet = shown.map(signature).toSet();
  final cachedSet = cachedRows.map(signature).toSet();
  return shownSet.length != cachedSet.length ||
      !shownSet.containsAll(cachedSet);
}

/// Fetch the group's member list straight from the SDK (all pages), for a
/// refresh of an OPEN page. Deliberately NOT the UIKit's
/// `groupProfile.loadGroupMemberList`: that one serves its last result for 2 s
/// after every load (so a join right after the page opened was answered with
/// the pre-join list) and re-fires `membersChange` itself. Returns null when
/// the SDK call fails.
Future<List<V2TimGroupMemberFullInfo>?> fetchGroupMembersFresh(
  String groupID,
) async {
  final members = <V2TimGroupMemberFullInfo>[];
  var nextSeq = '0';
  for (var page = 0; page < 100; page++) {
    final res = await TencentCloudChat.instance.chatSDKInstance.groupSDK
        .getGroupMemberList(
          groupID: groupID,
          filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
          nextSeq: nextSeq,
          count: 100,
        );
    if (res == null) return null;
    members.addAll(res.data?.memberInfoList ?? const []);
    final next = res.data?.nextSeq;
    if (next == null || next.isEmpty || next == '0' || next == nextSeq) break;
    nextSeq = next;
  }
  return members;
}
