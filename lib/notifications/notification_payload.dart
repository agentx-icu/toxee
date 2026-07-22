import 'package:flutter/foundation.dart';

enum NotificationTapTargetKind { c2c, group, incomingCall, friendRequest }

@immutable
class NotificationTapTarget {
  const NotificationTapTarget._({
    required this.kind,
    this.peerId,
    this.groupId,
    this.callId,
    this.senderId,
  });

  const NotificationTapTarget.c2c(String peerId)
    : this._(kind: NotificationTapTargetKind.c2c, peerId: peerId);

  const NotificationTapTarget.group(String groupId)
    : this._(kind: NotificationTapTargetKind.group, groupId: groupId);

  const NotificationTapTarget.incomingCall(String callId)
    : this._(kind: NotificationTapTargetKind.incomingCall, callId: callId);

  const NotificationTapTarget.friendRequest(String senderId)
    : this._(kind: NotificationTapTargetKind.friendRequest, senderId: senderId);

  final NotificationTapTargetKind kind;
  final String? peerId;
  final String? groupId;
  final String? callId;
  final String? senderId;

  @override
  bool operator ==(Object other) {
    return other is NotificationTapTarget &&
        other.kind == kind &&
        other.peerId == peerId &&
        other.groupId == groupId &&
        other.callId == callId &&
        other.senderId == senderId;
  }

  @override
  int get hashCode => Object.hash(kind, peerId, groupId, callId, senderId);

  @override
  String toString() {
    return 'NotificationTapTarget(kind: $kind, peerId: $peerId, '
        'groupId: $groupId, callId: $callId, senderId: $senderId)';
  }
}

NotificationTapTarget? parseNotificationTapPayload(String payload) {
  final trimmed = payload.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.startsWith('group_')) {
    final groupId = trimmed.substring('group_'.length);
    return groupId.isEmpty ? null : NotificationTapTarget.group(groupId);
  }
  if (trimmed.startsWith('c2c_')) {
    final peerId = trimmed.substring('c2c_'.length);
    return peerId.isEmpty ? null : NotificationTapTarget.c2c(peerId);
  }
  if (trimmed.startsWith('missed_call:')) {
    final peerId = trimmed.substring('missed_call:'.length);
    return peerId.isEmpty ? null : NotificationTapTarget.c2c(peerId);
  }
  if (trimmed.startsWith('incoming_call:')) {
    final body = trimmed.substring('incoming_call:'.length);
    if (body.isEmpty) return null;
    final separator = body.indexOf(':');
    final callId = separator == -1 ? body : body.substring(0, separator);
    return callId.isEmpty ? null : NotificationTapTarget.incomingCall(callId);
  }
  if (trimmed.startsWith('friend_req:')) {
    final senderId = trimmed.substring('friend_req:'.length);
    return senderId.isEmpty
        ? null
        : NotificationTapTarget.friendRequest(senderId);
  }

  return null;
}
