import 'package:tencent_cloud_chat_common/external/chat_data_provider.dart';

import 'fake_provider.dart';

/// A group that (re)appears in the joined set must lose the
/// "deleted conversation" tombstone a previous quit/dismiss/kick left in
/// [FakeChatDataProvider] — otherwise every rebuild keeps skipping it and the
/// group has no conversation row until someone speaks or the app restarts.
///
/// The join dialog lifts it explicitly (HomeGroupController step 3); a group
/// joined by ACCEPTING AN INVITE never goes through that dialog — it arrives
/// through the native self-join notification — so the poll's own diff is the
/// one place that sees every way a group can come back.
void liftGroupTombstones(Iterable<String> appearedGroupIds) {
  final provider = ChatDataProviderRegistry.provider;
  if (provider is! FakeChatDataProvider) return;
  for (final groupId in appearedGroupIds) {
    provider.unblockConversation('group_$groupId');
  }
}
