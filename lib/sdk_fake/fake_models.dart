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
  final String? groupType; // "group" or "conference", null for c2c
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
    this.mediaKind,
    this.isPending = false, // true if message is pending (offline, not sent yet)
    this.isReceived = false, // true if message has been received by peer
    this.isRead = false, // true if message has been read by peer
  });
  final String msgID;
  final String conversationID;
  final String fromUser;
  final String text;
  final int timestampMs;
  final String? filePath;
  final String? fileName; // original file name (for received files, to avoid showing id-prefixed names)
  final String? mediaKind; // image/video/audio/file
  final bool isPending; // true if message is pending (offline, not sent yet)
  final bool isReceived; // true if message has been received by peer
  final bool isRead; // true if message has been read by peer
}

class FakeUser {
  FakeUser({required this.userID, required this.nickName, this.faceUrl, this.online = false, this.status = ''});
  final String userID;
  final String nickName;
  final String? faceUrl;
  final bool online;
  final String status;
}

class FakeTypingEvent {
  FakeTypingEvent({required this.conversationID, required this.fromUser, required this.on});
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

class FakeGroupDeleted {
  FakeGroupDeleted({required this.groupID});
  final String groupID;
}


