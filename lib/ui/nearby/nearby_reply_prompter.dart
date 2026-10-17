import 'package:flutter/widgets.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_application.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../nearby/nearby_controller.dart';
import 'nearby_confirm_card.dart';

/// Feeds the friend applications HomePage receives to the nearby matcher and
/// shows the one-tap confirm card for each one that answers an intent we
/// sent. Accepting runs the ordinary acceptance path.
Future<void> handleNearbyReplies(
  BuildContext context,
  FfiChatService service,
  List<V2TimFriendApplication> applications,
) async {
  final replies = NearbyController.instance.offerApplications(applications);
  for (final reply in replies) {
    if (!context.mounted) return;
    final accept = await showNearbyReplyCard(context, reply);
    if (!context.mounted) return;
    if (accept) await service.acceptFriendRequest(reply.application.userID);
  }
}
