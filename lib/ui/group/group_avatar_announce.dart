import 'dart:async';

import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';

import '../../sdk_fake/fake_uikit_core.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';

typedef GroupFaceUrlSetter = Future<V2TimCallback> Function({
  required String groupID,
  required String groupType,
  String? faceUrl,
});

/// Persist a newly picked group avatar AND tell the rest of the app, the same
/// way a rename does (`_onChangeGroupName`).
///
/// The avatar picker used to only write `Prefs.setGroupAvatar`, so nothing
/// else learned about the change: the Contacts → Groups list kept the old
/// `V2TimGroupInfo.faceUrl`, the conversation row kept its cached faceUrl and
/// an open chat's header avatar kept the conversation captured at open, until
/// the next restart.
///
/// * `setGroupInfo(faceUrl:)` goes through `Tim2ToxSdkPlatform.setGroupInfo`,
///   which re-persists the pref and fires `onGroupInfoChanged` with
///   `V2TIM_GROUP_INFO_CHANGE_TYPE_FACE_URL` → UIKit's contact data updates
///   the group list entry. It is LOCAL only: Tox NGC has no group-avatar field,
///   so nothing crosses the wire (peers keep their own avatar choice).
///   Unawaited + caught, like the rename, so a slow platform never blocks.
/// * `refreshConversations()` rebuilds the conversation list from Prefs, which
///   updates the row and — through the live-conversation subscription in the
///   message header avatar — an open chat's header.
Future<void> announceGroupAvatarChange({
  required String groupID,
  required String groupType,
  required String path,
  GroupFaceUrlSetter? setGroupInfo,
  Future<void> Function()? refreshConversations,
}) async {
  await Prefs.setGroupAvatar(groupID, path);
  final setter = setGroupInfo ??
      TencentCloudChat.instance.chatSDKInstance.groupSDK.setGroupInfo;
  unawaited(
    setter(groupID: groupID, groupType: groupType, faceUrl: path)
        .then((res) {
          if (res.code != 0) {
            AppLogger.info('[GroupAvatar] setGroupInfo rc=${res.code}');
          }
        })
        .catchError((Object e, StackTrace st) {
          AppLogger.logError('[GroupAvatar] setGroupInfo failed', e, st);
        }),
  );
  try {
    await (refreshConversations ??
        () async => FakeUIKit.instance.im?.refreshConversations())();
  } on Object catch (e, st) {
    AppLogger.logError('[GroupAvatar] conversation refresh failed', e, st);
  }
}
