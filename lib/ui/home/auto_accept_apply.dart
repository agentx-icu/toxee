import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../util/logger.dart';
import '../../util/prefs.dart';
import '../group/group_invite_prompter.dart';
import 'package:tencent_cloud_chat_contact/widgets/group_member_identity.dart';
import 'package:tencent_cloud_chat_common/utils/group_announcement_permission.dart';

import '../group/group_join_failure_notifier.dart';

/// Load the account-scoped "auto-accept group invites" preference for [toxId]
/// and apply it at HomePage bootstrap (S47, the Dart half): mirror it into the
/// UI via [mirrorToUi] and push it into the native auto-accept gate via
/// [FfiChatService.setAutoAcceptGroupInvites] — both ONLY while [isStillMounted].
///
/// The order is deliberate and byte-for-byte matches the original inline
/// bootstrap (`if (mounted) { setState(mirror); service.set(value); }`):
/// [mirrorToUi] runs BEFORE the native push, so even if the synchronous FFI
/// setter throws, the UI still reflects the persisted value (codex). The
/// [isStillMounted] gate preserves the other half — an account switch that
/// unmounts HomePage before the async `Prefs.get` resolves must NOT mirror or
/// push a stale value into a service that may already be re-initialising for
/// another account.
///
/// Returns the loaded value. Extracted from the HomePage bootstrap so this
/// Pref→(UI + native-gate) apply is L1-testable without pumping HomePage.
Future<bool> loadAndApplyAutoAcceptGroupInvites(
  FfiChatService service,
  String toxId, {
  required bool Function() isStillMounted,
  required void Function(bool value) mirrorToUi,
}) async {
  final value = await Prefs.getAutoAcceptGroupInvites(toxId);
  if (isStillMounted()) {
    mirrorToUi(value);
    service.setAutoAcceptGroupInvites(value);
    // Invites that are already waiting — restored from the previous session,
    // or received before this point — are answered here: prompted for, or
    // accepted outright when the setting says so.
    GroupInvitePrompter.instance.attach(service, autoAccept: value);
    // Joins the group refused later (password, full) are explained here.
    GroupJoinFailureNotifier.instance.attach(service);
    // Friends who proved their per-group key show as themselves in NGC
    // member lists (MM-6).
    groupMemberFriendKeyResolver = service.friendForGroupMemberKey;
    // The announcement editor asks the Tox instance whether a topic change
    // would be accepted (topic lock + live role), not the V2TIM group type.
    groupAnnouncementEditableResolver = service.canSetGroupTopic;
  }
  return value;
}

/// The user toggled "auto-accept group invites" in settings: update the native
/// gate that decides about NEW invites, and let the prompter accept the ones
/// that are already waiting when the setting was switched on.
void applyAutoAcceptGroupInvitesChange(FfiChatService service, bool value) {
  service.setAutoAcceptGroupInvites(value);
  GroupInvitePrompter.instance.autoAccept = value;
}

/// Accept every pending friend application in [userIds], returning the ids
/// that were NOT accepted.
///
/// `FfiChatService.acceptFriendRequest` THROWS when the native accept fails
/// (an invalid/own public key, an allocation failure) — since
/// `tim2tox_ffi_accept_friend` started returning its callback's verdict
/// instead of an unconditional success, that is a real, reachable outcome.
/// The caller must therefore keep a failed application PENDING (so the user
/// can retry, and so the request is not silently lost) and must not report
/// blanket success. Returning the failures instead of swallowing them is what
/// makes that possible.
Future<List<String>> acceptFriendApplications(
  FfiChatService service,
  Iterable<String> userIds,
) async {
  final failed = <String>[];
  for (final uid in userIds) {
    if (uid.isEmpty) continue;
    try {
      await service.acceptFriendRequest(uid);
    } catch (e, st) {
      AppLogger.logError('[AutoAccept] acceptFriendRequest failed for $uid', e, st);
      failed.add(uid);
    }
  }
  return failed;
}
