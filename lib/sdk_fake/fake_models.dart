import 'package:tim2tox_dart/models/chat_message.dart';

String resolveFakeConversationGroupType({
  required String groupId,
  String? authoritativeGroupType,
  String? existingGroupType,
}) {
  for (final candidate in <String?>[
    authoritativeGroupType,
    existingGroupType,
  ]) {
    final value = candidate?.trim();
    if (value == null || value.isEmpty) continue;
    switch (value.toLowerCase()) {
      case 'av_conference':
        return 'av_conference';
      case 'conference':
      case 'avchatroom':
        return 'conference';
      case 'public':
      case 'meeting':
      case 'community':
        return value.toLowerCase();
      case 'group':
      case 'work':
        return 'group';
      default:
        return value;
    }
  }
  return groupId.startsWith('tox_conf_') ? 'conference' : 'group';
}

class FakeConversation {
  FakeConversation({
    required this.conversationID,
    required this.title,
    required this.faceUrl,
    required this.unreadCount,
    this.isGroup = false,
    this.isPinned = false,
    this.groupType,
  });
  final String conversationID; // c2c_<uid> or group_<gid>
  final String title;
  final String? faceUrl;
  final int unreadCount;
  final bool isGroup;
  final bool isPinned;
  final String? groupType;
}

class FakeMessage {
  FakeMessage({
    required this.msgID,
    required this.conversationID,
    required this.fromUser,
    required this.text,
    required this.timestampMs,
    this.filePath,
    this.fileName, // original file name (for received files, to avoid showing id-prefixed names)
    this.fileSize,
    this.mediaKind,
    this.cloudCustomData,
    this.isPending =
        false, // true if message is pending (offline, not sent yet)
    this.isReceived = false, // true if message has been received by peer
    this.isRead = false, // true if message has been read by peer
    this.isFailed = false, // our send failed; Retry re-queues it
    this.isCancelled = false, // our queued send was cancelled before it left
  });

  /// [m] as a [FakeMessage] in [conversationID], send state included.
  /// [withReceipts] false leaves the peer receipt flags off.
  factory FakeMessage.fromChat(
    ChatMessage m, {
    required String conversationID,
    bool withReceipts = true,
  }) => FakeMessage(
    msgID: m.msgID ?? '${m.timestamp.millisecondsSinceEpoch}_${m.fromUserId}',
    conversationID: conversationID,
    fromUser: m.fromUserId,
    text: m.text,
    timestampMs: m.timestamp.millisecondsSinceEpoch,
    filePath: m.filePath,
    fileName: m.fileName,
    fileSize: m.fileSize,
    mediaKind: m.mediaKind,
    cloudCustomData: m.cloudCustomData,
    isPending: m.isPending,
    isReceived: withReceipts && m.isReceived,
    isRead: withReceipts && m.isRead,
    isFailed: m.isFailed,
    isCancelled: m.isCancelled,
  );

  /// This message as a [ChatMessage] (send state included), from [isSelf]
  /// with [groupId] for a group conversation.
  ChatMessage toChat({required bool isSelf, String? groupId}) => ChatMessage(
    text: text,
    fromUserId: fromUser,
    isSelf: isSelf,
    timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
    groupId: groupId,
    msgID: msgID,
    filePath: filePath,
    mediaKind: mediaKind,
    isPending: isPending,
    isFailed: isFailed,
    isCancelled: isCancelled,
  );

  final String msgID;
  final String conversationID;
  final String fromUser;
  final String text;
  final int timestampMs;
  final String? filePath;
  final String?
  fileName; // original file name (for received files, to avoid showing id-prefixed names)
  final int? fileSize;
  final String? mediaKind; // image/video/audio/file
  final String? cloudCustomData;
  final bool isPending; // true if message is pending (offline, not sent yet)
  final bool isReceived; // true if message has been received by peer
  final bool isRead; // true if message has been read by peer
  final bool isFailed; // our send failed; Retry re-queues it
  final bool isCancelled; // our queued send was cancelled before it left
}

class FakeUser {
  FakeUser({
    required this.userID,
    required this.nickName,
    this.faceUrl,
    this.online = false,
    this.status = '',
  });
  final String userID;
  final String nickName;
  final String? faceUrl;
  final bool online;
  final String status;
}

class FakeTypingEvent {
  FakeTypingEvent({
    required this.conversationID,
    required this.fromUser,
    required this.on,
  });
  final String conversationID;
  final String fromUser;
  final bool on;
}

class FakeUnreadTotal {
  FakeUnreadTotal(this.total);
  final int total;
}

class FakeFriendApplication {
  FakeFriendApplication({
    required this.userID,
    required this.wording,
    this.nickName,
  });
  final String userID;
  final String wording;

  /// Optional applicant display name (Tox requests carry none at the protocol
  /// level; the L3 seed harness fills it for demo "new friend" requests).
  final String? nickName;
}

class FakeFriendDeleted {
  FakeFriendDeleted({required this.userID});
  final String userID;
}

/// A friend that (re)appeared in the Tox friend list since the previous poll.
/// Lifts the conversation tombstone a [FakeFriendDeleted] left behind.
class FakeFriendAdded {
  FakeFriendAdded({required this.userID});
  final String userID;
}

class FakeGroupDeleted {
  FakeGroupDeleted({required this.groupID});
  final String groupID;
}
