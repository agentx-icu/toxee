import 'nearby_records.dart';

/// Model types of the nearby feature (see nearby_service.dart).
/// [idle] = not running (never started, stopped, paused); [cellUnavailable]
/// = every cell we want is backing off / unavailable right now (the native
/// side keeps retrying).
enum NearbyStatus { idle, locating, joining, active, noLocation, dhtNotReady, cellUnavailable }

/// Someone in one of our cells, as last heard.
class NearbyPeer {
  NearbyPeer({
    required this.skHex,
    required this.ekHex,
    required this.ngcPeerPkHex,
    required this.record,
    required this.lastSeen,
  });
  final String skHex;
  String ekHex;

  /// toxcore-authenticated NGC peer key — the rate/binding key.
  String ngcPeerPkHex;
  PresenceRecord record;
  DateTime lastSeen;

  /// The cell the latest record arrived on (where intents are sent).
  String? cellChatIdHex;

  /// Every joined cell this peer was heard on; the peer stays listed until
  /// it is gone from all of them (plan §3.4 multi-cell de-duplication).
  final Set<String> cells = <String>{};

  String get name => record.name;
}

/// An intent we sent and may still be answered.
class PendingIntent {
  const PendingIntent({
    required this.nonceHex,
    required this.expiresAt,
    required this.targetSkHex,
    required this.targetEkHex,
    required this.targetName,
  });
  final String nonceHex;
  final DateTime expiresAt;
  final String targetSkHex;
  final String targetEkHex;
  final String targetName;
}

/// An intent we received (the card the receiver sees).
class IncomingIntent {
  const IncomingIntent({
    required this.fromSkHex,
    required this.fromName,
    required this.address,
    required this.nonceHex,
    required this.message,
    required this.receivedAt,
  });
  final String fromSkHex;
  final String fromName;
  final String address;
  final String nonceHex;
  final String message;
  final DateTime receivedAt;

  String get requestWording =>
      IntentBody(address: address, nonceHex: nonceHex, message: message, exp: 0)
          .requestWording();
}

enum NearbyIntentFailure { notRunning, messageTooLong, rateLimited, peerGone }
