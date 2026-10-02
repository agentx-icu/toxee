import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../call/av_conference_session_controller.dart';
import '../../call/av_conference_session_page.dart';
import '../../i18n/app_localizations.dart';
import '../../sdk_fake/fake_uikit_core.dart';
import '../../sdk_fake/self_conversation.dart';

bool isAvConferenceConversation(V2TimConversation? conversation) =>
    conversation?.groupType == 'av_conference';

/// The chat header's action slot: UIKit's default actions, the join action of
/// an A/V conference, and nothing for the self conversation ("note to self":
/// a local notebook — a call to yourself cannot connect).
///
/// [isMounted] guards the conference route push against a defunct host State.
Widget buildToxeeMessageHeaderActions(
  BuildContext context, {
  required MessageHeaderBuilderWidgets widgets,
  required MessageHeaderBuilderData data,
  required FfiChatService service,
  required bool Function() isMounted,
}) {
  final conversation = data.conversation;
  final userID = data.userID ?? conversation?.userID;
  if (userID != null && isSelfConversationId(service, 'c2c_$userID')) {
    return const SizedBox.shrink();
  }
  final groupId = conversation?.groupID;
  if (!isAvConferenceConversation(conversation) ||
      groupId == null ||
      groupId.isEmpty) {
    return widgets.messageHeaderActions;
  }
  final l10n = AppLocalizations.of(context)!;
  final manager = FakeUIKit.instance.callServiceManager;
  final canJoinConference = manager?.isCallingAvailable ?? false;
  return AvConferenceHeaderAction(
    enabled: canJoinConference,
    tooltip: '${l10n.join} ${l10n.audio}',
    onPressed: !canJoinConference || manager == null
        ? null
        : () {
            if (!isMounted()) return; // defunct-State guard (codex High)
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => AvConferenceSessionPage(
                  controller: AvConferenceSessionController(
                    groupId: groupId,
                    displayName: conversation?.showName ?? groupId,
                    bridge: manager.conferenceBridge,
                  ),
                ),
              ),
            );
          },
  );
}
