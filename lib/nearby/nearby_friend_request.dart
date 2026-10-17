import 'dart:async';

import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_application.dart';

import 'nearby_service.dart';

/// A friend application that answers one of our nearby intents: the sender
/// of the application (handshake-authenticated by Tox) and the card we
/// contacted. The UI shows both and asks for one tap; nothing is accepted
/// silently (plan §3.4, "Initiator side").
class NearbyReply {
  const NearbyReply({required this.application, required this.intent});
  final V2TimFriendApplication application;
  final PendingIntent intent;

  String get senderPublicKey => application.userID;
}

/// Watches friend applications for nearby nonces and hands matches to the UI.
///
/// Attached by `NearbyController` to the same application list HomePage
/// already receives; detached on session teardown.
class NearbyFriendRequestMatcher {
  NearbyFriendRequestMatcher(this._service);

  final NearbyService _service;
  final StreamController<NearbyReply> _replies =
      StreamController<NearbyReply>.broadcast();
  final Set<String> _seen = <String>{};

  Stream<NearbyReply> get replies => _replies.stream;

  /// Feeds the current application list. Each application is matched once.
  List<NearbyReply> offer(List<V2TimFriendApplication> applications) {
    final out = <NearbyReply>[];
    for (final app in applications) {
      final key = '${app.userID}|${app.addWording ?? ''}';
      if (_seen.contains(key)) continue;
      final intent = _service.matchFriendApplication(app.addWording);
      if (intent == null) continue;
      _seen.add(key);
      final reply = NearbyReply(application: app, intent: intent);
      out.add(reply);
      if (!_replies.isClosed) _replies.add(reply);
    }
    return out;
  }

  Future<void> dispose() => _replies.close();
}
